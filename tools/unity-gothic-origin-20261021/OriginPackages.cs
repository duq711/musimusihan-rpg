using System;
using System.IO;
using UnityEditor;
using UnityEditor.PackageManager;
using UnityEditor.PackageManager.Requests;

[InitializeOnLoad]
public static class OriginPackages
{
    static AddAndRemoveRequest request;
    static OriginPackages(){if(SessionState.GetBool("OriginPackagesPending",false))EditorApplication.update+=PollAfterReload;}
    public static void Install()
    {
        SessionState.SetBool("OriginPackagesPending",true);
        request=Client.AddAndRemove(new[]{"com.unity.cloud.gltfast@6.20.0","com.unity.nuget.newtonsoft-json@3.2.2"},new[]{"com.unity.collab-proxy","com.unity.feature.development","com.unity.ide.rider","com.unity.ide.visualstudio","com.unity.inputsystem","com.unity.timeline","com.unity.visualscripting"});
        EditorApplication.update+=Poll;
    }
    static void Poll()
    {
        if(request==null||!request.IsCompleted)return;
        if(request.Status==StatusCode.Failure){UnityEngine.Debug.LogError(request.Error.message);EditorApplication.Exit(1);return;}
        Finish();
    }
    static void PollAfterReload()
    {
        if(EditorApplication.isCompiling||EditorApplication.isUpdating)return;
        var manifest=File.ReadAllText("Packages/manifest.json");
        if(manifest.Contains("com.unity.cloud.gltfast")&&manifest.Contains("com.unity.nuget.newtonsoft-json"))Finish();
    }
    static void Finish(){SessionState.SetBool("OriginPackagesPending",false);UnityEngine.Debug.Log("ORIGIN_PACKAGES_READY");EditorApplication.Exit(0);}
}
