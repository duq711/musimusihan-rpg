using UnrealBuildTool;
public class UE_Agent_TestTarget : TargetRules
{
    public UE_Agent_TestTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Game;
        DefaultBuildSettings = BuildSettingsVersion.V7;
        IncludeOrderVersion = EngineIncludeOrderVersion.Unreal5_8;
        ExtraModuleNames.Add("UE_Agent_Test");
    }
}
