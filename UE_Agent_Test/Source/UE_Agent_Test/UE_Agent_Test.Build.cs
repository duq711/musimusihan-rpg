using UnrealBuildTool;
public class UE_Agent_Test : ModuleRules
{
    public UE_Agent_Test(ReadOnlyTargetRules Target) : base(Target)
    {
        PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
        PublicDependencyModuleNames.AddRange(new string[] { "Core", "CoreUObject", "Engine", "InputCore", "PhysicsCore", "Json", "JsonUtilities", "RHI" });
        if (Target.bBuildEditor) PrivateDependencyModuleNames.Add("UnrealEd");
    }
}
