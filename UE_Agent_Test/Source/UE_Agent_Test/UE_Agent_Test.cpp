#include "Modules/ModuleManager.h"
#include "AgentEditorBridge.h"
class FAgentGameModule : public FDefaultGameModuleImpl
{
public:
    virtual void StartupModule() override { StartAgentEditorBridge(); }
};
IMPLEMENT_PRIMARY_GAME_MODULE(FAgentGameModule, UE_Agent_Test, "UE_Agent_Test");
