using System;
using System.IO;
using Newtonsoft.Json.Linq;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;
using UnityEngine;

namespace MusimusihanRpg.Tools
{
    public static class LabradorPetBuild
    {
        public static string Build(string path, string reportPath, string scope = null)
        {
            if (EditorApplication.isPlaying || EditorApplication.isCompiling || EditorApplication.isUpdating)
                throw new InvalidOperationException("Wait for the stopped Editor to finish compilation and asset import before building.");
            path = Path.GetFullPath(path);
            string builds = Path.GetFullPath("Builds") + Path.DirectorySeparatorChar;
            if (!path.StartsWith(builds, StringComparison.Ordinal) || !path.EndsWith(".app", StringComparison.Ordinal))
                throw new InvalidOperationException("Build only to a separate app inside Builds.");
            if (Directory.Exists(path)) throw new InvalidOperationException("Preserve existing playable apps; use a new destination.");
            bool timing = PlayerSettings.enableFrameTimingStats;
            var backend = PlayerSettings.GetScriptingBackend(NamedBuildTarget.Standalone);
            BuildReport result;
            try
            {
                PlayerSettings.enableFrameTimingStats = true;
                PlayerSettings.SetScriptingBackend(NamedBuildTarget.Standalone, ScriptingImplementation.Mono2x);
                result = BuildPipeline.BuildPlayer(new BuildPlayerOptions {
                    scenes = new[] { "Assets/RPG/Scenes/Boot.unity", "Assets/RPG/Scenes/Sanctuary.unity", "Assets/RPG/Scenes/Workshop.unity" },
                    locationPathName = path, target = BuildTarget.StandaloneOSX, options = BuildOptions.None });
            }
            finally
            {
                PlayerSettings.enableFrameTimingStats = timing;
                PlayerSettings.SetScriptingBackend(NamedBuildTarget.Standalone, backend);
            }
            var receipt = new JObject {
                ["result"] = result.summary.result.ToString(), ["errors"] = result.summary.totalErrors,
                ["warnings"] = result.summary.totalWarnings, ["bytes"] = result.summary.totalSize,
                ["path"] = path, ["unity_version"] = Application.unityVersion,
                ["scope"] = scope ?? "Current native game with actual Labrador mouse petting. Gameplay and rendering acceptance recorded separately." };
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(reportPath)));
            File.WriteAllText(reportPath, receipt.ToString() + "\n");
            if (result.summary.result != BuildResult.Succeeded || result.summary.totalErrors != 0)
                throw new InvalidOperationException("Native Labrador build failed or contains shader errors.");
            return receipt.ToString();
        }
    }
}
