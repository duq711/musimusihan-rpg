// Compile/run in the stopped live Unity Editor through unity-cli run_script.
// Entry: MusimusihanRpg.Tools.LabradorPetRender.InspectAndRender(exportDirectory).
// Uses the installed model and clip, writes images/receipt only, and closes its own PreviewScene.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using Newtonsoft.Json.Linq;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.SceneManagement;

namespace MusimusihanRpg.Tools
{
    public static class LabradorPetRender
    {
        const int Width = 1280, Height = 900;
        const string PrefabPath = "Assets/RPG/Resources/Pets/Labrador/PetModel.prefab";
        const string ClipPath = "Assets/RPG/Resources/Pets/Labrador/Animations/PetEnjoy.anim";
        static int checks;

        static void Check(bool condition, string message)
        { checks++; if (!condition) throw new InvalidOperationException(message); }

        public static string DiagnoseMaterial(string exportDirectory) => DiagnoseMaterialVariants(exportDirectory, false);
        public static string DiagnoseNormalTexture(string exportDirectory) => DiagnoseMaterialVariants(exportDirectory, true);

        static string DiagnoseMaterialVariants(string exportDirectory, bool decodeNormals)
        {
            checks = 0;
            Check(!EditorApplication.isPlayingOrWillChangePlaymode && !EditorApplication.isCompiling, "Material diagnosis requires stopped, ready Edit mode.");
            var before = MainScenes(); int activeBefore = SceneManager.GetActiveScene().handle;
            var preview = EditorSceneManager.NewPreviewScene(); var temporary = new List<UnityEngine.Object>();
            string output = Path.GetFullPath(Path.Combine(exportDirectory, decodeNormals ? "../validation/unity-normal-decode" : "../validation/unity-material"));
            var receipt = new JObject();
            try
            {
                var prefab = Resources.Load<GameObject>("Pets/Labrador/PetModel"); var clip = Resources.Load<AnimationClip>("Pets/Labrador/Animations/PetEnjoy");
                Check(prefab != null && clip != null, "Actual Labrador prefab and PetEnjoy are required.");
                var model = (GameObject)PrefabUtility.InstantiatePrefab(prefab, preview);
                foreach (var behaviour in model.GetComponentsInChildren<Behaviour>(true)) behaviour.enabled = false;
                var renderers = model.GetComponentsInChildren<Renderer>(true); foreach (var renderer in renderers) renderer.enabled = true;
                clip.SampleAnimation(model, clip.length * .35f);
                var head = model.GetComponentsInChildren<Transform>(true).Single(t => t.name == "Head_1");
                var mouth = model.GetComponentsInChildren<Transform>(true).Single(t => t.name == "MouthSocket");
                var original = renderers.SelectMany(r => r.sharedMaterials).Where(m => m != null).Distinct().Single();
                var bounds = BakedBounds(model, temporary);
                var forward = Vector3.ProjectOnPlane(mouth.position - head.position, Vector3.up).normalized;
                var side = Vector3.Cross(Vector3.up, forward).normalized;
                var target = Vector3.Lerp(bounds.center, head.position, .36f) + Vector3.up * .025f;
                float distance = Mathf.Max(.85f, bounds.size.magnitude * 1.12f);
                var camera = Node(preview, "LabradorMaterialCamera", typeof(Camera)).GetComponent<Camera>();
                camera.enabled = false; camera.scene = preview; camera.clearFlags = CameraClearFlags.SolidColor;
                camera.backgroundColor = new Color(.82f, .84f, .85f, 1); camera.renderingPath = RenderingPath.Forward;
                camera.allowHDR = false; camera.allowMSAA = true; camera.fieldOfView = 34; camera.nearClipPlane = .02f; camera.farClipPlane = 15;
                camera.transform.position = target + forward * distance + side * distance * .48f + Vector3.up * distance * .24f;
                camera.transform.rotation = Quaternion.LookRotation(target - camera.transform.position, Vector3.up);
                StudioLight(preview, "StudioKey", target + forward * 2 + side * 1.5f + Vector3.up * 2.5f, target, 1.15f, new Color(1, .96f, .90f));
                StudioLight(preview, "StudioFill", target + forward * 1.3f - side * 2 + Vector3.up, target, .72f, new Color(.89f, .94f, 1));
                StudioLight(preview, "StudioRim", target - forward * 2 + side * .4f + Vector3.up * 2, target, .85f, Color.white);
                StudioFloor(preview, bounds.min.y - .002f, temporary);
                var a = new Material(original) { name = "Diagnosis_A_Actual", hideFlags = HideFlags.HideAndDontSave }; a.SetFloat("_PetStrokeStrength", 0); temporary.Add(a);
                var b = new Material(a) { name = "Diagnosis_B_NoNormal", hideFlags = HideFlags.HideAndDontSave }; b.SetFloat("_BumpScale", 0); temporary.Add(b);
                var c = new Material(b) { name = "Diagnosis_C_FlatMR", hideFlags = HideFlags.HideAndDontSave }; temporary.Add(c);
                var flat = new Texture2D(1, 1, TextureFormat.RGBA32, false, true) { hideFlags = HideFlags.HideAndDontSave };
                flat.SetPixel(0, 0, Color.clear); flat.Apply(); temporary.Add(flat); c.SetTexture("_MetallicGlossMap", flat); c.SetFloat("_GlossMapScale", 0);
                var d = new Material(Shader.Find("Unlit/Texture")) { name = "Diagnosis_D_Unlit", hideFlags = HideFlags.HideAndDontSave }; temporary.Add(d);
                d.SetTexture("_MainTex", original.GetTexture("_MainTex")); d.SetTextureScale("_MainTex", original.GetTextureScale("_MainTex")); d.SetTextureOffset("_MainTex", original.GetTextureOffset("_MainTex"));
                var variants = new[] { a, b, c, d };
                if (decodeNormals)
                {
                    string normalPath = Path.Combine(Path.GetFullPath(exportDirectory), "Textures/Labrador_Normal.png");
                    Check(File.Exists(normalPath), "Actual exported source normal PNG is missing.");
                    var rgba = new Texture2D(2, 2, TextureFormat.RGBA32, true, true) { name = "OriginalLinearNormalRGBA", hideFlags = HideFlags.HideAndDontSave, filterMode = FilterMode.Trilinear };
                    Check(rgba.LoadImage(File.ReadAllBytes(normalPath)), "Original normal PNG did not decode."); temporary.Add(rgba);
                    var pixels = rgba.GetPixels32(); for (int i = 0; i < pixels.Length; i++) pixels[i].a = 255; rgba.SetPixels32(pixels); rgba.Apply();
                    var flipped = new Texture2D(rgba.width, rgba.height, TextureFormat.RGBA32, true, true) { name = "FlippedLinearNormalRGBA", hideFlags = HideFlags.HideAndDontSave, filterMode = FilterMode.Trilinear };
                    for (int i = 0; i < pixels.Length; i++) pixels[i].g = (byte)(255 - pixels[i].g); flipped.SetPixels32(pixels); flipped.Apply(); temporary.Add(flipped);
                    var rawMaterial = new Material(a) { name = "Normal_E_RawRGBA", hideFlags = HideFlags.HideAndDontSave }; rawMaterial.SetTexture("_BumpMap", rgba); temporary.Add(rawMaterial);
                    var greenMaterial = new Material(a) { name = "Normal_F_FlipGreen", hideFlags = HideFlags.HideAndDontSave }; greenMaterial.SetTexture("_BumpMap", flipped); temporary.Add(greenMaterial);
                    var standard = new Material(Shader.Find("Standard")) { name = "Normal_G_StandardRaw", hideFlags = HideFlags.HideAndDontSave }; temporary.Add(standard);
                    standard.SetColor("_Color", Color.white); standard.SetTexture("_MainTex", original.GetTexture("_MainTex")); standard.SetTexture("_BumpMap", rgba);
                    standard.SetTexture("_MetallicGlossMap", original.GetTexture("_MetallicGlossMap")); standard.SetFloat("_BumpScale", .2f); standard.SetFloat("_GlossMapScale", 1);
                    standard.SetFloat("_Glossiness", 1); standard.SetFloat("_Metallic", 1); standard.EnableKeyword("_NORMALMAP"); standard.EnableKeyword("_METALLICGLOSSMAP");
                    variants = new[] { a, b, rawMaterial, greenMaterial, standard };
                }
                Directory.CreateDirectory(output); var images = new JArray();
                foreach (var material in variants)
                {
                    foreach (var renderer in renderers) renderer.sharedMaterials = renderer.sharedMaterials.Select(_ => material).ToArray();
                    images.Add(Render(camera, model, Path.Combine(output, material.name + ".png")));
                }
                receipt = new JObject { ["result"] = "Passed", ["checks"] = checks, ["unity_version"] = Application.unityVersion,
                    ["capture_method"] = "Same actual CPU-evaluated PetEnjoy pose, camera and studio. Clone materials in isolated PreviewScene only; no assets/importers changed.",
                    ["images"] = images, ["variants"] = new JObject { ["A"] = "Actual imported material, normal strength 0.2 and actual packed metallic/smoothness.",
                        ["B"] = "A with normal strength zero.", ["C"] = "B with the actual base color retained, metallic zero and uniform roughness one.", ["D"] = "Unlit actual base color only." },
                    ["original_material"] = AssetDatabase.GetAssetPath(original), ["shader"] = original.shader.name,
                    ["shader_errors"] = ShaderUtil.ShaderHasError(original.shader) };
                if (decodeNormals) receipt["variants"] = new JObject { ["A"] = "Actual Unity-imported normal texture, coat shader, strength 0.2.", ["B"] = "A with normal strength zero.",
                    ["E"] = "Actual source normal PNG decoded into temporary linear RGBA32, alpha forced one, coat shader, strength 0.2.",
                    ["F"] = "E with green channel inverted.", ["G"] = "E texture and actual base/metal/smooth maps in Unity Standard shader, strength 0.2." };
            }
            finally
            {
                if (preview.IsValid()) EditorSceneManager.ClosePreviewScene(preview);
                foreach (var item in temporary) if (item != null) UnityEngine.Object.DestroyImmediate(item);
                Check(SceneManager.GetActiveScene().handle == activeBefore && JToken.DeepEquals(before, MainScenes()), "Material diagnosis changed the main scene state.");
            }
            receipt["checks"] = checks; receipt["main_scenes_preserved"] = true;
            File.WriteAllText(Path.Combine(output, "receipt.json"), receipt.ToString() + "\n"); return receipt.ToString();
        }

        public static string InspectAndRender(string exportDirectory)
        {
            checks = 0;
            Check(!EditorApplication.isPlayingOrWillChangePlaymode && !EditorApplication.isCompiling, "Run in stopped, ready Edit mode.");
            var before = MainScenes(); int activeBefore = SceneManager.GetActiveScene().handle;
            var activeTexture = RenderTexture.active;
            string output = Path.GetFullPath(exportDirectory), validation = Path.GetFullPath(Path.Combine(output, "../validation/unity"));
            var prefab = Resources.Load<GameObject>("Pets/Labrador/PetModel");
            var clip = Resources.Load<AnimationClip>("Pets/Labrador/Animations/PetEnjoy");
            Check(prefab != null && AssetDatabase.GetAssetPath(prefab) == PrefabPath, "Install the actual PetModel prefab before rendering.");
            Check(clip != null && AssetDatabase.GetAssetPath(clip) == ClipPath && clip.length > 0, "Install the actual PetEnjoy clip before rendering.");
            var shader = Shader.Find("RPG/Labrador Petting");
            Check(shader != null && shader.isSupported, "The actual coat shader is missing or unsupported.");
            var preview = EditorSceneManager.NewPreviewScene();
            var temporary = new List<UnityEngine.Object>();
            JObject receipt = null;
            try
            {
                var model = (GameObject)PrefabUtility.InstantiatePrefab(prefab, preview);
                Check(model != null, "PreviewScene could not instantiate the actual prefab.");
                model.name = "LabradorPet_RenderOnly"; model.SetActive(true);
                foreach (var behaviour in model.GetComponentsInChildren<Behaviour>(true)) behaviour.enabled = false;
                foreach (var renderer in model.GetComponentsInChildren<Renderer>(true)) renderer.enabled = true;
                foreach (var skin in model.GetComponentsInChildren<SkinnedMeshRenderer>(true)) skin.updateWhenOffscreen = true;
                var transforms = model.GetComponentsInChildren<Transform>(true);
                Transform Bone(string name) => transforms.SingleOrDefault(t => t.name == name) ?? throw new InvalidOperationException("Missing actual bone: " + name);
                var head = Bone("Head_1"); var mouth = Bone("MouthSocket");
                var left = new[] { Bone("Ear1.L_5"), Bone("Ear2.L_4"), Bone("Ear3.L_3"), Bone("Ear4.L_2") };
                var right = new[] { Bone("Ear1.R_9"), Bone("Ear2.R_8"), Bone("Ear3.R_7"), Bone("Ear4.R_6") };
                var relevant = new[] { Bone("Neck1_14"), Bone("Neck2_13"), Bone("Neck3_12"), head, Bone("Neck3.001_11"), Bone("Neck3.002_10"), mouth }.Concat(left).Concat(right).ToArray();
                var restAxes = new JArray(relevant.Select(t => BoneReceipt(t, model.transform)));
                var meshReceipt = InspectMeshes(model, head, temporary);
                var materials = model.GetComponentsInChildren<Renderer>(true).SelectMany(r => r.sharedMaterials).Where(m => m != null).Distinct().ToArray();
                Check(materials.Length > 0 && materials.All(m => m.shader == shader), "Preview must use the installed coat shader on every actual renderer.");
                Check(materials.All(m => m.GetTexture("_MainTex") != null && m.GetTexture("_BumpMap") != null && m.GetTexture("_MetallicGlossMap") != null), "Actual PBR maps are missing.");
                float sampleTime = clip.length * .35f;
                clip.SampleAnimation(model, sampleTime);
                Check(transforms.All(t => Finite(t.localPosition) && Finite(t.localRotation)), "Actual PetEnjoy has a non-finite pose.");
                var skins = model.GetComponentsInChildren<SkinnedMeshRenderer>(true);
                var eyes = new Dictionary<SkinnedMeshRenderer, int>();
                foreach (var skin in skins)
                    for (int i = 0; i < skin.sharedMesh.blendShapeCount; i++)
                        if (skin.sharedMesh.GetBlendShapeName(i).EndsWith("target_1", StringComparison.Ordinal)) { eyes[skin] = i; break; }
                Check(eyes.Count > 0, "Original target_1 eyelid shape was lost in FBX import.");
                foreach (var pair in eyes) pair.Key.SetBlendShapeWeight(pair.Value, 0);
                var bounds = BakedBounds(model, temporary);
                var forward = Vector3.ProjectOnPlane(mouth.position - head.position, Vector3.up).normalized;
                Check(forward.sqrMagnitude > .9f, "Mouth/head positions do not establish the real facing direction.");
                var side = Vector3.Cross(Vector3.up, forward).normalized;
                var target = Vector3.Lerp(bounds.center, head.position, .36f) + Vector3.up * .025f;
                float distance = Mathf.Max(.85f, bounds.size.magnitude * 1.12f);
                var cameraObject = Node(preview, "LabradorStudioCamera", typeof(Camera));
                var camera = cameraObject.GetComponent<Camera>(); camera.enabled = false; camera.scene = preview;
                camera.clearFlags = CameraClearFlags.SolidColor; camera.backgroundColor = new Color(.82f, .84f, .85f, 1);
                camera.renderingPath = RenderingPath.Forward; camera.allowHDR = false; camera.allowMSAA = true;
                camera.fieldOfView = 34; camera.nearClipPlane = .02f; camera.farClipPlane = 15;
                camera.transform.SetPositionAndRotation(target + forward * distance + side * distance * .48f + Vector3.up * distance * .24f,
                    Quaternion.LookRotation(target - (target + forward * distance + side * distance * .48f + Vector3.up * distance * .24f), Vector3.up));
                StudioLight(preview, "StudioKey", target + forward * 2 + side * 1.5f + Vector3.up * 2.5f, target, 1.15f, new Color(1, .96f, .90f));
                StudioLight(preview, "StudioFill", target + forward * 1.3f - side * 2 + Vector3.up, target, .72f, new Color(.89f, .94f, 1));
                StudioLight(preview, "StudioRim", target - forward * 2 + side * .4f + Vector3.up * 2, target, .85f, Color.white);
                StudioFloor(preview, bounds.min.y - .002f, temporary);
                Directory.CreateDirectory(output); Directory.CreateDirectory(validation);
                var images = new JArray();
                string neutral = Path.Combine(validation, "neutral.png");
                images.Add(Render(camera, model, neutral));
                var sampledAxes = new JArray(relevant.Select(t => BoneReceipt(t, model.transform)));
                var folds = new JArray();
                Fold(left, head, forward, folds); Fold(right, head, forward, folds);
                images.Add(Render(camera, model, Path.Combine(validation, "ears.png")));
                foreach (var pair in eyes) pair.Key.SetBlendShapeWeight(pair.Value, 45);
                images.Add(Render(camera, model, Path.Combine(validation, "ears_squint_45.png")));
                Check(images.Select(i => (string)i["sha256"]).Distinct().Count() == 3, "Neutral, folded ears and relaxed eyelids must produce three distinct evaluated images.");
                // Same sub-millimetre localized stroke used by the installed runtime shader.
                foreach (var renderer in model.GetComponentsInChildren<Renderer>(true))
                {
                    var properties = new MaterialPropertyBlock(); renderer.GetPropertyBlock(properties);
                    properties.SetVector("_PetStrokeOrigin", head.position + Vector3.up * .055f - forward * .025f);
                    properties.SetVector("_PetStrokeDirection", -forward); properties.SetFloat("_PetStrokeStrength", .6f);
                    properties.SetFloat("_PetStrokeRadius", .065f); renderer.SetPropertyBlock(properties);
                }
                string poster = Path.Combine(output, "LabradorPet_Petting.png"); images.Add(Render(camera, model, poster));
                var messages = ShaderUtil.GetShaderMessages(shader);
                Check(!ShaderUtil.ShaderHasError(shader) && !messages.Any(m => m.severity.ToString() == "Error"), "The real rendered coat shader has compiler errors.");
                receipt = new JObject
                {
                    ["result"] = "Passed", ["unity_version"] = Application.unityVersion, ["checks"] = checks,
                    ["prefab"] = PrefabPath, ["clip"] = ClipPath, ["clip_sample_seconds"] = sampleTime,
                    ["size"] = new JArray(Width, Height), ["poster"] = poster, ["images"] = images,
                    ["capture_method"] = "Fresh CPU BakeMesh(true) pose and blendshape snapshots rendered with the actual material and stroke properties in an isolated Unity PreviewScene. This is an evaluated Unity pose, not a live app screenshot.",
                    ["rendered_pose_bounds_m"] = BoundsReceipt(bounds), ["head_position_m"] = V(head.position),
                    ["forward"] = V(forward), ["rest_bones"] = restAxes, ["sampled_bones"] = sampledAxes,
                    ["ear_fold"] = folds, ["meshes"] = meshReceipt,
                    ["eye_overlay"] = new JObject { ["source_shape"] = "target_1", ["unity_weight"] = 45, ["matching_renderers"] = eyes.Count },
                    ["shader"] = new JObject { ["name"] = shader.name, ["supported"] = shader.isSupported,
                        ["has_error"] = ShaderUtil.ShaderHasError(shader), ["messages"] = new JArray(messages.Select(m => new JObject { ["severity"] = m.severity.ToString(), ["message"] = m.message, ["line"] = m.line })) },
                    ["materials"] = new JArray(materials.Select(m => new JObject { ["asset"] = AssetDatabase.GetAssetPath(m), ["bump_scale"] = m.GetFloat("_BumpScale"), ["coat_mask"] = m.GetFloat("_PetCoatMask") })),
                    ["limitations"] = new JArray("Four actual Unity stills and imported rig/mask/shader inspection. Mouse input, temporal motion and full game integration are checked separately.")
                };
            }
            finally
            {
                RenderTexture.active = activeTexture;
                if (preview.IsValid()) EditorSceneManager.ClosePreviewScene(preview);
                foreach (var item in temporary) if (item != null) UnityEngine.Object.DestroyImmediate(item);
                Check(SceneManager.GetActiveScene().handle == activeBefore && JToken.DeepEquals(before, MainScenes()), "Main Editor scene state changed during preview.");
            }
            receipt["checks"] = checks; receipt["main_scenes_preserved"] = true;
            string report = Path.GetFullPath(Path.Combine(output, "../unity-render-summary.json"));
            File.WriteAllText(report, receipt.ToString() + "\n");
            return receipt.ToString();
        }

        static GameObject Node(Scene scene, string name, params Type[] components)
        {
            var node = EditorUtility.CreateGameObjectWithHideFlags(name, HideFlags.HideAndDontSave, components);
            SceneManager.MoveGameObjectToScene(node, scene); return node;
        }
        static void StudioLight(Scene scene, string name, Vector3 position, Vector3 target, float intensity, Color color)
        {
            var node = Node(scene, name, typeof(Light)); node.transform.SetPositionAndRotation(position, Quaternion.LookRotation(target - position));
            var light = node.GetComponent<Light>(); light.type = LightType.Directional; light.intensity = intensity; light.color = color; light.shadows = LightShadows.None;
        }
        static void StudioFloor(Scene scene, float height, List<UnityEngine.Object> temporary)
        {
            var mesh = new Mesh { name = "LabradorPreviewFloor", hideFlags = HideFlags.HideAndDontSave };
            mesh.vertices = new[] { new Vector3(-4, 0, -4), new Vector3(-4, 0, 4), new Vector3(4, 0, 4), new Vector3(4, 0, -4) };
            mesh.triangles = new[] { 0, 1, 2, 0, 2, 3 }; mesh.RecalculateNormals(); mesh.RecalculateBounds(); temporary.Add(mesh);
            var material = new Material(Shader.Find("Standard")) { name = "LabradorPreviewFloor", hideFlags = HideFlags.HideAndDontSave, color = new Color(.72f, .74f, .75f) };
            material.SetFloat("_Glossiness", 0); temporary.Add(material);
            var node = Node(scene, "LabradorStudioFloor", typeof(MeshFilter), typeof(MeshRenderer)); node.transform.position = Vector3.up * height;
            node.GetComponent<MeshFilter>().sharedMesh = mesh; node.GetComponent<MeshRenderer>().sharedMaterial = material;
        }
        static JObject Render(Camera camera, GameObject model, string path)
        {
            var target = new RenderTexture(Width, Height, 24, RenderTextureFormat.ARGB32, RenderTextureReadWrite.sRGB) { antiAliasing = 4, hideFlags = HideFlags.HideAndDontSave };
            var pixels = new Texture2D(Width, Height, TextureFormat.RGB24, false, false) { hideFlags = HideFlags.HideAndDontSave };
            var previous = RenderTexture.active;
            var evaluated = new List<GameObject>(); var bakedMeshes = new List<Mesh>();
            var originalSkins = new Dictionary<SkinnedMeshRenderer, bool>();
            try
            {
                target.Create(); camera.targetTexture = target;
                foreach (var skin in model.GetComponentsInChildren<SkinnedMeshRenderer>(true))
                {
                    if (!skin.enabled || !skin.gameObject.activeInHierarchy) continue;
                    var baked = new Mesh { name = "Evaluated_" + skin.name, hideFlags = HideFlags.HideAndDontSave };
                    bakedMeshes.Add(baked); skin.BakeMesh(baked, true);
                    Check(baked.vertexCount == skin.sharedMesh.vertexCount, "CPU pose snapshot lost actual skin vertices.");
                    var node = Node(model.scene, baked.name, typeof(MeshFilter), typeof(MeshRenderer));
                    evaluated.Add(node); node.transform.SetParent(skin.transform, false); node.layer = skin.gameObject.layer;
                    node.GetComponent<MeshFilter>().sharedMesh = baked;
                    var renderer = node.GetComponent<MeshRenderer>(); renderer.sharedMaterials = skin.sharedMaterials;
                    renderer.shadowCastingMode = skin.shadowCastingMode; renderer.receiveShadows = skin.receiveShadows;
                    renderer.lightProbeUsage = skin.lightProbeUsage; renderer.reflectionProbeUsage = skin.reflectionProbeUsage;
                    var properties = new MaterialPropertyBlock(); skin.GetPropertyBlock(properties); renderer.SetPropertyBlock(properties);
                    for (int i = 0; i < skin.sharedMaterials.Length; i++)
                    { properties.Clear(); skin.GetPropertyBlock(properties, i); if (!properties.isEmpty) renderer.SetPropertyBlock(properties, i); }
                    originalSkins.Add(skin, skin.enabled); skin.enabled = false;
                }
                camera.Render(); RenderTexture.active = target; pixels.ReadPixels(new Rect(0, 0, Width, Height), 0, 0); pixels.Apply();
                var colors = pixels.GetPixels32(); int magenta = colors.Count(c => c.r > 200 && c.g < 70 && c.b > 200);
                Check(magenta < colors.Length / 100, "Rendered image contains a magenta shader failure: " + path);
                var bytes = pixels.EncodeToPNG(); File.WriteAllBytes(path, bytes);
                return new JObject { ["path"] = path, ["bytes"] = bytes.Length, ["magenta_pixels"] = magenta, ["sha256"] = Sha256(bytes), ["evaluated_skins"] = evaluated.Count };
            }
            finally
            {
                foreach (var node in evaluated) if (node != null) UnityEngine.Object.DestroyImmediate(node);
                foreach (var mesh in bakedMeshes) if (mesh != null) UnityEngine.Object.DestroyImmediate(mesh);
                foreach (var pair in originalSkins) if (pair.Key != null) pair.Key.enabled = pair.Value;
                camera.targetTexture = null; RenderTexture.active = previous; target.Release(); UnityEngine.Object.DestroyImmediate(target); UnityEngine.Object.DestroyImmediate(pixels);
            }
        }
        static string Sha256(byte[] data)
        { using (var sha = SHA256.Create()) return BitConverter.ToString(sha.ComputeHash(data)).Replace("-", "").ToLowerInvariant(); }
        static void Fold(Transform[] chain, Transform head, Vector3 forward, JArray receipt)
        {
            float[] caps = { 8, 4, 2, 1 };
            for (int i = 0; i < chain.Length; i++)
            {
                var bone = chain[i]; var segment = i + 1 < chain.Length ? chain[i + 1].position - bone.position : bone.TransformDirection(Vector3.up);
                var inward = (head.position - bone.position).normalized;
                var folded = (-forward * .25f + Vector3.down * .65f + inward * .45f).normalized;
                var axis = Vector3.Cross(segment.normalized, folded).normalized;
                Check(axis.sqrMagnitude > .9f, "Actual ear segment cannot establish a safe fold axis: " + bone.name);
                var localAxis = bone.InverseTransformDirection(axis); var before = segment.normalized;
                bone.rotation = Quaternion.AngleAxis(caps[i], axis) * bone.rotation;
                var after = i + 1 < chain.Length ? (chain[i + 1].position - bone.position).normalized : bone.TransformDirection(Vector3.up).normalized;
                receipt.Add(new JObject { ["name"] = bone.name, ["degrees"] = caps[i], ["world_axis"] = V(axis), ["local_axis"] = V(localAxis), ["tip_before"] = V(before), ["tip_after"] = V(after), ["toward_fold_before"] = Vector3.Dot(before, folded), ["toward_fold_after"] = Vector3.Dot(after, folded) });
            }
        }
        static JArray InspectMeshes(GameObject model, Transform head, List<UnityEngine.Object> temporary)
        {
            var result = new JArray(); int maskedMeshes = 0;
            foreach (var skin in model.GetComponentsInChildren<SkinnedMeshRenderer>(true))
            {
                var mesh = skin.sharedMesh; Check(mesh != null && mesh.isReadable, "Actual mesh must remain readable for head-surface raycasting.");
                var colors = mesh.colors32; var weights = mesh.boneWeights;
                var baked = new Mesh { hideFlags = HideFlags.HideAndDontSave }; temporary.Add(baked); skin.BakeMesh(baked, true);
                var vertices = baked.vertices; var headPoints = new List<Vector3>(); var coatPoints = new List<Vector3>();
                bool IsHead(int b) => b >= 0 && b < skin.bones.Length && skin.bones[b] != null && (skin.bones[b].name == "Head_1" || skin.bones[b].name == "Neck3.001_11" || skin.bones[b].name == "Neck3.002_10");
                for (int i = 0; i < vertices.Length; i++)
                {
                    var point = head.InverseTransformPoint(skin.transform.TransformPoint(vertices[i]));
                    if (i < colors.Length && colors[i].r > 0) coatPoints.Add(point);
                    if (i >= weights.Length) continue; var w = weights[i];
                    float total = (IsHead(w.boneIndex0) ? w.weight0 : 0) + (IsHead(w.boneIndex1) ? w.weight1 : 0) + (IsHead(w.boneIndex2) ? w.weight2 : 0) + (IsHead(w.boneIndex3) ? w.weight3 : 0);
                    if (total >= .5f) headPoints.Add(point);
                }
                int coated = colors.Count(c => c.r > 0); if (colors.Length == mesh.vertexCount && coated > 0 && coated < mesh.vertexCount) maskedMeshes++;
                var shapes = new JArray();
                for (int s = 0; s < mesh.blendShapeCount; s++)
                {
                    var deltas = new Vector3[mesh.vertexCount]; mesh.GetBlendShapeFrameVertices(s, mesh.GetBlendShapeFrameCount(s) - 1, deltas, null, null);
                    int changed = 0, coatOverlap = 0; float maxDelta = 0, maxCoat = 0;
                    for (int i = 0; i < deltas.Length; i++) if (deltas[i].sqrMagnitude > 1e-14f)
                    { changed++; maxDelta = Mathf.Max(maxDelta, skin.transform.TransformVector(deltas[i]).magnitude); if (i < colors.Length && colors[i].r > 0) { coatOverlap++; maxCoat = Mathf.Max(maxCoat, colors[i].r / 255f); } }
                    string name = mesh.GetBlendShapeName(s);
                    if (name.EndsWith("target_1", StringComparison.Ordinal)) Check(coatOverlap == 0, "Authored coat mask touches original eyelid vertices.");
                    shapes.Add(new JObject { ["name"] = name, ["affected_vertices"] = changed, ["max_delta_m"] = maxDelta, ["coat_overlap_vertices"] = coatOverlap, ["max_overlap_mask"] = maxCoat });
                }
                result.Add(new JObject { ["renderer"] = AnimationUtility.CalculateTransformPath(skin.transform, model.transform), ["mesh"] = mesh.name, ["vertices"] = mesh.vertexCount,
                    ["triangles"] = mesh.triangles.Length / 3, ["bones"] = skin.bones.Length, ["color_vertices"] = colors.Length,
                    ["coat_vertices"] = coated, ["coat_max"] = colors.Length > 0 ? colors.Max(c => c.r) / 255f : 0,
                    ["head_local_skin_bounds_local_units"] = PointBounds(headPoints), ["head_local_coat_bounds_local_units"] = PointBounds(coatPoints), ["blend_shapes"] = shapes });
            }
            Check(maskedMeshes > 0, "No actual authored head/ear coat mask was imported."); return result;
        }
        static Bounds BakedBounds(GameObject model, List<UnityEngine.Object> temporary)
        {
            var points = new List<Vector3>();
            foreach (var skin in model.GetComponentsInChildren<SkinnedMeshRenderer>(true))
            { var mesh = new Mesh { hideFlags = HideFlags.HideAndDontSave }; temporary.Add(mesh); skin.BakeMesh(mesh, true); points.AddRange(mesh.vertices.Select(skin.transform.TransformPoint)); }
            foreach (var filter in model.GetComponentsInChildren<MeshFilter>(true))
                if (filter.sharedMesh != null && filter.sharedMesh.isReadable) points.AddRange(filter.sharedMesh.vertices.Select(filter.transform.TransformPoint));
            Check(points.Count > 1000, "Actual Labrador skin is missing from the preview."); var bounds = new Bounds(points[0], Vector3.zero); foreach (var point in points.Skip(1)) bounds.Encapsulate(point); return bounds;
        }
        static JObject BoneReceipt(Transform bone, Transform root)
        {
            return new JObject { ["name"] = bone.name, ["parent"] = bone.parent != null ? bone.parent.name : "", ["path"] = AnimationUtility.CalculateTransformPath(bone, root),
                ["local_position"] = V(bone.localPosition), ["local_rotation_xyzw"] = new JArray(bone.localRotation.x, bone.localRotation.y, bone.localRotation.z, bone.localRotation.w),
                ["world_position_m"] = V(bone.position), ["world_local_x"] = V(bone.right), ["world_local_y"] = V(bone.up), ["world_local_z"] = V(bone.forward) };
        }
        static JArray MainScenes()
        { var list = new JArray(); for (int i = 0; i < SceneManager.sceneCount; i++) { var scene = SceneManager.GetSceneAt(i); if (!EditorSceneManager.IsPreviewScene(scene)) list.Add(new JObject { ["handle"] = (int)scene.handle, ["path"] = scene.path, ["dirty"] = scene.isDirty, ["loaded"] = scene.isLoaded, ["root_count"] = scene.rootCount }); } return list; }
        static JObject PointBounds(List<Vector3> points)
        { if (points.Count == 0) return new JObject { ["count"] = 0 }; var bounds = new Bounds(points[0], Vector3.zero); foreach (var p in points.Skip(1)) bounds.Encapsulate(p); var result = BoundsReceipt(bounds); result["count"] = points.Count; return result; }
        static JObject BoundsReceipt(Bounds bounds) => new JObject { ["min"] = V(bounds.min), ["max"] = V(bounds.max), ["size"] = V(bounds.size) };
        static JArray V(Vector3 value) => new JArray(value.x, value.y, value.z);
        static bool Finite(Vector3 v) => float.IsFinite(v.x) && float.IsFinite(v.y) && float.IsFinite(v.z);
        static bool Finite(Quaternion q) => float.IsFinite(q.x) && float.IsFinite(q.y) && float.IsFinite(q.z) && float.IsFinite(q.w);
    }
}
