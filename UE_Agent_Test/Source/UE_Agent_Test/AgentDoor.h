#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "AgentDoor.generated.h"

class USceneComponent;
class UStaticMeshComponent;

/** A solid door leaf whose actor origin is its lower hinge. */
UCLASS()
class UE_AGENT_TEST_API AAgentDoor : public AActor
{
	GENERATED_BODY()

public:
	AAgentDoor();
	virtual void Tick(float DeltaSeconds) override;

	void Toggle();
	bool IsTargetOpen() const;
	bool IsFullyOpen() const;
	float GetDoorAngle() const;
	FVector GetPanelCenter() const;
	UStaticMeshComponent* GetPanel() const;

private:
	bool WouldOverlapPawn(float CandidateAngle) const;

	UPROPERTY(VisibleAnywhere, Category = "Door")
	TObjectPtr<USceneComponent> Hinge;

	UPROPERTY(VisibleAnywhere, Category = "Door")
	TObjectPtr<UStaticMeshComponent> Panel;

	bool bTargetOpen = false;
	float DoorAngle = 0.0f;
	static constexpr float OpenAngle = -100.0f;
	static constexpr float DegreesPerSecond = 140.0f;
};
