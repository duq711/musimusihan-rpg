using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;

namespace MusimusihanRpg.Gameplay
{
    /// <summary>Stroke response measured from head-surface motion, with bounded local skeletal overlays.</summary>
    public sealed class LabradorPettingResponse
    {
        public float Enjoyment { get; private set; }
        public float Intensity { get; private set; }
        public float LeftEar { get; private set; }
        public float RightEar { get; private set; }
        public float Yaw { get; private set; }
        public float Pitch { get; private set; }
        public float Roll { get; private set; }
        public int AcceptedStrokes { get; private set; }
        public float DistanceStroked { get; private set; }
        public bool Contact { get; private set; }
        Vector3 touch, direction;
        float targetIntensity;
        public void Stroke(Vector3 normalizedHeadPoint, Vector3 worldDeltaInHeadFrame, bool pressed, double delta)
        {
            if (!double.IsFinite(delta) || delta <= 0 || !Finite(normalizedHeadPoint) || !Finite(worldDeltaInHeadFrame)) return;
            Contact = pressed;
            if (!pressed) { targetIntensity = 0; return; }
            touch = Vector3.ClampMagnitude(normalizedHeadPoint, 1); direction = worldDeltaInHeadFrame;
            float distance = direction.magnitude;
            // A missed surface or a pointer jump must not become a long stroke.
            if (distance > .16f) { targetIntensity = 0; return; }
            targetIntensity = Mathf.Clamp01(distance / (float)delta * .7f);
            if (distance <= .0001f) return;
            AcceptedStrokes++; DistanceStroked += distance;
            Enjoyment = Mathf.Clamp01(Enjoyment + distance * (4.5f + 1.5f * (1 - targetIntensity)));
        }
        public void Advance(double delta)
        {
            if (!double.IsFinite(delta) || delta <= 0) return;
            float dt = (float)delta;
            Enjoyment = Mathf.Max(0, Enjoyment - dt * (Contact ? .007f : .035f));
            float smooth = 1 - Mathf.Exp(-dt * 9);
            Intensity = Mathf.Lerp(Intensity, Contact ? targetIntensity : 0, smooth);
            float pleasure = (Contact ? .06f : 0) + Intensity * .62f + Enjoyment * .24f;
            LeftEar = Mathf.Lerp(LeftEar, Mathf.Clamp01(pleasure * (1 - touch.x * .35f)), smooth);
            RightEar = Mathf.Lerp(RightEar, Mathf.Clamp01(pleasure * (1 + touch.x * .35f)), smooth);
            float follow = Contact ? 1 : Enjoyment * .22f;
            Yaw = Mathf.Lerp(Yaw, Mathf.Clamp(touch.x * 6 + direction.x * 55, -8, 8) * follow, smooth);
            Pitch = Mathf.Lerp(Pitch, Mathf.Clamp(-touch.y * 3 + direction.z * 45 + Enjoyment * 2, -5, 5) * follow, smooth);
            Roll = Mathf.Lerp(Roll, Mathf.Clamp(-touch.x * 4 - direction.x * 25, -5, 5) * follow, smooth);
            if (!Contact) direction = Vector3.Lerp(direction, Vector3.zero, smooth);
        }
        static bool Finite(Vector3 v) => float.IsFinite(v.x) && float.IsFinite(v.y) && float.IsFinite(v.z);
    }

    [DefaultExecutionOrder(500)]
    public sealed class LabradorPetting : DungeonInteractable
    {
        public const string TrialId = "pet_labrador_petting";
        public readonly LabradorPettingResponse Response = new LabradorPettingResponse();
        public bool Viewing { get; private set; }
        public bool ManualInput;
        public Vector3 LastStrokePoint { get; private set; }
        public Vector3 LastStrokeDirection { get; private set; }
        public bool LastPointerHit { get; private set; }
        public int SurfaceHits { get; private set; }
        public int HeadTriangles => surfaces.Sum(s => s.Triangles.Length / 3);
        public float FurStrength => Response.Intensity;
        public float EyeRelaxation { get; private set; }
        public float SurfaceRadius = .065f;
        public Transform Head { get; private set; }
        public Transform Mouth { get; private set; }
        public Camera ViewCamera => owner?.Eyes;
        public string CurrentAnimation => motion?.Current ?? "";
        public bool SuspendedView => suspendedOwner != null;
        public override bool Busy => Viewing;
        public override string Prompt => Viewing ? "머리 위에서 마우스 왼쪽 버튼을 누르고 움직여 쓰담쓰담 · E 나가기" : "[E] 래브라도 머리 쓰담쓰담";
        GameObject visual;
        PetAnimationPlayer motion;
        DungeonMotor owner;
        DungeonMotor suspendedOwner;
        PlayerPresentation presentation;
        SourceSceneRenderer sceneOutput;
        Transform neck1, neck2, neck3, upperJaw, lowerJaw;
        Transform[] leftEar, rightEar, reactive;
        readonly Dictionary<Transform, Quaternion> baseRotation = new Dictionary<Transform, Quaternion>();
        readonly List<HeadSurface> surfaces = new List<HeadSurface>();
        readonly Dictionary<SkinnedMeshRenderer, int> eyelids = new Dictionary<SkinnedMeshRenderer, int>();
        Renderer[] modelRenderers;
        MaterialPropertyBlock fur;
        Vector3 cameraLocalPosition;
        Quaternion cameraLocalRotation;
        float cameraFov, cameraNear;
        int cameraMask;
        bool ownerTimed, capturedBefore, gearEnabled;
        CursorLockMode cursorBefore;
        bool cursorVisibleBefore;
        readonly Dictionary<Renderer, bool> hiddenPlayer = new Dictionary<Renderer, bool>();
        Vector3 previousLocalHit, viewForward;
        Vector2 previousPointer;
        bool previousPressed, configured, restorePending;
        int enteredFrame;
        double blinkClock;
        string action = "IdleFriendly";
        float nextBlink = 5.2f;
        bool Live => configured && Game != null && Game.Session != null && !Game.WorldPaused && Game.Page == "dungeon" && !Game.Session.Body.IsDead && (Game.NativeGame == null || Game.NativeGame.State == "playing");

        public static LabradorPetting Spawn(WorkshopController game, GameObject prefab, AnimationClip[] clips, Vector3 position)
        {
            if (game == null || prefab == null || clips == null || !clips.Any(c => c != null && c.name == "IdleFriendly")) throw new ArgumentException("Actual Labrador and idle animation are required");
            var node = new GameObject("LabradorMousePetting"); node.transform.SetParent(game.DungeonRoot.transform, false); node.transform.position = position; node.layer = 2;
            var model = Instantiate(prefab, node.transform); model.name = "ActualLabrador"; model.SetActive(true);
            var pet = node.AddComponent<LabradorPetting>();
            try { pet.Configure(game, model, clips); }
            catch { Destroy(node); throw; }
            return pet;
        }
        public void Configure(WorkshopController game, GameObject model, AnimationClip[] clips)
        {
            Game = game; visual = model; motion = new PetAnimationPlayer(model, clips);
            foreach (string required in LabradorPettingAssets.RequiredClips) if (!motion.Has(required)) throw new InvalidOperationException("Missing actual Labrador petting clip: " + required);
            Transform Bone(string name) => model.GetComponentsInChildren<Transform>(true).FirstOrDefault(t => t.name == name) ?? throw new InvalidOperationException("Missing actual Labrador bone: " + name);
            Head = Bone("Head_1"); Mouth = Bone("MouthSocket"); neck1 = Bone("Neck1_14"); neck2 = Bone("Neck2_13"); neck3 = Bone("Neck3_12");
            upperJaw = Bone("Neck3.001_11"); lowerJaw = Bone("Neck3.002_10");
            leftEar = new[] { Bone("Ear1.L_5"), Bone("Ear2.L_4"), Bone("Ear3.L_3"), Bone("Ear4.L_2") };
            rightEar = new[] { Bone("Ear1.R_9"), Bone("Ear2.R_8"), Bone("Ear3.R_7"), Bone("Ear4.R_6") };
            reactive = new[] { neck1, neck2, neck3, Head, upperJaw, lowerJaw }.Concat(leftEar).Concat(rightEar).ToArray();
            foreach (var collider in model.GetComponentsInChildren<Collider>(true)) collider.enabled = false;
            modelRenderers = model.GetComponentsInChildren<Renderer>(true); fur = new MaterialPropertyBlock();
            foreach (var renderer in modelRenderers) renderer.gameObject.layer = 2;
            foreach (var skin in model.GetComponentsInChildren<SkinnedMeshRenderer>(true))
            {
                if (skin.sharedMesh == null) continue;
                var surface = new HeadSurface(skin);
                if (surface.Triangles.Length > 0) surfaces.Add(surface); else surface.Dispose();
                for (int i = 0; i < skin.sharedMesh.blendShapeCount; i++) if (skin.sharedMesh.GetBlendShapeName(i).EndsWith("target_1", StringComparison.Ordinal)) { eyelids[skin] = i; break; }
            }
            if (surfaces.Count == 0) throw new InvalidOperationException("Actual skinned Labrador head surface is missing");
            CreateFocus(new Bounds(new Vector3(0, .55f, .1f), new Vector3(.7f, 1, 1.1f)));
            configured = true; motion.Advance("IdleFriendly", .0001, true); CaptureBasePose(); ApplyReaction(); game.NotifyPetting(this);
        }
        public override bool Interact(DungeonMotor player)
        {
            if (Viewing) { ExitView(); return true; }
            if (!Available(player) || !Live || player != Game.DungeonPlayer || player.TimedInteraction || Game.Combat?.Busy == true || Game.Items?.IsActive == true) return false;
            return EnterView(player);
        }
        public bool EnterView(DungeonMotor player) => EnterView(player, false);
        bool EnterView(DungeonMotor player, bool resume)
        {
            if (!Live || player == null || player.Eyes == null || Viewing) return false;
            owner = player; presentation = player.GetComponent<PlayerPresentation>(); sceneOutput = player.GetComponentInChildren<SourceSceneRenderer>(true);
            var camera = player.Eyes; cameraLocalPosition = camera.transform.localPosition; cameraLocalRotation = camera.transform.localRotation;
            cameraFov = camera.fieldOfView; cameraNear = camera.nearClipPlane; cameraMask = camera.cullingMask;
            ownerTimed = player.TimedInteraction; capturedBefore = player.Captured; cursorBefore = Cursor.lockState; cursorVisibleBefore = Cursor.visible;
            gearEnabled = presentation?.GearCamera?.enabled == true;
            hiddenPlayer.Clear(); foreach (var renderer in player.GetComponentsInChildren<Renderer>(true)) hiddenPlayer[renderer] = renderer.enabled;
            player.TimedInteraction = true; player.StopPlanarMovement(); player.ReleasePointer();
            Viewing = restorePending = true; previousPressed = false;
            enteredFrame = Time.frameCount;
            viewForward = Forward();
            if (!resume) action = "PetEnjoy";
            RefreshView(); return true;
        }
        public void ExitView() => ExitView(false);
        void ExitView(bool suspend)
        {
            if (!restorePending) { Viewing = false; return; }
            Viewing = restorePending = false; previousPressed = false;
            if (suspend) suspendedOwner = owner;
            else { suspendedOwner = null; Response.Stroke(Vector3.zero, Vector3.zero, false, .001); action = "IdleFriendly"; }
            if (owner != null)
            {
                owner.TimedInteraction = ownerTimed;
                var camera = owner.Eyes;
                if (camera != null) { camera.transform.SetLocalPositionAndRotation(cameraLocalPosition, cameraLocalRotation); camera.fieldOfView = cameraFov; camera.nearClipPlane = cameraNear; camera.cullingMask = cameraMask; }
                foreach (var pair in hiddenPlayer) if (pair.Key != null) pair.Key.enabled = pair.Value;
                if (presentation?.GearCamera != null) presentation.GearCamera.enabled = gearEnabled;
                if (Game?.ManualClock != true && !owner.ManualClock && !Application.isBatchMode)
                {
                    if (suspend || !Application.isFocused || !owner.isActiveAndEnabled || owner != Game?.DungeonPlayer || Game?.WorldPaused == true) { owner.ReleasePointer(); Cursor.lockState = CursorLockMode.None; Cursor.visible = true; }
                    else if (capturedBefore) owner.CapturePointer();
                    else { Cursor.lockState = cursorBefore; Cursor.visible = cursorVisibleBefore; }
                }
            }
            hiddenPlayer.Clear(); owner = null; presentation = null; sceneOutput = null;
        }
        public override void Cancel(DungeonMotor player) => ExitView();
        void OnDisable() { if (configured) ExitView(true); }
        void OnDestroy() { ExitView(); suspendedOwner = null; foreach (var surface in surfaces) surface.Dispose(); }
        void Update()
        {
            if (!Viewing) return;
            if (Game == null || Game.Session.Body.IsDead) { ExitView(); return; }
            if (!Live) return;
            if (ManualInput || Game.ManualClock || owner.ManualClock) return;
            if (Input.GetKeyDown(KeyCode.E) && Time.frameCount != enteredFrame) { Game.ExitPettingView(); return; }
            Rect displayed = new Rect(0, 0, Mathf.Max(1, Screen.width), Mathf.Max(1, Screen.height));
            if (sceneOutput?.WindowTarget == true)
            { var content = SourceWindowLayout.Content(Screen.width, Screen.height); displayed = new Rect(content.x, content.y, content.width, content.height); }
            ProcessDisplayPointer(owner.Eyes, Input.mousePosition, displayed, Input.GetMouseButton(0), Time.unscaledDeltaTime);
        }
        void LateUpdate()
        {
            // F2 pauses the response clock while presentation scripts still synchronize their cameras.
            if (Viewing && owner != null && owner == Game?.DungeonPlayer && Game?.Session?.Body.IsDead == false) RefreshView();
        }
        public void RefreshView()
        {
            if (!Viewing || owner == null || owner.Eyes == null) return;
            var forward = viewForward; var right = Vector3.Cross(Vector3.up, forward).normalized;
            Vector3 target = Head.position + forward * .065f + Vector3.up * .045f;
            Vector3 position = target + forward * .90f + right * .32f + Vector3.up * .18f;
            owner.Eyes.transform.SetPositionAndRotation(position, Quaternion.LookRotation(target - position, Vector3.up));
            owner.Eyes.fieldOfView = 36; owner.Eyes.nearClipPlane = .02f;
            owner.Eyes.cullingMask &= ~((1 << PlayerPresentation.BodyLayer) | (1 << PlayerPresentation.EquipmentLayer));
            foreach (var renderer in hiddenPlayer.Keys) if (renderer != null) renderer.enabled = false;
            if (presentation?.GearCamera != null) presentation.GearCamera.enabled = false;
            if (owner.Captured) owner.ReleasePointer();
            if (Game.ManualClock != true && !owner.ManualClock && !Application.isBatchMode) { Cursor.lockState = CursorLockMode.None; Cursor.visible = true; }
        }
        public override void Advance(double delta)
        {
            if (!configured || !double.IsFinite(delta) || delta <= 0 || !Live) return;
            if (suspendedOwner != null && suspendedOwner == Game.DungeonPlayer)
            { var resumedPlayer = suspendedOwner; suspendedOwner = null; EnterView(resumedPlayer, true); }
            if (Viewing && (owner != Game.DungeonPlayer || owner.Session.HasCondition("paralysis"))) { ExitView(); return; }
            blinkClock += delta;
            Response.Advance(delta); motion.Advance(action, delta, true); CaptureBasePose(); ApplyReaction();
            if (blinkClock > nextBlink + .22) { blinkClock = 0; nextBlink = 4.8f + (Response.AcceptedStrokes % 4) * .61f; }
            if (Viewing) RefreshView();
        }
        public bool ProcessPointer(Camera camera, Vector2 position, bool pressed, double delta)
        {
            if (!Viewing || !Live || camera == null || !double.IsFinite(delta) || delta <= 0) return false;
            RefreshView();
            return ProcessRay(camera.ScreenPointToRay(position), position, pressed, delta);
        }
        /// <summary>Map displayed window pixels to the camera viewport, independent of its reduced render buffer.</summary>
        public bool ProcessDisplayPointer(Camera camera, Vector2 screenPosition, Rect displayedViewport, bool pressed, double delta)
        {
            if (!Viewing || !Live || camera == null || !double.IsFinite(delta) || delta <= 0) return false;
            RefreshView();
            if (displayedViewport.width <= 0 || displayedViewport.height <= 0 || !displayedViewport.Contains(screenPosition))
            { LastPointerHit = false; previousPressed = false; Response.Stroke(Vector3.zero, Vector3.zero, false, delta); return false; }
            Vector2 normalized = new Vector2((screenPosition.x - displayedViewport.x) / displayedViewport.width, (screenPosition.y - displayedViewport.y) / displayedViewport.height);
            return ProcessRay(camera.ViewportPointToRay(new Vector3(normalized.x, normalized.y, 0)), screenPosition, pressed, delta);
        }
        bool ProcessRay(Ray ray, Vector2 position, bool pressed, double delta)
        {
            bool hit = TryRaycastHead(ray, out Vector3 at, out _);
            LastPointerHit = hit;
            if (hit) SurfaceHits++;
            // Animated skin and camera motion cannot turn a stationary mouse into a stroke.
            Vector3 localHit = hit ? Head.InverseTransformPoint(at) : Vector3.zero;
            bool mouseMoved = (position - previousPointer).sqrMagnitude >= .01f;
            Vector3 movement = pressed && previousPressed && hit && mouseMoved ? Head.TransformVector(localHit - previousLocalHit) : Vector3.zero;
            if (!pressed || !hit) { Response.Stroke(Vector3.zero, Vector3.zero, false, delta); previousPressed = false; }
            else { Stroke(at, movement, true, delta); previousLocalHit = localHit; previousPressed = true; }
            previousPointer = position;
            ApplyReaction(); return hit;
        }
        public bool Stroke(Vector3 worldPoint, Vector3 worldDelta, bool pressed, double delta)
        {
            if (!Viewing || !Live || !double.IsFinite(delta) || delta <= 0) return false;
            var forward = Forward(); var right = Vector3.Cross(Vector3.up, forward).normalized; var up = Vector3.Cross(forward, right).normalized;
            Vector3 relative = worldPoint - Head.position;
            float width = Mathf.Max(.05f, Vector3.Distance(leftEar[0].position, rightEar[0].position) * .65f);
            Vector3 point = new Vector3(Vector3.Dot(relative, right), Vector3.Dot(relative, up), Vector3.Dot(relative, forward)) / Mathf.Max(.1f, width);
            Vector3 movement = new Vector3(Vector3.Dot(worldDelta, right), Vector3.Dot(worldDelta, up), Vector3.Dot(worldDelta, forward));
            Response.Stroke(point, movement, pressed, delta);
            if (pressed) { LastStrokePoint = worldPoint; LastStrokeDirection = worldDelta.sqrMagnitude > .00000001f ? worldDelta.normalized : LastStrokeDirection; }
            return true;
        }
        public bool TryRaycastHead(Ray ray, out Vector3 point, out Vector3 normal)
        {
            point = normal = Vector3.zero; float closest = float.PositiveInfinity;
            foreach (var surface in surfaces) if (surface.Raycast(ray, out float distance, out Vector3 hit, out Vector3 n) && distance < closest) { closest = distance; point = hit; normal = n; }
            if (!float.IsFinite(closest)) return false;
            if (Physics.Raycast(ray, out var obstruction, closest - .001f, 1 << DungeonCombatWorld.WorldLayer, QueryTriggerInteraction.Ignore)) return false;
            return true;
        }
        Vector3 Forward()
        { var direction = Vector3.ProjectOnPlane(Mouth.position - Head.position, Vector3.up); return direction.sqrMagnitude > .00001f ? direction.normalized : visual.transform.forward; }
        void CaptureBasePose() { foreach (var bone in reactive) baseRotation[bone] = bone.localRotation; }
        void ApplyReaction()
        {
            foreach (var bone in reactive) bone.localRotation = baseRotation[bone];
            Vector3 forward = Forward(), right = Vector3.Cross(Vector3.up, forward).normalized;
            void Rotate(Transform bone, float yaw, float pitch, float roll)
            {
                Quaternion world = Quaternion.AngleAxis(yaw, Vector3.up) * Quaternion.AngleAxis(pitch, right) * Quaternion.AngleAxis(roll, forward);
                Quaternion parent = bone.parent != null ? bone.parent.rotation : Quaternion.identity;
                bone.localRotation = Quaternion.Inverse(parent) * world * parent * baseRotation[bone];
            }
            Rotate(neck1, Response.Yaw * .12f, Response.Pitch * .12f, Response.Roll * .12f);
            Rotate(neck2, Response.Yaw * .18f, Response.Pitch * .18f, Response.Roll * .18f);
            // Neck3 moves head, ears, upper oral helper and lower jaw together.
            Rotate(neck3, Response.Yaw * .50f, Response.Pitch * .50f, Response.Roll * .50f);
            Rotate(Head, Response.Yaw * .20f, Response.Pitch * .20f, Response.Roll * .20f);
            Rotate(upperJaw, Response.Yaw * .20f, Response.Pitch * .20f, Response.Roll * .20f);
            Rotate(lowerJaw, 0, Response.Enjoyment * 1.2f, 0);
            // The source's .L/.R labels can occupy the opposite side of Unity's head frame.
            bool leftOnNegativeSide = Vector3.Dot(leftEar[0].position - rightEar[0].position, right) < 0;
            Fold(leftEar, leftOnNegativeSide ? Response.LeftEar : Response.RightEar, forward);
            Fold(rightEar, leftOnNegativeSide ? Response.RightEar : Response.LeftEar, forward);
            foreach (var pair in eyelids)
            {
                float blink = blinkClock >= nextBlink ? Mathf.Sin(Mathf.Clamp01((float)(blinkClock - nextBlink) / .22f) * Mathf.PI) * 100 : 0;
                EyeRelaxation = Mathf.Max(Response.Enjoyment * 45 + Response.Intensity * 8, blink);
                pair.Key.SetBlendShapeWeight(pair.Value, EyeRelaxation);
            }
            foreach (var renderer in modelRenderers)
            {
                renderer.GetPropertyBlock(fur); fur.SetVector("_PetStrokeOrigin", LastStrokePoint); fur.SetVector("_PetStrokeDirection", LastStrokeDirection);
                fur.SetFloat("_PetStrokeStrength", Response.Intensity); fur.SetFloat("_PetStrokeRadius", SurfaceRadius); renderer.SetPropertyBlock(fur);
            }
        }
        void Fold(Transform[] chain, float amount, Vector3 forward)
        {
            float[] caps = { 8, 4, 2, 1 };
            for (int i = 0; i < chain.Length; i++)
            {
                var bone = chain[i]; Vector3 segment = i + 1 < chain.Length ? chain[i + 1].position - bone.position : bone.TransformDirection(Vector3.up);
                Vector3 inward = (Head.position - bone.position).normalized;
                Vector3 folded = (-forward * .25f + Vector3.down * .65f + inward * .45f).normalized;
                Vector3 axis = Vector3.Cross(segment.normalized, folded);
                if (axis.sqrMagnitude < .00001f) continue;
                Quaternion parent = bone.parent != null ? bone.parent.rotation : Quaternion.identity;
                var world = Quaternion.AngleAxis(caps[i] * amount, axis.normalized);
                bone.localRotation = Quaternion.Inverse(parent) * world * parent * baseRotation[bone];
            }
        }

        sealed class HeadSurface : IDisposable
        {
            readonly SkinnedMeshRenderer skin;
            readonly Mesh baked;
            readonly List<Vector3> vertices = new List<Vector3>();
            public int[] Triangles { get; }
            public HeadSurface(SkinnedMeshRenderer renderer)
            {
                skin = renderer; baked = new Mesh { name = "PettingHeadRaycast", hideFlags = HideFlags.DontSave };
                var mesh = skin.sharedMesh; var weights = mesh.boneWeights;
                var selected = skin.bones.Select(b => b != null && (b.name == "Head_1" || b.name == "Neck3_12" || b.name.StartsWith("Ear") || b.name.StartsWith("Neck3."))).ToArray();
                bool Vertex(int v)
                {
                    if (v >= weights.Length) return false; var w = weights[v]; float total = 0;
                    if (w.boneIndex0 < selected.Length && selected[w.boneIndex0]) total += w.weight0;
                    if (w.boneIndex1 < selected.Length && selected[w.boneIndex1]) total += w.weight1;
                    if (w.boneIndex2 < selected.Length && selected[w.boneIndex2]) total += w.weight2;
                    if (w.boneIndex3 < selected.Length && selected[w.boneIndex3]) total += w.weight3;
                    return total > .30f;
                }
                var triangles = mesh.triangles; var head = new List<int>();
                for (int i = 0; i < triangles.Length; i += 3) if (Vertex(triangles[i]) && Vertex(triangles[i + 1]) && Vertex(triangles[i + 2])) { head.Add(triangles[i]); head.Add(triangles[i + 1]); head.Add(triangles[i + 2]); }
                Triangles = head.ToArray();
            }
            public bool Raycast(Ray world, out float distance, out Vector3 point, out Vector3 normal)
            {
                distance = float.PositiveInfinity; point = normal = Vector3.zero;
                if (!skin.enabled || !skin.gameObject.activeInHierarchy) return false;
                // Compensate the imported renderer's scale so the ray uses the same posed surface as the GPU skin.
                skin.BakeMesh(baked, true); baked.GetVertices(vertices); Vector3 origin = skin.transform.InverseTransformPoint(world.origin), direction = skin.transform.InverseTransformVector(world.direction);
                for (int i = 0; i < Triangles.Length; i += 3)
                {
                    Vector3 a = vertices[Triangles[i]], b = vertices[Triangles[i + 1]], c = vertices[Triangles[i + 2]], e1 = b - a, e2 = c - a;
                    Vector3 p = Vector3.Cross(direction, e2); float det = Vector3.Dot(e1, p); if (Mathf.Abs(det) < .00000001f) continue;
                    float inv = 1 / det; Vector3 t = origin - a; float u = Vector3.Dot(t, p) * inv; if (u < 0 || u > 1) continue;
                    Vector3 q = Vector3.Cross(t, e1); float v = Vector3.Dot(direction, q) * inv; if (v < 0 || u + v > 1) continue;
                    float hit = Vector3.Dot(e2, q) * inv; if (hit <= 0 || hit >= distance) continue;
                    distance = hit; point = world.GetPoint(hit); normal = skin.transform.TransformDirection(Vector3.Cross(e1, e2).normalized);
                }
                return float.IsFinite(distance);
            }
            public void Dispose() { if (baked != null) { if (Application.isPlaying) UnityEngine.Object.Destroy(baked); else UnityEngine.Object.DestroyImmediate(baked); } }
        }
    }
}
