// Live Editor run_script entry: MusimusihanRpg.Tools.LabradorLocomotionInstaller.Install(exportDirectory).
// Installs only the two gait FBX/anim assets. Existing source model, materials, prefab and care motions are conserved.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using Newtonsoft.Json.Linq;
using UnityEditor;
using UnityEngine;

namespace MusimusihanRpg.Tools
{
    public static class LabradorLocomotionInstaller
    {
        const string Root = "Assets/RPG/Resources/Pets/Labrador";
        static readonly string[] Names = { "Walk", "Run" };
        static int checks;
        static void Check(bool condition, string text) { checks++; if (!condition) throw new InvalidOperationException(text); }
        static string Hash(string path) { using var sha = SHA256.Create(); return BitConverter.ToString(sha.ComputeHash(File.ReadAllBytes(path))).Replace("-", "").ToLowerInvariant(); }
        public static string Install(string exportDirectory)
        {
            checks = 0; Check(!EditorApplication.isPlaying && !EditorApplication.isCompiling, "Install gait clips in ready Edit mode.");
            string source = Path.GetFullPath(exportDirectory);
            string manifestPath = Path.Combine(source, "locomotion-manifest.json");
            if (!File.Exists(manifestPath)) manifestPath = Path.GetFullPath(Path.Combine(source, "../../locomotion-manifest.json"));
            var manifest = JObject.Parse(File.ReadAllText(manifestPath));
            var specs = manifest["clips"].OfType<JObject>().ToArray(); float fps = (float?)manifest["fps"] ?? 60;
            Check(specs.Length == 2 && Names.All(n => specs.Count(s => (string)s["name"] == n) == 1), "Exactly the authored Walk and Run clips are required.");
            var prefab = AssetDatabase.LoadAssetAtPath<GameObject>(Root + "/PetModel.prefab");
            Check(prefab != null, "The existing actual Labrador prefab is required.");
            var conserved = Directory.GetFiles(Root, "*", SearchOption.AllDirectories).Where(p => !p.EndsWith(".meta") && !Names.Any(n => Path.GetFileNameWithoutExtension(p) == n)).ToDictionary(p => p, Hash);
            var instance = PrefabUtility.InstantiatePrefab(prefab) as GameObject;
            Check(instance != null, "Instantiate the existing actual Labrador.");
            try
            {
                foreach (var animation in instance.GetComponentsInChildren<Animation>(true)) animation.enabled = false;
                foreach (var animator in instance.GetComponentsInChildren<Animator>(true)) animator.enabled = false;
                var transforms = instance.GetComponentsInChildren<Transform>(true);
                var positions = transforms.Select(t => t.localPosition).ToArray(); var rotations = transforms.Select(t => t.localRotation).ToArray(); var scales = transforms.Select(t => t.localScale).ToArray();
                var clips = new JArray();
                foreach (var spec in specs)
                {
                    string name = (string)spec["name"], sourcePath = Path.Combine(source, name + ".fbx"), path = Root + "/Animations/" + name + ".fbx";
                    Check(File.Exists(sourcePath), "Final gait FBX missing: " + name);
                    Check((bool?)spec["loop"] == true && ((string)spec["root_motion"] ?? "").StartsWith("in-place", StringComparison.Ordinal), "Gait must be an authored in-place loop: " + name);
                    if (!File.Exists(path) || Hash(path) != Hash(sourcePath)) File.Copy(sourcePath, path, true);
                    AssetDatabase.ImportAsset(path, ImportAssetOptions.ForceSynchronousImport);
                    var importer = AssetImporter.GetAtPath(path) as ModelImporter;
                    Check(importer != null, "Actual FBX importer required: " + name);
                    importer.animationType = ModelImporterAnimationType.Legacy; importer.importAnimation = true;
                    importer.animationCompression = ModelImporterAnimationCompression.Off; importer.optimizeGameObjects = false;
                    importer.importCameras = importer.importLights = false; importer.globalScale = 1; importer.useFileScale = true;
                    var defaults = importer.defaultClipAnimations; Check(defaults.Length == 1, "One authored gait take required: " + name);
                    var config = defaults[0]; config.name = name; config.loopTime = true; config.loopPose = false; config.wrapMode = WrapMode.Loop;
                    config.lockRootRotation = config.lockRootHeightY = config.lockRootPositionXZ = false;
                    importer.clipAnimations = new[] { config }; importer.SaveAndReimport();
                    var imported = AssetDatabase.LoadAllAssetsAtPath(path).OfType<AnimationClip>().Where(c => !c.name.StartsWith("__preview__", StringComparison.Ordinal)).ToArray();
                    Check(imported.Length == 1, "One imported gait clip required: " + name);
                    var clip = UnityEngine.Object.Instantiate(imported[0]); clip.name = name; clip.legacy = true; clip.wrapMode = WrapMode.Loop;
                    string clipPath = Root + "/Animations/" + name + ".anim";
                    var existing = AssetDatabase.LoadAssetAtPath<AnimationClip>(clipPath);
                    if (existing == null) AssetDatabase.CreateAsset(clip, clipPath);
                    else { EditorUtility.CopySerialized(clip, existing); UnityEngine.Object.DestroyImmediate(clip); clip = existing; }
                    var bindings = AnimationUtility.GetCurveBindings(clip);
                    Check(bindings.Length > 200, "A real captured skeletal gait is required: " + name);
                    Check(bindings.All(b => b.type != typeof(Transform) || string.IsNullOrEmpty(b.path) || instance.transform.Find(b.path) != null), "Gait paths must bind the actual dog: " + name);
                    Check(Mathf.Abs(clip.length - (float)spec["duration"]) < 1.1f / fps, "Imported gait duration must match authoring: " + name);
                    Check(clip.legacy && clip.wrapMode == WrapMode.Loop && AnimationUtility.GetAnimationClipSettings(clip).loopTime, "Legacy gait must loop at runtime: " + name);
                    var root = transforms.Single(t => t.name == "GLTF_created_0_rootJoint");
                    Vector3[] first = null; Quaternion[] firstRot = null; Vector3 firstRoot = default; float loopPosition = 0, loopAngle = 0, rootPlanar = 0, maxAngle = 0, minY = float.PositiveInfinity, maxY = float.NegativeInfinity;
                    int intervals = Mathf.Max(16, Mathf.CeilToInt(clip.length * fps));
                    for (int sample = 0; sample <= intervals; sample++)
                    {
                        for (int i = 0; i < transforms.Length; i++) { transforms[i].localPosition = positions[i]; transforms[i].localRotation = rotations[i]; transforms[i].localScale = scales[i]; }
                        clip.SampleAnimation(instance, clip.length * sample / intervals);
                        Check(transforms.All(t => Finite(t.localPosition) && Finite(t.localScale) && Finite(t.localRotation)), "Finite actual gait sample: " + name + "/" + sample);
                        if (sample == 0) { first = transforms.Select(t => t.localPosition).ToArray(); firstRot = transforms.Select(t => t.localRotation).ToArray(); firstRoot = root.position; }
                        else for (int i = 0; i < transforms.Length; i++) maxAngle = Mathf.Max(maxAngle, Quaternion.Angle(firstRot[i], transforms[i].localRotation));
                        rootPlanar = Mathf.Max(rootPlanar, Vector3.ProjectOnPlane(root.position - firstRoot, Vector3.up).magnitude); minY = Mathf.Min(minY, root.position.y); maxY = Mathf.Max(maxY, root.position.y);
                        if (sample == intervals) for (int i = 0; i < transforms.Length; i++) { loopPosition = Mathf.Max(loopPosition, Vector3.Distance(first[i], transforms[i].localPosition)); loopAngle = Mathf.Max(loopAngle, Quaternion.Angle(firstRot[i], transforms[i].localRotation)); }
                    }
                    Check(maxAngle > 15, "Captured gait must articulate limbs: " + name);
                    Check(rootPlanar < .005f, "In-place root must not drift across the floor: " + name);
                    Check(loopPosition < .005f && loopAngle < 1, "Loop boundary must be continuous on the actual rig: " + name);
                    clips.Add(new JObject { ["name"] = name, ["asset"] = clipPath, ["fbx_sha256"] = Hash(path), ["duration_s"] = clip.length, ["bindings"] = bindings.Length, ["sample_count"] = intervals + 1, ["loop"] = true, ["loop_position_m"] = loopPosition, ["loop_angle_degrees"] = loopAngle, ["root_planar_drift_m"] = rootPlanar, ["root_vertical_range_m"] = maxY - minY, ["maximum_joint_rotation_degrees"] = maxAngle, ["speed_m_s"] = spec["speed_m_s"] });
                }
                AssetDatabase.SaveAssets();
                Check(conserved.All(p => File.Exists(p.Key) && Hash(p.Key) == p.Value), "Existing dog, textures, material, prefab and idle/petting clips are byte-identical.");
                var receipt = new JObject { ["result"] = "Passed", ["unity_version"] = Application.unityVersion, ["checks"] = checks, ["motions"] = clips, ["preserved_assets"] = conserved.Count, ["limitations"] = new JArray("Actual imported transforms and root loops are checked. DCC verifies paw support; runtime F2 and rendered appearance are checked separately.") };
                File.WriteAllText(Path.GetFullPath(Path.Combine(source, "../../locomotion-unity-import.json")), receipt.ToString() + "\n"); return receipt.ToString();
            }
            finally { UnityEngine.Object.DestroyImmediate(instance); }
        }
        static bool Finite(Vector3 v) => float.IsFinite(v.x) && float.IsFinite(v.y) && float.IsFinite(v.z);
        static bool Finite(Quaternion q) => float.IsFinite(q.x) && float.IsFinite(q.y) && float.IsFinite(q.z) && float.IsFinite(q.w);
    }
}
