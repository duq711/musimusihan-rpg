using UnityEngine;

namespace MusimusihanRpg.Gameplay
{
    /// <summary>Logical intent shared by the live input adapter and quiet frame replays.</summary>
    public struct PlayerFrameInput
    {
        public bool Captured, Sprint, Jump, AttackPressed, AttackReleased;
        public bool BlockPressed, BlockReleased, BlockHeld, PrimaryPressed, InteractPressed;
        public Vector2 Look, Move;
        // One-based shortcut; zero means no key event.
        public int SpellShortcut;

        public static PlayerFrameInput Read(DungeonMotor motor, bool nativeShortcuts)
        {
            if (NativeLiveFrameBenchmark.Requested) return default;
            var frame = new PlayerFrameInput
            {
                Captured = motor.Captured,
                Look = new Vector2(Input.GetAxisRaw("Mouse X") * 10, -Input.GetAxisRaw("Mouse Y") * 10),
                Move = new Vector2(Input.GetAxisRaw("Horizontal"), -Input.GetAxisRaw("Vertical")),
                Sprint = Input.GetKey(KeyCode.LeftShift) || Input.GetKey(KeyCode.RightShift), Jump = Input.GetKeyDown(KeyCode.Space),
                AttackPressed = Input.GetMouseButtonDown(0), AttackReleased = Input.GetMouseButtonUp(0),
                BlockPressed = Input.GetMouseButtonDown(1), BlockReleased = Input.GetMouseButtonUp(1),
                BlockHeld = Input.GetMouseButton(1), InteractPressed = Input.GetKeyDown(KeyCode.E),
                PrimaryPressed = !motor.NativeHud && Input.GetKeyDown(KeyCode.Alpha1)
            };
            if (!nativeShortcuts || Input.GetKey(KeyCode.LeftAlt) || Input.GetKey(KeyCode.RightAlt))
                for (int i = 0; i < 6; i++) if (Input.GetKeyDown(KeyCode.Alpha1 + i)) frame.SpellShortcut = i + 1;
            return frame;
        }
    }

    public sealed partial class WorkshopController
    {
        void AdvanceLiveFrame(double seconds, bool nativeFlow = false)
        {
            using var timing=NativeFrameBenchmarkDiagnostics.Measure("Workshop.AdvanceLiveFrame");
            var frame = frameClock.Advance(seconds);
            if(nativeFlow)NativeGame.Tick((float)frame.ProcessDelta);
            if (DungeonPlayer == null || DungeonPlayer.ManualClock) { Advance(frame.ProcessDelta); return; }
            bool native = NativeGame != null && (!Trials.Active || NativeGame.NativeTrial);
            var input=PlayerFrameInput.Read(DungeonPlayer,native);if(native)input=NativeGame.FilterResumeInput(input);
            input=FilterPettingFrameInput(input);
            AdvanceScheduledFrame(frame,input,physicsLease != null);
        }

        /// <summary>One explicit player tick for source replays, without OS input or cursor capture.</summary>
        public void AdvancePlayerFrame(double seconds, PlayerFrameInput input)
        {
            if (!double.IsFinite(seconds) || seconds <= 0) return;
            ApplyPlayerInput(input);
            NativeGame?.TickCaveWater(seconds);
            AdvanceWorld(seconds, input);
            AdvanceStress(seconds);
        }

        void ApplyPlayerInput(PlayerFrameInput input)
        {
            var motor = DungeonPlayer; var combat = Combat;
            if (motor == null || combat == null || Page != "dungeon" || SimulationPaused || motor.Paused
                || Session.Body.IsDead || motor.Camping || Session.HasCondition("paralysis") || combat.ExecutionActive) return;
            var bow = motor.GetComponent<BowCombat>(); var flail = motor.GetComponent<FlailCombat>();
            if (!input.Captured)
            {
                bow?.Cancel(); flail?.Cancel();
                if (combat.State == "windup" || combat.State == "active" || combat.State == "recovery") combat.Cancel();
                return;
            }
            // Inspection remains a timed interaction that can be cancelled by looking away.
            // Source current_trap captures the view only after disarming begins.
            if (!(Interaction?.Active is DungeonTrap trap && trap.Model.State == RuneTrapState.Phase.Disarming)) motor.Look(input.Look);
            if (NativeGame?.CampInputBlocked == true || Items.IsActive || combat.SafeZone || motor.TimedInteraction) return;
            if (input.PrimaryPressed && (bool)combat.RequestPrimaryWeapon()["accepted"]) input.SpellShortcut = 0;
            if (flail?.Equipped == true)
            {
                if (input.AttackPressed) flail.BeginMelee();
                if (input.BlockPressed) flail.BeginSpin();
                if (input.BlockReleased) flail.Release();
                return;
            }
            if (input.SpellShortcut > 0) Magic?.SelectSlot(input.SpellShortcut - 1);
            if (input.AttackPressed)
            {
                if (bow?.Equipped == true) bow.Begin();
                else if (Magic?.Equipped == true) Magic.CastSelected();
                else combat.Begin();
            }
            if (input.AttackReleased) { if (bow?.Drawing == true) bow.Release(); else combat.Release(); }
            if (input.BlockPressed && bow?.Equipped == true) bow.Cancel();
        }
    }
}
