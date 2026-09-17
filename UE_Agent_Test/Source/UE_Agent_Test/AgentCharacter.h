#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Character.h"
#include "AgentCharacter.generated.h"
class UCameraComponent;
class AAgentDoor;
UCLASS()
class UE_AGENT_TEST_API AAgentCharacter : public ACharacter
{
    GENERATED_BODY()
public:
    AAgentCharacter();
    virtual void SetupPlayerInputComponent(UInputComponent* Input) override;
    AAgentDoor* GetUsableDoor() const;
    UPROPERTY(VisibleAnywhere) TObjectPtr<UCameraComponent> Camera;
private:
    void Forward(float Value);
    void Right(float Value);
    void Turn(float Value);
    void Look(float Value);
    void Interact();
};
