using System.Collections.Generic;
using System.Linq;
using MusimusihanRpg.Gameplay;
using Newtonsoft.Json.Linq;
using NUnit.Framework;
using UnityEngine;

namespace MusimusihanRpg.Tests
{
    /// <summary>Explicit skin and skeletal fixtures test the real screen-ray path without substituting a shipped Labrador.</summary>
    public sealed class LabradorPettingTests
    {
        WorkshopController game;
        GameObject world, visual;
        LabradorPetting pet;
        DungeonMotor player;
        SkinnedMeshRenderer skin;
        Mesh mesh;
        Material material;
        Renderer hand;
        PlayerPresentation presentation;
        readonly List<AnimationClip> clips = new List<AnimationClip>();
        [SetUp] public void SetUp()
        {
            world = new GameObject("MousePettingPhysicsFixture");
            var floor = GameObject.CreatePrimitive(PrimitiveType.Cube); floor.transform.SetParent(world.transform); floor.transform.position = Vector3.down * .5f; floor.transform.localScale = new Vector3(40, 1, 40);
            var actor = new GameObject("Player", typeof(CharacterController), typeof(DungeonMotor), typeof(MeleeCombat)); actor.transform.SetParent(world.transform); player = actor.GetComponent<DungeonMotor>(); player.ManualClock = true;
            var eye = new GameObject("Eyes", typeof(Camera)); eye.transform.SetParent(actor.transform, false); eye.transform.localPosition = Vector3.up * .67f; player.Eyes = eye.GetComponent<Camera>(); player.Eyes.pixelRect = new Rect(0, 0, 800, 600); player.Eyes.aspect = 4f / 3;
            game = new GameObject("PettingRulesHost").AddComponent<WorkshopController>(); game.ManualClock = true; game.enabled = false; game.DungeonRoot = world; game.DungeonPlayer = player;
            game.ItemIcons = ((JObject)SourceCatalogs.Load().Inventory["ITEM_DEFINITIONS"]).Properties().Select(p => new WorkshopController.ItemIcon { Id = p.Name, Texture = Texture2D.whiteTexture }).ToArray();
            game.Initialize(); game.SetNativeWorld(world, player); player.Relocate(new Vector3(0, 1, 2), Quaternion.identity);
            presentation = actor.AddComponent<PlayerPresentation>(); presentation.enabled = false; presentation.Motor = player;
            var gear = new GameObject("GearCamera", typeof(Camera)); gear.transform.SetParent(actor.transform, false); presentation.GearCamera = gear.GetComponent<Camera>();
            var handNode = GameObject.CreatePrimitive(PrimitiveType.Cube); handNode.name = "TestHandRenderer"; handNode.transform.SetParent(actor.transform, false); Object.DestroyImmediate(handNode.GetComponent<Collider>()); hand = handNode.GetComponent<Renderer>();
            presentation.Left = handNode.AddComponent<SuppliedArm>(); // Active equipment root makes camera-sync assertions meaningful.
            var petNode = new GameObject("TestOnlyPettingSkin"); petNode.transform.SetParent(world.transform);
            visual = new GameObject("TestOnlyNamedSkeleton"); visual.transform.SetParent(petNode.transform, false);
            Transform Bone(string name, Transform parent, Vector3 at) { var node = new GameObject(name); node.transform.SetParent(parent, false); node.transform.localPosition = at; return node.transform; }
            var torso = Bone("Torso3_15", visual.transform, Vector3.zero);
            var n1 = Bone("Neck1_14", torso, Vector3.up * .3f); var n2 = Bone("Neck2_13", n1, Vector3.up * .13f); var n3 = Bone("Neck3_12", n2, Vector3.up * .10f);
            var head = Bone("Head_1", n3, Vector3.up * .07f); var upper = Bone("Neck3.001_11", n3, new Vector3(0, .05f, .1f)); var jaw = Bone("Neck3.002_10", upper, Vector3.down * .02f); Bone("MouthSocket", jaw, Vector3.forward * .12f);
            foreach (string side in new[] { "L", "R" })
            {
                float sign = side == "L" ? -1 : 1; int start = side == "L" ? 5 : 9;
                var ear = Bone("Ear1." + side + "_" + start, n3, new Vector3(sign * .16f, .13f, 0));
                for (int i = 2; i <= 4; i++) ear = Bone("Ear" + i + "." + side + "_" + (start - i + 1), ear, new Vector3(sign * .035f, -.04f, 0));
            }
            skin = visual.AddComponent<SkinnedMeshRenderer>();
            mesh = new Mesh { name = "ExplicitHeadAndTorsoSkinFixture" };
            mesh.vertices = new[] { new Vector3(-.18f, .45f, .08f), new Vector3(.18f, .45f, .08f), new Vector3(.18f, .9f, .08f), new Vector3(-.18f, .9f, .08f), new Vector3(-.2f, .05f, .08f), new Vector3(.2f, .05f, .08f), new Vector3(0, .3f, .08f) };
            mesh.triangles = new[] { 0, 1, 2, 0, 2, 3, 4, 5, 6 };
            mesh.boneWeights = Enumerable.Range(0, 7).Select(i => new BoneWeight { boneIndex0 = i < 4 ? 0 : 1, weight0 = 1 }).ToArray();
            skin.bones = new[] { head, torso }; skin.rootBone = torso; mesh.bindposes = skin.bones.Select(b => b.worldToLocalMatrix * skin.transform.localToWorldMatrix).ToArray();
            mesh.AddBlendShapeFrame("target_1", 100, new Vector3[7], new Vector3[7], new Vector3[7]); mesh.RecalculateNormals(); mesh.RecalculateBounds(); skin.sharedMesh = mesh;
            material = new Material(Shader.Find("Standard")); skin.sharedMaterial = material;
            foreach (string name in LabradorPettingAssets.RequiredClips)
            {
                var clip = new AnimationClip { name = name, legacy = true };
                foreach (var bone in visual.GetComponentsInChildren<Transform>())
                {
                    var pathParts = new List<string>(); var cursor = bone;
                    while (cursor != visual.transform) { pathParts.Insert(0, cursor.name); cursor = cursor.parent; }
                    string path = string.Join("/", pathParts); var q = bone.localRotation;
                    foreach (var axis in new[] { new KeyValuePair<string, float>("x", q.x), new KeyValuePair<string, float>("y", q.y), new KeyValuePair<string, float>("z", q.z), new KeyValuePair<string, float>("w", q.w) }) clip.SetCurve(path, typeof(Transform), "m_LocalRotation." + axis.Key, AnimationCurve.Linear(0, axis.Value, 1, axis.Value));
                }
                clips.Add(clip);
            }
            pet = petNode.AddComponent<LabradorPetting>(); pet.ManualInput = true; pet.Configure(game, visual, clips.ToArray()); Physics.SyncTransforms();
        }
        [TearDown] public void TearDown()
        {
            Object.DestroyImmediate(world); Object.DestroyImmediate(game.gameObject); Object.DestroyImmediate(mesh); Object.DestroyImmediate(material);
            foreach (var clip in clips) Object.DestroyImmediate(clip); clips.Clear();
        }
        Vector2 Pixel(float x = 0, float y = .68f) => player.Eyes.WorldToScreenPoint(new Vector3(x, y, .08f));
        void Drag(int count = 30)
        {
            Assert.True(pet.ProcessPointer(player.Eyes, Pixel(), true, .02));
            for (int i = 1; i <= count; i++) { Assert.True(pet.ProcessPointer(player.Eyes, Pixel(.035f * Mathf.Sin(i * .25f)), true, .02)); pet.Advance(.02); }
        }
        [Test] public void ResponseRejectsStationaryAndDiscontinuousPointerMotionAndBoundsFollow()
        {
            var response = new LabradorPettingResponse(); response.Stroke(Vector3.right, Vector3.zero, true, .02); response.Advance(.1); Assert.Zero(response.Enjoyment); Assert.Zero(response.AcceptedStrokes);
            response.Stroke(Vector3.right, Vector3.right, true, .02); Assert.Zero(response.Enjoyment);
            for (int i = 0; i < 100; i++) { response.Stroke(Vector3.right, new Vector3(.02f, 0, .02f), true, .02); response.Advance(.02); }
            Assert.Greater(response.Enjoyment, .7f); Assert.Greater(response.RightEar, response.LeftEar); Assert.LessOrEqual(Mathf.Abs(response.Yaw), 8); Assert.LessOrEqual(Mathf.Abs(response.Pitch), 5); Assert.LessOrEqual(Mathf.Abs(response.Roll), 5);
            response.Stroke(Vector3.zero, Vector3.zero, false, .02); response.Advance(35); Assert.Zero(response.Enjoyment); Assert.Less(response.Intensity, .001f);
        }
        [Test] public void ActualPosedHeadRaySelectsHeadTrianglesAndRejectsTorsoAndOcclusion()
        {
            Assert.AreEqual(2, pet.HeadTriangles);
            Assert.True(pet.TryRaycastHead(new Ray(new Vector3(0, .68f, 1), Vector3.back), out var hit, out _)); Assert.AreEqual(.08f, hit.z, .001f);
            Assert.False(pet.TryRaycastHead(new Ray(new Vector3(0, .17f, 1), Vector3.back), out _, out _));
            var wall = GameObject.CreatePrimitive(PrimitiveType.Cube); wall.transform.SetParent(world.transform); wall.transform.position = new Vector3(0, .68f, .5f); wall.transform.localScale = new Vector3(.4f, .4f, .1f); Physics.SyncTransforms();
            Assert.False(pet.TryRaycastHead(new Ray(new Vector3(0, .68f, 1), Vector3.back), out _, out _));
        }
        [Test] public void ScaledSkinRayMatchesTheRenderedHeadInWorldSpace()
        {
            visual.transform.localScale = Vector3.one * .3f; Physics.SyncTransforms();
            Vector3 expected = visual.transform.TransformPoint(new Vector3(0, .68f, .08f));
            Assert.True(pet.TryRaycastHead(new Ray(expected + Vector3.forward, Vector3.back), out var hit, out _));
            Assert.Less(Vector3.Distance(expected, hit), .0001f);
            Assert.False(pet.TryRaycastHead(new Ray(new Vector3(0, .68f, 1), Vector3.back), out _, out _));
        }
        [Test] public void ActualSourceEarNamesMapToTheTouchedSpatialSide()
        {
            // The shipped rig names its +X ear .L; reflect the ordinary fixture's labels to that layout.
            foreach (var ear in visual.GetComponentsInChildren<Transform>().Where(t => t.name.StartsWith("Ear")))
            { var at = ear.localPosition; at.x = -at.x; ear.localPosition = at; }
            var left = visual.GetComponentsInChildren<Transform>().Single(t => t.name == "Ear1.L_5");
            var right = visual.GetComponentsInChildren<Transform>().Single(t => t.name == "Ear1.R_9");
            Assert.Greater(left.position.x, right.position.x); Assert.True(pet.EnterView(player));
            pet.ProcessPointer(player.Eyes, Pixel(.09f), true, .02);
            for (int i = 1; i <= 15; i++) { Assert.True(pet.ProcessPointer(player.Eyes, Pixel(.09f + i * .002f), true, .02)); pet.Advance(.02); }
            Assert.Greater(pet.Response.RightEar, pet.Response.LeftEar);
            Assert.Greater(Quaternion.Angle(Quaternion.identity, left.localRotation), Quaternion.Angle(Quaternion.identity, right.localRotation) + .05f);
        }
        [Test] public void DisplayPointerMapsLetterboxedOutputToTheReducedWorldCamera()
        {
            Assert.True(pet.EnterView(player)); var camera = player.Eyes;
            var reduced = new RenderTexture(320, 180, 0); camera.targetTexture = reduced; camera.aspect = 16f / 9;
            try
            {
                pet.RefreshView(); Vector3 expected = new Vector3(.1f, .68f, .08f), normalized = camera.WorldToViewportPoint(expected);
                var content = SourceWindowLayout.Content(2000, 1200); var displayed = new Rect(content.x, content.y, content.width, content.height);
                Assert.Greater(content.y, 0); Assert.Greater(content.width, reduced.width);
                Vector2 pixel = displayed.min + new Vector2(normalized.x * displayed.width, normalized.y * displayed.height);
                Assert.False(pet.ProcessPointer(camera, pixel, true, .02), "Raw output pixels do not belong to the reduced camera surface.");
                Assert.True(pet.ProcessDisplayPointer(camera, pixel, displayed, true, .02)); Assert.Less(Vector3.Distance(expected, pet.LastStrokePoint), .001f);
                Assert.False(pet.ProcessDisplayPointer(camera, new Vector2(1000, 0), displayed, true, .02)); Assert.False(pet.Response.Contact);
            }
            finally { camera.targetTexture = null; Object.DestroyImmediate(reduced); }
        }
        [Test] public void SharedScreenPointerDrivesAsymmetricEarsHappyEyesAndFurWithoutRootRotation()
        {
            Assert.True(pet.EnterView(player)); Quaternion root = pet.transform.rotation; Drag();
            Assert.Greater(pet.Response.AcceptedStrokes, 20); Assert.Greater(pet.Response.DistanceStroked, .05f); Assert.Greater(pet.Response.Enjoyment, .2f); Assert.Greater(pet.Response.Intensity, 0);
            Assert.Greater(pet.EyeRelaxation, 0); Assert.AreEqual(pet.EyeRelaxation, skin.GetBlendShapeWeight(0), .001f); Assert.AreEqual(root, pet.transform.rotation);
            var block = new MaterialPropertyBlock(); skin.GetPropertyBlock(block); Assert.Greater(block.GetFloat("_PetStrokeStrength"), 0); Assert.AreEqual(.065f, block.GetFloat("_PetStrokeRadius"));
            Assert.False(player.Captured); Assert.True(player.TimedInteraction); Assert.False(hand.enabled); Assert.False(presentation.GearCamera.enabled);
        }
        [Test] public void ReleasedOrMissedScreenContactDoesNotAccumulateEnjoyment()
        {
            Assert.True(pet.EnterView(player)); Drag(); float happy = pet.Response.Enjoyment; int strokes = pet.Response.AcceptedStrokes;
            Assert.True(pet.ProcessPointer(player.Eyes, Pixel(), false, .02)); pet.Advance(1); Assert.Less(pet.Response.Enjoyment, happy); Assert.Less(pet.Response.Intensity, .001f);
            Assert.False(pet.ProcessPointer(player.Eyes, new Vector2(-1000, -1000), true, .02)); Assert.AreEqual(strokes, pet.Response.AcceptedStrokes); Assert.False(pet.Response.Contact);
        }
        [Test] public void StationaryScreenPointerCannotTurnAnAnimatedHeadIntoAStroke()
        {
            Assert.True(pet.EnterView(player)); Vector2 fixedPointer = Pixel();
            for (int i = 0; i < 120; i++) { pet.ProcessPointer(player.Eyes, fixedPointer, true, .02); pet.Advance(.02); }
            Assert.Zero(pet.Response.AcceptedStrokes); Assert.Zero(pet.Response.DistanceStroked); Assert.Zero(pet.Response.Enjoyment);
        }
        [Test] public void GameClockPauseBlocksPointerAndKeepsTheExactResponseAndPose()
        {
            Assert.True(pet.EnterView(player)); Drag(); float happy = pet.Response.Enjoyment; Quaternion head = pet.Head.localRotation; int strokes = pet.Response.AcceptedStrokes;
            game.TogglePause(); Assert.False(pet.ProcessPointer(player.Eyes, Pixel(.04f), true, 5)); pet.Advance(5);
            Assert.True(presentation.HasVisibleEquipment); presentation.GearCamera.enabled = true; hand.enabled = true;
            presentation.SyncGearCamera(); Assert.False(presentation.GearCamera.enabled);
            pet.SendMessage("LateUpdate"); presentation.SyncGearCamera();
            Assert.False(presentation.GearCamera.enabled); Assert.False(hand.enabled);
            Assert.AreEqual(happy, pet.Response.Enjoyment); Assert.AreEqual(head, pet.Head.localRotation); Assert.AreEqual(strokes, pet.Response.AcceptedStrokes); game.TogglePause();
            pet.Advance(.02); Assert.Less(pet.Response.Enjoyment, happy);
        }
        [Test] public void ExitAndWorldIsolationRestoreCameraGearAndTimedOwnerWithoutChangingPetState()
        {
            Vector3 position = player.Eyes.transform.localPosition; Quaternion rotation = player.Eyes.transform.localRotation; float fov = player.Eyes.fieldOfView; int mask = player.Eyes.cullingMask;
            Assert.True(pet.EnterView(player)); Drag(); float happy = pet.Response.Enjoyment; Quaternion head = pet.Head.localRotation; string animation = pet.CurrentAnimation;
            world.SetActive(false); Assert.False(pet.Viewing); Assert.True(pet.SuspendedView); Assert.AreEqual(happy, pet.Response.Enjoyment); Assert.AreEqual(head, pet.Head.localRotation); Assert.AreEqual(animation, pet.CurrentAnimation);
            Assert.False(player.TimedInteraction); Assert.True(hand.enabled); Assert.True(presentation.GearCamera.enabled); Assert.AreEqual(position, player.Eyes.transform.localPosition); Assert.AreEqual(rotation, player.Eyes.transform.localRotation); Assert.AreEqual(fov, player.Eyes.fieldOfView); Assert.AreEqual(mask, player.Eyes.cullingMask);
            world.SetActive(true); pet.Advance(.02); Assert.True(pet.Viewing); Assert.False(pet.SuspendedView); pet.ExitView(); Assert.False(player.TimedInteraction); Assert.True(hand.enabled); Assert.AreEqual(position, player.Eyes.transform.localPosition);
        }
        [Test] public void StandingEnjoyAndIdleTransitionsUseTheSharedClockAndDeathRejectsInput()
        {
            Assert.True(pet.EnterView(player)); pet.Advance(.2); Assert.AreEqual("PetEnjoy", pet.CurrentAnimation); pet.Advance(1); Assert.AreEqual("PetEnjoy", pet.CurrentAnimation);
            pet.ExitView(); pet.Advance(.2); Assert.AreEqual("IdleFriendly", pet.CurrentAnimation); pet.Advance(1); Assert.AreEqual("IdleFriendly", pet.CurrentAnimation);
            player.Session.Body.SetTotalForDebug(0); Assert.False(pet.EnterView(player)); Assert.False(pet.ProcessPointer(player.Eyes, Pixel(), true, .02));
        }
        [Test] public void ExitConsumesTheSameFrameInteractionAndAttackExactlyOnce()
        {
            Assert.True(pet.EnterView(player)); var input = new PlayerFrameInput { Captured = true, InteractPressed = true, AttackPressed = true, Move = Vector2.up };
            Assert.False(game.FilterPettingFrameInput(input).Captured); Assert.True(game.ExitPettingView());
            var consumed = game.FilterPettingFrameInput(input); Assert.False(consumed.Captured); Assert.False(consumed.InteractPressed); Assert.False(consumed.AttackPressed); Assert.AreEqual(Vector2.zero, consumed.Move);
            var next = game.FilterPettingFrameInput(input); Assert.True(next.Captured); Assert.True(next.InteractPressed); Assert.True(next.AttackPressed); Assert.AreEqual(input.Move, next.Move);
        }
    }
}
