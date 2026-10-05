using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using Newtonsoft.Json.Linq;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.UI;

namespace MusimusihanRpg.Gameplay
{
    public sealed partial class NativeGameFlow : MonoBehaviour
    {
        public TextAsset HideoutData;
        public TextAsset UiData, DrawingData, DungeonHudData;
        public Font CombatSerifFont;
        public NativeCombatHud CombatHud {get;private set;}
        public TorchIgnitionHud IgnitionHud {get;private set;}
        public Font LightFont, RegularFont, MediumFont, SerifFont, NumberFont;
        public NativeInventory Inventory {get;private set;}
        public NativeSettings Settings {get;private set;}
        public GameObject HideoutRoot;
        public GameObject DroppedPackagePrefab;
        public SourceUi.TextureBinding[] UiTextures;
        public GameObject ReliquaryRoot { get; private set; }
        public SourceUi Ui { get; private set; }
        public string State { get; private set; } = "title";
        public bool InHideout { get; private set; } = true;
        public bool IsTransitioning { get; private set; }
        public bool WorldPaused => NativeLoadingScreen.Visible || IsTransitioning || State != "playing" && !(State=="camp"&&game.Camp?.Activity.State=="resting");
        public bool NativeTrial {get;private set;}
        string priorTrialState;bool priorTrialHideout, preserveOriginalContainer;
        WorkshopController game;
        DungeonMotor motor;
        JObject data;
        float eventTime;double elapsed;
        HideoutAmbientMotion hideoutMotion;
        bool returningFromTrials;
        string modal,hideoutLocation;GameObject returnTitleFocus;
        readonly List<(Light light, float energy, float phase)> flicker = new List<(Light,float,float)>();

        public void Initialize(WorkshopController controller)
        {
            if (game != null) return;
            if(FindObjectsByType<AudioListener>(FindObjectsSortMode.None).Length==0){var ear=new GameObject("FirstPersonAudioListener",typeof(AudioListener),typeof(NativeAudioListener));ear.transform.SetParent(transform,false);ear.GetComponent<NativeAudioListener>().Game=controller;}
            game=controller;motor=game.DungeonPlayer;ReliquaryRoot=game.DungeonRoot;data=JObject.Parse(HideoutData.text);
            EnsureWorldEffects(HideoutRoot,HideoutTemplate);EnsureWorldEffects(ReliquaryRoot,ReliquaryTemplate);EnsureWorldEffects(CaveRoot,CaveTemplate);
            var canvas = new GameObject("OriginalGameInterface",typeof(RectTransform));
            Ui=canvas.AddComponent<SourceUi>();Ui.LightFont=LightFont;Ui.RegularFont=RegularFont;Ui.MediumFont=MediumFont;Ui.SerifFont=SerifFont;Ui.NumberFont=NumberFont;
            var controls=(JArray)(UiData!=null?JObject.Parse(UiData.text):data)["controls"];
            if(DungeonHudData!=null)foreach(var control in JObject.Parse(DungeonHudData.text)["controls"])controls.Add(control.DeepClone());
            if(MerchantData!=null)foreach(var control in JObject.Parse(MerchantData.text)["controls"])controls.Add(control.DeepClone());
            if(CookingData!=null)foreach(var control in JObject.Parse(CookingData.text)["controls"])controls.Add(control.DeepClone());
            if(CampData!=null)foreach(var control in JObject.Parse(CampData.text)["controls"])controls.Add(control.DeepClone());
            Ui.SpacedFont=SpacedFont;Ui.MerchantMediumFont=MerchantMediumFont;Ui.TitleFont=TitleFont;
            var characterData=Resources.Load<TextAsset>("Migration/CharacterUI/character-ui");var bindings=UiTextures.AsEnumerable();
            if(characterData!=null)
            {
                var character=JObject.Parse(characterData.text);foreach(var control in character["finger_controls"])controls.Add(control.DeepClone());
                var icons=character["finger_controls"].OfType<JObject>().Where(e=>e["icons"]!=null).SelectMany(e=>((JObject)e["icons"]).Properties().Select(p=>(string)p.Value)).Distinct();
                bindings=bindings.Concat(icons.Select(name=>new SourceUi.TextureBinding{Name="character/"+name,Texture=Resources.Load<Texture2D>("Migration/CharacterUI/"+System.IO.Path.GetFileNameWithoutExtension(name))}));
            }
            Ui.Build(controls,game.KoreanFont,bindings.ToArray());Ui.Visible("fingers",false);Ui.Signal=OnSignal;
            Settings=new NativeSettings(Ui);SetTitleActionsEnabled(true);
            // Share the existing settings modal with gameplay without showing the title screen.
            Ui.Find("ModalScrim").SetParent(Ui.CanvasRoot,false);Ui.Find("ModalScrim").SetAsLastSibling();
            // One full-screen fade survives title/world/HUD layer changes.
            // Both source fade controls have the same black, input-free style.
            var fadeRect=Ui.Find("HideoutSceneFade");fadeRect.SetParent(Ui.Find("hideout").parent,false);fadeRect.anchorMin=Vector2.zero;fadeRect.anchorMax=Vector2.one;fadeRect.offsetMin=fadeRect.offsetMax=Vector2.zero;fadeRect.SetAsLastSibling();Ui.Visible("SceneFade",false);
            hideoutLocation=Ui.Find("LocationTitle").GetComponentInChildren<Text>(true).text;
            Inventory=new NativeInventory(game,this,(JObject)JObject.Parse(DrawingData.text)["drawings"]);
            Inventory.TreatmentPartSelected+=SelectInventoryTreatmentPart;Inventory.ConsumableRequested+=UseInventoryConsumable;
            if(MerchantData!=null){Merchant=new NativeMerchant(game,this,JObject.Parse(MerchantData.text));Ui.RoutedSignal=(path,method,args)=>path.StartsWith("merchant")?Merchant.Handle(path,method,args):Inventory.Handle(path,method,args);}
            if(DungeonHudData!=null)CombatHud=new NativeCombatHud(game,this,JObject.Parse(DungeonHudData.text));
            IgnitionHud=new TorchIgnitionHud(this);
            Crafting=new NativeCrafting(game,this);
            if(CookingData!=null)Cooking=new NativeCooking(game,this,JObject.Parse(CookingData.text));
            if(CampData!=null)CampUi=new NativeCampOverlay(game,this,JObject.Parse(CampData.text));
            BindHideoutInteractions(HideoutRoot);
            BindHideoutLighting(HideoutRoot);
            ReliquaryRoot.SetActive(false);HideoutRoot.SetActive(false);if(CaveRoot!=null)CaveRoot.SetActive(false);motor.NativeHud=true;
            Ui.Visible("hideout",false);Ui.Visible("title",true);motor.ReleasePointer();
            UnityEngine.EventSystems.EventSystem.current.SetSelectedGameObject(Ui.Find("StartGameButton").gameObject);
        }
        internal void SelectInventoryTreatmentPart(string part){if(State=="inventory")game.Items.SelectTreatmentPart(part);}
        internal void UseInventoryConsumable(string id)
        {
            if(State!="inventory")return;
            var result=game.Items.Begin(id,game.Session.Inventory,true);game.Reply(result);
            Inventory.SetStatus((string)result["message"]??game.Message);
            if((bool?)result["accepted"]==true)CloseInventory();
        }
        public void Tick(float delta)
        {
            using var timing=NativeFrameBenchmarkDiagnostics.Measure("NativeGameFlow.Tick");
            Ui.gameObject.SetActive(true);
            RefreshTorchIgnitionHud();
            if(returningFromTrials)
            {returningFromTrials=false;motor=game.DungeonPlayer;motor.NativeHud=true;RestoreWorldPresentation();BindExpeditionPortal();if(InHideout)BindHideoutLighting(game.DungeonRoot);if(State=="merchant")Merchant.Refresh();Ui.Visible("title",State=="title");Ui.Visible("hideout",State!="title"&&State!="merchant");Ui.Visible("merchant",State=="merchant");if(State=="crafting")OpenCrafting(restore:true);if(State=="cooking")OpenCooking(true);if(State=="camp")SyncCampState();if(State=="inventory"){if(game.OpenChest!=null)Inventory.OpenContainer(game.OpenChest.Container);else Inventory.Open();}if(!WorldPaused)motor.CapturePointer();}
            if(IsTransitioning||NativeLoadingScreen.Visible){RefreshViewState();return;}
            TickExpeditionOutcome(delta);
            if (Input.GetKeyDown(KeyCode.F11))
            {if(State=="title")Settings.ToggleFullscreen();else if(InHideout&&State!="merchant")Settings.ToggleWindowMode();}
            if (Input.GetKeyDown(KeyCode.F2)) { OpenTrials();return; }
            if(game.PettingInputActive && (Input.GetKeyDown(KeyCode.Escape)||Input.GetKeyDown(KeyCode.E))){game.ExitPettingView();return;}
            if(CampInput())return;
            if(State=="camp"&&(Input.GetKeyDown(KeyCode.I)||Input.GetKeyDown(KeyCode.B))&&HandleCampShortcut(Input.GetKeyDown(KeyCode.I)?KeyCode.I:KeyCode.B,false,Input.GetKey(KeyCode.LeftControl)||Input.GetKey(KeyCode.RightControl)||Input.GetKey(KeyCode.LeftAlt)||Input.GetKey(KeyCode.RightAlt)||Input.GetKey(KeyCode.LeftCommand)||Input.GetKey(KeyCode.RightCommand)))return;
            if(Input.GetKeyDown(KeyCode.M)&&HandleMapShortcut(KeyCode.M)){RefreshViewState();return;}
            if(State=="paused"&&HandlePauseResume(Input.GetKeyDown(KeyCode.Escape)?KeyCode.Escape:Input.GetKeyDown(KeyCode.E)?KeyCode.E:KeyCode.None,Input.GetMouseButtonDown(0))){RefreshViewState();return;}
            if (Input.GetKeyDown(KeyCode.Escape))
            {
                if(HandleGameplaySettingsEscape()){RefreshViewState();return;}
                if(HandleTitleEscape())return;
                if(State=="fingers"){game.OpenTrials();return;}
                if(HandleCampShortcut(KeyCode.Escape))return;
                if(State=="cooking"){CloseCooking();return;}
                if(State=="crafting"){CloseCrafting();return;}
                if(State=="merchant"){Merchant.Back();return;}
                if(State=="inventory")Inventory.Cancel();
                else if(modal!=null)CloseModal();
                else if(State=="title")ShowTitleModal("QuitConfirmPanel");
                else if(State=="playing")Pause();
            }
            if(State=="crafting")Crafting.Refresh();
            if(State=="inventory")Inventory.Tick(delta);
            if(State=="inventory"&&(Input.GetKeyDown(KeyCode.I)||Input.GetKeyDown(KeyCode.B))&&HandleInventoryShortcut(Input.GetKeyDown(KeyCode.I)?KeyCode.I:KeyCode.B,false,InventoryModifiersHeld()))return;
            if(State=="playing")
            {
                if(Input.GetKeyDown(KeyCode.F)||Input.GetKeyDown(KeyCode.L))HandleTorchShortcut(Input.GetKeyDown(KeyCode.F)?KeyCode.F:KeyCode.L);
                if(Input.GetMouseButtonDown(0)&&!game.PettingInputActive)
                {
                    if(TryOpenEntranceFromClick(Input.mousePosition,motor.Captured)){RefreshViewState();return;}
                    if(!motor.Captured)motor.CapturePointer();
                }
                if(Input.GetKeyDown(KeyCode.I)||Input.GetKeyDown(KeyCode.B))HandleInventoryShortcut(Input.GetKeyDown(KeyCode.I)?KeyCode.I:KeyCode.B,false,InventoryModifiersHeld());
                TickCave(delta);
                if(InHideout&&!game.SimulationPaused)
                {
                    elapsed+=delta;if(hideoutMotion!=null)hideoutMotion.Apply(elapsed);
                    foreach(var light in flicker)if(light.light!=null&&light.light.enabled)light.light.intensity=(float)(light.energy*(.91+Math.Sin(elapsed*8.7+light.phase)*.055+Math.Sin(elapsed*19.1+light.phase*.7)*.025));
                    var room=game.DungeonRoot.GetComponent<HideoutStructure>();
                    var announcement=room?.Visit(SourcePose.Position(motor.transform.position));
                    if(announcement!=null)Notice(announcement.Text,announcement.Duration);
                    if(motor.transform.position.y < -4)motor.RecoverPosition(new Vector3(0,1,17.2f));
                }
            }
            RefreshViewState();
            if(State=="fingers")Fingers?.Refresh();
            if(eventTime>0&&State!="fingers"){eventTime-=delta;if(eventTime<=0){Ui.Text("HideoutEvent","");Ui.Text("Dungeon_event_label","");}}
            CombatHud?.Tick(delta);
        }
        static bool InventoryModifiersHeld()=>Input.GetKey(KeyCode.LeftControl)||Input.GetKey(KeyCode.RightControl)||Input.GetKey(KeyCode.LeftAlt)||Input.GetKey(KeyCode.RightAlt)||Input.GetKey(KeyCode.LeftCommand)||Input.GetKey(KeyCode.RightCommand);
        public bool HandleInventoryShortcut(KeyCode key,bool repeated=false,bool modifiers=false)
        {
            if((key!=KeyCode.I&&key!=KeyCode.B)||repeated||IsTransitioning||(State!="inventory"&&State!="playing"))return false;
            // Source B is an unmodified dungeon alias; hideout handles physical I only.
            if(key==KeyCode.B&&(InHideout||modifiers))return false;
            // Godot LineEdit consumes text before the world sees _unhandled_input.
            var selected=UnityEngine.EventSystems.EventSystem.current?.currentSelectedGameObject;
            var field=selected==null?null:selected.GetComponentInParent<InputField>();
            if(field!=null&&field.isActiveAndEnabled&&field.isFocused)return false;
            if(State=="inventory")Inventory.Cancel();else OpenInventory();
            return true;
        }
        public bool HandleTorchShortcut(KeyCode key)
        {
            if((key!=KeyCode.F&&key!=KeyCode.L)||State!="playing"||WorldPaused||game.SimulationPaused||CampInputBlocked)return false;
            if(game.Items.IsActive)
            {
                game.CancelUse();
                if(InHideout)Notice("아이템 사용 취소",.8f);
            }
            else
            {
                var torch=motor.GetComponent<PlayerPresentation>()?.Torch;if(torch==null)return false;
                if(torch.Lit||torch.Igniting)torch.Toggle();
                else if(!torch.BeginIgnition())return false;
                if(InHideout)Notice(torch.Igniting?"횃불 점화 중":torch.Lit?"횃불을 밝혔습니다":"횃불을 껐습니다",.8f);
            }
            RefreshTorchIgnitionHud();
            return true;
        }
        public void RefreshTorchIgnitionHud()
        {
            var torch=game?.DungeonPlayer?.GetComponent<PlayerPresentation>()?.Torch;
            IgnitionHud?.Tick(torch,State=="playing"&&!WorldPaused&&game?.SimulationPaused!=true);
        }
        void RefreshViewState()
        {
            motor.Paused=WorldPaused;bool visibleWorld=State!="title"&&State!="merchant"&&State!="crafting";
            var presentation=motor.GetComponent<PlayerPresentation>();if(presentation!=null)presentation.SetPresentationEnabled(visibleWorld);else motor.Eyes.enabled=visibleWorld;
            Ui.Camera.clearFlags=State=="title"||State=="merchant"?CameraClearFlags.SolidColor:CameraClearFlags.Depth;
            if(State!="title")game.DungeonRoot.SetActive(true);
            Ui.Text("InteractionPrompt",InHideout&&!WorldPaused&&!motor.TimedInteraction?game.Interaction?.Focus?.Prompt??"":"");
            RefreshHideoutInteractionHud();
            RefreshTorchIgnitionHud();
        }
        internal void RefreshHideoutInteractionHud()
        {
            if(Ui==null||motor==null)return;
            var action=motor.ActiveHideoutInteraction;bool active=InHideout&&action!=null&&action.Busy;
            Ui.Visible("TimedInteractionPanel",active);
            Ui.Range("TimedInteractionProgress",active?(float)(action.Elapsed/Math.Max(.001,action.ActiveDuration)):0);
            if(active){Ui.Text("TimedInteractionTitle",action.Title);Ui.Text("InteractionPrompt","");}
        }
        // Keep the original scene transition exclusive until both fades finish.
        void StartTransition(IEnumerator sequence)
        {if(!IsTransitioning)StartCoroutine(Transition(sequence));}
        IEnumerator Transition(IEnumerator sequence)
        {IsTransitioning=true;bool fromTitle=State=="title";if(fromTitle)SetTitleActionsEnabled(false);try{yield return sequence;}finally{IsTransitioning=false;if(fromTitle&&State=="title")SetTitleActionsEnabled(modal==null);}}
        public static Vector3 Vector(JToken a)=>new Vector3((float)a[0],(float)a[1],(float)a[2]);
        public static void ApplyPose(Transform transform,JToken pose)
        {transform.localPosition=SourcePose.Position(Vector(pose["position"]));var q=pose["rotation"];transform.localRotation=new Quaternion((float)q[0],-(float)q[1],-(float)q[2],(float)q[3]);transform.localScale=Vector(pose["scale"]);}
        public void OnSignal(string method)
        {
            if(IsTransitioning)return;
            switch(method)
            {
                case "_start_game": if(State=="title")StartTransition(StartJourney());break;
                case "_open_test_room":if(State=="title")StartTransition(LoadTrialsFromTitle());else OpenTrials();break;
                case "_open_settings":ShowTitleModal("SettingsPanel");break;
                case "_open_controls":ShowTitleModal("ControlsPanel");break;
                case "_open_info":ShowTitleModal("InfoPanel");break;
                case "_open_quit_confirmation":ShowTitleModal("QuitConfirmPanel");break;
                case "_close_modal":CloseModal();break;
                case "_confirm_quit":Application.Quit();break;
                case "_choose_dungeon_destination":StartTransition(TravelReliquary());break;
                case "_open_destination_map":OpenMap();break;
                case "_choose_cave_destination":StartTransition(TravelCave());break;
                case "_choose_merchant_destination":if(State=="map")StartTransition(TravelMerchant());break;
            }
        }
        void OpenTrials()
        {game.OpenTrials();}
        public void SuspendForTrials()
        {if(!game.Trials.Active){preserveOriginalContainer=game.OpenChest!=null;if(State=="crafting")Crafting.SavePresentation();}CampUi?.Hide();CampUi?.HidePlacement();if(game.Trials.Active&&State=="cooking")game.Cooking.Close();Cooking?.Hide();Crafting?.Hide();EndNativeTrial(true);returningFromTrials=true;Ui.gameObject.SetActive(false);if(game.DungeonPlayer!=null)game.DungeonPlayer.NativeHud=false;}
        public void BeginNativeCombatTrial()
        {
            SaveNativeTrialPresentation();NativeTrial=true;returningFromTrials=false;motor=game.DungeonPlayer;
            InHideout=false;State="playing";motor.NativeHud=true;motor.Paused=false;motor.Eyes.enabled=true;if(game.Combat!=null)game.Combat.SafeZone=false;
            RestoreWorldPresentation();ResetExpeditionOutcome();CombatHud.ResetSlots();
            Ui.gameObject.SetActive(true);Ui.Visible("title",false);Ui.Visible("hideout",true);Ui.Visible("merchant",false);
            Ui.Visible("DestinationModalScrim",false);Ui.Visible("HideoutPauseOverlay",false);Ui.Visible("HideoutInventoryOverlay",false);
            CombatHud.Tick(0);if(!game.ManualClock)motor.CapturePointer();
        }
        public void BeginNativeInventoryTrial(string id="inventory_details")
        {
            BeginNativeCombatTrial();OpenInventory();
            if(id=="inventory_details")Inventory.ShowDetail(game.Session.Inventory.Slots.FindIndex(s=>(string)s["id"]=="rusted_sword"),"");
        }
        public void BeginNativeSettingsTrial()
        {
            SaveNativeTrialPresentation();Settings.BeginTrial();
            NativeTrial=true;returningFromTrials=false;motor=game.DungeonPlayer;InHideout=true;State="title";
            motor.NativeHud=true;motor.Eyes.enabled=false;motor.ReleasePointer();
            Ui.gameObject.SetActive(true);Ui.Visible("title",true);Ui.Visible("hideout",false);Ui.Visible("merchant",false);
            ShowTitleModal("SettingsPanel");
        }
        public void EndNativeTrial(bool preserveLoot=false)
        {if(!preserveLoot)Settings?.EndTrial();if(!NativeTrial)return;Fingers?.Close();CampUi?.Hide();CampUi?.HidePlacement();game.Cooking?.Close();Cooking?.Hide();Crafting?.Hide();Inventory.Close();if(!preserveLoot&&game.OpenChest!=null)game.CloseLoot();NativeTrial=false;State=priorTrialState;InHideout=priorTrialHideout;RestoreNativeTrialPresentation();returningFromTrials=true;Ui.gameObject.SetActive(false);}
        void ClearDroppedPackages()
        {foreach(var item in game.DungeonRoot.GetComponentsInChildren<DroppedItem>(true)){item.gameObject.SetActive(false);Destroy(item.gameObject);}}
        IEnumerator Fade(float target,float duration)
        {
            var image=Ui.Find("HideoutSceneFade")?.GetComponent<Image>();
            if(image==null)yield break;image.gameObject.SetActive(true);float initial=image.color.a;
            for(float time=0;time<duration;time+=Time.unscaledDeltaTime){image.color=new Color(0,0,0,Mathf.Lerp(initial,target,time/duration));yield return null;}
            image.color=new Color(0,0,0,target);
        }
        IEnumerator StartJourney()
        {
            game.StartNativeJourney();State="transition";yield return Fade(1,.25f);yield return LoadPrepared("hideout",EnterHideout);yield return Fade(0,.25f);
        }
        void BindHideoutLighting(GameObject root)
        {
            Cooking?.BindWorld(root);flicker.Clear();elapsed=0;
            HideoutStructure.Ensure(root,data);
            hideoutMotion=root.GetComponent<HideoutAmbientMotion>();if(hideoutMotion!=null)hideoutMotion.Apply(0);
            foreach(var entry in data["animations"]["flicker_lights"])
            {var light=root.GetComponentsInChildren<Light>(true).FirstOrDefault(l=>l.name==((string)entry["light"]).Replace('/','_'));if(light!=null)flicker.Add((light,(float)entry["base"],(float)entry["phase"]));}
        }
        void BindHideoutInteractions(GameObject root)
        {
            if(root.GetComponentInChildren<HideoutInteraction>(true)!=null)return;
            foreach(var definition in data["interactions"])
            {var node=new GameObject((string)definition["action"]+"Interaction");node.transform.SetParent(root.transform,false);ApplyPose(node.transform,definition["transform"]);node.AddComponent<HideoutInteraction>().Configure(game,this,definition);}
        }
        public void EnterHideout()
        {
            Ui.Visible("merchant",false);ResetExpeditionOutcome();ClearDroppedPackages();
            game.Interaction?.Cancel();game.Combat?.Cancel();
            SwitchNativeWorld(HideoutRoot,HideoutTemplate);BindHideoutInteractions(game.DungeonRoot);BindHideoutLighting(game.DungeonRoot);
            game.DungeonRoot.GetComponent<HideoutStructure>().ResetVisits();
            InHideout=true;State="playing";modal=null;game.Combat.SafeZone=true;
            motor.ResetTrial(Vector(data["spawn"]["position"]));game.DungeonRoot.SetActive(true);motor.Eyes.nearClipPlane=(float)data["camera"]["near"];motor.Eyes.farClipPlane=(float)data["camera"]["far"];
            motor.Eyes.depthTextureMode|=DepthTextureMode.Depth;motor.NativeHud=true;motor.Paused=false;motor.CapturePointer();
            Ui.Visible("title",false);Ui.Visible("hideout",true);Ui.Visible("DestinationModalScrim",false);Ui.Visible("HideoutPauseOverlay",false);Ui.Visible("HideoutInventoryOverlay",false);
            RestoreWorldPresentation();motor.GetComponent<PlayerPresentation>().UpdatePose();game.EnsureNativePettingPet();Notice("침수된 순례자 납골당 · 아무도 원하지 않아 당신에게 남은 은신처",3.2f);
        }
        IEnumerator TravelReliquary()
        {
            if(State!="map"&&State!="merchant"&&State!="restart")yield break;State="transition";yield return Fade(1,.25f);ClearDroppedPackages();Ui.Visible("merchant",false);
            yield return LoadPrepared("main",()=>{
            SwitchNativeWorld(ReliquaryRoot,ReliquaryTemplate);game.EnterReliquary();
            InHideout=false;State="playing";modal=null;game.Combat.SafeZone=false;game.DungeonRoot.SetActive(true);motor.NativeHud=true;motor.Paused=false;motor.CapturePointer();
            CombatHud?.ResetSlots();ResetExpeditionOutcome();
            Ui.Visible("DestinationModalScrim",false);ApplyReliquaryEnvironment();
            });
            yield return Fade(0,.25f);
        }
        void ApplyEnvironment(JToken environment)
        {
            RenderSettings.ambientMode=AmbientMode.Flat;RenderSettings.ambientLight=(SourceUi.ColorOf(environment["ambient_light_color"]).linear*(float)environment["ambient_light_energy"]).gamma;
            RenderSettings.reflectionIntensity=0;
            RenderSettings.fog=(bool)environment["fog_enabled"];RenderSettings.fogMode=FogMode.Exponential;
            RenderSettings.fogDensity=(float)environment["fog_density"];SourceEnvironmentColors.Apply(motor.Eyes,environment);SourceGeometryFog.Configure(environment);
            SourceSceneRenderer.Ensure(motor.GetComponent<PlayerPresentation>()).Configure(environment);
        }
        public void ApplyReliquaryEnvironment(DungeonMotor target=null)
        {
            var player=target??motor;
            if(player.GetComponentInParent<NativeTrialWorld>() is NativeTrialWorld trial){trial.ApplyEnvironment(player);return;}
            RenderSettings.ambientMode=AmbientMode.Flat;RenderSettings.ambientLight=(new Color(.115f,.17f,.19f).linear*.34f).gamma;
            RenderSettings.reflectionIntensity=0;RenderSettings.fog=true;RenderSettings.fogMode=FogMode.Exponential;
            RenderSettings.fogDensity=.016f;
            SourceEnvironmentColors.Apply(player.Eyes,new Color(.006f,.009f,.013f),1,true,new Color(.045f,.092f,.1f),.46f,1);SourceGeometryFog.Reliquary();
            SourceSceneRenderer.Ensure(player.GetComponent<PlayerPresentation>()).Reliquary();
        }
        void ShowTitleModal(string panel)
        {if(modal==null)returnTitleFocus=UnityEngine.EventSystems.EventSystem.current.currentSelectedGameObject;RestoreTitleModal(panel);motor.ReleasePointer();FocusTitleModal(panel);}
        void RestoreTitleModal(string panel)
        {
            modal=panel;bool open=!string.IsNullOrEmpty(panel)&&panel!="destination";
            Ui.Visible("ModalScrim",open);
            foreach(string name in new[]{"SettingsPanel","ControlsPanel","InfoPanel","QuitConfirmPanel"})Ui.Visible(name,open&&name==panel);
            SetTitleActionsEnabled(!open&&!IsTransitioning);
        }
        public void OpenMap(){if(IsTransitioning||State!="playing"||!InHideout)return;motor.PrepareForInventory();State="map";modal="destination";motor.Paused=true;motor.ReleasePointer();Ui.Visible("DestinationModalScrim",true);Ui.Visible("DestinationPanel",true);FocusDestinationMap();}
        void CloseModal(){if(GameplaySettingsOpen){RestoreTitleModal(null);UnityEngine.EventSystems.EventSystem.current.SetSelectedGameObject(null);Resume();return;}if(NativeTrial&&game.Trials.CurrentEntry=="native_settings"){game.OpenTrials();return;}if(modal=="destination"){Ui.Visible("DestinationModalScrim",false);Ui.Visible("DestinationPanel",false);State="playing";modal=null;UnityEngine.EventSystems.EventSystem.current.SetSelectedGameObject(null);motor.Paused=game.SimulationPaused;motor.CapturePointer();}else {RestoreTitleModal(null);UnityEngine.EventSystems.EventSystem.current.SetSelectedGameObject(returnTitleFocus!=null&&returnTitleFocus.activeInHierarchy?returnTitleFocus:Ui.Find("StartGameButton").gameObject);}}
        void Pause()
        {
            State="paused";game.Items?.Cancel();
            if(!InHideout){game.Camp?.Cancel("야영을 중단하고 일시정지했습니다");CampUi?.Hide();CampUi?.HidePlacement();game.Interaction?.Cancel();motor.GetComponent<PlayerPresentation>()?.EndChest();game.Bow?.Cancel();game.Flail?.Cancel();}
            motor.Paused=true;motor.ReleasePointer();Ui.Visible("HideoutPauseOverlay",InHideout);CombatHud?.Tick(0);
        }
        void Resume(){State="playing";Ui.Visible("HideoutPauseOverlay",false);if(InHideout)UnityEngine.EventSystems.EventSystem.current.SetSelectedGameObject(null);motor.Paused=game.SimulationPaused;motor.CapturePointer();CombatHud?.Tick(0);}
        public void OpenInventory()
        {
            if(IsTransitioning)return;
            if(State=="camp")game.Camp.Leave("가방을 열어 자리에서 일어났습니다");
            if(game.Camp?.Activity.State=="placing")game.Camp.Cancel("가방을 열어 설치를 취소했습니다");
            if(State!="playing")return;motor.GetComponent<PlayerPresentation>()?.Torch?.CancelIgnition();motor.PrepareForInventory();State="inventory";motor.ReleasePointer();Inventory.Open();
        }
        public void OpenLoot(DungeonChest chest){State="inventory";motor.ReleasePointer();Inventory.OpenContainer(chest.Container);}
        public void CloseInventory(){Inventory.Close();if(game.OpenChest!=null)game.CloseLoot();State="playing";motor.CapturePointer();}
        public void ClearSceneMessages()
        {eventTime=0;foreach(string id in new[]{"HideoutEvent","Dungeon_event_label","InteractionPrompt","Dungeon_prompt_label"})Ui.Text(id,"");}
        public void Notice(string message,float seconds=2.4f){Ui.Text("HideoutEvent",message);Ui.Text("Dungeon_event_label",message);eventTime=seconds;}
        public void Activate(string action)
        {
            if(IsTransitioning)return;
            switch(action)
            {
                case "travel":OpenMap();break;
                case "rest":StartTransition(Rest());break;
                case "stash":OpenInventory();break;
                case "workbench":OpenCrafting("weapon");break;
                case "alchemy":OpenCrafting("consumable");break;
                case "meal":OpenCooking();break;
                case "hearth":ToggleHearth();break;
                case "wash":Notice("차가운 빗물로 피와 먼지를 씻었습니다",1.8f);break;
                case "storage":Notice("선반 대부분이 비어 있습니다 · 보급품이 쌓이면 이 방도 살아날 것입니다");break;
                case "flooded_store":Notice("배수 장치가 고장 나 있습니다 · 물을 빼면 재배실로 쓸 수 있습니다");break;
                case "ossuary_gate":Notice("납골당의 봉인이 안쪽에서 맥박칩니다 · 은신처 2단계에서 개방",2.5f);break;
                case "drain_gate":Notice("이 수로는 늪지대로 이어집니다 · 배수문 복구 후 보조 출구로 사용 가능",2.5f);break;
                default:Notice("이 작업대의 원본 상호작용을 Unity로 연결 중입니다.");break;
            }
        }
        IEnumerator Rest()
        {State="resting";yield return Fade(1,.34f);yield return new WaitForSecondsRealtime(.28f);game.Items.RestoreHealth(game.Session.Body.MaximumHealth);motor.RestoreStamina(100);yield return Fade(0,.48f);State="playing";Notice("축축한 침상에서도 잠은 들었습니다 · 몸과 원정 장비를 추슬렀습니다");}
    }

    public sealed class HideoutInteraction : DungeonInteractable
    {
        public string Action {get;private set;}
        public float Duration {get;private set;}
        public double ActiveDuration {get;private set;}
        public double Elapsed {get;private set;}
        public string Title=>label;
        string label; NativeGameFlow flow; DungeonMotor actor;
        public override bool Busy=>actor!=null;
        public override string Prompt=>Busy?label+" 중...":Duration>0?$"[E] {label} · {Duration:0.0}초":"[E] "+label;
        public void Configure(WorkshopController game,NativeGameFlow owner,JToken definition)
        {Game=game;flow=owner;Action=(string)definition["action"];label=Action=="workbench"?"제작대 · 무기·갑옷 제작":Action=="alchemy"?"제작대 · 물약 제작":(string)definition["prompt"];Duration=(float)definition["duration"];CreateFocus(new Bounds(SourcePose.Position(NativeGameFlow.Vector(definition["offset"])),NativeGameFlow.Vector(definition["size"])));}
        public override bool Interact(DungeonMotor player)
        {
            if(Busy||!Available(player))return false;if(Duration<=0){flow.Activate(Action);return true;}
            if(player.TimedInteraction||!double.IsFinite(Duration)||Game.Combat.State!="ready")return false;
            actor=player;ActiveDuration=Math.Max(0,Duration*Math.Max(0,player.InteractionDurationScale));Elapsed=0;
            player.ActiveHideoutInteraction=this;player.TimedInteraction=true;player.Blocking=false;player.StopPlanarMovement();
            flow.RefreshHideoutInteractionHud();if(ActiveDuration<=0)Advance(0);return true;
        }
        public override void Cancel(DungeonMotor player)
        {
            if(actor==null)return;
            if(actor.ActiveHideoutInteraction==this){actor.TimedInteraction=false;actor.ActiveHideoutInteraction=null;}
            actor=null;Elapsed=ActiveDuration=0;flow.RefreshHideoutInteractionHud();
        }
        public override void Advance(double delta)
        {
            if(!Busy||Game.SimulationPaused||!double.IsFinite(delta))return;
            Elapsed=Math.Min(ActiveDuration,Elapsed+Math.Max(0,delta));flow.RefreshHideoutInteractionHud();
            if(Elapsed<ActiveDuration)return;Cancel(actor);flow.Activate(Action);
        }
        void OnDestroy(){if(actor!=null)Cancel(actor);}
    }
}
