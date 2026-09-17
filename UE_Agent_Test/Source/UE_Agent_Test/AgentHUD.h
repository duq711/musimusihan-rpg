#pragma once
#include "CoreMinimal.h"
#include "GameFramework/HUD.h"
#include "AgentHUD.generated.h"
UCLASS()
class UE_AGENT_TEST_API AAgentHUD : public AHUD
{
    GENERATED_BODY()
public:
    virtual void DrawHUD() override;
};
