using MusimusihanRpg.Gameplay;
using Newtonsoft.Json.Linq;
using NUnit.Framework;

namespace MusimusihanRpg.Tests
{
    public sealed class PetTransactionsTests
    {
        ExpeditionInventory bag;
        [SetUp] public void SetUp() => bag = new ExpeditionInventory(SourceCatalogs.Load());
        JObject Stack(string id = "healing_draught", int quantity = 1) => new JObject { ["id"] = id, ["quantity"] = quantity, ["instance"] = new JObject { ["item_tag"] = "보존할 이름", ["durability"] = 17.5, ["rune"] = "ember" } };
        void Fill() { for (int i = 0; i < ExpeditionInventory.MaxSlots; i++) bag.AddItem("healing_draught", 1, false, new JObject { ["item_tag"] = "full-" + i }); }

        [Test] public void ReservedWorldStackRetainsItsExactInstanceAndPaysOnlyOnce()
        {
            var source = Stack(); var expected = source["instance"].DeepClone(); var payload = new PetItemPayload(source); var dog = new object(); var second = new object();
            Assert.True(payload.Reserve(dog)); Assert.False(payload.Reserve(second)); Assert.Zero(payload.TransferTo(bag, second));
            source["instance"]["item_tag"] = "outside mutation";
            Assert.AreEqual(1, payload.TransferTo(bag, dog)); Assert.Zero(payload.TransferTo(bag, dog)); Assert.Zero(payload.Remaining);
            Assert.AreEqual(1, bag.CountItem("healing_draught")); Assert.True(JToken.DeepEquals(expected, bag.Slots[0]["instance"]));
        }
        [Test] public void FullBagKeepsTheOriginalItemAvailableForLaterDelivery()
        {
            Fill(); var payload = new PetItemPayload(Stack()); var dog = new object(); Assert.True(payload.Reserve(dog));
            Assert.Zero(payload.TransferTo(bag, dog)); Assert.AreEqual(1, payload.Remaining); Assert.AreEqual(30, bag.CountItem("healing_draught"));
            bag.RemoveFromSlot(0, 1, false); Assert.AreEqual(1, payload.TransferTo(bag, dog)); Assert.Zero(payload.Remaining); Assert.AreEqual(30, bag.CountItem("healing_draught"));
        }
        [Test] public void PartialDeliveryConservesUnitsAndNeverMergesDifferentInstances()
        {
            Fill(); bag.RemoveFromSlot(0, 1, false);
            var payload = new PetItemPayload(Stack("linen_bandage", 11)); var dog = new object(); Assert.True(payload.Reserve(dog));
            int moved = payload.TransferTo(bag, dog); Assert.Greater(moved, 0); Assert.AreEqual(11, moved + payload.Remaining); Assert.Greater(payload.Remaining, 0);
            Assert.AreEqual(moved, bag.CountItem("linen_bandage")); Assert.AreEqual(30, bag.Slots.Count);
            if (payload.Remaining > 0) { payload.Release(dog); Assert.True(payload.Reserve(new object())); }
        }
        [Test] public void InventorySubscriberReentryCannotDuplicateCarriedLoot()
        {
            var payload = new PetItemPayload(Stack("wooden_arrow", 3)); var dog = new object(); Assert.True(payload.Reserve(dog)); int notifications = 0;
            bag.Changed += () => { notifications++; Assert.Zero(payload.TransferTo(bag, dog)); Assert.Zero(payload.Remaining); };
            Assert.AreEqual(3, payload.TransferTo(bag, dog)); Assert.AreEqual(1, notifications); Assert.AreEqual(3, bag.CountItem("wooden_arrow"));
        }
        [Test] public void ReservingFoodDoesNotConsumeItAndCommitRemovesExactlyOneUnit()
        {
            bag.AddItem("raw_meat", 3); var food = new PetFoodReservation(bag, bag.Slots[0]);
            Assert.AreEqual(3, bag.CountItem("raw_meat")); Assert.False(food.Committed);
            Assert.True(food.Commit(bag)); Assert.AreEqual(2, bag.CountItem("raw_meat")); Assert.False(food.Commit(bag)); Assert.AreEqual(2, bag.CountItem("raw_meat"));
        }
        [Test] public void ReplacedIdenticalFoodCannotBeConsumedByAStaleCareAction()
        {
            bag.AddItem("raw_meat", 2); var food = new PetFoodReservation(bag, bag.Slots[0]); var identical = (JObject)bag.Slots[0].DeepClone(); bag.Slots[0] = identical;
            Assert.False(food.Commit(bag)); Assert.AreEqual(2, bag.CountItem("raw_meat")); Assert.False(food.Committed);
        }
        [Test] public void ChangingToAnIsolatedTrialBagDoesNotConsumeOriginalOrTrialFood()
        {
            bag.AddItem("raw_meat", 2); var food = new PetFoodReservation(bag, bag.Slots[0]); var trial = new ExpeditionInventory(SourceCatalogs.Load()); trial.AddItem("raw_meat", 3);
            Assert.False(food.Commit(trial)); Assert.AreEqual(2, bag.CountItem("raw_meat")); Assert.AreEqual(3, trial.CountItem("raw_meat")); Assert.True(food.Commit(bag));
        }
        [Test] public void ContactWindowAcceptsAnOvershootExactlyOnceAndRejectsInvalidTime()
        {
            var contact = new PetContactLatch(); Assert.False(contact.Crossed(double.NaN, .58)); Assert.False(contact.Crossed(-1, .58)); Assert.False(contact.Crossed(.579, .58));
            Assert.True(contact.Crossed(3, .58)); Assert.False(contact.Crossed(3, .58)); contact.Reset(); Assert.True(contact.Crossed(.58, .58));
        }
        [Test] public void EmptyAndNegativeStacksCannotBecomeRewards()
        {
            Assert.Throws<System.ArgumentException>(() => new PetItemPayload(Stack(quantity: 0)));
            Assert.Throws<System.ArgumentException>(() => new PetItemPayload(Stack(quantity: -1)));
            Assert.Throws<System.ArgumentException>(() => new PetItemPayload(new JObject()));
            Assert.Throws<System.ArgumentException>(() => new PetItemPayload(new JObject { ["id"] = "healing_draught" }));
        }
    }
}
