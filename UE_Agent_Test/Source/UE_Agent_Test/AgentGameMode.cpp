#include "AgentGameMode.h"
#include "AgentCharacter.h"
#include "AgentHUD.h"
#include "AgentTestRunner.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "Engine/World.h"
AAgentGameMode::AAgentGameMode()
{
    DefaultPawnClass=AAgentCharacter::StaticClass();
    HUDClass=AAgentHUD::StaticClass();
}
void AAgentGameMode::BeginPlay()
{
    Super::BeginPlay();
    if (FParse::Param(FCommandLine::Get(),TEXT("AgentAutoTest")))
        GetWorld()->SpawnActor<AAgentTestRunner>();
}
