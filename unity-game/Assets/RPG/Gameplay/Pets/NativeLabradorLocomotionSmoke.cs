using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Newtonsoft.Json.Linq;
using UnityEngine;
using UnityEngine.UI;

namespace MusimusihanRpg.Gameplay
{
    /// <summary>Opt-in real player/F2 acceptance; operates without desktop input, focus changes or audible sound.</summary>
    public sealed class NativeLabradorLocomotionSmoke : MonoBehaviour
    {
        WorkshopController game;
        SourcePhysicsLease lease;
        readonly List<string> checks = new List<string>(), errors = new List<string>();
        readonly JObject diagnostics = new JObject();
        bool finished;
        float started;
        const float Step = 1f / 60;
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void Launch()
        {
            if (Application.isBatchMode && Environment.GetCommandLineArgs().Contains("-labradorLocomotionSmoke") && FindFirstObjectByType<NativeLabradorLocomotionSmoke>() == null)
                new GameObject("NativeLabradorLocomotionAcceptance").AddComponent<NativeLabradorLocomotionSmoke>();
        }
        void Awake() { DontDestroyOnLoad(gameObject); started = Time.realtimeSinceStartup; Application.runInBackground = true; AudioListener.pause = true; Application.logMessageReceived += Log; }
        void OnDestroy() { Application.logMessageReceived -= Log; lease?.Dispose(); }
        void Log(string text, string stack, LogType kind)
        { if ((kind == LogType.Error || kind == LogType.Exception || kind == LogType.Assert) && errors.Count < 25) errors.Add(text + "\n" + stack); }
        void Check(bool result, string text) { checks.Add(text); if (!result) throw new InvalidOperationException(text); }
        void BindClock() { game.ManualClock = true; game.DungeonPlayer.ManualClock = true; game.DungeonPlayer.ReleasePointer(); }
        void Advance(int frames) { for (int i = 0; i < frames; i++) game.AdvanceRenderFrame(Step, default, true); }
        static string Pose(GameObject model) => string.Join("|", model.GetComponentsInChildren<Transform>(true).Select(t => t.localPosition.ToString("R") + t.localRotation.ToString("R") + t.localScale.ToString("R")));
        IEnumerator Start()
        {
            while ((game = FindFirstObjectByType<WorkshopController>())?.NativeGame?.Ui == null || NativeLoadingScreen.Visible) yield return null;
            BindClock(); yield return null; lease = SourcePhysicsLease.TryAcquire();
            Check(lease != null, "Own deterministic physics without desktop input, focus changes or audio.");
            game.NativeGame.EnterHideout(); BindClock(); Physics.SyncTransforms(); Advance(2);
            Check(LabradorLocomotionAssets.TryLoad(out _, out var clips, out _), "Actual licensed Labrador, Walk and Run resources are installed.");
            Check(clips.Where(c => LabradorLocomotionAssets.RequiredClips.Contains(c.name)).All(c => c.legacy && c.wrapMode == WrapMode.Loop && c.length > .2f), "Both real native gait clips are nonempty loops.");
            var original = game.ActivePetting;
            Check(original != null, "Existing sanctuary petting Labrador remains installed.");
            var world = game.DungeonRoot; var bag = game.Session.Inventory;
            bool originalCombatHud = game.NativeGame.CombatHud.CombatInterfaceEnabled;
            string slots = new JArray(bag.Slots).ToString(), survival = game.Session.SurvivalSnapshot().ToString(); int crowns = game.Session.Crowns;
            var originalPose = original.transform.localToWorldMatrix; float enjoyment = original.Response.Enjoyment;
            game.OpenTrials(); BindClock(); yield return null;
            var row = game.TrialMenu.Ui.Nodes.Values.SingleOrDefault(t => t.name == "Feature_" + LabradorLocomotionDemo.TrialId);
            Check(row?.GetComponent<Button>() != null, "F2 displays the actual Labrador walking/running button.");
            row.GetComponent<Button>().onClick.Invoke(); BindClock(); Physics.SyncTransforms(); yield return null; Advance(2);
            var demo = game.ActiveLocomotion;
            Check(demo != null && game.Trials.CurrentEntry == LabradorLocomotionDemo.TrialId && !game.Trials.MenuOpen && game.NativeGame.State == "playing", "Actual F2 button dispatches the live gait room.");
            Check(!world.activeSelf && !ReferenceEquals(bag, game.Session.Inventory) && demo.transform.IsChildOf(game.DungeonRoot.transform), "Gait trial isolates the original world, dog and inventory.");
            Check(demo.Model.GetComponentsInChildren<SkinnedMeshRenderer>().Sum(r => r.sharedMesh.triangles.Length / 3) > 40000, "Gait moves the actual detailed skinned dog.");
            Check(demo.Viewing && game.PettingInputActive && game.DungeonPlayer.TimedInteraction && !game.DungeonPlayer.Captured, "Side view owns stationary player input and leaves the pointer free.");
            Check(!game.NativeGame.CombatHud.CombatInterfaceEnabled && !(bool)game.NativeGame.CombatHud.ActivateSlot(0)["accepted"], "Side view suppresses quick-slot key handling and prevents equipment or item use while switching gait.");
            var presentation = game.DungeonPlayer.GetComponent<PlayerPresentation>();
            var playerRenderers = game.DungeonPlayer.GetComponentsInChildren<Renderer>(true);
            int excludedLayers = (1 << PlayerPresentation.BodyLayer) | (1 << PlayerPresentation.EquipmentLayer);
            diagnostics["before_late_view"] = new JObject
            {
                ["enabled_player_renderers"] = new JArray(playerRenderers.Where(r => r.enabled).Select(r => r.name)),
                ["gear_camera_enabled"] = presentation?.GearCamera?.enabled == true,
                ["excluded_layers_visible"] = (game.DungeonPlayer.Eyes.cullingMask & excludedLayers) != 0
            };
            // Manual AdvanceRenderFrame finishes actor simulation before the real Unity LateUpdate.
            // PlayerPresentation.Advance can re-enable a supplied arm in that intermediate state.
            // Match Demo.LateUpdate(500) followed by SourceSceneRenderer.LateUpdate(1000)
            // before asserting the final frame; camera exclusion is also required independently.
            demo.RefreshView(); presentation?.SyncGearCamera();
            Check(playerRenderers.All(r => !r.enabled) && (presentation?.GearCamera == null || !presentation.GearCamera.enabled)
                && (game.DungeonPlayer.Eyes.cullingMask & excludedLayers) == 0,
                "Final gait view excludes body/equipment camera layers, hides every player renderer and disables the equipment camera.");
            var placed = demo.transform.localToWorldMatrix;
            Check(demo.SelectedAnimation == "Walk" && demo.CurrentAnimation == "Walk", "Fresh gait view begins with the actual walking loop.");
            Advance(60); string walkPose = Pose(demo.Model); float walkClock = demo.MotionTime;
            Advance(11);
            Check(demo.MotionTime > walkClock && Pose(demo.Model) != walkPose, "Walk advances the actual skeleton over native simulation frames.");
            Check(demo.SelectMotion("Run"), "The same mode command used by key 2 and its button switches to Run.");
            Advance(60); string runPose = Pose(demo.Model); float runClock = demo.MotionTime;
            Advance(7);
            Check(demo.CurrentAnimation == "Run" && demo.MotionTime > runClock && Pose(demo.Model) != runPose, "Run advances the actual skeleton independently of the walking loop.");
            Check(demo.transform.localToWorldMatrix == placed, "The motion demonstration stays rooted on its actual safe floor.");
            game.OpenTrials(); float pausedClock = demo.MotionTime; string pausedPose = Pose(demo.Model);
            Advance(90);
            Check(demo.MotionTime == pausedClock && Pose(demo.Model) == pausedPose && !demo.SelectMotion("Walk"), "F2 pause freezes the exact gait pose and rejects mode changes.");
            game.ResumeTrial(); BindClock(); Advance(2);
            Check(game.ActiveLocomotion == demo && demo.Viewing && demo.SelectedAnimation == "Run" && demo.MotionTime > pausedClock, "F2 resume retains the same dog, side view and selected gait.");
            Check(!demo.SelectMotion("Attack") && demo.SelectedAnimation == "Run", "Unprovided companion actions are not presented as implemented locomotion.");
            Check(game.ExitPettingView() && !demo.Viewing && !game.PettingInputActive && !game.DungeonPlayer.TimedInteraction, "E/Esc view exit restores player input ownership.");
            Check(game.NativeGame.CombatHud.CombatInterfaceEnabled == originalCombatHud, "View exit restores the original combat-interface flag.");
            game.NativeGame.CombatHud.SetCombatInterfaceEnabled(false);
            Check(game.BeginPettingTrialView() && game.ExitPettingView() && !game.NativeGame.CombatHud.CombatInterfaceEnabled, "An already-disabled combat interface stays disabled after a complete view cycle.");
            game.NativeGame.CombatHud.SetCombatInterfaceEnabled(originalCombatHud);
            Check(game.BeginPettingTrialView() && demo.Viewing && demo.SelectedAnimation == "Run", "Reopening the side view conserves the selected gait.");
            Check(game.RunTrial(LabradorLocomotionDemo.TrialId), "Retry dispatches the actual registered gait implementation.");
            BindClock(); yield return null; Advance(2); var retry = game.ActiveLocomotion;
            Check(retry != null && retry != demo && retry.Viewing && retry.SelectedAnimation == "Walk", "Retry creates a fresh actual dog and resets the gait to Walk.");
            game.ResetTrialLoadout(); BindClock(); yield return null;
            Check(game.Trials.MenuOpen && game.ActiveLocomotion == null, "Reset removes the demo and returns to the isolated paused menu.");
            Check(game.RunTrial(LabradorPetting.TrialId), "The existing handless petting F2 entry remains runnable.");
            BindClock(); yield return null; Advance(2);
            Check(game.ActivePetting != null && game.ActivePetting.Viewing && game.ActivePetting.CurrentAnimation == "PetEnjoy", "Existing PetEnjoy and its interactive close view remain intact.");
            game.EndTrials(); game.NativeGame.Tick(0); BindClock(); yield return null;
            Check(game.DungeonRoot == world && world.activeSelf && game.ActivePetting == original && ReferenceEquals(bag, game.Session.Inventory), "Exit restores the original world, petting Labrador and bag identity.");
            Check(slots == new JArray(bag.Slots).ToString() && survival == game.Session.SurvivalSnapshot().ToString() && crowns == game.Session.Crowns && enjoyment == original.Response.Enjoyment && originalPose == original.transform.localToWorldMatrix && game.NativeGame.CombatHud.CombatInterfaceEnabled == originalCombatHud, "Gait switching, pause, retry and reset conserve original inventory, survival, wallet, combat-interface flag and dog state.");
            diagnostics["screen_pixels"] = new JArray(Screen.width, Screen.height);
            diagnostics["camera_pixels"] = new JArray(game.DungeonPlayer.Eyes.pixelWidth, game.DungeonPlayer.Eyes.pixelHeight);
            diagnostics["clips"] = new JArray(clips.Where(c => LabradorLocomotionAssets.RequiredClips.Contains(c.name)).Select(c => new JObject { ["name"] = c.name, ["duration_s"] = c.length, ["loop"] = c.wrapMode == WrapMode.Loop }));
            Finish();
        }
        void Update()
        {
            if (finished) return;
            if (errors.Count > 0 || Time.realtimeSinceStartup - started > 300)
            { if (errors.Count == 0) errors.Add("Actual Labrador locomotion acceptance timeout."); StopAllCoroutines(); Finish(); }
        }
        void Finish()
        {
            if (finished) return; finished = true; lease?.Dispose(); lease = null;
            string path = Environment.GetEnvironmentVariable("RPG_LABRADOR_LOCOMOTION_RESULT");
            if (string.IsNullOrEmpty(path)) path = Path.Combine(Application.temporaryCachePath, "labrador-locomotion-acceptance.json");
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            File.WriteAllText(path, new JObject { ["result"] = errors.Count == 0 ? "Passed" : "Failed", ["unity_version"] = Application.unityVersion, ["checks"] = new JArray(checks), ["errors"] = new JArray(errors), ["diagnostics"] = diagnostics, ["limitations"] = new JArray("Actual native app and F2 flow use the same deterministic mode command as keys/buttons; physical desktop input, focus and sound are not exercised.", "This is an in-place animation preview. Pathfinding, following and companion combat are outside this motion request.", "DCC paw support and rendered appearance are reviewed separately.") }.ToString() + "\n");
            Application.Quit(errors.Count == 0 ? 0 : 1); enabled = false;
        }
    }
}
