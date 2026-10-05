using System;
using Newtonsoft.Json.Linq;
using UnityEngine;

namespace MusimusihanRpg.Gameplay
{
    /// <summary>Authored scene loot. Its actual package and instance travel in the dog's mouth.</summary>
    public sealed class PetFindableItem : DungeonInteractable
    {
        public PetItemPayload Payload { get; private set; }
        public bool Hidden { get; private set; }
        public bool Carried { get; private set; }
        public JObject Stack => Payload.Stack;
        public override bool Busy => false;
        public override string Prompt => "[E] " + Game.Session.Inventory.ItemName((string)Stack["id"]) + " ×" + Payload.Remaining + " 줍기";
        Transform sceneParent;
        Vector3 home;
        Vector3 sceneScale;
        Quaternion homeRotation;
        Renderer[] renderers;
        bool[] rendererEnabled;

        public static PetFindableItem Spawn(WorkshopController game, GameObject packagePrefab, Vector3 position, JObject stack, bool hidden = true)
        {
            if (game == null || game.DungeonRoot == null || packagePrefab == null) throw new ArgumentException("A real world and package prefab are required");
            var node = Instantiate(packagePrefab, game.DungeonRoot.transform);
            node.name = "PetFindableItem_" + (string)stack["id"];
            node.transform.SetPositionAndRotation(position, Quaternion.identity);
            var item = node.GetComponent<PetFindableItem>() ?? node.AddComponent<PetFindableItem>();
            item.Configure(game, stack, hidden); node.SetActive(true); return item;
        }

        public void Configure(WorkshopController game, JObject stack, bool hidden)
        {
            Game = game; Payload = new PetItemPayload(stack); Hidden = hidden;
            sceneParent = transform.parent; home = transform.position; homeRotation = transform.rotation;
            sceneScale = transform.localScale;
            // Visual packages are queryable only through this item's owned focus.
            foreach (var collider in GetComponentsInChildren<Collider>(true)) collider.enabled = false;
            renderers = GetComponentsInChildren<Renderer>(true); rendererEnabled = new bool[renderers.Length];
            for (int i = 0; i < renderers.Length; i++) rendererEnabled[i] = renderers[i].enabled;
            if (FocusCollider == null) CreateFocus(new Bounds(Vector3.up * .18f, new Vector3(.42f, .36f, .42f)));
            SetVisible(!hidden); FocusCollider.enabled = !hidden;
        }

        void SetVisible(bool visible)
        { for (int i = 0; i < renderers.Length; i++) if (renderers[i] != null) renderers[i].enabled = visible && rendererEnabled[i]; }

        public bool Reserve(LabradorCompanion pet) => !Carried && Payload.Reserve(pet);
        public void ReleaseReservation(LabradorCompanion pet)
        { if (Carried) return; Payload.Release(pet); FocusCollider.enabled = !Hidden && Payload.Owner == null && Payload.Remaining > 0; }
        public void Reveal() { Hidden = false; SetVisible(true); FocusCollider.enabled = Payload.Owner == null; }

        public bool Attach(LabradorCompanion pet, Transform mouth)
        {
            if (mouth == null || !ReferenceEquals(Payload.Owner, pet) || Payload.Remaining <= 0) return false;
            Reveal(); Carried = true; FocusCollider.enabled = false;
            Vector3 worldScale = transform.lossyScale * .24f;
            transform.SetParent(mouth, false); transform.localPosition = Vector3.zero; transform.localRotation = Quaternion.identity;
            Vector3 parentScale = mouth.lossyScale;
            transform.localScale = new Vector3(worldScale.x / Mathf.Max(.00001f, Mathf.Abs(parentScale.x)), worldScale.y / Mathf.Max(.00001f, Mathf.Abs(parentScale.y)), worldScale.z / Mathf.Max(.00001f, Mathf.Abs(parentScale.z)));
            return true;
        }

        public int Deliver(LabradorCompanion pet, ExpeditionInventory bag)
        {
            int moved = Payload.TransferTo(bag, pet);
            if (Payload.Remaining == 0)
            {
                FocusCollider.enabled = false; gameObject.SetActive(false); Destroy(gameObject);
            }
            return moved;
        }

        public void PutDown(LabradorCompanion pet, Vector3 position)
        {
            if (!ReferenceEquals(Payload.Owner, pet)) return;
            // On world shutdown retain the original scene owner and stack.
            transform.SetParent(sceneParent, true); transform.SetPositionAndRotation(position, homeRotation);
            transform.localScale = sceneScale;
            Carried = false; Payload.Release(pet); Hidden = false; SetVisible(true); FocusCollider.enabled = Payload.Remaining > 0;
        }

        public void RestoreHome(LabradorCompanion pet) => PutDown(pet, home);

        public override bool Interact(DungeonMotor player)
        {
            if (!Available(player) || Hidden || Carried || Payload.Owner != null || Payload.Remaining <= 0 || player.Eyes == null) return false;
            var at = transform.position + Vector3.up * .18f;
            if (Vector3.Distance(player.Eyes.transform.position, at) > 3 || Physics.Linecast(player.Eyes.transform.position, at, 1 << DungeonCombatWorld.WorldLayer, QueryTriggerInteraction.Ignore)) return false;
            if (!Payload.Reserve(player)) return false;
            int moved = Payload.TransferTo(player.Session.Inventory, player); Payload.Release(player);
            if (Payload.Remaining == 0) { FocusCollider.enabled = false; gameObject.SetActive(false); Destroy(gameObject); }
            Game.NativeGame?.Notice(moved > 0 ? "물어온 아이템을 주웠습니다." : "가방이 가득 찼습니다. 아이템은 바닥에 남아 있습니다.");
            return moved > 0;
        }
        public override void Cancel(DungeonMotor player) { }
        public override void Advance(double delta) { }
    }
}
