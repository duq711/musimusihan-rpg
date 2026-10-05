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
    /// <summary>Opt-in actual-player acceptance; no desktop input, focus changes or audible sound.</summary>
    public sealed class NativeLabradorSmoke : MonoBehaviour
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
            if (Application.isBatchMode && Environment.GetCommandLineArgs().Contains("-labradorPetSmoke") && FindFirstObjectByType<NativeLabradorSmoke>() == null)
                new GameObject("NativeLabradorAcceptance").AddComponent<NativeLabradorSmoke>();
        }
        void Awake() { DontDestroyOnLoad(gameObject); started = Time.realtimeSinceStartup; Application.runInBackground = true; AudioListener.pause = true; Application.logMessageReceived += Log; }
        void OnDestroy() { Application.logMessageReceived -= Log; lease?.Dispose(); }
        void Log(string text, string stack, LogType kind)
        { if ((kind == LogType.Error || kind == LogType.Exception || kind == LogType.Assert) && errors.Count < 25) errors.Add(text + "\n" + stack); }
        void Check(bool result, string text) { checks.Add(text); if (!result) throw new InvalidOperationException(text); }
        LabradorPetting Pet() => game.DungeonRoot.GetComponentsInChildren<LabradorPetting>().SingleOrDefault();
        void Advance(int frames)
        { for (int i = 0; i < frames; i++) game.AdvanceRenderFrame(Step, default, true); }
        void BindClock()
        { game.ManualClock = true; game.DungeonPlayer.ManualClock = true; game.DungeonPlayer.ReleasePointer(); }
        bool Pointer(LabradorPetting pet, out Vector2 pixel)
        {
            // Player feedback runs after the interaction clock; restore the close view
            // before projecting, just as production input does before its skin ray.
            pet.RefreshView();
            var eye = pet.ViewCamera;
            Vector3 center = eye.WorldToScreenPoint(pet.Head.position + Vector3.up * .045f);
            foreach (int y in new[] { 0, -1, 1, -2, 2, -3, 3 }) foreach (int x in new[] { 0, -1, 1, -2, 2, -3, 3 })
            {
                pixel = new Vector2(center.x + x * 16, center.y + y * 16);
                if (pet.TryRaycastHead(eye.ScreenPointToRay(pixel), out _, out _)) return true;
            }
            pixel = default; return false;
        }
        IEnumerator Start()
        {
            while ((game = FindFirstObjectByType<WorkshopController>())?.NativeGame?.Ui == null || NativeLoadingScreen.Visible) yield return null;
            BindClock(); yield return null; lease = SourcePhysicsLease.TryAcquire();
            Check(lease != null, "Own deterministic physics without desktop input, focus changes or audio.");
            game.NativeGame.EnterHideout(); BindClock(); Physics.SyncTransforms(); Advance(2);
            var original = Pet();
            Check(original != null && original.Head != null && original.Mouth != null, "Actual licensed Labrador is installed in the native sanctuary.");
            var bag = game.Session.Inventory; var world = game.DungeonRoot;
            string slots = new JArray(bag.Slots).ToString(), survival = game.Session.SurvivalSnapshot().ToString(); int crowns = game.Session.Crowns;
            var pose = original.transform.localToWorldMatrix; float enjoyment = original.Response.Enjoyment;
            game.OpenTrials(); BindClock(); yield return null;
            var row = game.TrialMenu.Ui.Nodes.Values.SingleOrDefault(t => t.name == "Feature_pet_labrador_petting");
            Check(row != null && row.GetComponent<Button>() != null, "F2 shows the actual standing Labrador petting button.");
            row.GetComponent<Button>().onClick.Invoke(); BindClock(); Physics.SyncTransforms(); yield return null;
            Check(game.Trials.CurrentEntry == LabradorPetting.TrialId && !game.Trials.MenuOpen && game.NativeGame.State == "playing", "Actual F2 button dispatches the live mouse-petting room.");
            var pet = Pet(); pet.ManualInput = true;
            Check(pet != null && pet != original && !world.activeSelf && !ReferenceEquals(bag, game.Session.Inventory), "F2 isolates the original dog, world and inventory.");
            Check(pet.GetComponentsInChildren<SkinnedMeshRenderer>().Sum(r => r.sharedMesh.triangles.Length / 3) > 40000 && pet.HeadTriangles > 500, "Actual detailed skinned model and head triangles are present.");
            if (!pet.Viewing)
            {
                game.AimAt(pet.FocusCollider.bounds.center); Physics.SyncTransforms();
                Check(game.Interaction.Interact(), "The real E interaction enters petting view.");
            }
            Advance(120); pet.RefreshView(); Physics.SyncTransforms();
            diagnostics["original_camera_pixels"] = new JArray(pet.ViewCamera.pixelWidth, pet.ViewCamera.pixelHeight);
            diagnostics["screen_pixels"] = new JArray(Screen.width, Screen.height);
            // Give the headless player's screen rays a deterministic viewport.
            pet.ViewCamera.pixelRect = new Rect(0, 0, 1280, 720); pet.ViewCamera.aspect = 1280f / 720;
            Check(pet.Viewing && game.DungeonPlayer.TimedInteraction && !game.DungeonPlayer.Captured, "Close view owns stationary input with a free pointer.");
            var presentation = game.DungeonPlayer.GetComponent<PlayerPresentation>();
            Check(presentation?.GearCamera == null || !presentation.GearCamera.enabled, "Petting renders no first-person equipment camera or hands.");
            Check(game.DungeonPlayer.GetComponentsInChildren<Renderer>(true).All(r => !r.enabled), "Existing player renderers are hidden during close petting.");
            Check(Pointer(pet, out var pixel), "Screen ray intersects the actual animated head skin.");
            var ear = pet.GetComponentsInChildren<Transform>().Single(t => t.name == "Ear1.L_5");
            Quaternion rest = ear.localRotation;
            pet.ProcessPointer(pet.ViewCamera, pixel, true, Step);
            int stationaryStrokes = pet.Response.AcceptedStrokes; float stationaryEnjoyment = pet.Response.Enjoyment;
            for (int i = 0; i < 120; i++) { Advance(1); pet.ProcessPointer(pet.ViewCamera, pixel, true, Step); }
            Check(pet.Response.AcceptedStrokes == stationaryStrokes && pet.Response.Enjoyment <= stationaryEnjoyment, "Holding a stationary screen cursor does not manufacture strokes from animated head motion.");
            pet.ProcessPointer(pet.ViewCamera, pixel, true, Step);
            for (int i = 0; i < 180; i++)
            {
                if (Pointer(pet, out var at)) pet.ProcessPointer(pet.ViewCamera, at + new Vector2(Mathf.Sin(i * .17f) * 22, Mathf.Cos(i * .13f) * 13), true, Step);
                Advance(1); if (i % 60 == 59) yield return null;
            }
            diagnostics["stroke_sample"] = new JObject { ["surface_hits"] = pet.SurfaceHits, ["strokes"] = pet.Response.AcceptedStrokes,
                ["distance_m"] = pet.Response.DistanceStroked, ["enjoyment"] = pet.Response.Enjoyment, ["intensity"] = pet.Response.Intensity,
                ["pixel"] = new JArray(pixel.x, pixel.y), ["camera_pixels"] = new JArray(pet.ViewCamera.pixelWidth, pet.ViewCamera.pixelHeight),
                ["viewing"] = pet.Viewing, ["page"] = game.Page, ["world_paused"] = game.WorldPaused, ["native_state"] = game.NativeGame.State };
            Check(pet.SurfaceHits > 20 && pet.Response.AcceptedStrokes > 20 && pet.Response.DistanceStroked > .02f, "Moving screen input records real skin strokes rather than fixed playback.");
            Check(pet.Response.Enjoyment > .05f && pet.Response.Intensity > .001f && Quaternion.Angle(rest, ear.localRotation) > .05f, "Actual strokes produce bounded enjoyment and ear movement.");
            Check(pet.EyeRelaxation > 1 && pet.FurStrength > 0, "Original eyelid shape and localized coat response react to actual strokes.");
            float activeIntensity = pet.Response.Intensity;
            pet.ProcessPointer(pet.ViewCamera, pixel, false, Step); Advance(90);
            Check(pet.Response.Intensity < activeIntensity * .1f, "Releasing the pointer smoothly stops the local stroke response.");
            game.OpenTrials(); float frozenEnjoyment = pet.Response.Enjoyment; Quaternion frozenEar = ear.localRotation;
            Advance(90);
            Check(pet.Response.Enjoyment == frozenEnjoyment && ear.localRotation == frozenEar, "F2 pause freezes enjoyment and the real skeletal pose.");
            game.ResumeTrial(); BindClock(); Advance(2);
            Check(Pet() == pet && !game.Trials.MenuOpen && pet.Viewing, "F2 resume retains the same dog and petting view.");
            Check(game.RunTrial(LabradorPetting.TrialId), "Retry invokes the registered native petting implementation.");
            BindClock(); yield return null; Advance(2);
            Check(Pet() != null && Pet() != pet && Pet().Response.AcceptedStrokes == 0, "Retry creates a fresh dog and clears prior pointer samples.");
            game.ResetTrialLoadout(); BindClock(); yield return null;
            Check(game.Trials.MenuOpen, "Reset returns to the isolated paused menu.");
            game.EndTrials(); game.NativeGame.Tick(0); BindClock(); yield return null;
            Check(game.DungeonRoot == world && world.activeSelf && Pet() == original && ReferenceEquals(bag, game.Session.Inventory), "Exit restores the original world, Labrador and bag identity.");
            Check(slots == new JArray(bag.Slots).ToString() && survival == game.Session.SurvivalSnapshot().ToString() && crowns == game.Session.Crowns && enjoyment == original.Response.Enjoyment && pose == original.transform.localToWorldMatrix, "Mouse petting, pause, reset and retry conserve original inventory, survival, wallet and dog state.");
            Finish();
        }
        void Update()
        { if (finished) return; if (errors.Count > 0 || Time.realtimeSinceStartup - started > 300) { if (errors.Count == 0) errors.Add("Actual Labrador acceptance timeout."); StopAllCoroutines(); Finish(); } }
        void Finish()
        {
            if (finished) return; finished = true; lease?.Dispose(); lease = null;
            string path = Environment.GetEnvironmentVariable("RPG_LABRADOR_RESULT");
            if (string.IsNullOrEmpty(path)) path = Path.Combine(Application.temporaryCachePath, "labrador-acceptance.json");
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            File.WriteAllText(path, new JObject { ["result"] = errors.Count == 0 ? "Passed" : "Failed", ["unity_version"] = Application.unityVersion, ["checks"] = new JArray(checks), ["errors"] = new JArray(errors), ["diagnostics"] = diagnostics, ["limitations"] = new JArray("Actual native app and F2 flow use deterministic screen-ray input; desktop keyboard, pointer focus and audible sound are not exercised.", "Rendered appearance is reviewed separately.") }.ToString() + "\n");
            Application.Quit(errors.Count == 0 ? 0 : 1); enabled = false;
        }
    }
}
