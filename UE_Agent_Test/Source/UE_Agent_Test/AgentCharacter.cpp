#include "AgentCharacter.h"
#include "AgentDoor.h"
#include "Camera/CameraComponent.h"
#include "Components/CapsuleComponent.h"
#include "Components/InputComponent.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "Engine/World.h"

AAgentCharacter::AAgentCharacter()
{
    GetCapsuleComponent()->InitCapsuleSize(34.f, 96.f);
    GetCharacterMovement()->MaxWalkSpeed = 280.f;
    GetCharacterMovement()->BrakingDecelerationWalking = 2048.f;
    GetCharacterMovement()->bOrientRotationToMovement = false;
    GetCharacterMovement()->MaxStepHeight = 30.f;
    bUseControllerRotationYaw = true;
    Camera = CreateDefaultSubobject<UCameraComponent>(TEXT("FirstPersonCamera"));
    Camera->SetupAttachment(GetCapsuleComponent());
    Camera->SetRelativeLocation(FVector(0, 0, 64));
    Camera->bUsePawnControlRotation = true;
    Camera->FieldOfView = 85.f;
}
void AAgentCharacter::SetupPlayerInputComponent(UInputComponent* Input)
{
    Super::SetupPlayerInputComponent(Input);
    Input->BindAxis(TEXT("MoveForward"), this, &AAgentCharacter::Forward);
    Input->BindAxis(TEXT("MoveRight"), this, &AAgentCharacter::Right);
    Input->BindAxis(TEXT("Turn"), this, &AAgentCharacter::Turn);
    Input->BindAxis(TEXT("Look"), this, &AAgentCharacter::Look);
    Input->BindAction(TEXT("Interact"), IE_Pressed, this, &AAgentCharacter::Interact);
}
void AAgentCharacter::Forward(float Value)
{
    if (Controller) AddMovementInput(FRotationMatrix(FRotator(0, Controller->GetControlRotation().Yaw, 0)).GetUnitAxis(EAxis::X), Value);
}
void AAgentCharacter::Right(float Value)
{
    if (Controller) AddMovementInput(FRotationMatrix(FRotator(0, Controller->GetControlRotation().Yaw, 0)).GetUnitAxis(EAxis::Y), Value);
}
void AAgentCharacter::Turn(float Value) { AddControllerYawInput(Value); }
void AAgentCharacter::Look(float Value) { AddControllerPitchInput(Value); }
AAgentDoor* AAgentCharacter::GetUsableDoor() const
{
    if (!Controller || !GetWorld()) return nullptr;
    FVector Eye; FRotator Rotation;
    Controller->GetPlayerViewPoint(Eye, Rotation);
    FHitResult Hit;
    FCollisionQueryParams Params(SCENE_QUERY_STAT(AgentDoorSight), false, this);
    if (GetWorld()->LineTraceSingleByChannel(Hit, Eye, Eye + Rotation.Vector() * 250.f, ECC_Visibility, Params))
        return Cast<AAgentDoor>(Hit.GetActor());
    return nullptr;
}
void AAgentCharacter::Interact()
{
    if (AAgentDoor* Door = GetUsableDoor())
    {
        Door->Toggle();
        UE_LOG(LogTemp, Display, TEXT("AGENT_INPUT E accepted; target=%s; player=%s"), Door->IsTargetOpen() ? TEXT("open") : TEXT("closed"), *GetActorLocation().ToString());
    }
    else UE_LOG(LogTemp, Display, TEXT("AGENT_INPUT E rejected; no nearby visible door"));
}
