using System;
using System.Collections.Generic;
using System.Linq;
using Newtonsoft.Json.Linq;
using UnityEngine;

namespace MusimusihanRpg.Gameplay
{
    /// <summary>The actual workshop UI and F2 trials share these services and clock.</summary>
    [DefaultExecutionOrder(-100)]
    public sealed partial class WorkshopController : MonoBehaviour
    {
        [Serializable] public sealed class ItemIcon { public string Id; public Texture2D Texture; public Rect Uv = new Rect(0, 0, 1, 1); }
        public Font KoreanFont;
        public ItemIcon[] ItemIcons = Array.Empty<ItemIcon>();
        public GameObject DungeonRoot;
        public DungeonMotor DungeonPlayer;
        public bool ManualClock;
        public NativeGameFlow NativeGame;
        public SourceCatalogs Catalog { get; private set; }
        public ExpeditionSession Session { get; private set; }
        public TestRoomSession Trials { get; private set; }
        public ItemUseRules Items { get; private set; }
        public SmithingSystem Smith { get; private set; }
        public AlchemySystem Alchemy { get; private set; }
        public HearthCookingSystem Cooking {get;private set;}
        public SimpleCraftingSystem Crafting {get;private set;}
        SimpleCraftingSystem savedCrafting;
        public WorkshopView View { get; private set; }
        public NativeTrialMenu TrialMenu {get;private set;}
        public string Page { get; private set; } = "inventory";
        public string Message { get; private set; } = "원정 장비와 치료품을 준비하십시오.";
        public bool Paused { get; private set; }
        public bool SimulationPaused => Paused || Trials.SimulationPaused || (NativeGame != null && (!Trials.Active||NativeGame.NativeTrial) && NativeGame.WorldPaused);
        public bool Dirty { get; private set; }
        double smithingPhase, savedSmithingPhase;
        public double SmithingAccuracy => Math.Max(0, Math.Min(1, 1 - Math.Abs(smithingPhase % 1.5 - .75) / .75));
        public readonly Dictionary<string, string> TrialInstructions = new Dictionary<string, string>();
        ItemUseRules savedItems;
        SmithingSystem savedSmith;
        AlchemySystem savedAlchemy;
        HearthCookingSystem savedCooking;
        string savedPage;
        bool savedPause;

        void Start() => Initialize();
        public void Initialize()
        {
            if (Session != null) return;
            Catalog = SourceCatalogs.Load(); ApplySimpleCraftingDescriptions(); Session = new ExpeditionSession(Catalog); Session.BeginNewJourney();
            if(NativeGame!=null)Catalog.TestRoomEntries.Add(new JObject{["id"]="native_settings",["category"]="시스템",["title"]="설정 · 음량·전체 화면·화질·성능",["action"]="native_settings",["detail"]="설정 조작·저장 시험 / 플레이 시험에서는 Esc로 설정 / F2 정지·재시도 / 실제 설정과 원정 복원"});
            // Manual forging and alchemy are superseded by the shared recipe queue.
            foreach(var entry in Catalog.TestRoomEntries.OfType<JObject>().Where(e=>new[]{"smithing","alchemy","alchemy_recipe","distilling"}.Contains((string)e["action"])).ToArray())entry.Remove();
            Catalog.TestRoomEntries.Add(new JObject{["id"]="simple_crafting",["category"]="제작",["title"]="간단 제작 · 재료·수량·대기열",["action"]="simple_crafting",["detail"]="제조법 선택 → 수량 → 제작 / 대기열 취소·재료 반환 / F2 정지·재보급·원정 복원"});
            AddPettingTrialEntries(); BindServices(); Trials = new TestRoomSession(Catalog, Session);
            Trials.BeforeTrialReset += () => { ResetOriginalRangedFeedback(); NativeGame?.EndNativeTrial(); Camp?.Dispose(); Items.Cancel(); Interaction?.Cancel(); Combat?.CancelExecution(); DungeonPlayer?.GetComponent<PlayerPresentation>()?.CancelTreatment(); CloseLoot(); };
            Trials.Restored += () =>
            {
                NativeGame?.EndNativeTrial();
                RestoreWorld();
                Items = savedItems; Smith = savedSmith; Alchemy = savedAlchemy; Cooking=savedCooking; Camp=savedCamp; Crafting=savedCrafting;
                Page = savedPage; Paused = savedPause;
                smithingPhase = savedSmithingPhase;
                savedItems = null; savedSmith = null; savedAlchemy = null; savedCooking=null; savedCamp=null; savedCrafting=null;
                Message = "시험 종료 · 원래 원정과 작업대로 돌아왔습니다."; Dirty = true;
            };
            BindInteraction(); RegisterTrials(); RegisterInteractionTrials(); RegisterCharacterTrials(); RegisterClothTrial(); RegisterHandProfiles(); RegisterCombatTrials(); RegisterNativeInventoryTrials(); RegisterSceneTrials(); RegisterOriginalCombatTrials(); RegisterPettingTrial();
            View = gameObject.AddComponent<WorkshopView>(); View.Initialize(this, KoreanFont);
            if (DungeonPlayer != null) DungeonPlayer.ReturnToMenu = OpenTrials;
            Dirty = true;
            if (NativeGame != null)
            {
                NativeGame.Initialize(this);RegisterPerformanceTrial();RegisterGalleryTrials();TrialMenu=gameObject.AddComponent<NativeTrialMenu>();TrialMenu.Initialize(this);
                Trials.RegisterMenuAction("survival_controls",()=>{OpenTrials();TrialMenu.FocusStatus();});
            }
        }
        void BindServices()
        {
            if(Camp!=null&&Camp!=savedCamp)Camp.Dispose();
            Items = new ItemUseRules(Catalog, Session); Smith = new SmithingSystem(Catalog, Session.Inventory);
            Alchemy = new AlchemySystem(Catalog, Session.Inventory);
            if(Crafting==null||!ReferenceEquals(Crafting.Inventory,Session.Inventory))Crafting=new SimpleCraftingSystem(Catalog,Session.Inventory);
            Cooking=new HearthCookingSystem(Catalog,Session,()=>DungeonPlayer?.Stamina??0,n=>DungeonPlayer?.RestoreStamina((float)n),CookingSceneFailure);
            if(NativeGame?.CampData!=null&&DungeonPlayer!=null)Camp=new NativeCamp(this);
            smithingPhase = 0;
            Items.Finished += Reply;
            Items.LiveActionBlocked=()=>DungeonPlayer?.GetComponent<PlayerPresentation>()?.TreatmentActionBlocked==true;
            Items.PresentationBusy=()=>DungeonPlayer?.GetComponent<PlayerPresentation>()?.TreatmentActive==true;
            Items.MotionRequested+=(id,part)=>DungeonPlayer?.GetComponent<PlayerPresentation>()?.PlayTreatment(id,part);
            Items.MotionStopped+=()=>DungeonPlayer?.GetComponent<PlayerPresentation>()?.CancelTreatment();
            Items.HealthRestored+=()=>DungeonPlayer?.AcknowledgeBodyHealth();
            if (DungeonPlayer != null) DungeonPlayer.Bind(Session);
        }
        void Update()
        {
            if (Session == null) return;
            SyncPhysicsOwnership();
            if(Gallery!=null)
            {
                if(!ManualClock&&(Input.GetKeyDown(KeyCode.F2)||Input.GetKeyDown(KeyCode.Escape)))CloseGallery();
                return;
            }
            if (NativeGame != null && (!Trials.Active||NativeGame.NativeTrial&&!Trials.MenuOpen))
            {
                if (ManualClock) NativeGame.Tick(Time.unscaledDeltaTime);
                else AdvanceLiveFrame(Time.unscaledDeltaTime, true);
                Dirty = false; View.Canvas.gameObject.SetActive(false); View.UICamera.gameObject.SetActive(false);
                return;
            }
            if (!ManualClock)
            {
                if (Input.GetKeyDown(KeyCode.F2)) HandleTrialNavigationKey(KeyCode.F2);
                if (Input.GetKeyDown(KeyCode.Escape)) HandleTrialNavigationKey(KeyCode.Escape);
                if (Input.GetKeyDown(KeyCode.F)&&TrialMenu?.NumberDragging!=true) CancelUse();
                if (!Trials.MenuOpen && !Paused)
                {
                    if (Input.GetKeyDown(KeyCode.E) && Page == "loot") CloseLoot();
                    if (Input.GetKeyDown(KeyCode.I)) { if (Page == "loot") CloseLoot(); else Navigate(Page == "inventory" && inExpedition ? "dungeon" : "inventory"); }

                }
                AdvanceLiveFrame(Time.unscaledDeltaTime);
            }
            if (Dirty) { Dirty = false; View.Rebuild(); }
            View.RefreshValues();
            bool characterReview = Page == "fingers" && !Trials.MenuOpen && !Paused;
            bool nativeMenuWorld=NativeGame!=null&&Trials.Active&&Trials.MenuOpen&&Gallery==null;
            bool dungeonVisible = nativeMenuWorld||(Page == "dungeon" || characterReview) && !Trials.MenuOpen && !Paused;
            if (DungeonRoot != null && DungeonRoot.activeSelf != dungeonVisible) DungeonRoot.SetActive(dungeonVisible);
            if (DungeonPlayer != null) DungeonPlayer.Paused = SimulationPaused || !dungeonVisible || characterReview;
            if(nativeMenuWorld)DungeonPlayer?.GetComponent<PlayerPresentation>()?.SetPresentationEnabled(true);
            View.Canvas.gameObject.SetActive(!dungeonVisible || characterReview); View.UICamera.gameObject.SetActive(!dungeonVisible || characterReview);
        }
        public bool HandleTrialNavigationKey(KeyCode key)
        {
            if(key!=KeyCode.F2&&key!=KeyCode.Escape)return false;
            if(Trials.MenuOpen&&TrialMenu?.ConsumeNavigationKey(key)==true)return true;
            if(key==KeyCode.F2){if(Trials.MenuOpen)ResumeTrial();else OpenTrials();}
            else if(Trials.MenuOpen)ResumeTrial();else {Paused=!Paused;Dirty=true;}
            return true;
        }
        public void Advance(double seconds)
        {
            if (!double.IsFinite(seconds) || seconds <= 0) return;
            AdvanceWorld(seconds);AdvanceStress(seconds);
        }
        void AdvanceWorld(double seconds, PlayerFrameInput? input = null, bool physicsOnly = false)
        {
            if (double.IsNaN(seconds) || double.IsInfinity(seconds) || seconds <= 0) return;
            DungeonPlayer?.AdvanceFeedback((float)seconds,SimulationPaused);
            if(CancelInvalidNativeCooking())return;
            if(Session.Body.IsDead){Items.Cancel();Interaction?.Cancel();DungeonPlayer?.GetComponent<PlayerPresentation>()?.CancelTreatment();DungeonPlayer?.GetComponent<PlayerPresentation>()?.EndChest();return;}
            if(NativeActivity("camp")){if(!SimulationPaused){AdvanceCombatState(seconds);if(!physicsOnly)Camp.Advance(seconds);DungeonPlayer.GetComponent<PlayerPresentation>()?.Advance(seconds,false);ResolveCombatWorld(seconds);}return;}
            if (AdvanceNativeActivities(physicsOnly ? 0 : seconds)) return;
            Items.Paused = SimulationPaused;
            if (SimulationPaused || Session.Body.IsDead) return;
            var presentation = DungeonPlayer == null ? null : DungeonPlayer.GetComponent<PlayerPresentation>();
            if (Page == "fingers") { if(!physicsOnly)presentation?.Advance((float)seconds, false); return; }
            if (Page == "dungeon")
            {
                // player.gd: item completion, timers/combat, movement, interaction,
                // viewmodel and stamina. game.gd resolves contacts after all actors.
                Items.Advance(seconds);
                AdvanceCombatState(seconds, input?.Captured == true && input.Value.BlockHeld);
                if (input.HasValue)
                {
                    var frame = input.Value;
                    if (frame.Jump) DungeonPlayer?.RequestJump();
                    DungeonPlayer?.Simulate(seconds, frame.Captured ? frame.Move : Vector2.zero, frame.Captured && frame.Sprint, false);
                }
                Interaction?.Advance(seconds);
                if (input?.Captured == true && input.Value.InteractPressed && !Session.HasCondition("paralysis")) Interaction?.Interact();
                presentation?.Advance(seconds, false);
                if (input.HasValue) DungeonPlayer?.AdvanceStamina(seconds);
                ResolveCombatWorld(seconds);
                // Opening a chest changes the page during interaction. Its new
                // search clock starts next tick, not again with the opening delta.
                if (Page != "dungeon") return;
            }
            if (physicsOnly) return;
            AdvanceActivities(seconds);
        }
        bool NativeActivity(string state) => NativeGame != null && NativeGame.State == state && (!Trials.Active || NativeGame.NativeTrial && !Trials.MenuOpen) && !Paused;
        bool AdvanceNativeActivities(double seconds)
        {
            if(NativeActivity("cooking")){if(seconds>0){Cooking.Advance(seconds);if(Cooking.State=="closed")NativeGame.CloseCooking();}return true;}
            if(NativeActivity("crafting")){if(seconds>0)Crafting.Tick(seconds);return true;}
            if(NativeGame?.State=="fingers"&&NativeGame.Fingers?.IsOpen==true){if(seconds>0)NativeGame.Fingers.Advance((float)seconds);return true;}
            return false;
        }
        void AdvanceProcessFrame(double seconds)
        {
            if(CancelInvalidNativeCooking())return;
            if(Session.Body.IsDead)return;
            if(NativeActivity("camp")){if(!SimulationPaused)Camp.Advance(seconds);}
            else if(!AdvanceNativeActivities(seconds)&&!SimulationPaused)
            {
                if(Page=="fingers")DungeonPlayer?.GetComponent<PlayerPresentation>()?.Advance(seconds,false);
                else AdvanceActivities(seconds);
            }
            AdvanceStress(seconds);
        }
        void AdvanceActivities(double seconds)
        {
            if (Page == "loot")
            {
                if (OpenChest != null && OpenChest.Container.AdvanceSearch(seconds).Count > 0) Dirty = true;
                return; // Source search advances while world and survival remain paused.
            }
            if (inExpedition && Page != "dungeon") return;
            if (Page != "dungeon") { Interaction?.Advance(seconds); Items.Advance(seconds); }
            if (Page == "loot") return;
            Crafting?.Tick(seconds);
            // The workshop is a safe area, matching hideout survival behavior.
            Camp?.Advance(seconds);
            // hideout.gd never advances expedition survival. Keep the low-level
            // safe-context primitive unchanged: explicit test-room time skips
            // still drain needs while protecting ailments, as in the source.
            var context=SurvivalContext();
            if((bool?)context["safe_zone"]!=true)Session.AdvanceSurvival(seconds,context);
        }
        public void StartNativeJourney(bool resetMagic=true) { Session.BeginNewJourney(resetMagic); BindServices(); }
        public void SetNativeWorld(GameObject root, DungeonMotor player)
        { Camp?.Dispose(); DungeonRoot=root;DungeonPlayer=player;BindServices();BindInteraction();Paused=false;Page="dungeon";inExpedition=true;Dirty=true; }
        public void Navigate(string page)
        {
            if (Trials.MenuOpen) return;
            if(page=="smithing"||page=="alchemy"||page=="crafting"){NativeGame?.OpenCrafting(page=="smithing"?"weapon":page=="alchemy"?"consumable":"all");return;}
            if (Page == "dungeon" && page != "dungeon") { Bow?.Cancel();Flail?.Cancel();Combat?.Cancel();Interaction?.Cancel(); DungeonPlayer?.ReleasePointer(); }
            Page = page; Dirty = true;
        }
        public void Reply(JObject result)
        {
            Message = (string)result["message"] ?? ((bool?)result["accepted"] == true ? "완료했습니다." : Reason((string)result["reason"]));
            Dirty = true;
        }
        static string Reason(string reason)
        {
            switch (reason)
            {
                case "full": case "inventory_full": return "가방이 가득 찼습니다.";
                case "not_enough_crowns": case "insufficient_funds": return "크라운이 부족합니다.";
                case "out_of_stock": return "상인에게 남은 물품이 없습니다.";
                case "protected_weapon": return "개조한 무기는 판매하지 않습니다.";
                case "not_owned": return "가방에 해당 물품이 없습니다.";
                default: return "지금은 이 작업을 할 수 없습니다.";
            }
        }
        public void Use(string id)
        {
            if (SimulationPaused) return;
            Items.Paused = false; Reply(Items.Begin(id, Session.Inventory, true));
        }
        public void CancelUse()
        {
            if (Items.Cancel()) Reply(Items.LastResult);
        }
        public void TogglePause() { if (!Trials.MenuOpen) { Paused = !Paused; ClearPendingFrameInput();if(Paused)StressEffects?.SetActive(false);Dirty = true; } }
        public void OpenTrials()
        {
            DismissGallery();StopClothObservation();
            if(NativeGame!=null&&NativeGame.IsTransitioning&&!NativeGame.CommittingLoadedScene)return;
            bool returningFromScene=Trials.Active&&NativeGame!=null&&!NativeGameFlow.IsCraftingTrial(Trials.CurrentEntry)&&DungeonRoot.GetComponent<NativeTrialWorld>()==null;
            // test_room.gd::F2 closes the bag and interrupts unpaid actions in the
            // sandbox. The original expedition remains suspended on first entry.
            if(Trials.Active)
            {
                if(NativeGame?.Inventory?.IsOpen==true)NativeGame.CloseInventory();
                else if(OpenChest!=null)CloseLoot();
                Camp?.Cancel("시험 메뉴 열기");
                // An execution owns both actors; the source pauses its shared clock.
                if(Combat?.ExecutionActive!=true){Items.Cancel();if(!PettingInputActive)DungeonPlayer?.PrepareForInventory();}
            }
            StressEffects?.SetActive(false);NativeGame?.SuspendForTrials();
            if (Page == "fingers") DungeonPlayer?.GetComponent<PlayerPresentation>()?.EndReview();
            if (!Trials.Active)
            {
                savedItems = Items; savedSmith = Smith; savedAlchemy = Alchemy; savedCooking=Cooking; savedCamp=Camp; savedCrafting=Crafting; savedPage = Page; savedPause = Paused;
                savedSmithingPhase = smithingPhase;
                IsolateWorld(); Trials.Begin(); BindServices();PrepareTrialRoomActors();DungeonPlayer?.ResetTrial(new Vector3(0,1,12));
                Message=$"{Catalog.TestRoomEntries.Count(e=>(string)e["id"]!="native_settings")}개 시험 항목 · AI 정지 표적으로 시작 · F2는 언제든 시험 메뉴";
            }
            else
            {
                Trials.OpenMenu();
                if(returningFromScene)
                {
                    // TestRoomSandbox.return_to_room replaces the connected scene,
                    // retaining the sandbox bag/body but discarding scene activities.
                    EnsureTrialRoom();BindServices();DungeonPlayer.ResetTrial(new Vector3(0,1,12));
                    Trials.SelectDefault("movement",true);NativeGame.ApplyReliquaryEnvironment(DungeonPlayer);
                }
            }
            Paused = false; Page = "trials"; Dirty = true;
            if(DungeonPlayer!=null){DungeonPlayer.Paused=true;DungeonPlayer.ReleasePointer();}
            if(Session.Body.IsDead)RecoverTrialStatus();
        }
        public bool RunTrial(string id)
        {
            TrialMenu?.CommitPending();
            if(!Trials.RunnableEntries.Any(e=>(string)e["id"]==id))return false;
            CancelScriptedCreepTrials();Combat?.CancelExecution();
            NativeGame?.Fingers?.Close();StopClothObservation();
            if(id!="player_hands_greybox"&&id!="player_hands_detailed")DungeonPlayer?.GetComponent<PlayerPresentation>()?.SetHandsProfile("original");
            if(Trials.IsMenuAction(id))return Trials.Run(id);
            // Original run_feature clears the placement obstacle/signs even when
            // the destination (for example movement) retains ordinary room actors.
            if(DungeonRoot!=null)foreach(var prop in DungeonRoot.GetComponentsInChildren<NativeTrialFixtureProp>(true))
                if(prop.transform.Find("CampPlacementInstructions")!=null){prop.gameObject.SetActive(false);Destroy(prop.gameObject);}
            if(Trials.Active&&UsesTrialRoom(id)&&Trials.RunnableEntries.Any(e=>(string)e["id"]==id))EnsureTrialRoom();
            bool accepted = Trials.Run(id);
            if (accepted) { Page = TrialPage(id); Message = TrialInstructions[id]; Paused = false; Dirty = true; if(DungeonRoot!=null)DungeonRoot.SetActive(Page=="dungeon"||Page=="loot");if(DungeonPlayer!=null)DungeonPlayer.Paused=SimulationPaused||Page!="dungeon"; }
            if(accepted&&Page=="dungeon"&&DungeonPlayer!=null)
            {if(DungeonPlayer.Eyes!=null)DungeonPlayer.Eyes.enabled=true;if(NativeGame!=null&&!NativeGameFlow.IsCaveTrial(id))NativeGame.ApplyReliquaryEnvironment(DungeonPlayer);}
            if(accepted&&NativeGameFlow.IsJourneyTrial(id)&&NativeGame!=null)NativeGame.BeginNativeJourneyTrial(id,true);
            if(accepted&&id=="simple_crafting"&&NativeGame!=null)NativeGame.BeginNativeCraftingTrial();
            if(accepted&&NativeGameFlow.IsCampTrial(id)&&NativeGame?.CampUi!=null)NativeGame.BeginNativeCampTrial();
            if(accepted&&id=="hideout_cooking"&&NativeGame?.Cooking!=null)NativeGame.BeginNativeCookingTrial();
            if(accepted&&InventoryTrial(id)&&NativeGame!=null)NativeGame.BeginNativeInventoryTrial(id);
            if(accepted&&id=="native_settings"&&NativeGame!=null)NativeGame.BeginNativeSettingsTrial();
            if(accepted&&NativeGameFlow.IsCaveTrial(id)&&NativeGame!=null)NativeGame.BeginNativeCaveTrial();
            if(accepted&&NativeGameFlow.IsSceneTrial(id)&&NativeGame!=null)NativeGame.BeginNativeSceneTrial(id);
            if(accepted&&(id=="movement"||CharacterWorldTrial(id)||TimedInventoryTrial(id)||CombatTrial(id)||TreatmentTrial(id)||InteractionTrial(id)||StressTrial(id)||PettingTrial(id))&&NativeGame!=null)NativeGame.BeginNativeCombatTrial();
            if(accepted&&(id=="player_appearance"||id=="player_finger_joints")&&NativeGame!=null)NativeGame.BeginNativeCharacterReview(id);
            if(accepted&&id=="player_cloth_motion"){DungeonPlayer.GetComponent<PlayerPresentation>().BeginClothObservation();NativeGame.Notice("WASD 걷기 · Shift 달리기 · F2 복귀\n몸·의상 배치 관찰 · 정적 자세·천 물리 미적용",6);}
            if(accepted&&(id=="player_hands_greybox"||id=="player_hands_detailed"))NativeGame.Notice((id.EndsWith("greybox")?"양손 그레이박스":"FP arms 양팔·손 모델")+" · 왼쪽 상자 E\nI 활 장착 → LMB 당기고 놓기 · F2 재시험",7);
            if(accepted&&!(NativeGame!=null&&(InventoryTrial(id)||TimedInventoryTrial(id))))DungeonPlayer?.ResetFeedback();
            if(accepted)ShowOriginalTrialNotice(id);
            if(accepted&&PettingTrial(id))BeginPettingTrialView();
            return accepted;
        }
        public void RetryTrial() { if (Trials.CurrentEntry.Length > 0) RunTrial(Trials.CurrentEntry); }
        public void ResumeTrial() { TrialMenu?.CommitPending();if(Trials.Active&&Trials.MenuOpen&&Trials.CurrentEntry.Length==0)Trials.SelectDefault("movement");if (Trials.Resume()) { Page = TrialPage(Trials.CurrentEntry); if(DungeonRoot!=null)DungeonRoot.SetActive(Page=="dungeon"||Page=="loot"); if(DungeonPlayer!=null)DungeonPlayer.Paused=SimulationPaused||Page!="dungeon";if(NativeGameFlow.IsJourneyTrial(Trials.CurrentEntry)&&NativeGame!=null)NativeGame.BeginNativeJourneyTrial(Trials.CurrentEntry);if(Trials.CurrentEntry=="simple_crafting"&&NativeGame!=null)NativeGame.BeginNativeCraftingTrial();if(NativeGameFlow.IsCampTrial(Trials.CurrentEntry)&&NativeGame?.CampUi!=null)NativeGame.BeginNativeCampTrial();if(Trials.CurrentEntry=="hideout_cooking"&&NativeGame?.Cooking!=null)NativeGame.BeginNativeCookingTrial(true);if(Trials.CurrentEntry=="native_settings"&&NativeGame!=null)NativeGame.BeginNativeSettingsTrial();if(NativeGameFlow.IsCaveTrial(Trials.CurrentEntry)&&NativeGame!=null)NativeGame.BeginNativeCaveTrial();if(NativeGameFlow.IsSceneTrial(Trials.CurrentEntry)&&NativeGame!=null)NativeGame.BeginNativeSceneTrial(Trials.CurrentEntry);if((Trials.CurrentEntry=="movement"||CharacterWorldTrial(Trials.CurrentEntry)||InventoryTrial(Trials.CurrentEntry)||TimedInventoryTrial(Trials.CurrentEntry)||CombatTrial(Trials.CurrentEntry)||TreatmentTrial(Trials.CurrentEntry)||InteractionTrial(Trials.CurrentEntry)||StressTrial(Trials.CurrentEntry)||PettingTrial(Trials.CurrentEntry))&&NativeGame!=null){NativeGame.BeginNativeCombatTrial();if(OpenChest!=null)OpenLoot(OpenChest);}if(PettingTrial(Trials.CurrentEntry))BeginPettingTrialView(); Dirty = true; } }
        public void EndTrials() {TrialMenu?.CommitPending();StopClothObservation();Trials.Finish();}
        string TrialPage(string id)
        {
            if((id=="native_settings"||id=="simple_crafting"||CharacterWorldTrial(id))&&NativeGame!=null)return "dungeon";
            if(NativeGameFlow.IsCampTrial(id)&&NativeGame?.CampData!=null)return "dungeon";
            if(id=="hideout_cooking"&&NativeGame?.CookingData!=null)return "dungeon";
            if((InventoryTrial(id)||TimedInventoryTrial(id)||NativeGameFlow.IsJourneyTrial(id))&&NativeGame!=null)return "dungeon";
            if(NativeGameFlow.IsCaveTrial(id)&&NativeGame!=null)return "dungeon";
            if(NativeGameFlow.IsSceneTrial(id)&&NativeGame!=null)return "dungeon";
            if (CombatTrial(id)||TreatmentTrial(id)||StressTrial(id)) return "dungeon";
            var entry = Catalog.TestRoomEntries.OfType<JObject>().FirstOrDefault(e => (string)e["id"] == id);
            string action = (string)entry?["action"];
            return action == "player_appearance" ? "appearance" : action == "player_finger_joints" ? (DungeonPlayer.GetComponent<PlayerPresentation>().Review ? "fingers" : "dungeon") : action == "movement" || action == "loot_container" || action == "traps" ? "dungeon" : action == "smithing" ? "smithing" : action == "alchemy" || action == "alchemy_recipe" || action == "distilling" ? "alchemy" : "inventory";
        }
        void Register(string id, string instruction, Action<JObject> prepare)
        {
            TrialInstructions[id] = instruction;
            Trials.Register(id, entry => { BindServices(); prepare(entry); });
        }
        int Supply(JObject supplies,int reservedSlots=0)
        {
            // Match the source trial restock policy; never replace real expedition stacks.
            if (!Trials.Active) throw new InvalidOperationException("Supplies require an isolated trial");
            var bag = Session.Inventory; int required = 0;
            foreach (var p in supplies.Properties())
            {
                int existing = bag.CountItem(p.Name); if (existing > 0) bag.RemoveItem(p.Name, existing, false);
                required += (int)Math.Ceiling((double)p.Value / Math.Max(1, (int?)bag.Definition(p.Name)["stack_max"] ?? 1));
            }
            if (reservedSlots < 0 || required + reservedSlots > ExpeditionInventory.MaxSlots) throw new InvalidOperationException("Trial supply definition exceeds bag capacity");
            int replaced=0;
            while (bag.Slots.Count + required + reservedSlots > ExpeditionInventory.MaxSlots) {bag.Slots.RemoveAt(bag.Slots.Count - 1);replaced++;}
            foreach (var p in supplies.Properties())
                if (bag.AddItem(p.Name, (int)p.Value, false) != 0) throw new InvalidOperationException("Trial supplies exceed capacity: " + p.Name);
            bag.NotifyChanged();
            return replaced;
        }
        void RegisterTrials()
        {
            RegisterCaveTrials(); RegisterJourneyTrials(); RegisterCampTrials(); RegisterTreatmentTrials(); RegisterStressTrials();
            Register("simple_crafting","제조법 선택 → 수량 → 제작 / × 취소·재료 반환 / F2 정지·재보급",_=>
            {
                if(NativeGame!=null){ReplaceNativeTrialWorld(NativeGame.HideoutTemplate);RecoverTrial();DungeonPlayer.ResetTrial(new Vector3(11.8f,1,-4));}
                Crafting=new SimpleCraftingSystem(Catalog,Session.Inventory);
                Supply(Crafting.TrialSupplies(),2);
            });
            if(NativeGame!=null)Register("native_settings","원본 음량·전체 화면과 저장 / 시험 설정만 변경 / F2 재시험·원래 설정 복원",_=>{});
            if(NativeGame?.CookingData!=null&&DungeonPlayer!=null)Register("hideout_cooking","실제 화롯불 냄비·꼬치 / 요리 완성 즉시 식사 / F2 정지·재보급",_=>
            {
                ReplaceNativeTrialWorld(NativeGame.HideoutTemplate);RecoverTrial();DungeonPlayer.ResetTrial(new Vector3(0,1,4.7f));DungeonPlayer.Paused=false;DungeonPlayer.Look(new Vector2(0,.2f/.00215f));Session.Body.SetTotalForDebug(35);DungeonPlayer.ConsumeStamina(80);Session.ClearConditions();Session.Hunger=15;Session.Thirst=20;Session.SetStress(55);
                var supplies=new JObject();foreach(var r in ((JObject)Catalog.Cooking["RECIPES"]).Properties())foreach(var resource in ((JObject)r.Value["resources"]).Properties())supplies[resource.Name]=((int?)supplies[resource.Name]??1)+(int)resource.Value;int replaced=Supply(supplies);
                TrialInstructions["hideout_cooking"]="실제 화롯불 냄비·꼬치 / 요리 완성 즉시 식사 / F2 정지·재보급"+(replaced>0?$" · 마지막 시험용 스택 {replaced}개를 보급품으로 교체했습니다":"");
            });
            if (DungeonRoot != null && DungeonPlayer != null)
                Register("movement", "원본 동쪽 장애물 코스 · WASD / Shift / Space · F2 재시험", _ => { if(DungeonRoot.GetComponent<NativeTrialWorld>()!=null)DungeonPlayer.ResetTrial(new Vector3(9,1,10),false);else {ClearActors();RecoverTrial();DungeonPlayer.ResetTrial(new Vector3(0,1,14.2f));} });
            Register("inventory", "장비 장착·해제 / 부위 선택·치료 / F2 재시험", _ => { });
            if(NativeGame!=null&&DungeonPlayer!=null)Register("inventory_details","원본 상세·이름표·장착·버리기 / 가방을 닫고 E 회수 / F2 재시험",_=>
            {ClearActors();RecoverTrial();DungeonPlayer.ResetTrial(new Vector3(0,1,9));Session.Inventory.SeedDefaultLoadout();Session.Inventory.AddItem("rusted_sword",1,false);Session.Inventory.AddItem("patched_mail",1,false);Session.Inventory.AddItem("linen_bandage",3,false);Session.Inventory.NotifyChanged();});
            foreach (string id in new[] { "body_health", "body_surgery" })
                Register(id, id == "body_surgery" ? "왼팔 0 → 수술키트로 1 복구 → 회복약으로 치료 / F 취소" : "일곱 부위의 체력을 확인하고 선택한 부위를 치료하십시오.", e =>
                {
                    RecoverTrial();
                    var supplies = new JObject { ["healing_draught"] = 4, ["surgery_kit"] = 2 };
                    foreach (var p in ((JObject)Catalog.Inventory["ITEM_DEFINITIONS"]).Properties())
                        if (p.Value["condition"] != null && new[] { "bandage", "cure_condition" }.Contains((string)p.Value["effect"])) supplies[p.Name] = 2;
                    Supply(supplies);
                    if ((string)e["payload"] == "surgery") Session.Body.Damage("left_arm", 60);
                    else foreach (string part in Catalog.BodyHealth["PART_ORDER"].Values<string>()) Session.Body.Damage(part, 5);
                    Items.SelectTreatmentPart("left_arm");
                });
            Register("timed_item_use", "치료품·식량·물 사용 → 남은 시간 / F 취소 / 완료할 때 소비", _ =>
            {
                Session.Body.Damage("left_arm", 30); Items.SelectTreatmentPart("left_arm");
                Session.ApplyCondition("bleeding", -1, "left_arm"); Session.Hunger = 35; Session.Thirst = 35;
            });
            foreach (var entry in Catalog.TestRoomEntries.OfType<JObject>())
            {
                string id = (string)entry["id"], action = (string)entry["action"];
                if (action == "condition") Register(id, "상태이상과 대응 치료품 / 부위를 선택하고 치료 / F2 재보급", e =>
                {
                    string condition = (string)e["payload"], part = condition == "fracture" ? "left_leg" : "left_arm";
                    Items.SelectTreatmentPart(part); Session.ApplyCondition(condition, -1, part);
                    var supplies = new JObject();
                    foreach (var p in ((JObject)Catalog.Inventory["ITEM_DEFINITIONS"]).Properties())
                        if ((string)p.Value["condition"] == condition && new[] { "bandage", "cure_condition" }.Contains((string)p.Value["effect"])) supplies[p.Name] = 2;
                    Supply(supplies);
                });

            }
        }
    }
}
