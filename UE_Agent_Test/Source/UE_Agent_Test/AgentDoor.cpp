#include "AgentDoor.h"

#include "CollisionQueryParams.h"
#include "CollisionShape.h"
#include "Components/SceneComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Engine/OverlapResult.h"
#include "Engine/StaticMesh.h"
#include "Engine/World.h"
#include "GameFramework/Pawn.h"
#include "UObject/ConstructorHelpers.h"

AAgentDoor::AAgentDoor()
{
	PrimaryActorTick.bCanEverTick = true;

	Hinge = CreateDefaultSubobject<USceneComponent>(TEXT("Hinge"));
	SetRootComponent(Hinge);
	Hinge->SetMobility(EComponentMobility::Movable);

	Panel = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("DoorPanel"));
	Panel->SetupAttachment(Hinge);
	Panel->SetMobility(EComponentMobility::Movable);
	Panel->SetRelativeLocation(FVector(0.0, 80.0, 120.0));
	Panel->SetRelativeScale3D(FVector(0.12, 1.6, 2.4));
	Panel->SetCollisionEnabled(ECollisionEnabled::QueryAndPhysics);
	Panel->SetCollisionObjectType(ECC_WorldDynamic);
	Panel->SetCollisionResponseToAllChannels(ECR_Block);
	Panel->SetGenerateOverlapEvents(false);
	Panel->SetCanEverAffectNavigation(false);

	static ConstructorHelpers::FObjectFinder<UStaticMesh> Cube(
		TEXT("/Engine/BasicShapes/Cube.Cube"));
	if (Cube.Succeeded())
	{
		Panel->SetStaticMesh(Cube.Object);
	}
}

void AAgentDoor::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);

	const float Goal = bTargetOpen ? OpenAngle : 0.0f;
	const float NextAngle = FMath::FInterpConstantTo(
		DoorAngle, Goal, DeltaSeconds, DegreesPerSecond);
	const float Distance = NextAngle - DoorAngle;
	if (FMath::IsNearlyZero(Distance))
	{
		return;
	}

	// Unreal does not sweep a rotation. Check the swept arc in steps of at most
	// one degree, including on a slow frame, before moving the solid panel.
	const int32 Steps = FMath::Max(1, FMath::CeilToInt(FMath::Abs(Distance)));
	const float StartAngle = DoorAngle;
	for (int32 Step = 1; Step <= Steps; ++Step)
	{
		const float CandidateAngle = StartAngle + Distance * float(Step) / float(Steps);
		if (WouldOverlapPawn(CandidateAngle))
		{
			// Keep the goal. The door resumes when the player moves clear, and a
			// new E press may reverse it immediately without a queued animation.
			break;
		}

		DoorAngle = CandidateAngle;
		SetActorRotation(FRotator(0.0f, DoorAngle, 0.0f));
	}
}

bool AAgentDoor::WouldOverlapPawn(float CandidateAngle) const
{
	const UWorld* World = GetWorld();
	if (!World || !Panel)
	{
		return false;
	}

	FTransform CandidateTransform = GetActorTransform();
	CandidateTransform.SetRotation(FRotator(0.0f, CandidateAngle, 0.0f).Quaternion());
	const FVector Center = CandidateTransform.TransformPosition(Panel->GetRelativeLocation());
	const FVector HalfSize = FVector(6.0, 80.0, 120.0)
		* CandidateTransform.GetScale3D().GetAbs() + FVector(0.5);

	FCollisionQueryParams Query(SCENE_QUERY_STAT(AgentDoorPawnClearance), false, this);
	const FCollisionObjectQueryParams Objects(ECC_Pawn);
	TArray<FOverlapResult> Overlaps;
	World->OverlapMultiByObjectType(Overlaps, Center, CandidateTransform.GetRotation(),
		Objects, FCollisionShape::MakeBox(HalfSize), Query);

	for (const FOverlapResult& Overlap : Overlaps)
	{
		if (Cast<APawn>(Overlap.GetActor()))
		{
			return true;
		}
	}
	return false;
}

void AAgentDoor::Toggle()
{
	bTargetOpen = !bTargetOpen;
}

bool AAgentDoor::IsTargetOpen() const
{
	return bTargetOpen;
}

bool AAgentDoor::IsFullyOpen() const
{
	return FMath::IsNearlyEqual(DoorAngle, OpenAngle, 0.1f);
}

float AAgentDoor::GetDoorAngle() const
{
	return DoorAngle;
}

FVector AAgentDoor::GetPanelCenter() const
{
	return Panel->GetComponentLocation();
}

UStaticMeshComponent* AAgentDoor::GetPanel() const
{
	return Panel.Get();
}
