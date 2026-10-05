// Run with Unity's run_script against the active project, in stopped Edit mode.
// Entry: MusimusihanRpg.Tools.LabradorPetInstaller.Install(exportDirectory).
// Writes only the local licensed pet resources; preserves importer metadata on reruns.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Newtonsoft.Json.Linq;
using UnityEditor;
using UnityEngine;

namespace MusimusihanRpg.Tools
{
    public static class LabradorPetInstaller
    {
        const string Root = "Assets/RPG/Resources/Pets/Labrador";
        static readonly string[] Names = { "IdleFriendly", "PetEnjoy" };
        static int checks;
        static void Check(bool condition, string message)
        { checks++; if (!condition) throw new InvalidOperationException(message); }

        public static string Install(string exportDirectory)
        {
            Check(!EditorApplication.isPlaying, "Stop Play before installing the actual pet assets.");
            checks = 0;
            string source = Path.GetFullPath(exportDirectory);
            var manifest = JObject.Parse(File.ReadAllText(Path.Combine(source, "animation-manifest.json")));
            var specs = manifest["clips"].OfType<JObject>().ToArray();
            var suppliedNames = specs.Select(s => (string)s["name"]).ToArray();
            Check(suppliedNames.Distinct().Count() == suppliedNames.Length && Names.All(suppliedNames.Contains), "Actual standing idle and enjoy motions are required for mouse petting.");
            foreach (string dir in new[] { Root, Root + "/Models", Root + "/Animations", Root + "/Textures" }) Directory.CreateDirectory(dir);
            string modelFile = (string)manifest["model"] ?? "LabradorPet_Model.fbx";
            Check(Path.GetFileName(modelFile) == modelFile, "Model filename must be local to the export directory.");
            string modelPath = Root + "/Models/" + modelFile;
            Copy(Path.Combine(source, modelFile), modelPath);
            foreach (var spec in specs) Copy(Path.Combine(source, "Animations", (string)spec["name"] + ".fbx"), Root + "/Animations/" + (string)spec["name"] + ".fbx");
            var textureNames = manifest["textures"] as JObject;
            Check(textureNames != null, "Export manifest must identify actual PBR textures.");
            foreach (var prop in textureNames.Properties())
            {
                string relative = (string)prop.Value;
                Check(!Path.IsPathRooted(relative) && !relative.Split('/', '\\').Contains(".."), "Texture path escapes export directory.");
                Copy(Path.Combine(source, relative), Root + "/Textures/" + Path.GetFileName(relative));
            }
            AssetDatabase.Refresh(ImportAssetOptions.ForceSynchronousImport);
            foreach (string obsolete in new[] { "PetSit", "PetRise" }.Where(n => !suppliedNames.Contains(n)))
                foreach (string extension in new[] { ".fbx", ".anim" })
                    if (File.Exists(Root + "/Animations/" + obsolete + extension)) AssetDatabase.DeleteAsset(Root + "/Animations/" + obsolete + extension);
            ConfigureModel(modelPath, false);
            var model = AssetDatabase.LoadAssetAtPath<GameObject>(modelPath);
            Check(model != null, "Actual model FBX was not imported.");
            var material = MakeMaterial(textureNames, (float?)manifest["metallicFactor"] ?? .0909091f, (float?)manifest["normalScale"] ?? .2f);
            var instance = PrefabUtility.InstantiatePrefab(model) as GameObject;
            Check(instance != null, "Actual model instantiation failed.");
            instance.name = "PetModel";
            try
            {
                foreach (var animator in instance.GetComponentsInChildren<Animator>(true)) animator.enabled = false;
                foreach (var animation in instance.GetComponentsInChildren<Animation>(true)) animation.enabled = false;
                foreach (var renderer in instance.GetComponentsInChildren<Renderer>(true)) renderer.sharedMaterials = renderer.sharedMaterials.Select(_ => material).ToArray();
                foreach (var renderer in instance.GetComponentsInChildren<SkinnedMeshRenderer>(true)) { renderer.updateWhenOffscreen = true; renderer.quality = SkinQuality.Bone4; }
                var skins = instance.GetComponentsInChildren<SkinnedMeshRenderer>(true);
                Check(skins.Any(r => Enumerable.Range(0, r.sharedMesh.blendShapeCount).Any(i => r.sharedMesh.GetBlendShapeName(i).EndsWith("target_1", StringComparison.Ordinal))), "Preserve the actual two-eye blink shape.");
                Check(skins.Any(r => r.sharedMesh.colors.Length == r.sharedMesh.vertexCount && r.sharedMesh.colors.Any(c => c.r > .9f) && r.sharedMesh.colors.Any(c => c.r < .1f)), "Authored coat mask must include coat and exclude eyes/nose.");
                var transforms = instance.GetComponentsInChildren<Transform>(true);
                var mouth = transforms.SingleOrDefault(t => t.name == "MouthSocket");
                Check(mouth != null, "Export must contain the anatomically authored MouthSocket.");
                Check(Vector3.Distance(mouth.lossyScale, Vector3.one) < .01f, "Socket attachments must be metre scale.");
                var renderers = instance.GetComponentsInChildren<Renderer>(true);
                Check(renderers.Length > 0, "Actual Labrador has no renderers.");
                var worldPoints = new List<Vector3>();
                foreach (var skin in skins)
                {
                    var baked = new Mesh();
                    try
                    {
                        // Unity's default false includes Transform scale in the baked vertices.
                        // Compensate that scale before measuring or raycasting in world space.
                        skin.BakeMesh(baked, true);
                        skin.localBounds = baked.bounds;
                        worldPoints.AddRange(baked.vertices.Select(skin.transform.TransformPoint));
                    }
                    finally { UnityEngine.Object.DestroyImmediate(baked); }
                }
                foreach (var filter in instance.GetComponentsInChildren<MeshFilter>(true))
                    if (filter.sharedMesh != null) worldPoints.AddRange(filter.sharedMesh.vertices.Select(filter.transform.TransformPoint));
                Check(worldPoints.Count > 1000, "Actual evaluated Labrador geometry is missing.");
                Bounds bounds = new Bounds(worldPoints[0], Vector3.zero);
                foreach (var point in worldPoints.Skip(1)) bounds.Encapsulate(point);
                Check(bounds.size.y > .35f && bounds.size.y < .95f && bounds.size.z > .5f && bounds.size.z < 1.9f, "Labrador must be at natural metre scale and face Unity +Z, including its tail.");
                var positions = transforms.Select(t => t.localPosition).ToArray();
                var rotations = transforms.Select(t => t.localRotation).ToArray();
                var scales = transforms.Select(t => t.localScale).ToArray();
                var clipReceipts = new JArray();
                foreach (var spec in specs)
                {
                    string name = (string)spec["name"], motionPath = Root + "/Animations/" + name + ".fbx";
                    ConfigureModel(motionPath, true, spec);
                    var imported = AssetDatabase.LoadAllAssetsAtPath(motionPath).OfType<AnimationClip>().Where(c => !c.name.StartsWith("__preview__", StringComparison.Ordinal)).ToArray();
                    Check(imported.Length == 1, "Expected one authored take: " + name);
                    var clip = UnityEngine.Object.Instantiate(imported[0]); clip.name = name; clip.legacy = true;
                    bool loop = (bool?)spec["loop"] ?? false; clip.wrapMode = loop ? WrapMode.Loop : WrapMode.ClampForever;
                    string clipPath = Root + "/Animations/" + name + ".anim";
                    var existing = AssetDatabase.LoadAssetAtPath<AnimationClip>(clipPath);
                    if (existing == null) AssetDatabase.CreateAsset(clip, clipPath);
                    else { EditorUtility.CopySerialized(clip, existing); UnityEngine.Object.DestroyImmediate(clip); clip = existing; }
                    var bindings = AnimationUtility.GetCurveBindings(clip);
                    Check(bindings.Length > 20, "No real skeletal curves: " + name);
                    Check(bindings.All(b => b.type != typeof(Transform) || string.IsNullOrEmpty(b.path) || instance.transform.Find(b.path) != null), "Animation hierarchy does not bind the real model: " + name);
                    Check(Mathf.Abs(clip.length - (float)spec["duration"]) < 2f / ((float?)manifest["fps"] ?? 30), "Authored duration differs after import: " + name);
                    float maxChange = 0, loopPosition = 0, loopAngle = 0;
                    Vector3[] first = null; Quaternion[] firstRot = null;
                    for (int sample = 0; sample < 5; sample++)
                    {
                        for (int i = 0; i < transforms.Length; i++) { transforms[i].localPosition = positions[i]; transforms[i].localRotation = rotations[i]; transforms[i].localScale = scales[i]; }
                        clip.SampleAnimation(instance, clip.length * sample / 4);
                        Check(transforms.All(t => Finite(t.localPosition) && Finite(t.localScale) && Finite(t.localRotation)), "Non-finite animated pose: " + name);
                        if (sample == 0) { first = transforms.Select(t => t.localPosition).ToArray(); firstRot = transforms.Select(t => t.localRotation).ToArray(); }
                        else for (int i = 0; i < transforms.Length; i++) maxChange = Mathf.Max(maxChange, Quaternion.Angle(firstRot[i], transforms[i].localRotation));
                        if (sample == 4) for (int i = 0; i < transforms.Length; i++) { loopPosition = Mathf.Max(loopPosition, Vector3.Distance(first[i], transforms[i].localPosition)); loopAngle = Mathf.Max(loopAngle, Quaternion.Angle(firstRot[i], transforms[i].localRotation)); }
                    }
                    Check(maxChange > .02f, "Clip does not move the actual rig: " + name);
                    if (loop) Check(loopPosition < .015f && loopAngle < 4, "Visible loop seam requires repair: " + name);
                    clipReceipts.Add(new JObject { ["name"] = name, ["asset"] = clipPath, ["duration"] = clip.length, ["bindings"] = bindings.Length, ["samples"] = 5, ["max_rotation_degrees"] = maxChange, ["loop"] = loop, ["loop_position_m"] = loopPosition, ["loop_rotation_degrees"] = loopAngle });
                }
                for (int i = 0; i < transforms.Length; i++) { transforms[i].localPosition = positions[i]; transforms[i].localRotation = rotations[i]; transforms[i].localScale = scales[i]; }
                string prefabPath = Root + "/PetModel.prefab";
                Check(PrefabUtility.SaveAsPrefabAsset(instance, prefabPath) != null, "Actual pet prefab was not saved.");
                AssetDatabase.SaveAssets();
                var receipt = new JObject { ["result"] = "Passed", ["unity_version"] = Application.unityVersion, ["checks"] = checks, ["prefab"] = prefabPath, ["mouth_path"] = AnimationUtility.CalculateTransformPath(mouth, instance.transform), ["height_m"] = bounds.size.y, ["length_m"] = bounds.size.z, ["renderers"] = renderers.Length, ["motions"] = clipReceipts, ["source_normal_strength"] = (float?)manifest["normalScale"] ?? .2f, ["unity_normal_strength"] = material.GetFloat("_BumpScale"), ["limitations"] = new JArray("Actual import, hierarchy bindings, five sampled poses per clip and loop boundaries. Full world, care contacts and rendering are checked separately.") };
                string report = Path.Combine(source, "../unity-import-summary.json"); File.WriteAllText(report, receipt.ToString() + "\n");
                return receipt.ToString();
            }
            finally { UnityEngine.Object.DestroyImmediate(instance); }
        }

        static void Copy(string source, string destination)
        {
            Check(File.Exists(source), "Final production source missing: " + source);
            if (!File.Exists(destination) || !File.ReadAllBytes(source).SequenceEqual(File.ReadAllBytes(destination))) File.Copy(source, destination, true);
        }
        static void ConfigureModel(string path, bool animation, JObject spec = null)
        {
            var importer = AssetImporter.GetAtPath(path) as ModelImporter;
            Check(importer != null, "ModelImporter missing: " + path);
            importer.animationType = ModelImporterAnimationType.Legacy; importer.importAnimation = animation;
            importer.animationCompression = ModelImporterAnimationCompression.Off; importer.optimizeGameObjects = false;
            importer.importCameras = false; importer.importLights = false; importer.globalScale = 1; importer.useFileScale = true; importer.isReadable = true;
            importer.importBlendShapes = true;
            if (animation)
            {
                var defaults = importer.defaultClipAnimations; Check(defaults.Length == 1, "Multiple or missing authored takes: " + path);
                var config = defaults[0]; config.name = (string)spec["name"]; config.loopTime = (bool?)spec["loop"] ?? false; config.loopPose = false;
                config.lockRootRotation = false; config.lockRootHeightY = false; config.lockRootPositionXZ = false;
                importer.clipAnimations = new[] { config };
            }
            importer.SaveAndReimport();
        }
        static Material MakeMaterial(JObject names, float metallicFactor, float normalScale)
        {
            string PathFor(string key) => Root + "/Textures/" + Path.GetFileName((string)names[key]);
            Check(names["baseColor"] != null && names["normal"] != null && names["metallicRoughness"] != null, "Base color, normal and metallic/roughness are required.");
            Texture(PathFor("baseColor"), false, true); Texture(PathFor("normal"), true, false); Texture(PathFor("metallicRoughness"), false, false);
            var source = new Texture2D(2, 2, TextureFormat.RGBA32, false, true);
            Check(source.LoadImage(File.ReadAllBytes(PathFor("metallicRoughness"))), "Actual roughness PNG did not decode.");
            var pixels = source.GetPixels32();
            for (int i = 0; i < pixels.Length; i++) pixels[i] = new Color32((byte)Mathf.RoundToInt(pixels[i].b * metallicFactor), 0, 0, (byte)(255 - pixels[i].g));
            var packed = new Texture2D(source.width, source.height, TextureFormat.RGBA32, false, true); packed.SetPixels32(pixels); packed.Apply();
            string packedPath = Root + "/Textures/Labrador_MetallicSmoothness.png";
            File.WriteAllBytes(packedPath, packed.EncodeToPNG()); UnityEngine.Object.DestroyImmediate(source); UnityEngine.Object.DestroyImmediate(packed);
            AssetDatabase.ImportAsset(packedPath, ImportAssetOptions.ForceSynchronousImport); Texture(packedPath, false, false);
            string path = Root + "/Labrador.mat"; var material = AssetDatabase.LoadAssetAtPath<Material>(path);
            var shader = Shader.Find("RPG/Labrador Petting");
            Check(shader != null && shader.isSupported, "Petting coat shader must compile on this machine.");
            if (material == null) { material = new Material(shader); AssetDatabase.CreateAsset(material, path); }
            else material.shader = shader;
            material.SetTexture("_MainTex", AssetDatabase.LoadAssetAtPath<Texture2D>(PathFor("baseColor"))); material.SetTexture("_BumpMap", AssetDatabase.LoadAssetAtPath<Texture2D>(PathFor("normal")));
            material.SetTexture("_MetallicGlossMap", AssetDatabase.LoadAssetAtPath<Texture2D>(packedPath)); material.SetFloat("_Metallic", 1); material.SetFloat("_GlossMapScale", 1);
            // Actual material comparisons isolate large torso seams to Unity's normal/tangent path.
            // Keep the source map for future repair; albedo coat detail and local petComb remain active.
            material.SetFloat("_BumpScale", 0);
            material.EnableKeyword("_NORMALMAP"); material.EnableKeyword("_METALLICGLOSSMAP"); EditorUtility.SetDirty(material); return material;
        }
        static void Texture(string path, bool normal, bool srgb)
        {
            var importer = AssetImporter.GetAtPath(path) as TextureImporter; Check(importer != null, "Actual texture importer missing: " + path);
            importer.textureType = normal ? TextureImporterType.NormalMap : TextureImporterType.Default; importer.sRGBTexture = srgb;
            importer.maxTextureSize = 2048; importer.mipmapEnabled = true; importer.filterMode = FilterMode.Trilinear; importer.anisoLevel = 8; importer.textureCompression = TextureImporterCompression.Compressed; importer.SaveAndReimport();
        }
        static bool Finite(Vector3 v) => float.IsFinite(v.x) && float.IsFinite(v.y) && float.IsFinite(v.z);
        static bool Finite(Quaternion q) => float.IsFinite(q.x) && float.IsFinite(q.y) && float.IsFinite(q.z) && float.IsFinite(q.w);
    }
}
