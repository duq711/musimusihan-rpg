#include "AgentRoom.h"
#include "Components/SceneComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Components/PointLightComponent.h"
#include "Components/TextRenderComponent.h"
#include "UObject/ConstructorHelpers.h"
#include "Engine/StaticMesh.h"
AAgentRoom::AAgentRoom()
{
    RootComponent = CreateDefaultSubobject<USceneComponent>(TEXT("RoomRoot"));
    RootComponent->SetMobility(EComponentMobility::Static);
    static ConstructorHelpers::FObjectFinder<UStaticMesh> Cube(TEXT("/Engine/BasicShapes/Cube.Cube"));
    auto Box = [&](const TCHAR* Name, FVector Position, FVector Size)
    {
        auto* Mesh = CreateDefaultSubobject<UStaticMeshComponent>(Name);
        Mesh->SetupAttachment(RootComponent);
        Mesh->SetStaticMesh(Cube.Object);
        Mesh->SetRelativeLocation(Position);
        Mesh->SetRelativeScale3D(Size / 100.f);
        Mesh->SetCollisionProfileName(TEXT("BlockAll"));
        Mesh->SetMobility(EComponentMobility::Static);
    };
    Box(TEXT("Floor"), FVector(0,0,-10), FVector(840,740,20));
    Box(TEXT("Ceiling"), FVector(0,0,310), FVector(840,740,20));
    Box(TEXT("WestWall"), FVector(-410,0,150), FVector(20,740,300));
    Box(TEXT("NorthWall"), FVector(0,-360,150), FVector(840,20,300));
    Box(TEXT("SouthWall"), FVector(0,360,150), FVector(840,20,300));
    Box(TEXT("DoorWallNorth"), FVector(410,-225,150), FVector(20,270,300));
    Box(TEXT("DoorWallSouth"), FVector(410,225,150), FVector(20,270,300));
    Box(TEXT("DoorLintel"), FVector(410,0,270), FVector(20,180,60));
    Box(TEXT("OutsideFloor"), FVector(710,0,-10), FVector(620,740,20));
    Box(TEXT("OutsideEnd"), FVector(1010,0,100), FVector(20,740,200));
    Box(TEXT("OutsideNorth"), FVector(710,-360,100), FVector(620,20,200));
    Box(TEXT("OutsideSouth"), FVector(710,360,100), FVector(620,20,200));
    Box(TEXT("FrameNorth"), FVector(394,-96,122), FVector(24,12,244));
    Box(TEXT("FrameSouth"), FVector(394,96,122), FVector(24,12,244));
    Box(TEXT("FrameTop"), FVector(394,0,250), FVector(24,204,12));
    auto Light = [&](const TCHAR* Name, FVector Position, FLinearColor Color, float Intensity)
    {
        auto* L = CreateDefaultSubobject<UPointLightComponent>(Name);
        L->SetupAttachment(RootComponent);
        L->SetRelativeLocation(Position);
        L->SetMobility(EComponentMobility::Movable);
        L->SetLightColor(Color);
        L->SetIntensity(Intensity);
        L->SetAttenuationRadius(1300.f);
        L->SetCastShadows(true);
    };
    Light(TEXT("RoomLight"), FVector(-120,0,250), FLinearColor(1.f,.88f,.68f), 12000.f);
    Light(TEXT("DoorLight"), FVector(240,0,270), FLinearColor(1.f,.95f,.85f), 5000.f);
    Light(TEXT("OutsideLight"), FVector(690,0,280), FLinearColor(.6f,.8f,1.f), 10000.f);
    auto* Sign=CreateDefaultSubobject<UTextRenderComponent>(TEXT("ExitSign"));
    Sign->SetupAttachment(RootComponent);
    Sign->SetRelativeLocation(FVector(385,0,274));
    Sign->SetRelativeRotation(FRotator(0,180,0));
    Sign->SetHorizontalAlignment(EHTA_Center);
    Sign->SetText(FText::FromString(TEXT("EXIT")));
    Sign->SetTextRenderColor(FColor(60,200,100));
    Sign->SetWorldSize(22);
}
