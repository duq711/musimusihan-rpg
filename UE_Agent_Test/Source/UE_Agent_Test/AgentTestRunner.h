#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "InputCoreTypes.h"
#include "AgentTestRunner.generated.h"

class AAgentCharacter;
class AAgentDoor;
class APlayerController;
class FJsonObject;

/** Runtime acceptance checks use the same player-controller key path as gameplay. */
UCLASS()
class UE_AGENT_TEST_API AAgentTestRunner : public AActor
{
	GENERATED_BODY()
public:
	AAgentTestRunner();
	virtual void Tick(float DeltaSeconds) override;

private:
	enum class EAction : uint8 { Wait, Setup, HoldKey, MouseYaw, MousePitch, Interact, RapidInteract };
	enum class ECheck : uint8
	{
		None, InitialState, Forward, Backward, Right, Left, Yaw, Pitch,
		WallAndFloor, SideWall, ClosedInside, OpenAndUsable, PassedDoor,
		ClosedOutside, ClosedState, FarRejected, WallRejected, RapidClosed,
		ClosingPausesAtPlayer, ClosingResumesAfterWalkingAway
	};
	struct FStep
	{
		FString Name;
		EAction Action = EAction::Wait;
		ECheck Check = ECheck::None;
		float Duration = 0.2f;
		FVector Position = FVector::ZeroVector;
		FRotator Rotation = FRotator::ZeroRotator;
		FKey Key;
		bool bAimAtDoor = false;
	};

	UPROPERTY() TObjectPtr<AAgentCharacter> Player;
	UPROPERTY() TObjectPtr<AAgentDoor> Door;
	UPROPERTY() TObjectPtr<APlayerController> Controller;
	TArray<FStep> Steps;
	TArray<TSharedPtr<FJsonObject>> Results;
	TArray<TSharedPtr<FJsonObject>> InputEvents;
	TArray<TSharedPtr<FJsonObject>> Setups;
	TArray<FString> ScreenshotRequests;
	int32 StepIndex = -1;
	int32 FailureCount = 0;
	int32 RapidPressCount = 0;
	int32 MouseSampleCount = 0;
	float Elapsed = 0.f;
	float TotalElapsed = 0.f;
	float EReleaseAt = 0.f;
	float NextRapidPressAt = 0.f;
	float CaptureWaitRemaining = 0.f;
	float LastMouseSampleAt = -1.f;
	bool bEPressed = false;
	bool bFinished = false;
	bool bEverBelowFloor = false;
	bool bCapture = false;
	bool bWaitingToAdvance = false;
	FVector StartPosition;
	FRotator StartRotation;

	void BuildSteps();
	void EnterStep();
	void FinishStep();
	void SendKey(const FKey& Key, EInputEvent Event, float Amount);
	void PressE();
	void AimAtDoor();
	void Record(const FString& Name, bool bPass, const FString& Detail);
	void RequestCapture(const FString& Name);
	void Finish();
};
