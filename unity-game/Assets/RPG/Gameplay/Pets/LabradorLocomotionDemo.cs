using System;
using System.Collections.Generic;
using System.Linq;
using Newtonsoft.Json.Linq;
using UnityEngine;

namespace MusimusihanRpg.Gameplay
{
    public static class LabradorLocomotionAssets
    {
        public static readonly string[] RequiredClips = { "Walk", "Run" };
        public static bool TryLoad(out GameObject prefab, out AnimationClip[] clips, out string failure)
        {
            prefab = Resources.Load<GameObject>(LabradorPettingAssets.Resource + "/PetModel");
            clips = Resources.LoadAll<AnimationClip>(LabradorPettingAssets.Resource + "/Animations");
            var supplied = clips;
            var missing = RequiredClips.Where(name => !supplied.Any(c => c != null && c.name == name)).ToArray();
            if (prefab == null || missing.Length > 0)
            { failure = "실제 래브라도 걷기·달리기 에셋 누락: " + (prefab == null ? "PetModel " : "") + string.Join(", ", missing); return false; }
            failure = ""; return true;
        }
        public static bool Available => TryLoad(out _, out _, out _);
        public static void AddEntries(JArray entries)
        {
            if (!Available || entries.Any(e => (string)e["id"] == LabradorLocomotionDemo.TrialId)) return;
            entries.Add(new JObject
            {
                ["id"] = LabradorLocomotionDemo.TrialId, ["category"] = "장면", ["title"] = "래브라도 · 걷기 / 달리기 모션",
                ["action"] = "movement", ["detail"] = "실제 강아지 제자리 순환 모션 · 1 걷기 / 2 달리기 · E/Esc 시점 나가기 · F2 정지·재시도·원정 복원"
            });
        }
        public static void AddTrialControls(JArray controls, JArray entries)
        {
            var entry = entries.OfType<JObject>().FirstOrDefault(e => (string)e["id"] == LabradorLocomotionDemo.TrialId);
            var rows = controls.OfType<JObject>().Where(e => ((string)e["path"] ?? "").StartsWith("trial/category_4/") && ((string)e["name"] ?? "").StartsWith("Feature_")).ToArray();
            if (entry == null || rows.Length == 0 || controls.Any(e => (string)e["name"] == "Feature_" + LabradorLocomotionDemo.TrialId)) return;
            var extra = (JObject)rows.Last().DeepClone(); string original = (string)extra["name"], name = "Feature_" + LabradorLocomotionDemo.TrialId;
            float y = rows.Max(e => (float)e["rect"][1] + (float)e["rect"][3]) + 7;
            extra["name"] = name; extra["path"] = ((string)extra["path"]).Replace(original, name);
            extra["text"] = entry["title"] + "\n" + entry["detail"]; extra["rect"][1] = y; controls.Add(extra);
            var content = controls.OfType<JObject>().First(e => ((string)e["path"] ?? "").StartsWith("trial/category_4/") && (string)e["name"] == "TrialEntries");
            content["rect"][3] = y + (float)extra["rect"][3] - (float)content["rect"][1];
        }
    }

    /// <summary>Actual authored in-place gait loops, viewed without moving the player or capturing the pointer.</summary>
    [DefaultExecutionOrder(500)]
    public sealed class LabradorLocomotionDemo : DungeonInteractable
    {
        public const string TrialId = "pet_labrador_locomotion";
        public bool Viewing { get; private set; }
        public bool ManualInput;
        public string CurrentAnimation => motion?.Current ?? "";
        public float MotionTime => motion?.Time ?? 0;
        public string SelectedAnimation { get; private set; } = "Walk";
        public GameObject Model { get; private set; }
        public override bool Busy => Viewing;
        public override string Prompt => "[E] 래브라도 모션 보기 · 1 걷기 / 2 달리기 · F2 시험 메뉴";
        PetAnimationPlayer motion;
        DungeonMotor owner, suspendedOwner;
        PlayerPresentation presentation;
        Vector3 cameraPosition;
        Quaternion cameraRotation;
        float cameraFov, cameraNear;
        int cameraMask;
        bool ownerTimed, gearEnabled, capturedBefore, restorePending, combatInterfaceEnabled;
        NativeCombatHud combatHud;
        CursorLockMode cursorBefore;
        bool cursorVisibleBefore;
        readonly Dictionary<Renderer, bool> hiddenPlayer = new Dictionary<Renderer, bool>();
        GUIStyle titleStyle, buttonStyle;
        bool Live => Game != null && Game.Session != null && !Game.WorldPaused && Game.Page == "dungeon" && !Game.Session.Body.IsDead && (Game.NativeGame == null || Game.NativeGame.State == "playing");

        public static LabradorLocomotionDemo Spawn(WorkshopController game, GameObject prefab, AnimationClip[] clips, Vector3 position)
        {
            if (game == null || prefab == null || clips == null) throw new ArgumentException("Actual Labrador locomotion resources are required.");
            var node = new GameObject("LabradorLocomotionDemo"); node.transform.SetParent(game.DungeonRoot.transform, false); node.transform.position = position;
            var demo = node.AddComponent<LabradorLocomotionDemo>();
            try
            {
                demo.Game = game; demo.Model = Instantiate(prefab, node.transform); demo.Model.name = "ActualLabrador";
                foreach (var collider in demo.Model.GetComponentsInChildren<Collider>(true)) collider.enabled = false;
                foreach (var renderer in demo.Model.GetComponentsInChildren<Renderer>(true)) renderer.gameObject.layer = 2;
                demo.motion = new PetAnimationPlayer(demo.Model, clips);
                foreach (string name in LabradorLocomotionAssets.RequiredClips) if (!demo.motion.Has(name)) throw new InvalidOperationException("Missing actual gait: " + name);
                demo.CreateFocus(new Bounds(new Vector3(0, .47f, 0), new Vector3(.85f, 1.15f, 1.95f)));
                demo.motion.Advance("Walk", .0001, true); game.NotifyLocomotion(demo); return demo;
            }
            catch { Destroy(node); throw; }
        }
        public bool SelectMotion(string name)
        {
            if (!Live || !Viewing || !LabradorLocomotionAssets.RequiredClips.Contains(name) || !motion.Has(name)) return false;
            SelectedAnimation = name; motion.Advance(name, .0001, true); return true;
        }
        public override bool Interact(DungeonMotor player)
        { if (Viewing) { ExitView(); return true; } return Available(player) && EnterView(player); }
        public bool EnterView(DungeonMotor player)
        {
            if (!Live || player == null || player != Game.DungeonPlayer || player.Eyes == null || Viewing) return false;
            owner = player; suspendedOwner = null; presentation = player.GetComponent<PlayerPresentation>();
            var camera = owner.Eyes; cameraPosition = camera.transform.localPosition; cameraRotation = camera.transform.localRotation;
            cameraFov = camera.fieldOfView; cameraNear = camera.nearClipPlane; cameraMask = camera.cullingMask;
            ownerTimed = player.TimedInteraction; capturedBefore = player.Captured; gearEnabled = presentation?.GearCamera?.enabled == true;
            combatHud = Game.NativeGame?.CombatHud; combatInterfaceEnabled = combatHud?.CombatInterfaceEnabled == true;
            cursorBefore = Cursor.lockState; cursorVisibleBefore = Cursor.visible;
            hiddenPlayer.Clear(); foreach (var renderer in owner.GetComponentsInChildren<Renderer>(true)) hiddenPlayer[renderer] = renderer.enabled;
            owner.TimedInteraction = true; owner.StopPlanarMovement(); owner.ReleasePointer(); Viewing = restorePending = true;
            combatHud?.SetCombatInterfaceEnabled(false);
            RefreshView(); return true;
        }
        public void RefreshView()
        {
            if (!Viewing || owner == null || owner.Eyes == null) return;
            Vector3 target = transform.position + Vector3.up * .43f;
            Vector3 position = target + transform.right * 2.25f - transform.forward * .8f + Vector3.up * .6f;
            owner.Eyes.transform.SetPositionAndRotation(position, Quaternion.LookRotation(target - position, Vector3.up));
            owner.Eyes.fieldOfView = 39; owner.Eyes.nearClipPlane = .025f;
            owner.Eyes.cullingMask &= ~((1 << PlayerPresentation.BodyLayer) | (1 << PlayerPresentation.EquipmentLayer));
            foreach (var renderer in hiddenPlayer.Keys) if (renderer != null) renderer.enabled = false;
            if (presentation?.GearCamera != null) presentation.GearCamera.enabled = false;
            if (owner.Captured) owner.ReleasePointer();
            if (!Application.isBatchMode && !Game.ManualClock && !owner.ManualClock) { Cursor.lockState = CursorLockMode.None; Cursor.visible = true; }
        }
        public void ExitView() => ExitView(false);
        void ExitView(bool suspend)
        {
            if (!restorePending) { Viewing = false; return; }
            Viewing = restorePending = false; suspendedOwner = suspend ? owner : null;
            if (owner != null)
            {
                owner.TimedInteraction = ownerTimed;
                if (owner.Eyes != null)
                {
                    owner.Eyes.transform.SetLocalPositionAndRotation(cameraPosition, cameraRotation);
                    owner.Eyes.fieldOfView = cameraFov; owner.Eyes.nearClipPlane = cameraNear; owner.Eyes.cullingMask = cameraMask;
                }
                foreach (var pair in hiddenPlayer) if (pair.Key != null) pair.Key.enabled = pair.Value;
                if (presentation?.GearCamera != null) presentation.GearCamera.enabled = gearEnabled;
                combatHud?.SetCombatInterfaceEnabled(combatInterfaceEnabled);
                if (!Application.isBatchMode && !Game.ManualClock && !owner.ManualClock)
                {
                    if (suspend || !Application.isFocused || !owner.isActiveAndEnabled || owner != Game.DungeonPlayer || Game.WorldPaused)
                    { owner.ReleasePointer(); Cursor.lockState = CursorLockMode.None; Cursor.visible = true; }
                    else if (capturedBefore) owner.CapturePointer();
                    else { Cursor.lockState = cursorBefore; Cursor.visible = cursorVisibleBefore; }
                }
            }
            hiddenPlayer.Clear(); owner = null; presentation = null; combatHud = null;
        }
        public override void Cancel(DungeonMotor player) => ExitView();
        void OnDisable() => ExitView(true);
        void OnDestroy() { ExitView(); suspendedOwner = null; }
        public override void Advance(double delta)
        {
            if (!Live || !double.IsFinite(delta) || delta <= 0) return;
            if (suspendedOwner != null && suspendedOwner == Game.DungeonPlayer) EnterView(suspendedOwner);
            motion.Advance(SelectedAnimation, delta, true); if (Viewing) RefreshView();
        }
        void Update()
        {
            if (!Viewing || !Live || ManualInput || Game.ManualClock || owner.ManualClock) return;
            if (Input.GetKeyDown(KeyCode.Alpha1) || Input.GetKeyDown(KeyCode.Keypad1)) SelectMotion("Walk");
            if (Input.GetKeyDown(KeyCode.Alpha2) || Input.GetKeyDown(KeyCode.Keypad2)) SelectMotion("Run");
        }
        void LateUpdate() { if (Viewing && owner == Game?.DungeonPlayer && Game?.Session?.Body.IsDead == false) RefreshView(); }
        void OnGUI()
        {
            if (!Viewing || !Live || Application.isBatchMode) return;
            if (titleStyle == null)
            {
                titleStyle = new GUIStyle(GUI.skin.label) { font = Game.KoreanFont, fontSize = 18, alignment = TextAnchor.MiddleCenter };
                buttonStyle = new GUIStyle(GUI.skin.button) { font = Game.KoreanFont, fontSize = 18 };
            }
            float x = Screen.width * .5f;
            GUI.Label(new Rect(x - 280, Screen.height - 112, 560, 32), "래브라도 제자리 모션 · " + (SelectedAnimation == "Run" ? "달리기" : "걷기") + " · F2 정지 / 재시도", titleStyle);
            if (GUI.Button(new Rect(x - 245, Screen.height - 72, 150, 40), "1 · 걷기", buttonStyle)) SelectMotion("Walk");
            if (GUI.Button(new Rect(x - 75, Screen.height - 72, 150, 40), "2 · 달리기", buttonStyle)) SelectMotion("Run");
            if (GUI.Button(new Rect(x + 95, Screen.height - 72, 150, 40), "E / Esc 나가기", buttonStyle)) Game.ExitPettingView();
        }
    }
}
