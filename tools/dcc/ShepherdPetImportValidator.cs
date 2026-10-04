// Copy this source into Assets/Editor of a SMALL, DISPOSABLE Unity 6000.3.25f1 project.
// Do not place it in the main game project. Required marker: ProjectSettings/ShepherdPetValidation.marker.
// Required env: SHEPHERD_PACKAGE_DIR (folder containing model, Animations/, Textures/, manifest).
// Optional env: SHEPHERD_REPORT, SHEPHERD_EXPORT_PACKAGE, SHEPHERD_ROOT_NODE.
// Entry point: MusimusihanRpg.Tools.ShepherdPetImportValidator.Run
// Official API references: ModelImporter.avatarSetup/sourceAvatar/motionNodeName;
// AnimationUtility.GetCurveBindings; Standard metallic texture alpha stores smoothness.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEditor.Animations;
using UnityEngine;
using UnityEngine.Rendering;

namespace MusimusihanRpg.Tools
{
    public static class ShepherdPetImportValidator
    {
        const string AssetsRoot = "Assets/ShepherdPetLocal";
        const string ModelName = "ShepherdPet_Model.fbx";
        const int ExpectedClipCount = 16;

        [Serializable] public sealed class Manifest { public int fps; public MotionSpec[] clips; }
        [Serializable] public sealed class MotionSpec
        {
            public string name; public int[] frames; public float duration; public bool loop; public EventSpec[] events;
        }
        [Serializable] public sealed class EventSpec { public float time; public string name; }
        [Serializable] public sealed class ClipReceipt
        {
            public string name, asset; public float duration, frameRate; public bool loop;
            public int bindings, keys, boundTransforms, sampleCount;
            public float maxPoseChangeDegrees, maxMeshChangeMeters, loopPositionErrorMeters, loopRotationErrorDegrees;
        }
        [Serializable] public sealed class Receipt
        {
            public string unityVersion, result, completedUtc, rootNode, prefab, controller, package, mouthSocketPath;
            public int checks, passed, failed, meshes, triangles, bones, clips;
            public float modelHeightMeters, modelLengthMeters;
            public Vector3 mouthSocketPositionMeters;
            public string[] errors, limitations;
            public ClipReceipt[] animations;
        }
        static Receipt receipt;
        static readonly List<string> Errors = new List<string>();

        public static void Run()
        {
            receipt = new Receipt { unityVersion = Application.unityVersion };
            Errors.Clear();
            string report = Environment.GetEnvironmentVariable("SHEPHERD_REPORT") ?? "Artifacts/shepherd-import.json";
            try
            {
                Require(File.Exists("ProjectSettings/ShepherdPetValidation.marker"), "Disposable-project marker missing; refusing game-project import");
                Require(Application.unityVersion == "6000.3.25f1", "Use the installed project Unity version 6000.3.25f1");
                Require(GraphicsSettings.defaultRenderPipeline == null, "Built-in render pipeline required");
                string source = Environment.GetEnvironmentVariable("SHEPHERD_PACKAGE_DIR");
                Require(!string.IsNullOrEmpty(source) && Directory.Exists(source), "SHEPHERD_PACKAGE_DIR must name final local production files");
                var manifest = JsonUtility.FromJson<Manifest>(File.ReadAllText(Path.Combine(source, "animation-manifest.json")));
                Require(manifest != null && manifest.clips != null && manifest.clips.Length == ExpectedClipCount, "Manifest must declare 16 clips");
                Require(manifest.fps == 30, "Expected authored frame rate: 30 FPS");
                Require(manifest.clips.Select(c => c.name).Distinct().Count() == ExpectedClipCount, "Duplicate clip names");
                foreach (var spec in manifest.clips)
                {
                    Require(!string.IsNullOrEmpty(spec.name) && Path.GetFileName(spec.name) == spec.name, "Clip names must be plain file names");
                    Require(spec.duration > 0 && Finite(spec.duration), "Invalid clip duration: " + spec.name);
                    Require(spec.frames != null && spec.frames.Length == 2 && spec.frames[1] > spec.frames[0], "Clip needs [first,last] frame range: " + spec.name);
                    foreach (var ev in spec.events ?? new EventSpec[0])
                        Require(Finite(ev.time) && ev.time >= 0 && ev.time <= spec.duration && !string.IsNullOrEmpty(ev.name), "Invalid authored event: " + spec.name);
                }
                CopyProductionFiles(source, manifest);
                AssetDatabase.Refresh(ImportAssetOptions.ForceSynchronousImport);
                string modelPath = AssetsRoot + "/" + ModelName;
                ConfigureModel(modelPath, false, null, null);
                var model = AssetDatabase.LoadAssetAtPath<GameObject>(modelPath);
                Require(model != null, "Model FBX import produced no GameObject");
                var avatar = AssetDatabase.LoadAllAssetsAtPath(modelPath).OfType<Avatar>().SingleOrDefault();
                Require(avatar != null && avatar.isValid && !avatar.isHuman, "Model needs a valid Generic Avatar");
                string rootNode = Environment.GetEnvironmentVariable("SHEPHERD_ROOT_NODE");
                if (string.IsNullOrEmpty(rootNode)) rootNode = FindRootNode(model.transform);
                Require(!string.IsNullOrEmpty(rootNode) && FindTransform(model.transform, rootNode) != null, "Generic motion root not found: " + rootNode);
                receipt.rootNode = rootNode;
                var modelImporter = (ModelImporter)AssetImporter.GetAtPath(modelPath);
                modelImporter.motionNodeName = rootNode;
                modelImporter.SaveAndReimport();
                model = AssetDatabase.LoadAssetAtPath<GameObject>(modelPath);
                avatar = AssetDatabase.LoadAllAssetsAtPath(modelPath).OfType<Avatar>().Single();
                var material = CreateStandardMaterial();
                var clips = new List<AnimationClip>();
                var clipsReceipt = new List<ClipReceipt>();
                foreach (var spec in manifest.clips)
                {
                    string motionPath = AssetsRoot + "/Animations/" + spec.name + ".fbx";
                    ConfigureModel(motionPath, true, avatar, spec);
                    var motionImporter = (ModelImporter)AssetImporter.GetAtPath(motionPath);
                    Require(motionImporter.animationType == ModelImporterAnimationType.Generic &&
                        motionImporter.avatarSetup == ModelImporterAvatarSetup.CopyFromOther && motionImporter.sourceAvatar == avatar,
                        "Animation must use the model's shared Generic Avatar: " + spec.name);
                    var imported = AssetDatabase.LoadAllAssetsAtPath(motionPath).OfType<AnimationClip>()
                        .Where(c => !c.name.StartsWith("__preview__", StringComparison.Ordinal)).ToArray();
                    Require(imported.Length == 1 && imported[0].name == spec.name, "Expected one named animation in " + motionPath);
                    var clip = imported[0];
                    Require(!clip.legacy && !clip.humanMotion, "Expected Generic animation: " + spec.name);
                    Require(Mathf.Abs(clip.length - spec.duration) <= 1.5f / manifest.fps, "Duration differs from manifest: " + spec.name);
                    Require(Mathf.Abs(clip.frameRate - manifest.fps) <= .05f, "Frame rate differs from manifest: " + spec.name);
                    Require(clip.isLooping == spec.loop, "Loop setting differs from manifest: " + spec.name);
                    clipsReceipt.Add(CheckBindingsAndSamples(model, clip, spec));
                    clips.Add(clip);
                }
                receipt.clips = clips.Count;
                receipt.animations = clipsReceipt.ToArray();
                CreatePrefabAndController(model, avatar, material, clips);
                AssetDatabase.SaveAssets();
                string package = Environment.GetEnvironmentVariable("SHEPHERD_EXPORT_PACKAGE");
                if (!string.IsNullOrEmpty(package))
                {
                    EnsureParent(package);
                    AssetDatabase.ExportPackage(AssetsRoot, package, ExportPackageOptions.Recurse | ExportPackageOptions.IncludeDependencies);
                    Require(File.Exists(package) && new FileInfo(package).Length > 0, "Local Unity package export failed");
                    receipt.package = Path.GetFullPath(package);
                }
                receipt.result = "Passed";
            }
            catch (Exception ex)
            {
                receipt.result = "Failed";
                Errors.Add(ex.ToString());
                Debug.LogError(ex);
            }
            finally
            {
                receipt.completedUtc = DateTime.UtcNow.ToString("o");
                receipt.errors = Errors.ToArray();
                receipt.failed = Errors.Count;
                receipt.passed = receipt.checks - receipt.failed;
                receipt.limitations = new[] {
                    "Isolated Editor import, CPU skin sampling and Built-in material bindings only; visual review is separate.",
                    "No combat AI, hidden-item logic, feeding interaction, player hand animation or game/F2 integration is claimed.",
                    "Authored event metadata is retained in the manifest; no unimplemented AnimationEvent receivers are installed.",
                    "Licensed model, FBX clips, materials, prefab and package are local production assets; do not publish their binaries."
                };
                EnsureParent(report);
                File.WriteAllText(report, JsonUtility.ToJson(receipt, true) + "\n");
                if (Application.isBatchMode) EditorApplication.Exit(receipt.result == "Passed" ? 0 : 1);
            }
        }

        static void CopyProductionFiles(string source, Manifest manifest)
        {
            Directory.CreateDirectory(AssetsRoot + "/Animations");
            Directory.CreateDirectory(AssetsRoot + "/Textures");
            var paths = new List<string> { ModelName, "animation-manifest.json", "Textures/T_GermanShepherd_B.png", "Textures/T_GermanShepherd_N.png", "Textures/T_GermanShepherd_R.png" };
            paths.AddRange(manifest.clips.Select(c => "Animations/" + c.name + ".fbx"));
            foreach (string path in paths)
            {
                string from = Path.Combine(source, path);
                Require(File.Exists(from), "Final production file missing: " + path);
                string to = Path.Combine(AssetsRoot, path);
                if (Path.GetFullPath(from) != Path.GetFullPath(to)) File.Copy(from, to, true);
            }
        }

        static void ConfigureModel(string path, bool animation, Avatar sourceAvatar, MotionSpec spec)
        {
            var importer = AssetImporter.GetAtPath(path) as ModelImporter;
            Require(importer != null, "No FBX ModelImporter: " + path);
            importer.animationType = ModelImporterAnimationType.Generic;
            importer.avatarSetup = sourceAvatar == null ? ModelImporterAvatarSetup.CreateFromThisModel : ModelImporterAvatarSetup.CopyFromOther;
            importer.sourceAvatar = sourceAvatar;
            importer.importAnimation = animation;
            importer.animationCompression = ModelImporterAnimationCompression.Off;
            importer.optimizeGameObjects = false;
            importer.importCameras = false;
            importer.importLights = false;
            importer.globalScale = 1f;
            importer.useFileScale = true;
            importer.isReadable = true;
            if (animation)
            {
                var defaults = importer.defaultClipAnimations;
                Require(defaults.Length == 1, "Each animation FBX must contain exactly one take: " + path);
                var clip = defaults[0];
                clip.name = spec.name;
                clip.loopTime = spec.loop;
                clip.loopPose = spec.loop;
                clip.keepOriginalOrientation = true;
                clip.keepOriginalPositionY = true;
                clip.keepOriginalPositionXZ = true;
                clip.lockRootRotation = true;
                clip.lockRootHeightY = true;
                clip.lockRootPositionXZ = true;
                importer.clipAnimations = new[] { clip };
                importer.motionNodeName = receipt.rootNode;
            }
            importer.SaveAndReimport();
        }

        static Material CreateStandardMaterial()
        {
            string b = AssetsRoot + "/Textures/T_GermanShepherd_B.png", n = AssetsRoot + "/Textures/T_GermanShepherd_N.png", r = AssetsRoot + "/Textures/T_GermanShepherd_R.png";
            ConfigureTexture(b, false, true, false);
            ConfigureTexture(n, true, false, false);
            ConfigureTexture(r, false, false, true);
            var roughness = AssetDatabase.LoadAssetAtPath<Texture2D>(r);
            var values = roughness.GetPixels32();
            for (int i = 0; i < values.Length; ++i) values[i] = new Color32(0, 0, 0, (byte)(255 - values[i].r));
            var smoothness = new Texture2D(roughness.width, roughness.height, TextureFormat.RGBA32, false, true);
            smoothness.SetPixels32(values); smoothness.Apply();
            string smoothPath = AssetsRoot + "/Textures/T_GermanShepherd_MetallicSmoothness.png";
            File.WriteAllBytes(smoothPath, smoothness.EncodeToPNG());
            UnityEngine.Object.DestroyImmediate(smoothness);
            AssetDatabase.ImportAsset(smoothPath, ImportAssetOptions.ForceSynchronousImport);
            ConfigureTexture(smoothPath, false, false, false);
            Directory.CreateDirectory(AssetsRoot + "/Materials");
            string materialPath = AssetsRoot + "/Materials/ShepherdPet_Standard.mat";
            var shader = Shader.Find("Standard");
            Require(shader != null, "Built-in Standard shader missing");
            var mat = new Material(shader) { name = "ShepherdPet_Standard" };
            mat.SetTexture("_MainTex", AssetDatabase.LoadAssetAtPath<Texture2D>(b));
            mat.SetTexture("_BumpMap", AssetDatabase.LoadAssetAtPath<Texture2D>(n));
            mat.SetTexture("_MetallicGlossMap", AssetDatabase.LoadAssetAtPath<Texture2D>(smoothPath));
            mat.SetFloat("_Metallic", 0); mat.SetFloat("_GlossMapScale", 1); mat.SetFloat("_BumpScale", 1);
            mat.EnableKeyword("_NORMALMAP"); mat.EnableKeyword("_METALLICGLOSSMAP");
            // The selected model's coat texture contains fur-card alpha (10.7% of texels are non-opaque).
            // Cutout retains solid depth/shadows and prevents black rectangles around the fur cards.
            mat.SetFloat("_Mode", 1); mat.SetFloat("_Cutoff", .5f);
            mat.SetInt("_SrcBlend", (int)BlendMode.One); mat.SetInt("_DstBlend", (int)BlendMode.Zero);
            mat.SetInt("_ZWrite", 1); mat.EnableKeyword("_ALPHATEST_ON");
            mat.DisableKeyword("_ALPHABLEND_ON"); mat.DisableKeyword("_ALPHAPREMULTIPLY_ON");
            mat.SetOverrideTag("RenderType", "TransparentCutout"); mat.renderQueue = (int)RenderQueue.AlphaTest;
            if (File.Exists(materialPath)) AssetDatabase.DeleteAsset(materialPath);
            AssetDatabase.CreateAsset(mat, materialPath);
            Require(mat.shader.name == "Standard" && mat.GetTexture("_MainTex") != null && mat.GetTexture("_BumpMap") != null && mat.GetTexture("_MetallicGlossMap") != null,
                "Standard base color, normal and converted smoothness bindings required");
            Require(((TextureImporter)AssetImporter.GetAtPath(n)).textureType == TextureImporterType.NormalMap, "Normal map importer type incorrect");
            Require(!((TextureImporter)AssetImporter.GetAtPath(smoothPath)).sRGBTexture, "Metallic/smoothness texture must use linear samples");
            Require(mat.IsKeywordEnabled("_ALPHATEST_ON") && mat.GetFloat("_Mode") == 1 && mat.GetFloat("_Cutoff") == .5f,
                "Fur-card alpha requires Standard Cutout material");
            return mat;
        }

        static void ConfigureTexture(string path, bool normal, bool srgb, bool readable)
        {
            var importer = (TextureImporter)AssetImporter.GetAtPath(path);
            importer.textureType = normal ? TextureImporterType.NormalMap : TextureImporterType.Default;
            importer.sRGBTexture = srgb;
            importer.isReadable = readable;
            importer.maxTextureSize = 2048;
            importer.textureCompression = readable ? TextureImporterCompression.Uncompressed : TextureImporterCompression.Compressed;
            importer.SaveAndReimport();
        }

        static ClipReceipt CheckBindingsAndSamples(GameObject model, AnimationClip clip, MotionSpec spec)
        {
            var item = new ClipReceipt { name = spec.name, asset = AssetDatabase.GetAssetPath(clip), duration = clip.length, frameRate = clip.frameRate, loop = clip.isLooping };
            var instance = UnityEngine.Object.Instantiate(model);
            var transforms = instance.GetComponentsInChildren<Transform>(true);
            var positions = transforms.Select(t => t.localPosition).ToArray();
            var rotations = transforms.Select(t => t.localRotation).ToArray();
            var scales = transforms.Select(t => t.localScale).ToArray();
            var bindings = AnimationUtility.GetCurveBindings(clip);
            item.bindings = bindings.Length;
            Require(bindings.Length > 0, "No animation curves: " + spec.name);
            var bound = new HashSet<string>();
            foreach (var binding in bindings)
            {
                var curve = AnimationUtility.GetEditorCurve(clip, binding);
                Require(curve != null && curve.length > 0, "Empty curve: " + spec.name + "/" + binding.path);
                item.keys += curve.length;
                foreach (var key in curve.keys) Require(Finite(key.time) && Finite(key.value), "Non-finite animation key: " + spec.name);
                if (binding.type == typeof(Transform))
                {
                    Require(FindTransform(instance.transform, binding.path) != null, "Curve cannot bind to model: " + spec.name + "/" + binding.path);
                    bound.Add(binding.path);
                }
            }
            item.boundTransforms = bound.Count;
            var renderers = instance.GetComponentsInChildren<SkinnedMeshRenderer>(true);
            Require(renderers.Length > 0, "Skinned mesh missing");
            var baked = new Mesh();
            Vector3[] firstMesh = null, firstPose = null;
            Quaternion[] firstRot = null;
            try
            {
                float[] times = { 0, clip.length * .25f, clip.length * .5f, clip.length * .75f, clip.length };
                foreach (float time in times)
                {
                    for (int i = 0; i < transforms.Length; i++) { transforms[i].localPosition = positions[i]; transforms[i].localRotation = rotations[i]; transforms[i].localScale = scales[i]; }
                    clip.SampleAnimation(instance, time);
                    for (int i = 0; i < transforms.Length; i++)
                    {
                        Require(Finite(transforms[i].localPosition) && Finite(transforms[i].localRotation), "Non-finite sampled bone: " + spec.name);
                        if (firstRot != null) item.maxPoseChangeDegrees = Mathf.Max(item.maxPoseChangeDegrees, Quaternion.Angle(firstRot[i], transforms[i].localRotation));
                    }
                    renderers[0].BakeMesh(baked);
                    var vertices = baked.vertices;
                    Require(vertices.Length > 0 && vertices.All(Finite), "Invalid deformed mesh: " + spec.name);
                    if (firstMesh == null)
                    {
                        firstMesh = vertices; firstPose = transforms.Select(t => t.localPosition).ToArray(); firstRot = transforms.Select(t => t.localRotation).ToArray();
                    }
                    else
                    {
                        Require(vertices.Length == firstMesh.Length, "Vertex count changes during sampling: " + spec.name);
                        for (int i = 0; i < vertices.Length; i++) item.maxMeshChangeMeters = Mathf.Max(item.maxMeshChangeMeters, Vector3.Distance(vertices[i], firstMesh[i]));
                    }
                    if (time == clip.length)
                        for (int i = 0; i < transforms.Length; i++)
                        {
                            item.loopPositionErrorMeters = Mathf.Max(item.loopPositionErrorMeters, Vector3.Distance(firstPose[i], transforms[i].localPosition));
                            item.loopRotationErrorDegrees = Mathf.Max(item.loopRotationErrorDegrees, Quaternion.Angle(firstRot[i], transforms[i].localRotation));
                        }
                    item.sampleCount++;
                }
                Require(item.maxMeshChangeMeters > .00001f || item.maxPoseChangeDegrees > .01f, "Clip samples have no actual motion: " + spec.name);
            }
            finally { UnityEngine.Object.DestroyImmediate(baked); UnityEngine.Object.DestroyImmediate(instance); }
            return item;
        }

        static void CreatePrefabAndController(GameObject model, Avatar avatar, Material material, List<AnimationClip> clips)
        {
            Directory.CreateDirectory(AssetsRoot + "/Prefabs");
            string controllerPath = AssetsRoot + "/ShepherdPet.controller";
            if (File.Exists(controllerPath)) AssetDatabase.DeleteAsset(controllerPath);
            var controller = AnimatorController.CreateAnimatorControllerAtPath(controllerPath);
            var machine = controller.layers[0].stateMachine;
            foreach (var clip in clips) { var state = machine.AddState(clip.name); state.motion = clip; }
            var idle = machine.states.FirstOrDefault(s => s.state.name.IndexOf("idle", StringComparison.OrdinalIgnoreCase) >= 0).state;
            machine.defaultState = idle != null ? idle : machine.states[0].state;
            var instance = UnityEngine.Object.Instantiate(model);
            instance.name = "ShepherdPet";
            var animator = instance.GetComponent<Animator>() ?? instance.AddComponent<Animator>();
            animator.avatar = avatar; animator.runtimeAnimatorController = controller; animator.applyRootMotion = false;
            var renderers = instance.GetComponentsInChildren<SkinnedMeshRenderer>(true);
            receipt.meshes = renderers.Length;
            var allBones = new HashSet<Transform>();
            var worldBounds = renderers[0].bounds;
            foreach (var renderer in renderers)
            {
                Require(renderer.sharedMesh != null && renderer.bones.All(b => b != null), "Skin has missing mesh or bone references");
                receipt.triangles += renderer.sharedMesh.triangles.Length / 3;
                foreach (var bone in renderer.bones) allBones.Add(bone);
                renderer.sharedMaterials = Enumerable.Repeat(material, renderer.sharedMaterials.Length).ToArray();
                worldBounds.Encapsulate(renderer.bounds);
            }
            receipt.bones = allBones.Count;
            receipt.modelHeightMeters = worldBounds.size.y;
            receipt.modelLengthMeters = Mathf.Max(worldBounds.size.x, worldBounds.size.z);
            Require(receipt.bones > 10, "Expected articulated quadruped skin");
            Require(receipt.triangles == 2272, "Triangle count differs from selected official model: " + receipt.triangles);
            Require(receipt.modelHeightMeters > .3f && receipt.modelHeightMeters < 1.5f && receipt.modelLengthMeters > .5f && receipt.modelLengthMeters < 2.5f,
                "Model scale is outside metre-scale German Shepherd dimensions");
            var head = instance.GetComponentsInChildren<Transform>(true).SingleOrDefault(t => t.name == "DEF-spine.011");
            Require(head != null, "Authored head bone missing for mouth socket");
            var mouth = new GameObject("MouthSocket").transform;
            mouth.position = head.position + head.TransformDirection(Vector3.up) * -.06f + head.TransformDirection(Vector3.forward) * .13f;
            mouth.rotation = head.rotation;
            mouth.SetParent(head, true);
            receipt.mouthSocketPath = AnimationUtility.CalculateTransformPath(mouth, instance.transform);
            receipt.mouthSocketPositionMeters = mouth.position;
            Require(Vector3.Distance(mouth.lossyScale, Vector3.one) < .001f, "Mouth socket must preserve metre-scale attachments");
            string prefabPath = AssetsRoot + "/Prefabs/ShepherdPet.prefab";
            var prefab = PrefabUtility.SaveAsPrefabAsset(instance, prefabPath);
            Require(prefab != null && prefab.GetComponent<Animator>().avatar == avatar, "Prefab must retain shared Generic Avatar");
            receipt.prefab = prefabPath; receipt.controller = controllerPath;
            UnityEngine.Object.DestroyImmediate(instance);
        }

        static string FindRootNode(Transform root)
        {
            var armature = root.GetComponentsInChildren<Transform>(true).FirstOrDefault(t => t != root && t.name == "ShepherdPet");
            if (armature != null) return AnimationUtility.CalculateTransformPath(armature, root);
            var pelvis = root.GetComponentsInChildren<Transform>(true).FirstOrDefault(t => t.name == "DEF-spine.004");
            return pelvis != null ? AnimationUtility.CalculateTransformPath(pelvis, root) : "";
        }
        static Transform FindTransform(Transform root, string path) { return string.IsNullOrEmpty(path) ? root : root.Find(path); }
        static bool Finite(float f) { return !float.IsNaN(f) && !float.IsInfinity(f); }
        static bool Finite(Vector3 v) { return Finite(v.x) && Finite(v.y) && Finite(v.z); }
        static bool Finite(Quaternion q) { return Finite(q.x) && Finite(q.y) && Finite(q.z) && Finite(q.w); }
        static void Require(bool valid, string message)
        {
            receipt.checks++;
            if (!valid) throw new InvalidOperationException(message);
        }
        static void EnsureParent(string path) { string parent = Path.GetDirectoryName(Path.GetFullPath(path)); if (!string.IsNullOrEmpty(parent)) Directory.CreateDirectory(parent); }
    }
}
