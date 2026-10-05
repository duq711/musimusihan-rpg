using System;
using System.Linq;
using Newtonsoft.Json.Linq;
using UnityEngine;

namespace MusimusihanRpg.Gameplay
{
    /// <summary>The standing handless interaction needs only its actual idle and enjoyment clips.</summary>
    public static class LabradorPettingAssets
    {
        public const string Resource = "Pets/Labrador";
        public static readonly string[] RequiredClips = { "IdleFriendly", "PetEnjoy" };
        public static bool TryLoad(out GameObject prefab, out AnimationClip[] clips, out string failure)
        {
            prefab = Resources.Load<GameObject>(Resource + "/PetModel");
            clips = Resources.LoadAll<AnimationClip>(Resource);
            if (prefab == null) { failure = "실제 래브라도 모델이 설치되지 않았습니다."; return false; }
            var supplied = clips;
            var missing = RequiredClips.Where(name => !supplied.Any(c => c != null && c.name == name)).ToArray();
            if (missing.Length > 0) { failure = "래브라도 쓰다듬기 모션 누락: " + string.Join(", ", missing); return false; }
            failure = ""; return true;
        }
        public static bool Available => TryLoad(out _, out _, out _);
        public static void AddEntries(JArray entries)
        {
            if (!Available || entries.Any(e => (string)e["id"] == LabradorPetting.TrialId)) return;
            entries.Add(new JObject
            {
                ["id"] = LabradorPetting.TrialId, ["category"] = "장면", ["title"] = "래브라도 · 마우스로 머리 쓰다듬기",
                ["action"] = "movement", ["detail"] = "실제 머리 위에서 LMB를 누르고 움직이기 · 귀·고개·털·눈 반응 · E/Esc 나가기 · F2 정지·재시도·원정 복원"
            });
        }
        public static void AddTrialControls(JArray controls, JArray entries)
        {
            var entry = entries.OfType<JObject>().FirstOrDefault(e => (string)e["id"] == LabradorPetting.TrialId);
            if (entry == null) return;
            var rows = controls.OfType<JObject>().Where(e => ((string)e["path"] ?? "").StartsWith("trial/category_4/") && ((string)e["name"] ?? "").StartsWith("Feature_")).ToArray();
            if (rows.Length == 0 || controls.Any(e => (string)e["name"] == "Feature_" + LabradorPetting.TrialId)) return;
            var extra = (JObject)rows.Last().DeepClone(); string original = (string)extra["name"], name = "Feature_" + LabradorPetting.TrialId;
            float y = rows.Max(e => (float)e["rect"][1] + (float)e["rect"][3]) + 7;
            extra["name"] = name; extra["path"] = ((string)extra["path"]).Replace(original, name);
            extra["text"] = entry["title"] + "\n" + entry["detail"]; extra["rect"][1] = y; controls.Add(extra);
            var content = controls.OfType<JObject>().First(e => ((string)e["path"] ?? "").StartsWith("trial/category_4/") && (string)e["name"] == "TrialEntries");
            content["rect"][3] = y + (float)extra["rect"][3] - (float)content["rect"][1];
        }
    }

    public sealed partial class WorkshopController
    {
        GameObject pettingWorld;
        LabradorPetting pettingPet;
        bool consumeNextPettingFrame;
        public LabradorPetting ActivePetting
        {
            get
            {
                if (pettingWorld != DungeonRoot)
                { pettingWorld = DungeonRoot; pettingPet = DungeonRoot == null ? null : DungeonRoot.GetComponentInChildren<LabradorPetting>(true); }
                return pettingPet != null && pettingPet.gameObject.activeInHierarchy ? pettingPet : null;
            }
        }
        public void NotifyPetting(LabradorPetting pet) { pettingWorld = DungeonRoot; pettingPet = pet; }
        public bool PettingInputActive => ActivePetting?.Viewing == true;
        public static bool PettingTrial(string id) => id == LabradorPetting.TrialId;
        public void AddPettingTrialEntries() { if (NativeGame != null) LabradorPettingAssets.AddEntries(Catalog.TestRoomEntries); }
        public void RegisterPettingTrial()
        {
            if (!Catalog.TestRoomEntries.Any(e => (string)e["id"] == LabradorPetting.TrialId) || !LabradorPettingAssets.Available) return;
            Register(LabradorPetting.TrialId, "손 없이 머리 위에서 마우스를 누르고 움직여 쓰담쓰담 · E/Esc 나가기 · F2 정지·재시도", _ =>
            {
                if (!LabradorPettingAssets.TryLoad(out var prefab, out var clips, out string failure)) throw new InvalidOperationException(failure);
                EnsureTrialRoom(); ClearActors(); RecoverTrial();
                DungeonPlayer.ResetTrial(new Vector3(0, 1, 12)); trialEnemyAi = false;
                var position = new Vector3(0, .025f, 10.5f);
                if (!TryPettingFloor(position, out position)) throw new InvalidOperationException("래브라도 시험의 안전한 바닥을 찾지 못했습니다.");
                var pet = LabradorPetting.Spawn(this, prefab, clips, position); FacePettingPlayer(pet);
                AimAt(pet.Head.position); Physics.SyncTransforms();
            });
        }
        public bool BeginPettingTrialView()
        {
            if (!Trials.Active || !PettingTrial(Trials.CurrentEntry) || Trials.MenuOpen || WorldPaused) return false;
            var pet = ActivePetting; if (pet == null) return false;
            if (pet.Viewing) { pet.RefreshView(); return true; }
            AimAt(pet.Head.position); return Interaction.Interact();
        }
        public bool ExitPettingView()
        {
            var pet = ActivePetting; if (pet?.Viewing != true) return false;
            pet.ExitView(); if (Interaction?.Active == pet) Interaction.Cancel();
            consumeNextPettingFrame = true; ClearPendingFrameInput(); return true;
        }
        public PlayerFrameInput FilterPettingFrameInput(PlayerFrameInput input)
        {
            if (consumeNextPettingFrame) { consumeNextPettingFrame = false; return default; }
            return PettingInputActive ? default : input;
        }
        public LabradorPetting EnsureNativePettingPet()
        {
            if (DungeonRoot == null || DungeonPlayer == null || NativeGame?.InHideout != true || Trials.Active) return null;
            var existing = ActivePetting; if (existing != null) return existing;
            if (!LabradorPettingAssets.TryLoad(out var prefab, out var clips, out _)) return null;
            Vector3 forward = Vector3.ProjectOnPlane(DungeonPlayer.Eyes.transform.forward, Vector3.up).normalized;
            if (forward.sqrMagnitude < .1f) forward = Vector3.back;
            foreach (float distance in new[] { 1.2f, 1.65f, 2.1f }) foreach (float angle in new[] { 0f, 28f, -28f, 55f, -55f })
            {
                var proposed = DungeonPlayer.transform.position + Quaternion.AngleAxis(angle, Vector3.up) * forward * distance;
                if (!TryPettingFloor(proposed, out var position)) continue;
                if (Physics.Linecast(DungeonPlayer.Eyes.transform.position, position + Vector3.up * .75f, 1 << DungeonCombatWorld.WorldLayer, QueryTriggerInteraction.Ignore)) continue;
                var pet = LabradorPetting.Spawn(this, prefab, clips, position); FacePettingPlayer(pet); return pet;
            }
            Debug.LogWarning("실제 래브라도를 놓을 안전한 은신처 바닥이 없습니다."); return null;
        }
        static bool TryPettingFloor(Vector3 proposed, out Vector3 position)
        {
            position = proposed;
            if (!Physics.Raycast(proposed + Vector3.up * 2, Vector3.down, out var floor, 4, 1 << DungeonCombatWorld.WorldLayer, QueryTriggerInteraction.Ignore) || floor.normal.y < .75f) return false;
            position = floor.point + Vector3.up * .005f;
            return !Physics.CheckCapsule(position + Vector3.up * .3f, position + Vector3.up * .85f, .27f, 1 << DungeonCombatWorld.WorldLayer, QueryTriggerInteraction.Ignore);
        }
        void FacePettingPlayer(LabradorPetting pet)
        {
            Vector3 current = Vector3.ProjectOnPlane(pet.Mouth.position - pet.Head.position, Vector3.up).normalized;
            Vector3 toward = Vector3.ProjectOnPlane(DungeonPlayer.transform.position - pet.Head.position, Vector3.up).normalized;
            if (current.sqrMagnitude > .1f && toward.sqrMagnitude > .1f) pet.transform.rotation = Quaternion.AngleAxis(Vector3.SignedAngle(current, toward, Vector3.up), Vector3.up) * pet.transform.rotation;
        }
    }
}
