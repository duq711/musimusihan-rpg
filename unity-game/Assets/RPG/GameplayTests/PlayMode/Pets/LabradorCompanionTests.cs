using System.Collections.Generic;
using System.Linq;
using MusimusihanRpg.Gameplay;
using Newtonsoft.Json.Linq;
using NUnit.Framework;
using UnityEngine;

namespace MusimusihanRpg.Tests
{
    /// <summary>Collision-only fixtures exercise the production companion and exact game inventory.</summary>
    public sealed class LabradorCompanionTests
    {
        WorkshopController game;
        GameObject world, package;
        LabradorCompanion pet;
        DungeonMotor player;
        readonly List<AnimationClip> clips = new List<AnimationClip>();
        [SetUp] public void SetUp()
        {
            world = new GameObject("PetBehaviorPhysicsFixture");
            var floor = GameObject.CreatePrimitive(PrimitiveType.Cube); floor.name = "Floor"; floor.transform.SetParent(world.transform); floor.transform.position = Vector3.down * .5f; floor.transform.localScale = new Vector3(40, 1, 40);
            var actor = new GameObject("Player", typeof(CharacterController), typeof(DungeonMotor), typeof(MeleeCombat)); actor.transform.SetParent(world.transform); player = actor.GetComponent<DungeonMotor>(); player.ManualClock = true;
            var eye = new GameObject("Eyes", typeof(Camera)); eye.transform.SetParent(actor.transform, false); eye.transform.localPosition = Vector3.up * .67f; player.Eyes = eye.GetComponent<Camera>();
            game = new GameObject("PetRulesHost").AddComponent<WorkshopController>(); game.ManualClock = true; game.enabled = false; game.DungeonRoot = world; game.DungeonPlayer = player;
            game.ItemIcons = ((JObject)SourceCatalogs.Load().Inventory["ITEM_DEFINITIONS"]).Properties().Select(p => new WorkshopController.ItemIcon { Id = p.Name, Texture = Texture2D.whiteTexture }).ToArray();
            game.Initialize(); game.SetNativeWorld(world, player); player.Relocate(Vector3.up, Quaternion.identity);
            var node = new GameObject("TestOnlyDogCollision", typeof(CharacterController)); node.transform.SetParent(world.transform); node.transform.position = new Vector3(0, .025f, -1.5f);
            var visual = new GameObject("TestOnlyClipTarget"); visual.transform.SetParent(node.transform, false); var mouth = new GameObject("MouthSocket"); mouth.transform.SetParent(visual.transform, false); mouth.transform.localPosition = new Vector3(0, .4f, .4f);
            foreach (string name in LabradorCompanion.RequiredClips)
            { var clip = new AnimationClip { name = name, legacy = true }; clip.SetCurve("", typeof(Transform), "m_LocalPosition.x", AnimationCurve.Linear(0, 0, 1, 0)); clips.Add(clip); }
            pet = node.AddComponent<LabradorCompanion>(); pet.ManualInput = true; pet.Configure(game, visual, clips.ToArray(), mouth.transform);
            package = new GameObject("TestOnlyPackageGeometry"); package.SetActive(false); Physics.SyncTransforms();
        }
        [TearDown] public void TearDown()
        {
            Object.DestroyImmediate(world); Object.DestroyImmediate(package); Object.DestroyImmediate(game.gameObject);
            foreach (var clip in clips) Object.DestroyImmediate(clip); clips.Clear();
        }
        [Test] public void PettingLocksOnlyTheRealPlayerAndFinishesOnceWhilePauseFreezesIt()
        {
            Assert.True(pet.Interact(player)); Assert.True(player.TimedInteraction); Assert.False(pet.TryFeed(player)); Assert.False(pet.TrySearch(player));
            pet.Advance(.5); var phase = pet.Phase; double elapsed = pet.Elapsed; game.TogglePause(); pet.Advance(20);
            Assert.AreEqual(phase, pet.Phase); Assert.AreEqual(elapsed, pet.Elapsed); Assert.Zero(pet.CompletedPets); game.TogglePause();
            pet.Advance(3); Assert.AreEqual(1, pet.CompletedPets); Assert.False(player.TimedInteraction); Assert.False(pet.Busy); Assert.AreEqual(3, pet.Affection);
        }
        [Test] public void FeedingPaysAtTheEatingContactAndNeverTwice()
        {
            var bag = player.Session.Inventory; bag.Slots.Clear(); bag.AddItem("raw_meat", 3);
            Assert.True(pet.TryFeed(player)); Assert.AreEqual(3, bag.CountItem("raw_meat")); pet.Advance(1.3); Assert.AreEqual(3, bag.CountItem("raw_meat"));
            pet.Advance(.1); Assert.AreEqual(2, bag.CountItem("raw_meat")); Assert.AreEqual(1, pet.MealsEaten); pet.Advance(4);
            Assert.AreEqual(2, bag.CountItem("raw_meat")); Assert.AreEqual(1, pet.MealsEaten); Assert.False(player.TimedInteraction); Assert.AreEqual(5, pet.Affection);
        }
        [Test] public void CancelAndWorldIsolationBeforeEatingPreserveActualFood()
        {
            var bag = player.Session.Inventory; bag.Slots.Clear(); bag.AddItem("raw_meat", 2);
            Assert.True(pet.TryFeed(player)); pet.Advance(.7); pet.Cancel(player); Assert.AreEqual(2, bag.CountItem("raw_meat")); Assert.False(player.TimedInteraction);
            Assert.True(pet.TryFeed(player)); world.SetActive(false); Assert.AreEqual(2, bag.CountItem("raw_meat")); Assert.False(player.TimedInteraction); Assert.False(pet.Busy); Assert.Zero(pet.Affection);
        }
        [Test] public void DeathPauseAndNonExplorationPagesRejectPetCommands()
        {
            game.TogglePause(); Assert.False(pet.TryFeed(player)); Assert.False(pet.Interact(player)); Assert.False(pet.TrySearch(player)); game.TogglePause();
            game.Navigate("inventory"); Assert.False(pet.TrySearch(player)); game.SetNativeWorld(world, player);
            player.Session.Body.SetTotalForDebug(0); Assert.False(pet.TrySearch(player)); Assert.False(pet.HandleCommand(KeyCode.R));
        }
        [Test] public void BlockedGroundRoutesAroundWallsAndNeverCrossesUnsupportedSpace()
        {
            var wall = GameObject.CreatePrimitive(PrimitiveType.Cube); wall.transform.SetParent(world.transform); wall.transform.position = new Vector3(0, .7f, 0); wall.transform.localScale = new Vector3(2, 1.4f, .25f); Physics.SyncTransforms();
            Vector3 from = new Vector3(0, .025f, -1.5f), to = new Vector3(0, .025f, 1.5f);
            Assert.False(PetWalkRoute.Clear(from, to)); var route = new PetWalkRoute(); Vector3 direction = route.Direction(from, to, 0);
            Assert.Greater(direction.sqrMagnitude, .5f); Assert.True(PetWalkRoute.Clear(from, from + direction * .4f));
            world.transform.Find("Floor").gameObject.SetActive(false); Physics.SyncTransforms(); Assert.False(PetWalkRoute.Clear(from, to));
        }
        [Test] public void ReservedHiddenItemIsNotTeleportedOrRevealedByAnUnreachableRoute()
        {
            var item = PetFindableItem.Spawn(game, package, new Vector3(8, .025f, -1.5f), new JObject { ["id"] = "wooden_arrow", ["quantity"] = 2 }, true);
            Vector3 original = item.transform.position; Assert.True(item.Hidden); Assert.True(pet.TrySearch(player)); pet.Advance(1.1);
            Assert.AreSame(pet, item.Payload.Owner); pet.Cancel(player);
            Assert.AreEqual(original, item.transform.position); Assert.True(item.Hidden); Assert.Null(item.Payload.Owner); Assert.AreEqual(2, item.Payload.Remaining);
        }
        [Test] public void F2DeactivationPreservesAnInFlightSearchStateAndWorldClaim()
        {
            var item = PetFindableItem.Spawn(game, package, new Vector3(8, .025f, -1.5f), new JObject { ["id"] = "wooden_arrow", ["quantity"] = 2 }, true);
            Assert.True(pet.TrySearch(player)); pet.Advance(1.2); var phase = pet.Phase; var elapsed = pet.Elapsed; var position = pet.transform.position;
            world.SetActive(false); Assert.AreEqual(phase, pet.Phase); Assert.AreEqual(elapsed, pet.Elapsed); Assert.AreEqual(position, pet.transform.position); Assert.AreSame(pet, item.Payload.Owner); Assert.Zero(pet.Affection);
            world.SetActive(true); Physics.SyncTransforms(); pet.Advance(.1); Assert.Greater(pet.Elapsed, elapsed); Assert.AreSame(pet, item.Payload.Owner);
        }
    }
}
