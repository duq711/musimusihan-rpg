#include "AgentBuildMapCommandlet.h"
#if WITH_EDITOR
#include "FileHelpers.h"
#include "Editor.h"
#include "Engine/World.h"
#include "GameFramework/PlayerStart.h"
#include "GameFramework/WorldSettings.h"
#include "AgentRoom.h"
#include "AgentDoor.h"
#include "AgentGameMode.h"
#endif
UAgentBuildMapCommandlet::UAgentBuildMapCommandlet()
{
    IsClient=false; IsServer=false; IsEditor=true; LogToConsole=true;
}
int32 UAgentBuildMapCommandlet::Main(const FString& Params)
{
#if WITH_EDITOR
    UWorld* World=UEditorLoadingAndSavingUtils::NewBlankMap(false);
    if (!World) return 1;
    World->SpawnActor<AAgentRoom>()->SetActorLabel(TEXT("Test room and outside landing"));
    World->SpawnActor<AAgentDoor>(FVector(400,-80,0),FRotator::ZeroRotator)->SetActorLabel(TEXT("E interaction hinged door"));
    World->SpawnActor<APlayerStart>(FVector(-150,0,98),FRotator::ZeroRotator)->SetActorLabel(TEXT("Safe first person start"));
    World->GetWorldSettings()->DefaultGameMode=AAgentGameMode::StaticClass();
    const bool Saved=UEditorLoadingAndSavingUtils::SaveMap(World,TEXT("/Game/Maps/TestRoom"));
    UE_LOG(LogTemp,Display,TEXT("AGENT_MAP_SAVE %s"),Saved?TEXT("PASS"):TEXT("FAIL"));
    return Saved?0:1;
#else
    return 1;
#endif
}
