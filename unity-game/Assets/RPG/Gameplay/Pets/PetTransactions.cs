using System;
using Newtonsoft.Json.Linq;

namespace MusimusihanRpg.Gameplay
{
    /// <summary>A scene item remains its own owner until inventory has accepted it.</summary>
    public sealed class PetItemPayload
    {
        public JObject Stack { get; }
        public object Owner { get; private set; }
        public int Remaining => (int?)Stack["quantity"] ?? 0;
        bool transferring;

        public PetItemPayload(JObject stack)
        {
            if (stack == null || string.IsNullOrEmpty((string)stack["id"]) || ((int?)stack["quantity"] ?? 0) <= 0)
                throw new ArgumentException("A real, positive world item stack is required", nameof(stack));
            Stack = (JObject)stack.DeepClone();
        }

        public bool Reserve(object owner)
        {
            if (owner == null || Remaining <= 0 || transferring || Owner != null) return false;
            Owner = owner; return true;
        }

        public void Release(object owner) { if (ReferenceEquals(Owner, owner) && !transferring) Owner = null; }

        public int TransferTo(ExpeditionInventory bag, object owner)
        {
            if (bag == null || transferring || !ReferenceEquals(Owner, owner) || Remaining <= 0) return 0;
            transferring = true;
            try
            {
                int before = Remaining;
                int remaining = bag.AddItem((string)Stack["id"], before, false, Stack["instance"] as JObject);
                Stack["quantity"] = remaining;
                int moved = before - remaining;
                // Subscribers see both owners already updated, including on re-entry.
                if (moved > 0) bag.NotifyChanged();
                return moved;
            }
            finally { transferring = false; }
        }
    }

    /// <summary>Care reserves an exact stack identity, and pays at the first eating contact.</summary>
    public sealed class PetFoodReservation
    {
        readonly ExpeditionInventory bag;
        readonly JObject stack;
        bool committed;
        public string Id => (string)stack["id"];
        public bool Committed => committed;
        public PetFoodReservation(ExpeditionInventory bag, JObject stack) { this.bag = bag; this.stack = stack; }

        public bool Commit(ExpeditionInventory currentBag)
        {
            if (committed || !ReferenceEquals(bag, currentBag)) return false;
            int index = bag.Slots.IndexOf(stack);
            if (index < 0 || (int?)stack["quantity"] <= 0) return false;
            committed = true;
            return (int?)bag.RemoveFromSlot(index, 1)["quantity"] == 1;
        }
    }

    public sealed class PetContactLatch
    {
        bool resolved;
        public void Reset() => resolved = false;
        public bool Crossed(double elapsed, double contactTime)
        {
            if (resolved || !double.IsFinite(elapsed) || elapsed < contactTime) return false;
            resolved = true; return true;
        }
    }
}
