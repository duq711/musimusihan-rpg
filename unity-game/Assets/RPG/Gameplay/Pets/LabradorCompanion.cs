using System;
using System.Collections.Generic;
using System.Linq;
using Newtonsoft.Json.Linq;
using UnityEngine;

namespace MusimusihanRpg.Gameplay
{
    /// <summary>Real companion actions run once on the game's existing interaction clock.</summary>
    [RequireComponent(typeof(CharacterController))]
    public sealed class LabradorCompanion : DungeonInteractable
    {
        public enum ActionPhase { Follow, ChaseEnemy, Bite, Sniff, SeekItem, Found, Pickup, Returning, Drop, PetSit, PetEnjoy, PetRise, EatStart, EatLoop, EatEnd }
        public static readonly string[] RequiredClips = { "IdleFriendly", "Walk", "Run", "CombatBite", "SearchSniff", "SearchWalk", "SearchFound", "RetrievePickup", "RetrieveCarryWalk", "RetrieveDrop", "EatStart", "EatLoop", "EatEnd", "PetSit", "PetEnjoy", "PetRise" };
        public ActionPhase Phase { get; private set; }
        public double Elapsed { get; private set; }
        public int LandedBites { get; private set; }
        public int DeliveredUnits { get; private set; }
        public int MealsEaten { get; private set; }
        public int CompletedPets { get; private set; }
        public float Affection { get; private set; }
        public string AnimationName => motion?.Current ?? "";
        public Transform Mouth { get; private set; }
        public PetFindableItem CarriedItem => item != null && item.Carried ? item : null;
        public CreepCombatant CombatTarget => enemy;
        public bool ManualInput;
        public float WalkSpeed = 1.7f, RunSpeed = 3.7f, SearchRadius = 12;
        public double BiteDamage = 9, BiteContactTime = .58;
        public event Action<string, DungeonMotor, LabradorCompanion> CareStarted;
        public event Action<string, DungeonMotor, LabradorCompanion> CareEnded;
        public override bool Busy => careOwner != null;
        public override string Prompt => Busy ? (IsFeeding ? "밥 먹는 중…" : "쓰담쓰담 중…") : "[E] 쓰담쓰담  ·  [G] 밥 주기  ·  [R] 숨겨진 물건 찾기";
        public bool IsFeeding => Phase == ActionPhase.EatStart || Phase == ActionPhase.EatLoop || Phase == ActionPhase.EatEnd;
        CharacterController motor;
        PetAnimationPlayer motion;
        readonly PetWalkRoute route = new PetWalkRoute();
        readonly PetContactLatch contact = new PetContactLatch();
        readonly List<CreepCombatant> enemies = new List<CreepCombatant>();
        readonly List<PetFindableItem> finds = new List<PetFindableItem>();
        CreepCombatant enemy;
        PetFindableItem item;
        DungeonMotor careOwner;
        ExpeditionInventory careBag;
        PetFoodReservation food;
        double threatScan, attackCooldown, routeStuck;
        float gravity, speed;
        bool initialized;
        DungeonMotor Player => Game?.DungeonPlayer;
        bool Live => initialized && Game != null && Game.Session != null && !Game.WorldPaused && Game.Page == "dungeon" && !Game.Session.Body.IsDead && (Game.NativeGame == null || Game.NativeGame.State == "playing");

        public static LabradorCompanion Spawn(WorkshopController game, GameObject prefab, AnimationClip[] clips, Vector3 at, string mouthName = "MouthSocket")
        {
            if (game == null || game.DungeonRoot == null || prefab == null || clips == null || RequiredClips.Any(n => !clips.Any(c => c != null && c.name == n)))
            { Debug.LogError("Labrador companion requires the actual Labrador prefab and all sixteen pet clips."); return null; }
            var node = new GameObject("LabradorCompanion", typeof(CharacterController));
            node.transform.SetParent(game.DungeonRoot.transform, false); node.transform.position = at;
            var visual = Instantiate(prefab, node.transform); visual.name = "LabradorModel"; visual.SetActive(true);
            var mouth = visual.GetComponentsInChildren<Transform>(true).FirstOrDefault(t => t.name == mouthName);
            if (mouth == null) { Debug.LogError("Labrador prefab has no authored mouth socket: " + mouthName); Destroy(node); return null; }
            var pet = node.AddComponent<LabradorCompanion>(); pet.Configure(game, visual, clips, mouth);
            return pet;
        }

        public void Configure(WorkshopController game, GameObject visual, AnimationClip[] clips, Transform mouth)
        {
            if (game == null || visual == null || mouth == null || clips == null || RequiredClips.Any(n => !clips.Any(c => c != null && c.name == n))) throw new ArgumentException("Actual model, mouth socket and complete named clips required");
            Game = game; Mouth = mouth; motion = new PetAnimationPlayer(visual, clips);
            foreach (var collider in visual.GetComponentsInChildren<Collider>(true)) collider.enabled = false;
            motor = GetComponent<CharacterController>(); motor.height = .65f; motor.radius = .20f; motor.center = Vector3.up * .34f;
            motor.skinWidth = .008f; motor.stepOffset = .20f; motor.slopeLimit = 45;
            // Existing world layer owns only walls and floors, never the dog itself.
            gameObject.layer = 2;
            foreach (var renderer in visual.GetComponentsInChildren<Renderer>(true)) renderer.gameObject.layer = 2;
            CreateFocus(new Bounds(Vector3.up * .38f, new Vector3(.65f, .65f, .95f)));
            initialized = true; Change(ActionPhase.Follow);
        }

        void Update()
        {
            if (ManualInput || Game == null || Game.ManualClock || !Live || Game.Interaction?.RefreshFocus() != this) return;
            if (Input.GetKeyDown(KeyCode.G)) HandleCommand(KeyCode.G);
            if (Input.GetKeyDown(KeyCode.R)) HandleCommand(KeyCode.R);
        }
        public bool HandleCommand(KeyCode key)
        {
            if (!Live || Player == null || Player.Eyes == null || Game.Interaction?.RefreshFocus() != this) return false;
            if (key == KeyCode.G) { if (Busy) { Cancel(careOwner); return true; } return TryFeed(Player); }
            if (key == KeyCode.R) return TrySearch(Player);
            return false;
        }
        bool CanCare(DungeonMotor player)
        {
            if (!Live || !Available(player) || player != Player || player.TimedInteraction || player.Blocking || player.ActionBusy || Game.Items?.IsActive == true || Game.Combat?.State != null && Game.Combat.State != "ready" || Busy || item != null) return false;
            if (Phase != ActionPhase.Follow || Vector3.Distance(player.transform.position, transform.position + Vector3.up * .75f) > 2.8f) return false;
            return !Physics.Linecast(player.transform.position, transform.position + Vector3.up * .4f, 1 << DungeonCombatWorld.WorldLayer, QueryTriggerInteraction.Ignore);
        }
        public override bool Interact(DungeonMotor player)
        {
            if (!CanCare(player)) return false;
            BeginCare(player, "petting"); Change(ActionPhase.PetSit); return true;
        }
        public bool TryFeed(DungeonMotor player)
        {
            if (!CanCare(player)) return false;
            // Reuse actual carried game supplies; no food is created by the pet.
            var bag = player.Session.Inventory;
            var stack = bag.Slots.FirstOrDefault(s => (string)s["id"] == "raw_meat" && (int)s["quantity"] > 0)
                ?? bag.Slots.FirstOrDefault(s => (string)s["id"] == "beef_jerky" && (int)s["quantity"] > 0);
            if (stack == null) { Notice("밥으로 줄 생고기나 소고기 육포가 가방에 없습니다."); return false; }
            food = new PetFoodReservation(bag, stack); BeginCare(player, "feeding"); Change(ActionPhase.EatStart); return true;
        }
        public bool TrySearch(DungeonMotor player)
        {
            if (!CanCare(player)) return false;
            enemy = null; Change(ActionPhase.Sniff); Notice("킁킁! 주변에서 숨겨진 물건을 찾고 있습니다."); return true;
        }
        void BeginCare(DungeonMotor player, string kind)
        {
            careOwner = player; careBag = player.Session.Inventory; player.TimedInteraction = true; player.Blocking = false; player.StopPlanarMovement();
            Face(player.transform.position - transform.position, 1);
            CareStarted?.Invoke(kind, player, this);
        }
        void EndCare(bool completed)
        {
            if (careOwner == null) return;
            bool feeding = IsFeeding; var actor = careOwner; careOwner = null; careBag = null;
            actor.TimedInteraction = false;
            if (completed && !feeding) { CompletedPets++; Affection = Mathf.Min(100, Affection + 3); }
            CareEnded?.Invoke(feeding ? "feeding" : "petting", actor, this);
            food = null;
        }
        public override void Cancel(DungeonMotor player)
        {
            if (Busy && player != careOwner) return;
            EndCare(false); ReleaseItem(true); enemy = null; Change(ActionPhase.Follow);
        }
        // F2 preserves the inactive original world. A search or carried package
        // stays in that world with the same pose, claim, clock and affection.
        void OnDisable()
        { if (initialized && Busy) { EndCare(false); Change(ActionPhase.Follow); } }
        void OnDestroy() { if (!initialized) return; EndCare(false); ReleaseItem(true); }
        void Notice(string text) { Game.NativeGame?.Notice(text, 2.7f); Game.Reply(new JObject { ["accepted"] = true, ["message"] = text }); }
        void Change(ActionPhase next)
        { Phase = next; Elapsed = 0; contact.Reset(); route.Reset(); routeStuck = 0; speed = 0; }
        public override void Advance(double delta)
        {
            if (!initialized || !double.IsFinite(delta) || delta <= 0 || Game == null || Game.Session == null) return;
            if (Game.Session.Body.IsDead) { Cancel(careOwner); return; }
            if (!Live) return;
            if (Busy && (careOwner != Player || !ReferenceEquals(careBag, Player.Session.Inventory) || Player.Session.HasCondition("paralysis") || Vector3.Distance(Player.transform.position, transform.position + Vector3.up * .75f) > 3)) { Cancel(careOwner); return; }
            double remaining = delta;
            while (remaining > .0000001 && Live)
            {
                double step = Math.Min(1.0 / 30, remaining); remaining -= step; Step(step);
            }
        }
        void Step(double delta)
        {
            Elapsed += delta; attackCooldown = Math.Max(0, attackCooldown - delta); threatScan -= delta; speed = 0;
            switch (Phase)
            {
                case ActionPhase.Follow:
                    if (threatScan <= 0) { threatScan = .35; enemy = NearestThreat(); if (enemy != null) { Change(ActionPhase.ChaseEnemy); break; } }
                    var forward = Vector3.ProjectOnPlane(Player.AimDirection, Vector3.up).normalized;
                    Vector3 follow = Ground(Player.transform.position - forward * 1.35f + Player.transform.right * .85f);
                    float distance = Planar(follow - transform.position);
                    if (distance > .65f) Move(follow, distance > 3 ? RunSpeed : WalkSpeed, delta);
                    break;
                case ActionPhase.ChaseEnemy:
                    if (!ValidEnemy(enemy)) { enemy = null; Change(ActionPhase.Follow); break; }
                    var enemyFloor = Ground(enemy.transform.position);
                    if (Planar(enemyFloor - transform.position) <= .92f && ClearSight(enemy.transform.position))
                    { Face(enemy.transform.position - transform.position, (float)delta * 9); if (attackCooldown <= 0) Change(ActionPhase.Bite); }
                    else Move(enemyFloor, RunSpeed, delta);
                    break;
                case ActionPhase.Bite:
                    if (ValidEnemy(enemy)) Face(enemy.transform.position - transform.position, (float)delta * 5);
                    if (contact.Crossed(Elapsed, BiteContactTime)) Bite();
                    if (Elapsed >= Duration("CombatBite", 1.2f)) { attackCooldown = .65; Change(ValidEnemy(enemy) ? ActionPhase.ChaseEnemy : ActionPhase.Follow); }
                    break;
                case ActionPhase.Sniff:
                    if (Elapsed >= Duration("SearchSniff", 2))
                    {
                        Game.DungeonRoot.GetComponentsInChildren(false, finds);
                        item = finds.Where(i => i.Payload != null && i.Payload.Owner == null && i.Payload.Remaining > 0 && Planar(i.transform.position - transform.position) <= SearchRadius)
                            .OrderBy(i => (i.transform.position - transform.position).sqrMagnitude).FirstOrDefault(i => i.Reserve(this));
                        if (item == null) { Notice("근처에서는 물어올 물건을 찾지 못했습니다."); Change(ActionPhase.Follow); }
                        else Change(ActionPhase.SeekItem);
                    }
                    break;
                case ActionPhase.SeekItem:
                    if (item == null || !ReferenceEquals(item.Payload.Owner, this)) { item = null; Change(ActionPhase.Follow); break; }
                    if (Planar(item.transform.position - transform.position) < .68f && ClearSight(item.transform.position + Vector3.up * .2f)) { item.Reveal(); Change(ActionPhase.Found); }
                    else { Move(item.transform.position, WalkSpeed, delta); if (Elapsed > 18 || routeStuck > 3) { ReleaseItem(false); Notice("가는 길이 막혀 있습니다. 다른 위치에서 다시 찾아보세요."); Change(ActionPhase.Follow); } }
                    break;
                case ActionPhase.Found:
                    if (Elapsed >= Duration("SearchFound", 1.1f)) Change(ActionPhase.Pickup);
                    break;
                case ActionPhase.Pickup:
                    if (contact.Crossed(Elapsed, .75) && (item == null || !item.Attach(this, Mouth))) { ReleaseItem(false); Change(ActionPhase.Follow); break; }
                    if (Elapsed >= Duration("RetrievePickup", 1.5f)) Change(ActionPhase.Returning);
                    break;
                case ActionPhase.Returning:
                    if (item == null) { Change(ActionPhase.Follow); break; }
                    var home = Ground(Player.transform.position);
                    if (Planar(home - transform.position) < 1.4f && ClearSight(Player.transform.position)) Change(ActionPhase.Drop);
                    else { Move(home, WalkSpeed, delta); if (Elapsed > 25 || routeStuck > 3) { ReleaseItem(false); Notice("물어온 물건을 안전하게 내려놓았습니다."); Change(ActionPhase.Follow); } }
                    break;
                case ActionPhase.Drop:
                    if (contact.Crossed(Elapsed, .8) && item != null)
                    {
                        int moved = item.Deliver(this, Player.Session.Inventory); DeliveredUnits += moved;
                        if (item.Payload.Remaining > 0) { item.PutDown(this, DropPoint()); Notice(moved > 0 ? "물어온 일부를 가방에 넣었습니다. 나머지는 옆에 내려놓았습니다." : "가방이 가득 차 물어온 물건을 옆에 내려놓았습니다."); }
                        else Notice("찾아온 " + Player.Session.Inventory.ItemName((string)item.Stack["id"]) + " ×" + moved + "을 가방에 넣었습니다.");
                        item = null;
                    }
                    if (Elapsed >= Duration("RetrieveDrop", 1.5f)) Change(ActionPhase.Follow);
                    break;
                case ActionPhase.PetSit: if (Elapsed >= Duration("PetSit", 1.5f)) Change(ActionPhase.PetEnjoy); break;
                case ActionPhase.PetEnjoy: if (Elapsed >= Duration("PetEnjoy", 3)) Change(ActionPhase.PetRise); break;
                case ActionPhase.PetRise: if (Elapsed >= Duration("PetRise", 1.2f)) { EndCare(true); Change(ActionPhase.Follow); } break;
                case ActionPhase.EatStart: if (Elapsed >= Duration("EatStart", 1)) Change(ActionPhase.EatLoop); break;
                case ActionPhase.EatLoop:
                    if (contact.Crossed(Elapsed, .35))
                    {
                        if (food == null || !food.Commit(Player.Session.Inventory)) { Notice("준비한 먹이가 바뀌어 밥 주기를 취소했습니다."); Cancel(careOwner); break; }
                        MealsEaten++; Affection = Mathf.Min(100, Affection + 5);
                    }
                    if (Elapsed >= Math.Max(2, Duration("EatLoop", 2) * 2)) Change(ActionPhase.EatEnd);
                    break;
                case ActionPhase.EatEnd: if (Elapsed >= Duration("EatEnd", 1)) { EndCare(true); Change(ActionPhase.Follow); } break;
            }
            gravity = motor.isGrounded ? -1 : Mathf.Max(-12, gravity - (float)delta * 18);
            if (motor.enabled) motor.Move(Vector3.up * gravity * (float)delta);
            Animate(delta);
        }
        CreepCombatant NearestThreat()
        {
            if (Game.Combat == null || Game.Combat.SafeZone) return null;
            Game.DungeonRoot.GetComponentsInChildren(false, enemies);
            return enemies.Where(ValidEnemy).Where(e => e.Target == Game.Combat && Planar(e.transform.position - Player.transform.position) < 7 && (e.State != "idle" || Game.Combat.Busy || e.Health < e.MaximumHealth))
                .OrderBy(e => (e.transform.position - transform.position).sqrMagnitude).FirstOrDefault();
        }
        bool ValidEnemy(CreepCombatant target) => target != null && target.gameObject.activeInHierarchy && !target.Dead && target.Anatomy != null && target.State != "execution" && target.KnockdownPhase == "none" && Game.Combat != null && !Game.Combat.SafeZone && Planar(target.transform.position - Player.transform.position) < 10;
        bool ClearSight(Vector3 target) => !Physics.Linecast(transform.position + Vector3.up * .42f, target, 1 << DungeonCombatWorld.WorldLayer, QueryTriggerInteraction.Ignore);
        void Bite()
        {
            if (!ValidEnemy(enemy) || Planar(enemy.transform.position - transform.position) > 1.2f) return;
            Vector3 from = Mouth.position;
            Vector3 toward = enemy.Anatomy.AimPoint("left_leg") - from;
            Vector3 to = from + Vector3.ClampMagnitude(toward, .64f);
            if (Physics.Linecast(from, to, 1 << DungeonCombatWorld.WorldLayer, QueryTriggerInteraction.Ignore)) return;
            var hit = enemy.QueryHit(from, to, .075f);
            if (!hit.Hit) return;
            double before = enemy.Health; enemy.ReceiveHit(BiteDamage, transform.position, .1, hit);
            if (enemy.Health < before) { LandedBites++; Game.Combat.NotifyProjectileHit(before - enemy.Health); }
        }
        Vector3 Ground(Vector3 at)
        { return Physics.Raycast(at + Vector3.up * .3f, Vector3.down, out var hit, 2.7f, 1 << DungeonCombatWorld.WorldLayer, QueryTriggerInteraction.Ignore) ? hit.point : new Vector3(at.x, transform.position.y, at.z); }
        static float Planar(Vector3 v) => new Vector2(v.x, v.z).magnitude;
        void Face(Vector3 toward, float blend)
        { toward.y = 0; if (toward.sqrMagnitude > .001f) transform.rotation = Quaternion.Slerp(transform.rotation, Quaternion.LookRotation(toward), Mathf.Clamp01(blend)); }
        void Move(Vector3 target, float requestedSpeed, double delta)
        {
            var direction = route.Direction(transform.position, target, delta);
            if (direction.sqrMagnitude < .001f) { routeStuck += delta; return; }
            Vector3 before = transform.position; Face(direction, (float)delta * 7);
            motor.Move(direction * requestedSpeed * (float)delta);
            float traveled = Planar(transform.position - before); speed = traveled / (float)delta;
            routeStuck = traveled < .001f ? routeStuck + delta : 0;
        }
        Vector3 DropPoint()
        {
            foreach (var offset in new[] { transform.forward * .65f, transform.right * .65f, -transform.right * .65f, Vector3.zero })
            { var candidate = Ground(transform.position + offset); if (PetWalkRoute.Floor(candidate, out var ground)) return ground + Vector3.up * .025f; }
            return transform.position + Vector3.up * .025f;
        }
        void ReleaseItem(bool restoreHome)
        {
            if (item == null) return;
            if (!item.Carried) item.ReleaseReservation(this);
            else if (restoreHome) item.RestoreHome(this); else item.PutDown(this, DropPoint());
            item = null;
        }
        float Duration(string name, float fallback) => motion.Duration(name, fallback);
        void Animate(double delta)
        {
            string clip; bool loop = false;
            switch (Phase)
            {
                case ActionPhase.Follow: case ActionPhase.ChaseEnemy: clip = speed > 2.3f ? "Run" : speed > .05f ? "Walk" : "IdleFriendly"; loop = true; break;
                case ActionPhase.Sniff: clip = "SearchSniff"; loop = true; break;
                case ActionPhase.SeekItem: clip = speed > .05f ? "SearchWalk" : "SearchSniff"; loop = true; break;
                case ActionPhase.Returning: clip = "RetrieveCarryWalk"; loop = true; break;
                case ActionPhase.Bite: clip = "CombatBite"; break;
                case ActionPhase.Found: clip = "SearchFound"; break;
                case ActionPhase.Pickup: clip = "RetrievePickup"; break;
                case ActionPhase.Drop: clip = "RetrieveDrop"; break;
                default: clip = Phase.ToString(); loop = Phase == ActionPhase.PetEnjoy || Phase == ActionPhase.EatLoop; break;
            }
            motion.Advance(clip, delta, loop);
        }
    }
}
