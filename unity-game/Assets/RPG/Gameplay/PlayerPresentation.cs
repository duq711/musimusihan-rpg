using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;

namespace MusimusihanRpg.Gameplay
{
    /// <summary>Shared real player hands. Review controls pose the same rigs used by gameplay.</summary>
    public sealed partial class PlayerPresentation : MonoBehaviour
    {
        public const int BodyLayer = 17, EquipmentLayer = 19;
        public DungeonMotor Motor;
        public SuppliedArm Left, Right;
        public GameObject Body;
        public Camera GearCamera;
        public SwordPresentation Weapons;
        public BowPresentation Archery;
        public FlailPresentation Flail;
        public MagicPresentation Magic;
        public TorchPresentation Torch;
        public bool Review { get; private set; }
        public bool Sequence { get; private set; }
        public int SelectedSide { get; private set; }
        public string HandView { get; private set; } = "dorsal";
        public float MotionClock { get; private set; }
        public bool WorldContactEnabled { get; private set; }
        float sequenceTime;string previousReviewProfile="original";
        public string PreviousReviewProfile=>previousReviewProfile;
        public static readonly string[] ReviewDigits = { "thumb", "index", "middle", "ring", "little" };
        readonly Dictionary<int, Dictionary<string, Vector3>> values = new Dictionary<int, Dictionary<string, Vector3>>();
        public void Initialize()
        {
            Left.Initialize(); Right.Initialize();
            SourceBodyMaterials.Apply(Body);
            if (values.Count == 0) foreach (int side in new[] { -1, 1 }) values.Add(side, ReviewDigits.ToDictionary(d => d, d => Vector3.zero));
            Motor.Eyes.cullingMask &= ~((1 << BodyLayer) | (1 << EquipmentLayer) | (1 << PlayerPortrait.Layer));
            if (Application.isPlaying)
            {
                SourceSceneRenderer.Ensure(this);
                if (GearCamera != null)
                {
                    var environment = GearCamera.GetComponent<SourceEquipmentEnvironment>();
                    if (environment == null) environment = GearCamera.gameObject.AddComponent<SourceEquipmentEnvironment>();
                    environment.Player = this;
                }
            }
            UpdatePose();
        }
        void Awake() { if (Left != null && Right != null) Initialize(); }
        public bool BeginReview()
        {
            if(Review)return true;
            if(ChestStowed||Motor.Camping||Motor.Session!=null&&(Motor.Session.Inventory.Equipment["weapon"].Length>0||Motor.Session.Inventory.Equipment["offhand"].Length>0))return false;
            previousReviewProfile=HandsProfile;if(!SetHandsProfile("detailed"))return false;
            CancelTreatment(); EndChest();
            Initialize(); Review = true; Sequence = false; sequenceTime = 0; SelectedSide = 0; HandView = "dorsal";
            Left.ResetPose(); Right.ResetPose(); SetAll(0); UpdatePose(); Motor.ReleasePointer();return true;
        }
        public void EndReview()
        {
            if (!Review) return; Review = false; Sequence = false; Left.ResetPose(); Right.ResetPose();SetHandsProfile(previousReviewProfile);previousReviewProfile="original";HandView="dorsal"; UpdatePose();
        }
        public bool SelectSide(int side)
        { if (side != -1 && side != 0 && side != 1) return false; Sequence = false; SelectedSide = side; return true; }
        public bool SelectView(string view)
        { if (view != "dorsal" && view != "palm" && view != "wrist_side") return false; HandView = view; UpdatePose(); return true; }
        public Vector3 ReviewValues(string digit) => SelectedSide == 0 ? (values[-1][digit] + values[1][digit]) * .5f : values[SelectedSide][digit];
        bool SetValue(string digit, int joint, float amount)
        {
            if (!Review || !ReviewDigits.Contains(digit) || joint < 0 || joint > 2 || !float.IsFinite(amount)) return false;
            foreach (int side in new[] { -1, 1 })
            {
                if (SelectedSide != 0 && SelectedSide != side) continue;
                var v = values[side][digit]; v[joint] = Mathf.Clamp01(amount); values[side][digit] = v;
                (side < 0 ? Left : Right).SetJointFlexion(digit, joint, amount);
            }
            return true;
        }
        public bool SetJoint(string digit, int joint, float amount)
        { if (!SetValue(digit, joint, amount)) return false; Sequence = false; return true; }
        void SetAll(float amount) { foreach (string digit in ReviewDigits) for (int joint = 0; joint < 3; joint++) SetValue(digit, joint, amount); }
        public void Preset(bool fist) { Sequence = false; SetAll(fist ? 1 : 0); }
        public void ToggleSequence()
        {
            if (!Review) return;
            if (Sequence) { Sequence = false; return; }
            SetAll(0); sequenceTime = 0; Sequence = true;
        }
        public void Advance(double seconds, bool paused)
        {
            Torch?.AdvanceIgnition(seconds,paused);
            if (paused || !double.IsFinite(seconds) || seconds <= 0) return;
            float delta=(float)seconds;
            if (Review && Sequence)
            {
                sequenceTime += delta; SetAll(0); int step = Mathf.FloorToInt(sequenceTime);
                if (step >= 15) Sequence = false;
                else SetValue(ReviewDigits[step / 3], step % 3, Mathf.Sin(Mathf.PI * (sequenceTime % 1)));
            }
            if(AdvanceTreatment(delta))return;
            if(ChestStowed){ApplyChestEquipment();return;}
            if(Motor.Camping){UpdatePose();return;}
            if(Weapons?.Combat.ExecutionActive==true){UpdatePose();return;}
            if (!Review) { AdvanceMotion(delta); Motor.AdvanceCameraFeedback(delta,MotionClock); } RefreshPose(seconds);
        }
        public void UpdatePose()=>RefreshPose(0);
        void RefreshPose(double seconds)
        {
            using var timing=NativeFrameBenchmarkDiagnostics.Measure("PlayerPresentation.RefreshPose");
            if (Left == null || Right == null || Motor?.Eyes == null) return;
            Torch?.ObserveIgnitionContext();
            ObserveMotionInventory();
            Right.SetDrawGlove(Weapons?.DrawReaching==true&&!TreatmentActive);
            if(TreatmentActive){ApplyTreatmentEquipment();SyncGearCamera();return;}
            if(ChestStowed){ApplyChestEquipment();return;}
            // Authored sword/shield rigs stay production skins in the source greybox review.
            Right.UseProductionGeometry(Weapons?.OwnsRight==true);Left.UseProductionGeometry(Weapons?.OwnsLeft==true||Magic?.ShieldHeld==true);
            // An unused idle hand must not leave fingertips at the screen edge.
            Right.gameObject.SetActive(!Motor.Camping&&(Review||Weapons?.OwnsRight==true||Archery?.OwnsHands==true||Flail?.OwnsRight==true||Magic?.OwnsRight==true));
            // Unity's camera faces +Z. The source frame faces -Z after glTF reflection.
            var frame = Motor.Eyes.transform.rotation * Quaternion.Euler(0, 180, 0);
            Vector3 Point(Vector3 source) => Motor.Eyes.transform.position + frame * SourcePose.Position(source);
            foreach (int side in new[] { -1, 1 })
            {
                if (!Review && (side<0&&Torch?.OwnsLeft==true||Archery?.OwnsHands==true||side>0&&Flail?.OwnsRight==true||side>0&&Magic?.OwnsRight==true||side<0&&Magic?.OwnsLeft==true||Weapons != null && (side > 0 ? Weapons.OwnsRight : Weapons.OwnsLeft))) continue;
                var arm = side < 0 ? Left : Right;
                var contact = Review ? new Vector3(side < 0 ? -.27f : .025f, .035f, -.43f)
                    : side < 0 ? new Vector3(-.43f, -.29f + Mathf.Sin(MotionClock * 1.8f) * .004f, -.65f) : new Vector3(.43f, -.60f, -.65f);
                var orientation = frame * SourcePose.Euler(Review ? new Vector3(1.35f, -side * .25f, side * .10f)
                    : side < 0 ? new Vector3(.75f, .35f, -.26f) : new Vector3(.75f, -.28f, .25f));
                if (Review && HandView != "dorsal") orientation *= Quaternion.AngleAxis(HandView == "palm" ? 180 : side * 90, Vector3.forward);
                arm.transform.rotation = orientation; arm.transform.position = Point(contact) - orientation * SourcePose.Position(arm.ContactCenter);
                var shoulder = Point(new Vector3(side * .29f, -.34f, .10f));
                var pole = frame * SourcePose.Position(new Vector3(side * .65f, -.85f, .14f));
                arm.FitArm(shoulder, Elbow(shoulder, arm.transform.position, pole));
                if (!Review) arm.SetRelaxedPose();
            }
            Weapons?.ApplyPose(seconds);Archery?.ApplyPose((float)seconds);Flail?.ApplyPose((float)seconds);Magic?.ApplyPose((float)seconds);Torch?.ApplyPose(seconds);
            if(!Review&&!Motor.Camping)Weapons?.Combat.AdvanceImpact(seconds);
            RefreshLeftHandVisibility();
            SyncGearCamera();
        }
        void RefreshLeftHandVisibility()
        {
            if(Left==null||Motor==null)return;
            Left.gameObject.SetActive(!Motor.Camping&&(Weapons?.OwnsLeft==true||Archery?.OwnsHands==true||Torch?.OwnsLeft==true||Magic?.OwnsLeft==true&&(Magic.ShieldHeld||Magic.Combat.RecoilRemaining>0)));
        }
        public void RefreshTorchVisibility()
        {
            // A torch switch changes visibility without re-evaluating equipment
            // instances, combat poses or another action's presentation state.
            if(!Review&&!TreatmentActive&&!ChestStowed)RefreshLeftHandVisibility();
            if(Motor?.Eyes!=null)SyncGearCamera();
        }
        static Vector3 Elbow(Vector3 shoulder, Vector3 wrist, Vector3 pole)
        {
            var axis = wrist - shoulder; var direction = axis.sqrMagnitude > .000001f ? axis.normalized : Vector3.back;
            var perpendicular = pole - direction * Vector3.Dot(pole, direction); if (perpendicular.sqrMagnitude < .000001f) perpendicular = Vector3.down;
            float bend = Mathf.Clamp(.23f - (axis.magnitude - .4f) * .34f, .045f, .23f);
            return Vector3.Lerp(shoulder, wrist, .52f) + perpendicular.normalized * bend;
        }
        public void SetWorldContact(bool contact)
        {
            WorldContactEnabled=contact;
            if (contact) Motor.Eyes.cullingMask |= 1 << EquipmentLayer; else Motor.Eyes.cullingMask &= ~(1 << EquipmentLayer);
            SyncGearCamera();
        }
        static bool Visible(Component node)=>node!=null&&node.gameObject.activeInHierarchy;
        static bool Visible(GameObject node)=>node!=null&&node.activeInHierarchy;
        public bool HasVisibleEquipment=>TreatmentActive||Visible(Left)||Visible(Right)||Visible(Torch?.Model)
            ||Visible(Weapons?.SwordModel)||Visible(Weapons?.DaggerModel)||Visible(Weapons?.ShieldPivot)
            ||Visible(Archery?.Shape)||Visible(Flail?.Model)||Visible(Magic?.Model);
        public void SyncGearCamera()
        {
            if (GearCamera == null) return;
            var game = Motor?.FrameOwner ?? Motor?.GetComponent<MeleeCombat>()?.Game;
            if (game?.PettingInputActive == true) { GearCamera.enabled = false; return; }
            // The source stops the transparent pass when all carried roots are
            // stowed, when the player camera is hidden, or during world contact.
            GearCamera.enabled=ClothCamera==null&&Motor.Eyes.isActiveAndEnabled&&!WorldContactEnabled&&HasVisibleEquipment;
            var eyes = Motor.Eyes; GearCamera.transform.SetPositionAndRotation(eyes.transform.position, eyes.transform.rotation);
            GearCamera.fieldOfView = eyes.fieldOfView; GearCamera.nearClipPlane = Mathf.Min(eyes.nearClipPlane, .025f);
            GearCamera.farClipPlane = eyes.farClipPlane;
            GearCamera.orthographic=eyes.orthographic;GearCamera.orthographicSize=eyes.orthographicSize;
            var renderer=GetComponentInChildren<SourceSceneRenderer>(true);
            var separate=renderer!=null?renderer.EquipmentTarget:null;
            GearCamera.targetTexture = separate!=null?separate:eyes.targetTexture;
            GearCamera.cullingMask = Motor.Camping ? 0 : 1 << EquipmentLayer;
            GearCamera.clearFlags = separate!=null?CameraClearFlags.SolidColor:CameraClearFlags.Depth;
            GearCamera.backgroundColor=Color.clear;GearCamera.depth = eyes.depth + 1;
        }
        void LateUpdate()
        {
            // Re-applying the pose after world contacts could start a handoff twice
            // and render a different attack phase from the one used for the hit.
            if (!Motor.Paused && Motor.FrameOwner == null) UpdatePose();
            else SyncGearCamera();
        }
        public void Render(Camera camera, RenderTexture target)
        {
            var sceneRenderer = GetComponentInChildren<SourceSceneRenderer>(true);
            if (camera == Motor.Eyes && sceneRenderer != null && sceneRenderer.Ready)
            { sceneRenderer.RenderTo(target); GetComponent<WeaponHud>()?.Render(target); return; }
            var previous = camera.targetTexture; var previousGear = GearCamera == null ? null : GearCamera.targetTexture;
            camera.targetTexture = target; camera.Render();
            if (camera == Motor.Eyes && GearCamera != null && GearCamera.enabled) { SyncGearCamera(); GearCamera.Render(); }
            if(camera==Motor.Eyes)GetComponent<WeaponHud>()?.Render(target);
            camera.targetTexture = previous; if (GearCamera != null) GearCamera.targetTexture = previousGear;
        }
    }
}
