using System.Collections.Generic;
using System.Linq;
using MusimusihanRpg.Gameplay;
using Newtonsoft.Json.Linq;
using NUnit.Framework;
using UnityEngine;

namespace MusimusihanRpg.Tests
{
    /// <summary>Explicit clips exercise view ownership and the production gait clock; real asset import is checked separately.</summary>
    public sealed class LabradorLocomotionTests
    {
        WorkshopController game;
        GameObject world, prefab;
        DungeonMotor player;
        LabradorLocomotionDemo demo;
        Renderer hand;
        PlayerPresentation presentation;
        Vector3 originalCameraPosition;
        Quaternion originalCameraRotation;
        float originalCameraFov, originalCameraNear;
        int originalCameraMask;
        readonly List<AnimationClip> clips = new List<AnimationClip>();
        [SetUp] public void SetUp()
        {
            world = new GameObject("ExplicitGaitFixture");
            var actor = new GameObject("Player", typeof(CharacterController), typeof(DungeonMotor), typeof(MeleeCombat)); actor.transform.SetParent(world.transform); player = actor.GetComponent<DungeonMotor>(); player.ManualClock = true;
            var eye = new GameObject("Eyes", typeof(Camera)); eye.transform.SetParent(actor.transform, false); eye.transform.localPosition = Vector3.up * .7f; player.Eyes = eye.GetComponent<Camera>();
            game = new GameObject("GaitRulesHost").AddComponent<WorkshopController>(); game.enabled = false; game.ManualClock = true; game.DungeonRoot = world; game.DungeonPlayer = player;
            game.ItemIcons = ((JObject)SourceCatalogs.Load().Inventory["ITEM_DEFINITIONS"]).Properties().Select(p => new WorkshopController.ItemIcon { Id = p.Name, Texture = Texture2D.whiteTexture }).ToArray();
            game.Initialize(); game.SetNativeWorld(world, player);
            presentation = actor.AddComponent<PlayerPresentation>(); presentation.enabled = false; presentation.Motor = player;
            var gear = new GameObject("GearCamera", typeof(Camera)); gear.transform.SetParent(actor.transform, false); presentation.GearCamera = gear.GetComponent<Camera>();
            var node = GameObject.CreatePrimitive(PrimitiveType.Cube); node.name = "ExistingHand"; node.transform.SetParent(actor.transform, false); Object.DestroyImmediate(node.GetComponent<Collider>()); hand = node.GetComponent<Renderer>(); presentation.Left = node.AddComponent<SuppliedArm>();
            prefab = new GameObject("ExplicitGaitSkeleton"); new GameObject("Leg").transform.SetParent(prefab.transform, false);
            foreach (string name in LabradorLocomotionAssets.RequiredClips)
            {
                var clip = new AnimationClip { name = name, legacy = true, wrapMode = WrapMode.Loop };
                clip.SetCurve("Leg", typeof(Transform), "m_LocalPosition.y", new AnimationCurve(new Keyframe(0, 0), new Keyframe(name == "Walk" ? .5f : .25f, name == "Walk" ? .08f : .20f), new Keyframe(name == "Walk" ? 1 : .5f, 0)));
                clips.Add(clip);
            }
            demo = LabradorLocomotionDemo.Spawn(game, prefab, clips.ToArray(), new Vector3(0, .005f, 0)); demo.ManualInput = true;
            // The production motor settles its own eye height during game initialization.
            // Conservation must compare the actual settled entry camera, not the fixture's pre-bind height.
            originalCameraPosition = player.Eyes.transform.localPosition; originalCameraRotation = player.Eyes.transform.localRotation;
            originalCameraFov = player.Eyes.fieldOfView; originalCameraNear = player.Eyes.nearClipPlane; originalCameraMask = player.Eyes.cullingMask;
            Assert.True(demo.EnterView(player));
        }
        [TearDown] public void TearDown()
        {
            Object.DestroyImmediate(world); Object.DestroyImmediate(game.gameObject); Object.DestroyImmediate(prefab);
            foreach (var clip in clips) Object.DestroyImmediate(clip); clips.Clear();
        }
        [Test] public void DistinctGaitClocksMoveFixtureLimbsAndKeepPlacementFixed()
        {
            var root = demo.transform.localToWorldMatrix;
            demo.Advance(.3); var leg = demo.Model.transform.Find("Leg"); float walkY = leg.localPosition.y;
            Assert.Greater(walkY, .02f); Assert.AreEqual("Walk", demo.CurrentAnimation);
            Assert.True(demo.SelectMotion("Run")); demo.Advance(.25);
            Assert.AreEqual("Run", demo.CurrentAnimation); Assert.Greater(leg.localPosition.y, walkY);
            Assert.False(demo.SelectMotion("Attack")); Assert.AreEqual("Run", demo.SelectedAnimation);
            for (int i = 0; i < 180; i++) demo.Advance(1f / 60);
            Assert.AreEqual(root, demo.transform.localToWorldMatrix);
        }
        [Test] public void PauseFreezesExactPoseAndRejectsSelectionThenResumesSameGait()
        {
            demo.SelectMotion("Run"); demo.Advance(.27); float clock = demo.MotionTime; Vector3 leg = demo.Model.transform.Find("Leg").localPosition;
            game.TogglePause(); demo.Advance(2);
            Assert.AreEqual(clock, demo.MotionTime); Assert.AreEqual(leg, demo.Model.transform.Find("Leg").localPosition); Assert.False(demo.SelectMotion("Walk"));
            game.TogglePause(); demo.Advance(.07);
            Assert.Greater(demo.MotionTime, clock); Assert.AreEqual("Run", demo.SelectedAnimation); Assert.True(demo.Viewing);
        }
        [Test] public void SideViewHidesHandsFiltersInputAndRestoresCameraAndOwnership()
        {
            Assert.True(game.PettingInputActive); Assert.True(player.TimedInteraction); Assert.False(player.Captured); Assert.False(hand.enabled); Assert.False(presentation.GearCamera.enabled);
            Assert.DoesNotThrow(() => demo.RefreshView(), "Fixture with no native HUD retains valid view ownership.");
            Vector3 side = player.Eyes.transform.position; demo.RefreshView(); Assert.AreEqual(side, player.Eyes.transform.position);
            var input = new PlayerFrameInput { Move = Vector2.one, InteractPressed = true, PrimaryPressed = true };
            var filtered = game.FilterPettingFrameInput(input); Assert.AreEqual(Vector2.zero, filtered.Move); Assert.False(filtered.InteractPressed); Assert.False(filtered.PrimaryPressed);
            Assert.True(game.ExitPettingView()); Assert.False(player.TimedInteraction); Assert.False(game.PettingInputActive); Assert.True(hand.enabled); Assert.True(presentation.GearCamera.enabled);
            Assert.AreEqual(originalCameraPosition, player.Eyes.transform.localPosition); Assert.AreEqual(originalCameraRotation, player.Eyes.transform.localRotation);
            Assert.AreEqual(originalCameraFov, player.Eyes.fieldOfView); Assert.AreEqual(originalCameraNear, player.Eyes.nearClipPlane); Assert.AreEqual(originalCameraMask, player.Eyes.cullingMask);
            Assert.False(game.FilterPettingFrameInput(input).InteractPressed, "The exit E frame is consumed once."); Assert.True(game.FilterPettingFrameInput(input).InteractPressed);
        }
        [Test] public void SuspendingWorldReleasesOwnershipAndReactivationRetainsGaitAndPoseClock()
        {
            demo.SelectMotion("Run"); demo.Advance(.3); float clock = demo.MotionTime;
            world.SetActive(false); Assert.False(demo.Viewing); Assert.False(player.TimedInteraction); Assert.True(hand.enabled);
            world.SetActive(true); demo.Advance(.02);
            Assert.True(demo.Viewing); Assert.True(game.PettingInputActive); Assert.AreEqual("Run", demo.SelectedAnimation); Assert.Greater(demo.MotionTime, clock); Assert.False(hand.enabled);
        }
    }
}
