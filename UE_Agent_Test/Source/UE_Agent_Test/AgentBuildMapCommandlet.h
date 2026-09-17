#pragma once
#include "CoreMinimal.h"
#include "Commandlets/Commandlet.h"
#include "AgentBuildMapCommandlet.generated.h"
UCLASS()
class UE_AGENT_TEST_API UAgentBuildMapCommandlet : public UCommandlet
{
    GENERATED_BODY()
public:
    UAgentBuildMapCommandlet();
    virtual int32 Main(const FString& Params) override;
};
