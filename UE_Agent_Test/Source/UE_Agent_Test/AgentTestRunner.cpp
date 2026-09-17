#include "AgentTestRunner.h"
#include "AgentCharacter.h"
#include "AgentDoor.h"
#include "AgentEditorBridge.h"
#include "Components/CapsuleComponent.h"
#include "Dom/JsonObject.h"
#include "Engine/World.h"
#include "EngineUtils.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "GameFramework/PlayerController.h"
#include "GenericPlatform/GenericPlatformMisc.h"
#include "HAL/FileManager.h"
#include "InputKeyEventArgs.h"
#include "Kismet/GameplayStatics.h"
#include "Misc/App.h"
#include "Misc/CommandLine.h"
#include "Misc/DateTime.h"
#include "Misc/FileHelper.h"
#include "Misc/EngineVersion.h"
#include "Misc/Paths.h"
#include "Misc/Parse.h"
#include "RHI.h"
#include "Serialization/JsonSerializer.h"
#include "UnrealClient.h"

namespace
{
TSharedPtr<FJsonObject> VectorJson(const FVector& V)
{
	TSharedPtr<FJsonObject> Obj = MakeShared<FJsonObject>();
	Obj->SetNumberField(TEXT("x"), V.X);
	Obj->SetNumberField(TEXT("y"), V.Y);
	Obj->SetNumberField(TEXT("z"), V.Z);
	return Obj;
}
TArray<TSharedPtr<FJsonValue>> ObjectsAsValues(const TArray<TSharedPtr<FJsonObject>>& Objects)
{
	TArray<TSharedPtr<FJsonValue>> Values;
	for (const auto& Obj : Objects) Values.Add(MakeShared<FJsonValueObject>(Obj));
	return Values;
}
}

AAgentTestRunner::AAgentTestRunner()
{
	PrimaryActorTick.bCanEverTick = true;
	PrimaryActorTick.TickGroup = TG_PostUpdateWork;
}

void AAgentTestRunner::BuildSteps()
{
	bCapture = FParse::Param(FCommandLine::Get(), TEXT("AgentCapture"));
	auto Add = [this](const TCHAR* Name, EAction Action, float Duration, ECheck Check = ECheck::None, FKey Key = FKey())
	{
		FStep Step;
		Step.Name = Name; Step.Action = Action; Step.Duration = Duration; Step.Check = Check; Step.Key = Key;
		Steps.Add(Step);
	};
	auto Setup = [this](const TCHAR* Name, const FVector& Position, const FRotator& Rotation, bool bAim = false)
	{
		FStep Step;
		Step.Name = Name; Step.Action = EAction::Setup; Step.Duration = 0.25f;
		Step.Position = Position; Step.Rotation = Rotation; Step.bAimAtDoor = bAim;
		Steps.Add(Step);
	};
	Add(TEXT("initial_spawn_and_closed_door"), EAction::Wait, bCapture ? 2.f : 0.8f, ECheck::InitialState);
	Add(TEXT("W_key_forward"), EAction::HoldKey, 0.5f, ECheck::Forward, EKeys::W);
	Add(TEXT("settle_after_W"), EAction::Wait, 0.2f);
	Add(TEXT("S_key_backward"), EAction::HoldKey, 0.5f, ECheck::Backward, EKeys::S);
	Add(TEXT("settle_after_S"), EAction::Wait, 0.2f);
	Add(TEXT("D_key_right"), EAction::HoldKey, 0.5f, ECheck::Right, EKeys::D);
	Add(TEXT("settle_after_D"), EAction::Wait, 0.2f);
	Add(TEXT("A_key_left"), EAction::HoldKey, 0.5f, ECheck::Left, EKeys::A);
	Add(TEXT("settle_after_A"), EAction::Wait, 0.2f);
	Add(TEXT("MouseX_changes_view_yaw"), EAction::MouseYaw, 0.25f, ECheck::Yaw);
	Add(TEXT("MouseY_changes_view_pitch"), EAction::MousePitch, 0.25f, ECheck::Pitch);
	Setup(TEXT("setup_for_solid_wall"), FVector(-150, 250, 98), FRotator::ZeroRotator);
	Add(TEXT("W_into_wall_stops_and_floor_supports"), EAction::HoldKey, 2.4f, ECheck::WallAndFloor, EKeys::W);
	Setup(TEXT("setup_for_side_wall"), FVector(0, 0, 98), FRotator::ZeroRotator);
	Add(TEXT("D_into_side_wall_stops"), EAction::HoldKey, 1.65f, ECheck::SideWall, EKeys::D);
	Setup(TEXT("setup_for_closed_door"), FVector(180, 0, 98), FRotator::ZeroRotator);
	Add(TEXT("closed_door_blocks_actual_W_movement"), EAction::HoldKey, 1.15f, ECheck::ClosedInside, EKeys::W);
	Setup(TEXT("setup_near_door_but_looking_away"), FVector(280, 0, 98), FRotator(0, 180, 0));
	Add(TEXT("near_looking_away_E_rejected"), EAction::Interact, 0.6f, ECheck::FarRejected);
	Setup(TEXT("setup_near_closed_door"), FVector(280, 0, 98), FRotator::ZeroRotator, true);
	Add(TEXT("near_E_opens_door"), EAction::Interact, 1.05f, ECheck::OpenAndUsable);
	Setup(TEXT("setup_to_walk_through_open_door"), FVector(280, 0, 98), FRotator::ZeroRotator);
	Add(TEXT("open_door_allows_actual_W_passage"), EAction::HoldKey, 1.45f, ECheck::PassedDoor, EKeys::W);
	Setup(TEXT("setup_outside_to_close"), FVector(600, 0, 98), FRotator(0, 180, 0), true);
	Add(TEXT("outside_E_closes_door"), EAction::Interact, 1.05f, ECheck::ClosedState);
	Setup(TEXT("setup_outside_closed_door"), FVector(620, 0, 98), FRotator(0, 180, 0));
	Add(TEXT("reclosed_door_blocks_actual_W_movement"), EAction::HoldKey, 1.15f, ECheck::ClosedOutside, EKeys::W);
	Setup(TEXT("setup_far_from_door"), FVector(-150, 0, 98), FRotator::ZeroRotator, true);
	Add(TEXT("far_E_does_not_open_door"), EAction::Interact, 0.9f, ECheck::FarRejected);
	Setup(TEXT("setup_open_for_wall_occlusion"), FVector(280, 0, 98), FRotator::ZeroRotator, true);
	Add(TEXT("E_opens_for_occlusion_setup"), EAction::Interact, 1.05f, ECheck::OpenAndUsable);
	Setup(TEXT("setup_close_but_behind_jamb_wall"), FVector(330, -230, 98), FRotator::ZeroRotator, true);
	Add(TEXT("wall_occluded_E_does_not_close_door"), EAction::Interact, 0.9f, ECheck::WallRejected);
	Setup(TEXT("setup_close_after_occlusion"), FVector(280, 0, 98), FRotator::ZeroRotator, true);
	Add(TEXT("E_closes_after_occlusion_test"), EAction::Interact, 1.05f, ECheck::ClosedState);
	Setup(TEXT("setup_open_for_player_clearance"), FVector(280, 0, 98), FRotator::ZeroRotator, true);
	Add(TEXT("E_opens_for_player_clearance_setup"), EAction::Interact, 1.05f, ECheck::OpenAndUsable);
	Setup(TEXT("setup_player_in_closing_arc"), FVector(450, -10, 98), FRotator::ZeroRotator, true);
	Add(TEXT("E_close_pauses_before_hitting_stationary_player"), EAction::Interact, 0.8f, ECheck::ClosingPausesAtPlayer);
	Setup(TEXT("setup_same_position_aim_away_from_closing_door"), FVector(450, -10, 98), FRotator::ZeroRotator);
	Add(TEXT("W_walks_clear_and_door_resumes_closing"), EAction::HoldKey, 1.3f, ECheck::ClosingResumesAfterWalkingAway, EKeys::W);
	for (int32 Cycle = 1; Cycle <= 10; ++Cycle)
	{
		Setup(*FString::Printf(TEXT("cycle_%02d_prepare_open"), Cycle), FVector(280, 0, 98), FRotator::ZeroRotator, true);
		Add(*FString::Printf(TEXT("cycle_%02d_E_open"), Cycle), EAction::Interact, 1.05f, ECheck::OpenAndUsable);
		Setup(*FString::Printf(TEXT("cycle_%02d_prepare_close"), Cycle), FVector(280, 0, 98), FRotator::ZeroRotator, true);
		Add(*FString::Printf(TEXT("cycle_%02d_E_close"), Cycle), EAction::Interact, 1.05f, ECheck::ClosedState);
	}
	Setup(TEXT("setup_for_ten_rapid_E_inputs"), FVector(280, 0, 98), FRotator::ZeroRotator, true);
	Add(TEXT("ten_rapid_E_inputs_leave_consistent_closed_door"), EAction::RapidInteract, 2.3f, ECheck::RapidClosed);
	Setup(TEXT("setup_for_final_closed_collision"), FVector(180, 0, 98), FRotator::ZeroRotator);
	Add(TEXT("door_still_blocks_after_rapid_E"), EAction::HoldKey, 1.15f, ECheck::ClosedInside, EKeys::W);
	Setup(TEXT("setup_for_final_open"), FVector(280, 0, 98), FRotator::ZeroRotator, true);
	Add(TEXT("E_still_opens_after_repetition"), EAction::Interact, 1.05f, ECheck::OpenAndUsable);
	Setup(TEXT("setup_for_final_passage"), FVector(280, 0, 98), FRotator::ZeroRotator);
	Add(TEXT("door_still_passable_after_repetition"), EAction::HoldKey, 1.45f, ECheck::PassedDoor, EKeys::W);
	Add(TEXT("allow_final_capture_to_finish"), EAction::Wait, 1.2f);
}

void AAgentTestRunner::SendKey(const FKey& Key, EInputEvent Event, float Amount)
{
	const bool bHandled = Controller->InputKey(FInputKeyEventArgs::CreateSimulated(Key, Event, Amount));
	TSharedPtr<FJsonObject> Entry = MakeShared<FJsonObject>();
	Entry->SetNumberField(TEXT("time_seconds"), TotalElapsed);
	Entry->SetStringField(TEXT("key"), Key.ToString());
	Entry->SetStringField(TEXT("event"), Event == IE_Pressed ? TEXT("pressed") : Event == IE_Released ? TEXT("released") : TEXT("axis"));
	Entry->SetNumberField(TEXT("amount"), Amount);
	Entry->SetBoolField(TEXT("controller_returned_handled"), bHandled);
	Entry->SetStringField(TEXT("step"), Steps.IsValidIndex(StepIndex) ? Steps[StepIndex].Name : TEXT("startup"));
	InputEvents.Add(Entry);
}

void AAgentTestRunner::PressE()
{
	SendKey(EKeys::E, IE_Pressed, 1.f);
	bEPressed = true;
	EReleaseAt = TotalElapsed + 0.045f;
}

void AAgentTestRunner::AimAtDoor()
{
	FVector Eye; FRotator Ignored;
	Player->GetActorEyesViewPoint(Eye, Ignored);
	Controller->SetControlRotation((Door->GetPanelCenter() - Eye).Rotation());
}

void AAgentTestRunner::EnterStep()
{
	Elapsed = 0.f;
	const FStep& Step = Steps[StepIndex];
	if (Step.Action == EAction::Setup)
	{
		Player->GetCharacterMovement()->StopMovementImmediately();
		Player->SetActorLocation(Step.Position, false, nullptr, ETeleportType::TeleportPhysics);
		Controller->SetControlRotation(Step.Rotation);
		if (Step.bAimAtDoor) AimAtDoor();
		TSharedPtr<FJsonObject> Entry = MakeShared<FJsonObject>();
		Entry->SetStringField(TEXT("name"), Step.Name);
		Entry->SetStringField(TEXT("method"), TEXT("test setup teleport and view aim; not counted as movement or interaction evidence"));
		Entry->SetObjectField(TEXT("position"), VectorJson(Step.Position));
		Entry->SetBoolField(TEXT("aim_at_panel"), Step.bAimAtDoor);
		Entry->SetNumberField(TEXT("time_seconds"), TotalElapsed);
		Setups.Add(Entry);
	}
	StartPosition = Player->GetActorLocation();
	StartRotation = Controller->GetControlRotation();
	MouseSampleCount = 0;
	LastMouseSampleAt = -1.f;
	if (Step.Action == EAction::HoldKey) SendKey(Step.Key, IE_Pressed, 1.f);
	if (Step.Action == EAction::Interact) PressE();
	if (Step.Action == EAction::RapidInteract)
	{
		RapidPressCount = 0;
		NextRapidPressAt = TotalElapsed;
	}
	UE_LOG(LogTemp, Display, TEXT("AGENT_TEST STEP %s"), *Step.Name);
}

void AAgentTestRunner::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);
	if (bFinished) return;
	TotalElapsed += DeltaSeconds;
	if (!Player || !Controller || !Door)
	{
		Controller = UGameplayStatics::GetPlayerController(GetWorld(), 0);
		Player = Controller ? Cast<AAgentCharacter>(Controller->GetPawn()) : nullptr;
		TActorIterator<AAgentDoor> DoorIterator(GetWorld());
		if (DoorIterator) Door = *DoorIterator;
		if (!Player || !Controller || !Door)
		{
			if (TotalElapsed > 15.f)
			{
				Record(TEXT("startup"), false, TEXT("Player controller, possessed player, or door not found within 15 seconds."));
				Finish();
			}
			return;
		}
		BuildSteps();
		StepIndex = 0;
		EnterStep();
	}
	if (Player->GetActorLocation().Z < 85.f) bEverBelowFloor = true;
	if (bEPressed && TotalElapsed >= EReleaseAt)
	{
		SendKey(EKeys::E, IE_Released, 0.f);
		bEPressed = false;
	}
	if (bWaitingToAdvance)
	{
		CaptureWaitRemaining -= DeltaSeconds;
		if (CaptureWaitRemaining <= 0.f)
		{
			bWaitingToAdvance = false;
			++StepIndex;
			if (StepIndex >= Steps.Num()) Finish();
			else EnterStep();
		}
		return;
	}
	Elapsed += DeltaSeconds;
	const FStep& Step = Steps[StepIndex];
	const bool bMouseStep = Step.Action == EAction::MouseYaw || Step.Action == EAction::MousePitch;
	if (bMouseStep && MouseSampleCount < 12)
	{
		SendKey(Step.Action == EAction::MouseYaw ? EKeys::MouseX : EKeys::MouseY, IE_Axis, 4.0f);
		++MouseSampleCount;
		LastMouseSampleAt = TotalElapsed;
	}
	if (Step.Action == EAction::RapidInteract && RapidPressCount < 10 && !bEPressed && TotalElapsed >= NextRapidPressAt)
	{
		AimAtDoor();
		PressE();
		++RapidPressCount;
		NextRapidPressAt = TotalElapsed + 0.10f;
	}
	// A timed-only mouse step can submit too few samples during expensive
	// rendered frames. Deliver a fixed count, then allow the controller to
	// consume the final queued input on later ticks before measuring rotation.
	const bool bMouseInputConsumed = !bMouseStep ||
		(MouseSampleCount >= 12 && LastMouseSampleAt >= 0.f && TotalElapsed - LastMouseSampleAt >= 0.1f);
	if (Elapsed >= Step.Duration && bMouseInputConsumed)
	{
		FinishStep();
		if (CaptureWaitRemaining > 0.f) bWaitingToAdvance = true;
		else
		{
			++StepIndex;
			if (StepIndex >= Steps.Num()) Finish();
			else EnterStep();
		}
	}
}

void AAgentTestRunner::FinishStep()
{
	const FStep& Step = Steps[StepIndex];
	if (Step.Action == EAction::HoldKey) SendKey(Step.Key, IE_Released, 0.f);
	if (Step.Check == ECheck::None)
	{
		if (Step.Name == TEXT("setup_outside_to_close")) RequestCapture(TEXT("open_door_close_prompt"));
		return;
	}
	const FVector P = Player->GetActorLocation();
	const FVector D = P - StartPosition;
	const FRotator RotationDelta = (Controller->GetControlRotation() - StartRotation).GetNormalized();
	const bool bFloor = P.Z >= 90.f && P.Z <= 105.f && Player->GetCharacterMovement()->IsMovingOnGround();
	const bool bOpen = Door->IsTargetOpen() && Door->IsFullyOpen();
	const bool bClosed = !Door->IsTargetOpen() && FMath::Abs(Door->GetDoorAngle()) <= 1.f;
	bool bPass = false;
	switch (Step.Check)
	{
	case ECheck::InitialState: bPass = bFloor && bClosed && FMath::Abs(P.X + 150.f) < 10.f && FMath::Abs(P.Y) < 10.f; break;
	case ECheck::Forward: bPass = D.X > 65.f && FMath::Abs(D.Y) < 10.f; break;
	case ECheck::Backward: bPass = D.X < -65.f && FMath::Abs(D.Y) < 10.f; break;
	case ECheck::Right: bPass = D.Y > 65.f && FMath::Abs(D.X) < 15.f; break;
	case ECheck::Left: bPass = D.Y < -65.f && FMath::Abs(D.X) < 15.f; break;
	case ECheck::Yaw: bPass = FMath::Abs(RotationDelta.Yaw) > 5.f; break;
	case ECheck::Pitch: bPass = FMath::Abs(RotationDelta.Pitch) > 5.f; break;
	case ECheck::WallAndFloor: bPass = P.X > 320.f && P.X < 375.f && FMath::Abs(P.Y - 250.f) < 10.f && bFloor; break;
	case ECheck::SideWall: bPass = P.Y > 295.f && P.Y < 320.f && bFloor; break;
	case ECheck::ClosedInside: bPass = bClosed && P.X > 320.f && P.X < 370.f && bFloor; break;
	case ECheck::OpenAndUsable: bPass = bOpen; break;
	case ECheck::PassedDoor: bPass = bOpen && P.X > 590.f && P.X < 850.f && bFloor; break;
	case ECheck::ClosedOutside: bPass = bClosed && P.X > 425.f && P.X < 475.f && bFloor; break;
	case ECheck::ClosedState: bPass = bClosed; break;
	case ECheck::FarRejected: bPass = bClosed && Player->GetUsableDoor() == nullptr; break;
	case ECheck::WallRejected: bPass = bOpen && Player->GetUsableDoor() == nullptr && FVector::Dist(P, Door->GetPanelCenter()) < 250.f; break;
	case ECheck::RapidClosed: bPass = RapidPressCount == 10 && bClosed; break;
	case ECheck::ClosingPausesAtPlayer:
		bPass = !Door->IsTargetOpen() && Door->GetDoorAngle() > -99.f && Door->GetDoorAngle() < -1.f &&
			D.Size() < 2.f && bFloor && !bEverBelowFloor;
		break;
	case ECheck::ClosingResumesAfterWalkingAway:
		bPass = bClosed && P.X > 650.f && D.X > 200.f && bFloor && !bEverBelowFloor;
		break;
	default: break;
	}
	Record(Step.Name, bPass, FString::Printf(TEXT("start=%s; end=%s; displacement=%s; view_delta=%s; door_angle=%.2f; target_open=%d; grounded=%d; mouse_samples=%d"),
		*StartPosition.ToCompactString(), *P.ToCompactString(), *D.ToCompactString(), *RotationDelta.ToCompactString(), Door->GetDoorAngle(), Door->IsTargetOpen(), bFloor, MouseSampleCount));
	if (Step.Name == TEXT("initial_spawn_and_closed_door") || Step.Name == TEXT("closed_door_blocks_actual_W_movement") ||
		Step.Name == TEXT("near_E_opens_door") || Step.Name == TEXT("open_door_allows_actual_W_passage") ||
		Step.Name == TEXT("outside_E_closes_door") || Step.Name == TEXT("far_E_does_not_open_door") ||
		Step.Name == TEXT("ten_rapid_E_inputs_leave_consistent_closed_door") || Step.Name == TEXT("door_still_passable_after_repetition"))
		RequestCapture(Step.Name);
}

void AAgentTestRunner::RequestCapture(const FString& Name)
{
	if (!bCapture || GUsingNullRHI || !FApp::CanEverRender()) return;
	const FString Directory = FPaths::ConvertRelativePathToFull(FPaths::Combine(FPaths::ProjectDir(), TEXT("Evidence/screenshots")));
	IFileManager::Get().MakeDirectory(*Directory, true);
	const FString Path = FPaths::Combine(Directory, Name + TEXT(".png"));
	ScreenshotRequests.Add(Path);
	FScreenshotRequest::RequestScreenshot(Path, false, false);
	// Preserve this actual checkpoint for rendered frames before the next setup
	// can teleport or re-aim the player. The screenshot is asynchronous.
	CaptureWaitRemaining = 0.20f;
	UE_LOG(LogTemp, Display, TEXT("AGENT_TEST SCREENSHOT_REQUEST %s"), *Path);
}

void AAgentTestRunner::Record(const FString& Name, bool bPass, const FString& Detail)
{
	if (!bPass) ++FailureCount;
	TSharedPtr<FJsonObject> Entry = MakeShared<FJsonObject>();
	Entry->SetStringField(TEXT("name"), Name);
	Entry->SetBoolField(TEXT("pass"), bPass);
	Entry->SetStringField(TEXT("detail"), Detail);
	Entry->SetNumberField(TEXT("time_seconds"), TotalElapsed);
	if (Steps.IsValidIndex(StepIndex) &&
		(Steps[StepIndex].Action == EAction::MouseYaw || Steps[StepIndex].Action == EAction::MousePitch))
	{
		Entry->SetNumberField(TEXT("mouse_input_samples"), MouseSampleCount);
		Entry->SetNumberField(TEXT("seconds_since_final_mouse_sample"), TotalElapsed - LastMouseSampleAt);
	}
	if (Player)
	{
		Entry->SetObjectField(TEXT("position"), VectorJson(Player->GetActorLocation()));
		Entry->SetObjectField(TEXT("start_position"), VectorJson(StartPosition));
	}
	if (Door)
	{
		Entry->SetNumberField(TEXT("door_angle"), Door->GetDoorAngle());
		Entry->SetBoolField(TEXT("target_open"), Door->IsTargetOpen());
	}
	Results.Add(Entry);
	UE_LOG(LogTemp, Display, TEXT("AGENT_TEST %s %s: %s"), bPass ? TEXT("PASS") : TEXT("FAIL"), *Name, *Detail);
}

void AAgentTestRunner::Finish()
{
	if (bFinished) return;
	bFinished = true;
	if (Controller && bEPressed) { SendKey(EKeys::E, IE_Released, 0.f); bEPressed = false; }
	Record(TEXT("never_fell_below_floor_during_runtime"), !bEverBelowFloor, TEXT("Every runner tick monitored player center Z; threshold 85 cm for 96 cm capsule half height."));
	TSharedPtr<FJsonObject> Root = MakeShared<FJsonObject>();
	Root->SetStringField(TEXT("verification_mode"), TEXT("Unreal running game world; simulated keyboard/mouse events injected into actual PlayerController InputKey path. No door Toggle call or state write in test runner."));
	Root->SetStringField(TEXT("visual_verification"), TEXT("Not performed by this runtime runner. These results do not prove displayed pixels or OS-level input delivery."));
	Root->SetStringField(TEXT("setup_disclosure"), TEXT("Test setup teleports and view aiming are logged separately; movement and interaction outcomes use runtime input, collision and ticking."));
	Root->SetStringField(TEXT("utc_time"), FDateTime::UtcNow().ToIso8601());
	Root->SetStringField(TEXT("engine_version"), FEngineVersion::Current().ToString());
	Root->SetStringField(TEXT("command_line"), FCommandLine::Get());
	Root->SetNumberField(TEXT("world_type"), static_cast<int32>(GetWorld()->WorldType));
	Root->SetBoolField(TEXT("is_play_in_editor"), GetWorld()->IsPlayInEditor());
	Root->SetBoolField(TEXT("null_rhi"), GUsingNullRHI);
	Root->SetBoolField(TEXT("can_ever_render"), FApp::CanEverRender());
	Root->SetBoolField(TEXT("capture_requested"), bCapture);
	TArray<TSharedPtr<FJsonValue>> ScreenshotEntries;
	for (const FString& Path : ScreenshotRequests)
	{
		TSharedPtr<FJsonObject> Entry = MakeShared<FJsonObject>();
		Entry->SetStringField(TEXT("path"), Path);
		Entry->SetBoolField(TEXT("file_exists_at_report_time"), IFileManager::Get().FileExists(*Path));
		ScreenshotEntries.Add(MakeShared<FJsonValueObject>(Entry));
	}
	Root->SetArrayField(TEXT("screenshot_requests"), ScreenshotEntries);
	Root->SetNumberField(TEXT("duration_game_seconds"), TotalElapsed);
	Root->SetNumberField(TEXT("assertions"), Results.Num());
	Root->SetNumberField(TEXT("failures"), FailureCount);
	Root->SetBoolField(TEXT("all_passed"), FailureCount == 0);
	Root->SetArrayField(TEXT("results"), ObjectsAsValues(Results));
	Root->SetArrayField(TEXT("input_events"), ObjectsAsValues(InputEvents));
	Root->SetArrayField(TEXT("setup_events"), ObjectsAsValues(Setups));
	FString Json;
	TSharedRef<TJsonWriter<>> Writer = TJsonWriterFactory<>::Create(&Json);
	FJsonSerializer::Serialize(Root.ToSharedRef(), Writer);
	const FString Directory = FPaths::Combine(FPaths::ProjectDir(), TEXT("Evidence"));
	IFileManager::Get().MakeDirectory(*Directory, true);
	const FString TimestampPath = FPaths::Combine(Directory, FString::Printf(TEXT("runtime_%s.json"), *FDateTime::UtcNow().ToString(TEXT("%Y%m%d_%H%M%S"))));
	const bool bSaved = FFileHelper::SaveStringToFile(Json, *TimestampPath, FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM);
	FFileHelper::SaveStringToFile(Json, *FPaths::Combine(Directory, TEXT("runtime_results.json")), FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM);
	UE_LOG(LogTemp, Display, TEXT("AGENT_TEST COMPLETE assertions=%d failures=%d saved=%d path=%s"), Results.Num(), FailureCount, bSaved, *TimestampPath);
	const int32 ExitCode = FailureCount == 0 && bSaved ? 0 : 1;
	if (!FinishAgentEditorTest(ExitCode))
		FPlatformMisc::RequestExitWithStatus(false, ExitCode);
}
