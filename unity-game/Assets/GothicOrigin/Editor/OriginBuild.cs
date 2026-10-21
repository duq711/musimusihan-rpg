using System;
using System.IO;
using System.Linq;
using Newtonsoft.Json.Linq;
using TMPro;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.TextCore.LowLevel;

namespace MusimusihanRpg.GothicOrigin.Editor
{
    public static class OriginBuild
    {
        public const string ScenePath="Assets/GothicOrigin/OriginBoot.unity";
        static TMP_FontAsset Font(string source,string name,int size,string characters)
        {
            string path="Assets/GothicOrigin/Resources/"+name+".asset";var prior=AssetDatabase.LoadAssetAtPath<TMP_FontAsset>(path);if(prior!=null)return prior;
            var font=AssetDatabase.LoadAssetAtPath<UnityEngine.Font>("Assets/GothicOrigin/SourceFonts/"+source+".ttf");if(font==null)throw new FileNotFoundException(source);
            var asset=TMP_FontAsset.CreateFontAsset(font,size,7,GlyphRenderMode.SDFAA,2048,2048,AtlasPopulationMode.Dynamic,true);asset.name=name;AssetDatabase.CreateAsset(asset,path);
            asset.TryAddCharacters(characters,out string missing);if(!string.IsNullOrEmpty(missing))Debug.LogWarning(name+" unsupported glyphs: "+missing);
            AssetDatabase.AddObjectToAsset(asset.material,asset);foreach(var atlas in asset.atlasTextures)if(atlas!=null&&!AssetDatabase.Contains(atlas))AssetDatabase.AddObjectToAsset(atlas,asset);EditorUtility.SetDirty(asset);return asset;
        }
        [MenuItem("RPG/Gothic Origin/Prepare fresh native scene")]
        public static void Prepare()
        {
            PlayerSettings.companyName="Musimusihan";PlayerSettings.productName="Musimusihan Gothic Origin";PlayerSettings.bundleVersion="0.1.0";PlayerSettings.SetApplicationIdentifier(NamedBuildTarget.Standalone,"com.musimusihan.gothicorigin");PlayerSettings.SetScriptingBackend(NamedBuildTarget.Standalone,ScriptingImplementation.Mono2x);PlayerSettings.SetArchitecture(NamedBuildTarget.Standalone,1);PlayerSettings.defaultScreenWidth=1280;PlayerSettings.defaultScreenHeight=900;PlayerSettings.fullScreenMode=FullScreenMode.Windowed;PlayerSettings.runInBackground=true;PlayerSettings.enableFrameTimingStats=true;PlayerSettings.resizableWindow=true;PlayerSettings.usePlayerLog=true;
            var settings=new SerializedObject(AssetDatabase.LoadAllAssetsAtPath("ProjectSettings/ProjectSettings.asset")[0]);var handler=settings.FindProperty("activeInputHandler");if(handler!=null){handler.intValue=0;settings.ApplyModifiedPropertiesWithoutUndo();}
            QualitySettings.antiAliasing=2;QualitySettings.vSyncCount=0;QualitySettings.shadows=ShadowQuality.Disable;QualitySettings.pixelLightCount=0;QualitySettings.globalTextureMipmapLimit=0;
            var shaders=AssetDatabase.FindAssets("t:Shader",new[]{"Packages/com.unity.cloud.gltfast/Runtime/Shader/Built-In"}).Select(AssetDatabase.GUIDToAssetPath).Select(AssetDatabase.LoadAssetAtPath<Shader>).Where(s=>s!=null).ToList();shaders.Add(Shader.Find("Standard"));var graphics=new SerializedObject(AssetDatabase.LoadAllAssetsAtPath("ProjectSettings/GraphicsSettings.asset")[0]);var included=graphics.FindProperty("m_AlwaysIncludedShaders");for(int i=0;i<included.arraySize;i++)shaders.Add(included.GetArrayElementAtIndex(i).objectReferenceValue as Shader);shaders=shaders.Where(s=>s!=null).Distinct().ToList();included.arraySize=shaders.Count;for(int i=0;i<shaders.Count;i++)included.GetArrayElementAtIndex(i).objectReferenceValue=shaders[i];graphics.ApplyModifiedPropertiesWithoutUndo();
            var gltf=AssetDatabase.LoadAssetAtPath<Shader>("Packages/com.unity.cloud.gltfast/Runtime/Shader/Built-In/glTFUnlit.shader");if(gltf==null)throw new Exception("glTFast unlit shader missing");
            const string matPath="Assets/GothicOrigin/Resources/MapUnlit.mat";if(!File.Exists(matPath))AssetDatabase.CreateAsset(new Material(gltf),matPath);
            string characters=string.Join("",Directory.GetFiles("Assets/GothicOrigin/Runtime","*.cs").Select(File.ReadAllText))+"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 −◇●■+%/";characters=new string(characters.Where(c=>!char.IsControl(c)).Distinct().ToArray());
            var sans=Font("ExpeditionSansKR","OriginSans",64,characters);Font("SanctuarySerifKR400","OriginSerif",72,characters);Font("SanctuaryCinzel400","OriginDisplay",90,"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 /.-");
            var tmp=AssetDatabase.LoadAssetAtPath<TMP_Settings>("Assets/TextMesh Pro/Resources/TMP Settings.asset");if(tmp==null)throw new Exception("TMP essential resources missing");var serialized=new SerializedObject(tmp);serialized.FindProperty("m_defaultFontAsset").objectReferenceValue=sans;serialized.ApplyModifiedPropertiesWithoutUndo();EditorUtility.SetDirty(tmp);
            var scene=EditorSceneManager.NewScene(NewSceneSetup.EmptyScene,NewSceneMode.Single);new GameObject("GothicOrigin").AddComponent<OriginGame>();EditorSceneManager.SaveScene(scene,ScenePath);EditorBuildSettings.scenes=new[]{new EditorBuildSettingsScene(ScenePath,true)};AssetDatabase.SaveAssets();
        }
        public static void Run()
        {
            Prepare();var args=Environment.GetCommandLineArgs();int at=Array.IndexOf(args,"-buildOutput");string output=at>=0?args[at+1]:"Builds/MusimusihanRPG-GothicOrigin.app";
            var report=BuildPipeline.BuildPlayer(new BuildPlayerOptions{scenes=new[]{ScenePath},target=BuildTarget.StandaloneOSX,locationPathName=output,options=BuildOptions.CompressWithLz4});
            var summary=new JObject{["result"]=report.summary.result.ToString(),["errors"]=report.summary.totalErrors,["warnings"]=report.summary.totalWarnings,["bytes"]=report.summary.totalSize,["output"]=Path.GetFullPath(output)};File.WriteAllText("origin-build-summary.json",summary.ToString());if(report.summary.result!=BuildResult.Succeeded||report.summary.totalErrors>0)throw new Exception("Native origin build failed: "+summary);Debug.Log("ORIGIN_BUILD_SUCCEEDED "+summary);
        }
    }
}
