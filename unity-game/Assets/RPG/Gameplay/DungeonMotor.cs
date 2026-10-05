using System;
using Newtonsoft.Json.Linq;
using UnityEngine;

namespace MusimusihanRpg.Gameplay
{
    /// <summary>Native collision-based movement, using the source player.gd movement rules.</summary>
    [RequireComponent(typeof(CharacterController))]
    public sealed partial class DungeonMotor : MonoBehaviour
    {
        public Camera Eyes;
        public Font KoreanFont;
        public bool ManualClock;
        public WorkshopController FrameOwner { get; internal set; }
        public bool NativeHud;
        public bool Blocking, BowDrawing, FlailBusy, ActionBusy, TimedInteraction, Camping, Paused;
        public double InteractionDurationScale = 1;
        public HideoutInteraction ActiveHideoutInteraction {get;internal set;}
        public ExpeditionSession Session { get; private set; }
        double stamina=100;
        public float Stamina { get=>(float)stamina; private set=>stamina=value; }
        public Vector3 Velocity { get; private set; }
        public bool Grounded => controller != null && (controller.isGrounded || Camping && campGrounded);
        public int LandingCount { get; private set; }
        public string MovementPhase { get; private set; } = "grounded";
        public double MovementTime { get; private set; }
        public double MovementRunTime { get; private set; }
        public float LandingStrength { get; private set; }
        public bool Captured { get; private set; }
        public float ViewPitch=>pitch;
        public Vector3 AimDirection=>transform.rotation*Quaternion.AngleAxis(pitch,Vector3.right)*Vector3.back;
        public Action ReturnToMenu;
        CharacterController controller;
        float staminaDelay, pitch, preCampPitch, preCampHeadY;
        double bob;
        public bool MovementAirborne=>knownFloor&&!lastGrounded;
        bool jumpPending, knownFloor, lastGrounded, campGrounded;
        GUIStyle label;
        public float MovementMultiplier => Session == null ? 1 : Session.HasCondition("paralysis") ? 0
            : Mathf.Pow(.65f, Session.Body.ImpairmentCount(new[] { "left_leg", "right_leg" }, Session.HasCondition("fracture")));
        public void Bind(ExpeditionSession session)
        {
            Session = session; session.EnsureJourney(); BindFeedback(); controller = GetComponent<CharacterController>();
            gameObject.layer = DungeonCombatWorld.PlayerLayer;
            controller.height = 1.78f; controller.radius = .36f; controller.center = Vector3.zero;
            controller.skinWidth = .001f; controller.stepOffset = .3f; controller.slopeLimit = 45;
        }
        public void ResetTrial(Vector3 sourcePosition,bool recoverStamina=true)
        {
            GetComponent<PlayerPresentation>()?.Torch?.CancelIgnition();
            GetComponent<PlayerPresentation>()?.CancelTreatment();
            GetComponent<PlayerPresentation>()?.EndChest();
            if (controller == null) controller = GetComponent<CharacterController>();
            controller.enabled = false; transform.position = new Vector3(-sourcePosition.x, sourcePosition.y, sourcePosition.z);
            transform.rotation = Quaternion.identity; controller.enabled = true;
            Velocity = Vector3.zero; if(recoverStamina){Stamina = 100; staminaDelay = 0;} jumpPending = false; knownFloor = false; LandingCount = 0;
            MovementPhase="grounded"; MovementTime=MovementRunTime=LandingStrength=0;
            pitch = 0; bob=0; headHeight=.67f; ResetFeedback(); SetEyePose(); ReleasePointer();
            Blocking = BowDrawing = FlailBusy = ActionBusy = TimedInteraction = Camping = false;
            GetComponent<MeleeCombat>()?.ResetTrial(); GetComponent<SwordPresentation>()?.ResetTrial();
            GetComponent<BowCombat>()?.ResetTrial();GetComponent<FlailCombat>()?.ResetTrial();GetComponent<MagicCombat>()?.ResetTrial();
        }
        public void TeleportForTrial(Vector3 sourcePosition)
        {
            PrepareForInventory();if(controller==null)controller=GetComponent<CharacterController>();
            controller.enabled=false;transform.SetPositionAndRotation(new Vector3(-sourcePosition.x,sourcePosition.y,sourcePosition.z),Quaternion.identity);controller.enabled=true;
            Velocity=Vector3.zero;pitch=0;SetEyePose();
        }
        public void Relocate(Vector3 position,Quaternion rotation)
        {if(controller==null)controller=GetComponent<CharacterController>();controller.enabled=false;transform.SetPositionAndRotation(position,rotation);controller.enabled=true;Velocity=Vector3.zero;controller.Move(Vector3.down*.001f);}
        internal void RecoverPosition(Vector3 position)
        {
            // hideout.gd's fall guard changes only position and velocity. Keep
            // aim, stamina, pending actions and movement presentation intact.
            if(controller==null)controller=GetComponent<CharacterController>();
            bool wasEnabled=controller.enabled;controller.enabled=false;
            transform.position=position;Velocity=Vector3.zero;controller.enabled=wasEnabled;
        }
        public void RecoverForTrial(){Stamina=100;staminaDelay=0;Velocity=Vector3.zero;Blocking=false;ResetFeedback();}
        public void StopPlanarMovement(){Velocity=new Vector3(0,Velocity.y,0);}
        public void PrepareForInventory()
        {
            // player.gd::prepare_for_inventory: opening the bag interrupts actions,
            // while preserving vertical motion, aim, resources and landing history.
            var combat=GetComponent<MeleeCombat>();var game=combat?.Game;var presentation=GetComponent<PlayerPresentation>();
            game?.Items.Cancel();presentation?.CancelTreatment();
            ResetReferenceMovementMotion();
            if(Camping||game?.Camp?.Activity.State=="placing")game?.Camp?.Cancel("가방을 열어 야영을 중단했습니다");
            GetComponent<BowCombat>()?.Cancel();GetComponent<FlailCombat>()?.Cancel();game?.Interaction?.Cancel();presentation?.EndChest();combat?.Cancel();
            Velocity=new Vector3(0,Velocity.y,0);
        }
        public void ResetReferenceMovementMotion()
        {
            jumpPending=knownFloor=lastGrounded=false;MovementPhase="grounded";MovementTime=MovementRunTime=LandingStrength=0;
            GetComponent<SwordPresentation>()?.ResetReferenceMovement();
        }
        public void SetCamping(bool enabled)
        {
            if(enabled==Camping)return;if(enabled){campGrounded=Grounded;preCampPitch=pitch;preCampHeadY=headHeight;}
            Camping=enabled;Velocity=Vector3.zero;pitch=enabled?-26:preCampPitch;headHeight=enabled?.12f:preCampHeadY;
            // Relocation resets Unity contact flags. Re-probe the real floor on
            // standing so immediate tent re-entry/jump retains Godot's grounded state.
            if(!enabled&&campGrounded&&controller!=null&&controller.enabled)controller.Move(Vector3.down*.02f);
            SetEyePose();ApplyFeedbackPosition();GetComponent<PlayerPresentation>()?.UpdatePose();
        }
        public JObject RequestJump()
        {
            string reason = MovementMultiplier < 1 ? "injured" : Camping || Session?.Body.IsDead == true ? "unavailable"
                : Paused ? "paused" : !Grounded || jumpPending ? "not_grounded" : TimedInteraction || BowDrawing || FlailBusy || ActionBusy ? "busy"
                : Stamina < 12 ? "not_enough_stamina" : "";
            if (reason.Length > 0) return new JObject { ["accepted"] = false, ["reason"] = reason, ["stamina_spent"] = 0 };
            Velocity = new Vector3(Velocity.x, 5.2f, Velocity.z); Spend(12); jumpPending = true;SetMovementPhase("takeoff");
            return new JObject { ["accepted"] = true, ["stamina_spent"] = 12 };
        }
        internal void AdvanceSafeZoneRecovery(double seconds)
        {
            if(Session==null||Paused||Camping||Session.Body.IsDead||!double.IsFinite(seconds)||seconds<=0||GetComponent<MeleeCombat>()?.SafeZone!=true)return;
            Session.RelieveStress(Session.StressRules["SAFE_RECOVERY_RATE"]*seconds);
        }
        public void Simulate(double seconds, Vector2 sourceInput, bool sprint = false, bool recoverStamina = true)
        {
            if (Session == null || Paused || Camping || Session.Body.IsDead || seconds <= 0 || !double.IsFinite(seconds)) return;
            float delta=(float)seconds;
            // The complete game advances recovery before combat can spend this frame.
            // A standalone movement actor owns its own recovery clock.
            if(GetComponent<MeleeCombat>()?.Game==null){AdvanceSafeZoneRecovery(seconds);AdvanceRecoveryDelay(delta);}
            if(GetComponent<MeleeCombat>()?.ExecutionActive==true)return;
            MovementTime += seconds;
            var velocity = Velocity;
            if (!Grounded && !jumpPending) velocity.y -= 18 * delta;
            else if (Grounded && !jumpPending) velocity.y = -1;
            var movement = Vector2.ClampMagnitude(sourceInput, 1);
            if (TimedInteraction || MovementMultiplier == 0) movement = Vector2.zero;
            if (MovementMultiplier == 0) { velocity.x = 0; velocity.z = 0; }
            // glTFast reflects X; Godot forward is -Z, and the camera faces -Z.
            var direction = transform.TransformDirection(new Vector3(-movement.x, 0, movement.y)).normalized;
            float speed = 4.2f;
            bool sprinting = MovementMultiplier >= 1 && !TimedInteraction && !BowDrawing && !FlailBusy && sprint && movement.y < -.15f && Stamina > 0;
            if (sprinting && !ActionBusy && !Blocking) { speed = 6.2f; Spend(17 * delta); }
            if (movement.y > .1f) speed *= .72f; else if (Mathf.Abs(movement.x) > .1f) speed *= .86f;
            if (ActionBusy) speed *= .56f; if (Blocking) speed *= .48f; if (BowDrawing) speed *= .55f; if (FlailBusy) speed *= .65f;
            speed *= MovementMultiplier;
            float acceleration = direction == Vector3.zero ? 24 : 18;
            velocity.x = Mathf.MoveTowards(velocity.x, direction.x * speed, acceleration * delta);
            velocity.z = Mathf.MoveTowards(velocity.z, direction.z * speed, acceleration * delta);
            var flags = controller.Move(velocity * delta);
            if ((flags & CollisionFlags.Above) != 0 && velocity.y > 0) velocity.y = 0;
            ObserveFloor(velocity.y);
            // The downward contact probe keeps Unity grounded; it is not the
            // player's resulting velocity after the floor has stopped the fall.
            if(Grounded&&velocity.y<0)velocity.y=0;
            Velocity = velocity;
            if (recoverStamina) AdvanceStamina(seconds);
            float planar = new Vector2(velocity.x, velocity.z).magnitude;
            if (Grounded && planar > .01) MovementRunTime += seconds * Math.Clamp(planar / 4.2,0,1);
            if (Grounded && planar > .3) bob += seconds * (sprinting ? 10.5 : 7.3);
            if (Eyes != null)
            {
                headHeight = Grounded && planar > .3
                    ? (float)(.67 + Math.Sin(bob) * Math.Min(planar / 4.2, 1) * .025)
                    : Mathf.Lerp(headHeight, .67f, Mathf.Min(delta * 8, 1));
                ApplyFeedbackPosition();
            }
        }
        public void AdvanceStamina(double seconds)
        {
            if (Session == null || Paused || Camping || Session.Body.IsDead || !double.IsFinite(seconds) || seconds <= 0) return;
            bool regenBlocked=GetComponent<MeleeCombat>() is MeleeCombat combat?combat.State=="windup":ActionBusy;
            if (staminaDelay <= 0 && !regenBlocked && !BowDrawing && !FlailBusy && !Blocking) stamina = Math.Min(100, stamina + 25.0 * (float)seconds);
        }
        void Spend(float amount) => ConsumeStamina(amount);
        void ObserveFloor(float verticalSpeed)
        {
            var motion=GetComponent<SwordPresentation>()?.Motion;
            if(Grounded)
            {
                if(knownFloor&&!lastGrounded){LandingCount++;LandingStrength=Mathf.Clamp(-verticalSpeed/5.2f,.15f,1);SetMovementPhase("land");}
                else if(MovementPhase!="land"||MovementTime>=(motion?.Duration("land")??.24))SetMovementPhase("grounded");
            }
            else if(jumpPending)SetMovementPhase("takeoff");
            else if(MovementPhase!="takeoff"||MovementTime>=(motion?.Duration("takeoff")??.16)||verticalSpeed<=0)SetMovementPhase("air");
            lastGrounded=Grounded;knownFloor=true;jumpPending=false;
        }
        void SetMovementPhase(string phase){if(MovementPhase!=phase){MovementPhase=phase;MovementTime=0;}}
        public void AdvanceRecoveryDelay(double delta)
        {if(Session!=null&&!Paused&&!Camping&&!Session.Body.IsDead&&GetComponent<MeleeCombat>()?.State!="dead"&&double.IsFinite(delta)&&delta>0)staminaDelay=Mathf.Max(0,staminaDelay-(float)delta);}
        public double ConsumeStamina(double amount, float delay = .72f)
        {
            if(!double.IsFinite(amount)||amount<0)return 0;
            // Preserve the paid amount before subtraction, as the source does.
            // Reconstructing it from two large balances shifts the exact 10% slack boundary.
            double spent=Math.Min(Math.Max(0,stamina),amount);stamina=Math.Max(0,stamina-spent);staminaDelay=delay;return spent;
        }
        internal void ClampExhaustedStamina(){if(stamina<=.000001)stamina=0;}
        internal void SetTrialStamina(float value){if(float.IsFinite(value))Stamina=Mathf.Clamp(value,0,100);}
        public void RestoreStamina(float amount)
        { if (float.IsFinite(amount) && amount > 0) stamina = Math.Min(100, stamina + amount); }
        public void Look(Vector2 sourcePixelDelta)
        {
            if (Paused||Camping||GetComponent<MeleeCombat>()?.ExecutionActive==true) return;
            transform.Rotate(0, sourcePixelDelta.x * .00215f * Mathf.Rad2Deg, 0, Space.Self);
            pitch = Mathf.Clamp(pitch - sourcePixelDelta.y * .00215f * Mathf.Rad2Deg, -82, 78); SetEyePose();
        }
        void SetEyePose()
        { if (Eyes != null) { Eyes.transform.localRotation = Quaternion.AngleAxis(pitch, Vector3.right) * Quaternion.Euler(0, 180, 0); ApplyFeedbackPosition(); } }
        public void ViewRecoil(Vector3 sourceRadians)
        {if(Eyes!=null)Eyes.transform.localRotation=Quaternion.AngleAxis(pitch,Vector3.right)*SourcePose.Euler(sourceRadians)*Quaternion.Euler(0,180,0);}
        public void ExecutionCamera(Vector3 offset,Vector3 sourceRadians)
        {
            var head=Quaternion.AngleAxis(pitch,Vector3.right);
            Eyes.transform.localPosition=Vector3.up*.67f+head*offset;
            Eyes.transform.localRotation=head*SourcePose.Euler(sourceRadians)*Quaternion.Euler(0,180,0);
        }
        public void MoveExecution(float delta,float elapsed,Vector3 contact,float distance,bool approach)
        {
            var velocity=new Vector3(0,Grounded?-1:Velocity.y-18*delta,0);var toward=contact-transform.position;toward.y=0;
            if(approach&&toward.sqrMagnitude>.000001f)
            {
                transform.rotation=Quaternion.Slerp(transform.rotation,Quaternion.LookRotation(-toward),Mathf.Min(1,delta*12));
                if(elapsed<.30f&&toward.magnitude>distance)
                {float speed=Mathf.Min(2.8f,(toward.magnitude-distance)/Mathf.Max(delta,.30f-elapsed));velocity+=toward.normalized*speed;}
            }
            MovementTime+=delta;controller.Move(velocity*delta);ObserveFloor(velocity.y);Velocity=velocity;
        }
        public void StopExecutionMovement(){Velocity=new Vector3(0,Velocity.y,0);ExecutionCamera(Vector3.zero,Vector3.zero);}
        public float MoveExecutionStep(Vector3 step)
        {
            var before=transform.position;controller.Move(step);return Mathf.Max(0,step.magnitude-Vector3.Dot(transform.position-before,step.normalized));
        }
        public void RearExecutionCamera(Vector3 focus,float entryYaw,float entryPitch,float blend,Vector3 offset)
        {
            var toward=focus-(transform.position+Vector3.up*.67f);float yaw=Mathf.Atan2(-toward.x,-toward.z)*Mathf.Rad2Deg;
            transform.rotation=Quaternion.Euler(0,Mathf.LerpAngle(entryYaw,yaw,blend),0);pitch=Mathf.Lerp(entryPitch,Mathf.Atan2(toward.y,new Vector2(toward.x,toward.z).magnitude)*Mathf.Rad2Deg,blend);
            ExecutionCamera(offset,Vector3.zero);
        }
        public void AimAt(Vector3 target)
        {
            if (Eyes == null) return;
            var delta = target - Eyes.transform.position;
            transform.rotation = Quaternion.Euler(0, Mathf.Atan2(-delta.x, -delta.z) * Mathf.Rad2Deg, 0);
            pitch = Mathf.Clamp(Mathf.Atan2(delta.y, new Vector2(delta.x, delta.z).magnitude) * Mathf.Rad2Deg, -82, 78);
            SetEyePose();
        }
        void Update()
        {
            if (ManualClock || Session == null || FrameOwner != null) return;
            if (Input.GetKeyDown(KeyCode.Escape)) ReleasePointer();
            if(!Captured&&!Paused)
            {
                // Match the source's unlocked-input cancellation. A paused F2
                // actor keeps its separate frozen state until the trial resumes.
                GetComponent<BowCombat>()?.Cancel();GetComponent<FlailCombat>()?.Cancel();
                var combat=GetComponent<MeleeCombat>();
                if(combat!=null&&(combat.State=="windup"||combat.State=="active"||combat.State=="recovery"))combat.Cancel();
            }
            if (Captured && !Paused)
            {
                Look(new Vector2(Input.GetAxisRaw("Mouse X") * 10, -Input.GetAxisRaw("Mouse Y") * 10));
                if (Input.GetKeyDown(KeyCode.Space)) RequestJump();
            }
            var movement = Captured ? new Vector2(Input.GetAxisRaw("Horizontal"), -Input.GetAxisRaw("Vertical")) : Vector2.zero;
            Simulate(Time.deltaTime, movement, Captured && (Input.GetKey(KeyCode.LeftShift) || Input.GetKey(KeyCode.RightShift)));
        }
        public void ReleasePointer()
        {
            FrameOwner?.ClearPendingFrameInput();
            if (!Captured) return;
            Captured = false; Cursor.lockState = CursorLockMode.None; Cursor.visible = true;
        }
        public void CapturePointer()
        { if(NativeLiveFrameBenchmark.Requested||ManualClock||GetComponent<MeleeCombat>()?.Game?.ManualClock==true||GetComponent<MeleeCombat>()?.Game?.PettingInputActive==true)return;Captured=true;Cursor.lockState=CursorLockMode.Locked;Cursor.visible=false; }
        void OnDisable() => ReleasePointer();
        void OnApplicationFocus(bool focus)
        {
            if(NativeLiveFrameBenchmark.Requested)return;
            if(!focus){ReleasePointer();GetComponent<BowCombat>()?.Cancel();GetComponent<FlailCombat>()?.Cancel();GetComponent<DungeonInteractionController>()?.Cancel();}
            var game=GetComponent<MeleeCombat>()?.Game;
            if(!ManualClock&&game!=null&&!game.ManualClock&&game.DungeonPlayer==this)game.NativeGame?.HandleWindowFocus(focus);
        }
        void OnGUI()
        {
            if (NativeLiveFrameBenchmark.Requested || ManualClock || Session == null || Paused || NativeHud) return;
            if (label == null) label = new GUIStyle(GUI.skin.label) { font = KoreanFont, fontSize = 20, normal = { textColor = Color.white } };
            GUI.Label(new Rect(24, 16, Screen.width - 48, 60), $"기력 {Stamina:0}   ·   WASD 이동 / Shift 달리기 / Space 점프 / F2 시험실 / Esc 커서 해제", label);
            if (!Captured)
            {
                if (GUI.Button(new Rect(Screen.width / 2f - 150, Screen.height / 2f - 28, 300, 56), "둘러보기 · 마우스 조작 시작", label))
                { Captured = true; Cursor.lockState = CursorLockMode.Locked; Cursor.visible = false; }
                if (GUI.Button(new Rect(24, 82, 220, 44), "시험실로 돌아가기", label)) ReturnToMenu?.Invoke();
            }
        }
    }
}
