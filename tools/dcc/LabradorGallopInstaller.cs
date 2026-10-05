// Run with live Unity run_script after the authored gallop has passed independent visual/skin review.
// Entry: MusimusihanRpg.Tools.LabradorGallopInstaller.Install(sourceFbx, manifestPath, beforeSnapshot, reportPath).
// Replaces only existing Run.fbx/Run.anim and preserves their GUIDs plus every Walk/care/model asset.
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
    public static class LabradorGallopInstaller
    {
        const string Root = "Assets/RPG/Resources/Pets/Labrador";
        const string RunFbx = Root + "/Animations/Run.fbx", RunAnim = Root + "/Animations/Run.anim";
        static readonly string[] Feet = { "FF.L_46", "FF.R_50", "FFB.L_44", "FFB.R_48" };
        static readonly Dictionary<string, string> Ankles = new Dictionary<string, string>
        {
            { "FF.L_46", "IKFrontLeg.L_47" }, { "FF.R_50", "IKFrontLeg.R_51" },
            { "FFB.L_44", "IKBackLeg.L_45" }, { "FFB.R_48", "IKBackLeg.R_49" }
        };
        const float FootRegionWeight = .65f;
        static int checks;
        static void Check(bool condition, string text) { checks++; if (!condition) throw new InvalidOperationException(text); }
        static string Hash(string path) { using var sha = SHA256.Create(); return BitConverter.ToString(sha.ComputeHash(File.ReadAllBytes(path))).Replace("-", "").ToLowerInvariant(); }

        public static string Install(string sourceFbx, string manifestPath, string beforeSnapshot, string reportPath)
        {
            checks = 0;
            Check(!EditorApplication.isPlaying && !EditorApplication.isCompiling, "Install an independently reviewed gallop in ready Edit mode.");
            sourceFbx = Path.GetFullPath(sourceFbx); manifestPath = Path.GetFullPath(manifestPath); reportPath = Path.GetFullPath(reportPath);
            Check(File.Exists(sourceFbx) && Path.GetExtension(sourceFbx).Equals(".fbx", StringComparison.OrdinalIgnoreCase), "The final authored Run FBX is required.");
            var manifest = JObject.Parse(File.ReadAllText(manifestPath));
            var specs = manifest["clips"].OfType<JObject>().Where(s => (string)s["name"] == "Run").ToArray();
            Check(specs.Length == 1, "The approved manifest must identify exactly one Run clip; other clips stay unchanged.");
            var spec = specs[0]; float fps = (float?)manifest["fps"] ?? 60, duration = (float?)spec["duration"] ?? 0;
            Check(float.IsFinite(fps) && fps > 0 && float.IsFinite(duration) && duration > .2f && (bool?)spec["loop"] == true
                && ((string)spec["root_motion"] ?? "").StartsWith("in-place", StringComparison.Ordinal), "New Run must have a finite authored period and an in-place loop policy.");
            var before = JObject.Parse(File.ReadAllText(beforeSnapshot)); var records = (JObject)before["files"];
            Check(records != null && records.Count > 15, "A complete preservation snapshot is required.");
            Check(records.Properties().All(p => File.Exists(p.Name) && Hash(p.Name) == (string)p.Value["sha256"]), "Existing Labrador assets must still match the snapshot before Run replacement.");
            var prefab = AssetDatabase.LoadAssetAtPath<GameObject>(Root + "/PetModel.prefab");
            var existing = AssetDatabase.LoadAssetAtPath<AnimationClip>(RunAnim); var importer = AssetImporter.GetAtPath(RunFbx) as ModelImporter;
            Check(prefab != null && existing != null && importer != null, "Existing actual dog and Run resources are required; this tool does not create a replacement dog.");
            string fbxGuid = AssetDatabase.AssetPathToGUID(RunFbx), animGuid = AssetDatabase.AssetPathToGUID(RunAnim);
            Check(fbxGuid == (string)records[RunFbx + ".meta"]?["guid"] && animGuid == (string)records[RunAnim + ".meta"]?["guid"], "The original Run GUIDs must match the snapshot.");
            var instance = PrefabUtility.InstantiatePrefab(prefab) as GameObject;
            Check(instance != null, "Instantiate the preserved actual Labrador for real imported-pose evaluation.");
            byte[] originalFbx = File.ReadAllBytes(RunFbx); var originalClip = UnityEngine.Object.Instantiate(existing);
            string originalImporter = EditorJsonUtility.ToJson(importer);
            bool mutated = false;
            try
            {
                foreach (var animation in instance.GetComponentsInChildren<Animation>(true)) animation.enabled = false;
                foreach (var animator in instance.GetComponentsInChildren<Animator>(true)) animator.enabled = false;
                File.Copy(sourceFbx, RunFbx, true); mutated = true;
                AssetDatabase.ImportAsset(RunFbx, ImportAssetOptions.ForceSynchronousImport);
                importer = AssetImporter.GetAtPath(RunFbx) as ModelImporter;
                importer.animationType = ModelImporterAnimationType.Legacy; importer.importAnimation = true;
                importer.animationCompression = ModelImporterAnimationCompression.Off; importer.optimizeGameObjects = false;
                importer.importCameras = importer.importLights = false; importer.globalScale = 1; importer.useFileScale = true;
                var defaults = importer.defaultClipAnimations; Check(defaults.Length == 1, "The final Run FBX must contain one authored take.");
                var config = defaults[0]; config.name = "Run"; config.loopTime = true; config.loopPose = false; config.wrapMode = WrapMode.Loop;
                config.lockRootRotation = config.lockRootHeightY = config.lockRootPositionXZ = false;
                importer.clipAnimations = new[] { config }; importer.SaveAndReimport();
                var supplied = AssetDatabase.LoadAllAssetsAtPath(RunFbx).OfType<AnimationClip>().Where(c => !c.name.StartsWith("__preview__", StringComparison.Ordinal)).ToArray();
                Check(supplied.Length == 1, "Exactly one actual gallop clip must import.");
                var clip = UnityEngine.Object.Instantiate(supplied[0]); clip.name = "Run"; clip.legacy = true; clip.wrapMode = WrapMode.Loop;
                try { EditorUtility.CopySerialized(clip, existing); }
                finally { UnityEngine.Object.DestroyImmediate(clip); }
                var receipt = Validate(instance, existing, spec, fps);
                AssetDatabase.SaveAssets();
                Check(AssetDatabase.AssetPathToGUID(RunFbx) == fbxGuid && AssetDatabase.AssetPathToGUID(RunAnim) == animGuid, "Replacing Run conserves both existing GUIDs.");
                var conserved = records.Properties().Where(p => p.Name != RunFbx && p.Name != RunAnim && p.Name != RunFbx + ".meta").ToArray();
                Check(conserved.All(p => File.Exists(p.Name) && Hash(p.Name) == (string)p.Value["sha256"]), "Walk, both care clips, original dog, materials, textures and their metadata remain byte-identical.");
                Check(Hash(RunFbx) == Hash(sourceFbx), "The installed FBX exactly matches the approved source.");
                receipt["result"] = "Passed"; receipt["checks"] = checks; receipt["unity_version"] = Application.unityVersion;
                receipt["source_fbx"] = sourceFbx; receipt["source_fbx_sha256"] = Hash(sourceFbx); receipt["manifest_sha256"] = Hash(manifestPath);
                receipt["installed_fbx_guid"] = fbxGuid; receipt["installed_anim_guid"] = animGuid;
                receipt["installed_anim_sha256"] = Hash(RunAnim); receipt["preserved_files"] = conserved.Length;
                receipt["limitations"] = new JArray("Imported rig, real evaluated skin, four paw support/swing and airborne samples are measured. Physical force and visual style are reviewed in the separate DCC/preview acceptance.", "The runtime reads the actual clip period at rate 1; this upgrade does not add companion navigation or change Walk/petting.");
                Directory.CreateDirectory(Path.GetDirectoryName(reportPath)); File.WriteAllText(reportPath, receipt.ToString() + "\n"); return receipt.ToString();
            }
            catch
            {
                if (mutated)
                {
                    // Restore through importer/asset APIs; never hand-edit prefab, importer or animation YAML.
                    File.WriteAllBytes(RunFbx, originalFbx); AssetDatabase.ImportAsset(RunFbx, ImportAssetOptions.ForceSynchronousImport);
                    importer = AssetImporter.GetAtPath(RunFbx) as ModelImporter;
                    EditorJsonUtility.FromJsonOverwrite(originalImporter, importer); importer.SaveAndReimport();
                    EditorUtility.CopySerialized(originalClip, existing); AssetDatabase.SaveAssets();
                }
                throw;
            }
            finally { UnityEngine.Object.DestroyImmediate(originalClip); UnityEngine.Object.DestroyImmediate(instance); }
        }

        static JObject Validate(GameObject instance, AnimationClip clip, JObject spec, float fps)
        {
            var bindings = AnimationUtility.GetCurveBindings(clip);
            Check(bindings.Length > 200 && bindings.All(b => b.type != typeof(Transform) || string.IsNullOrEmpty(b.path) || instance.transform.Find(b.path) != null), "Every authored gallop curve binds the existing actual dog.");
            Check(Mathf.Abs(clip.length - (float)spec["duration"]) < 1.1f / fps && clip.legacy && clip.wrapMode == WrapMode.Loop && AnimationUtility.GetAnimationClipSettings(clip).loopTime, "Actual Run period and loop settings match the approved authoring.");
            var transforms = instance.GetComponentsInChildren<Transform>(true);
            var positions = transforms.Select(t => t.localPosition).ToArray(); var rotations = transforms.Select(t => t.localRotation).ToArray(); var scales = transforms.Select(t => t.localScale).ToArray();
            var joint = transforms.Single(t => t.name == "GLTF_created_0_rootJoint");
            var skin = instance.GetComponentsInChildren<SkinnedMeshRenderer>(true).Where(r => r.sharedMesh != null && Feet.Concat(Ankles.Values).All(n => r.bones.Any(b => b.name == n)))
                .OrderByDescending(r => r.sharedMesh.vertexCount).FirstOrDefault();
            Check(skin != null && skin.sharedMesh.vertexCount > 20000, "The actual detailed body skin supplies the four paw regions.");
            var weights = skin.sharedMesh.boneWeights;
            var pads = Feet.ToDictionary(n => n, n =>
            {
                int toe = Array.FindIndex(skin.bones, b => b.name == n), ankle = Array.FindIndex(skin.bones, b => b.name == Ankles[n]);
                // Acquired heel skin can belong primarily to the ankle (e.g. 79% ankle/12% toe).
                // Use the complete anatomical foot region for contact/flight classification.
                // Whole-body floor penetration remains checked independently on every skin vertex.
                return Enumerable.Range(0, weights.Length).Where(i => Weight(weights[i], toe) + Weight(weights[i], ankle) >= FootRegionWeight).ToArray();
            });
            Check(pads.All(p => p.Value.Length > 20), "All four complete ankle/toe foot-skin regions exist on the real dog.");
            int intervals = Mathf.Max(24, Mathf.CeilToInt(clip.length * 120));
            var lows = Feet.ToDictionary(n => n, _ => float.PositiveInfinity); var highs = Feet.ToDictionary(n => n, _ => float.NegativeInfinity);
            Vector3[] first = null; Quaternion[] firstRot = null; Vector3 firstRoot = default;
            float loopPosition = 0, loopAngle = 0, rootPlanar = 0, maxAngle = 0, skinLow = float.PositiveInfinity, airborneClearance = 0;
            int flightSamples = 0; var phaseSamples = new JArray(); var baked = new Mesh();
            try
            {
                for (int sample = 0; sample <= intervals; sample++)
                {
                    for (int i = 0; i < transforms.Length; i++) { transforms[i].localPosition = positions[i]; transforms[i].localRotation = rotations[i]; transforms[i].localScale = scales[i]; }
                    clip.SampleAnimation(instance, clip.length * sample / intervals);
                    Check(transforms.All(t => Finite(t.localPosition) && Finite(t.localScale) && Finite(t.localRotation)), "Finite actual gallop pose: " + sample);
                    if (sample == 0) { first = transforms.Select(t => t.localPosition).ToArray(); firstRot = transforms.Select(t => t.localRotation).ToArray(); firstRoot = joint.position; }
                    else for (int i = 0; i < transforms.Length; i++) maxAngle = Mathf.Max(maxAngle, Quaternion.Angle(firstRot[i], transforms[i].localRotation));
                    rootPlanar = Mathf.Max(rootPlanar, Vector3.ProjectOnPlane(joint.position - firstRoot, Vector3.up).magnitude);
                    if (sample == intervals) for (int i = 0; i < transforms.Length; i++) { loopPosition = Mathf.Max(loopPosition, Vector3.Distance(first[i], transforms[i].localPosition)); loopAngle = Mathf.Max(loopAngle, Quaternion.Angle(firstRot[i], transforms[i].localRotation)); }
                    skin.BakeMesh(baked, true); var world = baked.vertices.Select(skin.transform.TransformPoint).ToArray();
                    Check(world.All(Finite), "Finite actual gallop skin: " + sample);
                    skinLow = Mathf.Min(skinLow, world.Min(v => v.y));
                    var footHeights = pads.ToDictionary(p => p.Key, p => p.Value.Min(i => world[i].y));
                    foreach (string name in Feet) { lows[name] = Mathf.Min(lows[name], footHeights[name]); highs[name] = Mathf.Max(highs[name], footHeights[name]); }
                    float flightHeight = footHeights.Values.Min(); airborneClearance = Mathf.Max(airborneClearance, flightHeight);
                    if (sample < intervals && flightHeight > .005f) flightSamples++;
                    if (sample % Mathf.Max(1, intervals / 8) == 0 || sample == intervals)
                        phaseSamples.Add(new JObject { ["phase"] = (float)sample / intervals, ["paw_floor_y_m"] = JObject.FromObject(footHeights), ["all_paws_airborne"] = flightHeight > .005f });
                }
            }
            finally { UnityEngine.Object.DestroyImmediate(baked); }
            Check(maxAngle > 15 && rootPlanar < .005f, "New Run articulates the rig while its placement root stays fixed.");
            Check(loopPosition < .005f && loopAngle < 1, "New gallop loops continuously on the actual model.");
            Check(skinLow > -.0045f, "Actual imported skin stays within 4.5mm floor tolerance.");
            Check(Feet.All(n => lows[n] < .006f && lows[n] > -.0045f && highs[n] > .02f), "Each actual paw contacts the floor and has a visible swing arc.");
            Check(flightSamples > 0, "New actual gallop includes a distinct all-four-paws airborne phase.");
            return new JObject
            {
                ["clip"] = "Run", ["duration_s"] = clip.length, ["speed_m_s"] = spec["speed_m_s"], ["bindings"] = bindings.Length,
                ["skin_samples"] = intervals + 1, ["sample_hz"] = 120, ["root_planar_drift_m"] = rootPlanar,
                ["loop_position_m"] = loopPosition, ["loop_angle_degrees"] = loopAngle, ["maximum_joint_rotation_degrees"] = maxAngle,
                ["skin_floor_minimum_m"] = skinLow, ["paw_floor_minimum_m"] = JObject.FromObject(lows), ["paw_floor_maximum_m"] = JObject.FromObject(highs),
                ["foot_region_policy"] = "Acquired ankle + toe skin weight sum >= 0.65; heel included; whole-body floor bound unchanged",
                ["foot_regions"] = new JArray(Feet.Select(n => new JObject { ["toe"] = n, ["ankle"] = Ankles[n], ["minimum_combined_weight"] = FootRegionWeight, ["vertices"] = pads[n].Length })),
                ["airborne_samples"] = flightSamples, ["airborne_fraction"] = (float)flightSamples / intervals, ["airborne_clearance_m"] = airborneClearance, ["phase_samples"] = phaseSamples
            };
        }
        static float Weight(BoneWeight w, int bone) => (w.boneIndex0 == bone ? w.weight0 : 0) + (w.boneIndex1 == bone ? w.weight1 : 0) + (w.boneIndex2 == bone ? w.weight2 : 0) + (w.boneIndex3 == bone ? w.weight3 : 0);
        static bool Finite(Vector3 v) => float.IsFinite(v.x) && float.IsFinite(v.y) && float.IsFinite(v.z);
        static bool Finite(Quaternion q) => float.IsFinite(q.x) && float.IsFinite(q.y) && float.IsFinite(q.z) && float.IsFinite(q.w);
    }
}
