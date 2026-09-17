using UnrealBuildTool;
public class UE_Agent_TestEditorTarget : TargetRules
{
    public UE_Agent_TestEditorTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Editor;
        DefaultBuildSettings = BuildSettingsVersion.V7;
        IncludeOrderVersion = EngineIncludeOrderVersion.Unreal5_8;
        ExtraModuleNames.Add("UE_Agent_Test");
    }
}
