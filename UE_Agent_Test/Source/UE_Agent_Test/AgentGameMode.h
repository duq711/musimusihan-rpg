#pragma once
#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "AgentGameMode.generated.h"
UCLASS()
class UE_AGENT_TEST_API AAgentGameMode : public AGameModeBase
{
    GENERATED_BODY()
public:
    AAgentGameMode();
    virtual void BeginPlay() override;
};
