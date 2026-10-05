using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using Newtonsoft.Json.Linq;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;
namespace MusimusihanRpg.Gameplay
{
    /// <summary>Original measured F2 controls operating on the isolated live expedition.</summary>
    public sealed class NativeTrialMenu:MonoBehaviour
    {
        public SourceUi Ui {get;private set;}
        public int Category {get;private set;}
        public bool AllowDesktopPointer=>!Application.isBatchMode&&game!=null&&!game.ManualClock&&game.DungeonPlayer?.ManualClock!=true;
        public bool NumberDragging=>GetComponentsInChildren<TrialSpinArrow>().Any(a=>a.Dragging);
        public bool ConsumeNavigationKey(KeyCode key)
        {
            if(NumberDragging)return true;
            var selected=EventSystem.current?.currentSelectedGameObject;
            var field=selected!=null&&selected.transform.IsChildOf(Ui.transform)?selected.GetComponent<TrialNumberInput>():null;
            return key==KeyCode.Escape&&field!=null&&field.ConsumeEscape();
        }
        public readonly Dictionary<string,SourceSettingsSlider> Sliders=new Dictionary<string,SourceSettingsSlider>();
        public readonly Dictionary<string,InputField> Numbers=new Dictionary<string,InputField>();
        readonly Dictionary<string,double> values=new Dictionary<string,double>();
        readonly Dictionary<string,string> pending=new Dictionary<string,string>();
        readonly Dictionary<string,string> featureIds=new Dictionary<string,string>();
        static readonly string[] Stats={"health","stamina","hunger","thirst","stress"};
        WorkshopController game;JObject source;bool syncing,shown;Dropdown bodyParts;string[] bodyIds;
        public void Initialize(WorkshopController controller)
        {
            game=controller;source=JObject.Parse(Resources.Load<TextAsset>("Migration/Trials/trials").text);
            Ui=new GameObject("OriginalTrialUI").AddComponent<SourceUi>();Ui.transform.SetParent(transform,false);
            var native=game.NativeGame;Ui.RegularFont=native?.RegularFont;Ui.LightFont=native?.LightFont;Ui.MediumFont=native?.MediumFont;
            var controls=new JArray(source["layouts"].SelectMany(x=>x.Children()).Select(x=>x.DeepClone()));
            var settings=game.Catalog.TestRoomEntries.OfType<JObject>().FirstOrDefault(e=>(string)e["id"]=="native_settings");
            if(settings!=null)
            {
                var rows=controls.OfType<JObject>().Where(e=>((string)e["path"]).StartsWith("trial/category_4/")&&((string)e["name"]).StartsWith("Feature_")).ToArray();
                var extra=(JObject)rows.Last().DeepClone();var at=(JArray)extra["rect"];at[1]=rows.Max(e=>(float)e["rect"][1]+(float)e["rect"][3])+7;
                string oldName=(string)extra["name"];extra["name"]="Feature_native_settings";extra["path"]=((string)extra["path"]).Replace(oldName,"Feature_native_settings");extra["text"]=settings["title"]+"\n"+settings["detail"];controls.Add(extra);
                var content=controls.OfType<JObject>().First(e=>((string)e["path"]).StartsWith("trial/category_4/")&&(string)e["name"]=="TrialEntries");content["rect"][3]=(float)at[1]+(float)at[3]-(float)content["rect"][1];
            }
            LabradorPettingAssets.AddTrialControls(controls,game.Catalog.TestRoomEntries);
            ApplyCurrentTrialEntries(controls);
            Ui.Build(controls,game.KoreanFont??Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf"),Array.Empty<SourceUi.TextureBinding>());
            Ui.Camera.depth=110;Ui.Renderer.Output.depth=111;
            foreach(var entry in game.Catalog.TestRoomEntries.OfType<JObject>())featureIds["Feature_"+((string)entry["id"]).Replace(':','_')]=(string)entry["id"];
            foreach(var pair in Ui.Nodes)
            {
                var rect=pair.Value;var button=rect.GetComponent<Button>();if(button==null)continue;
                button.onClick.RemoveAllListeners();string name=rect.name;
                if(name.StartsWith("TrialCategory_")){int index=int.Parse(name.Substring(14));button.onClick.AddListener(()=>SelectCategory(index));}
                else if(name=="TrialStatsButton")button.onClick.AddListener(FocusStatus);
                else if(name=="TrialAction_0")button.onClick.AddListener(()=>{CommitPending();game.ResumeTrial();});
                else if(name=="TrialAction_1")button.onClick.AddListener(()=>{CommitPending();game.RecoverTrialStatus();Refresh();});
                else if(name=="TrialAction_2")button.onClick.AddListener(()=>{CommitPending();game.ResetTrialLoadout();Refresh();});
                else if(name=="TrialAction_3")button.onClick.AddListener(()=>{CommitPending();game.EndTrials();});
                else if(featureIds.TryGetValue(name,out var id)){var text=rect.GetComponentInChildren<Text>();text.rectTransform.offsetMin=new Vector2(12,0);text.rectTransform.offsetMax=new Vector2(-12,0);button.onClick.AddListener(()=>{CommitPending();game.RunTrial(id);});}
            }
            BuildStats();SelectCategory(0);Ui.gameObject.SetActive(false);
        }
        void ApplyCurrentTrialEntries(JArray controls)
        {
            var live=new HashSet<string>(game.Catalog.TestRoomEntries.OfType<JObject>().Select(e=>"Feature_"+((string)e["id"]).Replace(':','_')));
            var rows=controls.OfType<JObject>().Where(e=>((string)e["name"]).StartsWith("Feature_")).ToArray();
            var crafting=game.Catalog.TestRoomEntries.OfType<JObject>().FirstOrDefault(e=>NativeGameFlow.IsCraftingTrial((string)e["id"]));
            if(crafting!=null&&!rows.Any(e=>(string)e["name"]=="Feature_simple_crafting"))
            {
                var template=rows.First(e=>(string)e["name"]=="Feature_smithing_forge");
                var extra=(JObject)template.DeepClone();
                extra["name"]="Feature_simple_crafting";
                extra["path"]=((string)extra["path"]).Replace("Feature_smithing_forge","Feature_simple_crafting");
                extra["text"]=crafting["title"]+"\n"+crafting["detail"];
                extra["signals"]=new JArray();controls.Add(extra);
            }
            foreach(var row in rows.Where(e=>!live.Contains((string)e["name"])))row.Remove();
            var counts=new int[5];
            for(int category=0;category<5;category++)
            {
                string prefix="trial/category_"+category+"/";
                var current=controls.OfType<JObject>().Where(e=>((string)e["path"]).StartsWith(prefix)&&((string)e["name"]).StartsWith("Feature_")).OrderBy(e=>(float)e["rect"][1]).ToArray();
                counts[category]=current.Length;if(current.Length==0)continue;
                float y=(float)current[0]["rect"][1];
                foreach(var row in current){row["rect"][1]=y;y+=(float)row["rect"][3]+7;}
                var content=controls.OfType<JObject>().First(e=>((string)e["path"]).StartsWith(prefix)&&(string)e["name"]=="TrialEntries");
                content["rect"][3]=y-7-(float)content["rect"][1];
            }
            foreach(var tab in controls.OfType<JObject>().Where(e=>((string)e["name"]).StartsWith("TrialCategory_")))
            {
                int index=int.Parse(((string)tab["name"]).Substring(14));
                string label=((string)tab["text"]).Split(new[]{' '},StringSplitOptions.RemoveEmptyEntries)[0];
                tab["text"]=label+"  "+counts[index];
            }
        }
        RectTransform Node(string name,int category=-1)=>Ui.Nodes.Values.FirstOrDefault(x=>x.name==name&&Ui.Nodes.First(p=>p.Value==x).Key.StartsWith("trial/category_"+(category<0?Category:category)+"/"));
        public void SelectCategory(int category)
        {
            CommitPending();Category=Mathf.Clamp(category,0,4);for(int i=0;i<5;i++){Ui.Find("trial/category_"+i).gameObject.SetActive(i==Category);for(int j=0;j<5;j++){var style=Node("TrialCategory_"+j,i).GetComponent<SourceButtonStyle>();style.OnPointerExit(null);style.OnDeselect(null);style.SetPressed(j==Category);}}
            var scroll=Node("TrialScroll").GetComponent<ScrollRect>();scroll.verticalNormalizedPosition=1;Refresh();
            if(shown&&EventSystem.current!=null)EventSystem.current.SetSelectedGameObject(Node("TrialCategory_"+Category).gameObject);
        }
        public void FocusStatus(){SelectCategory(2);if(EventSystem.current!=null)EventSystem.current.SetSelectedGameObject(Sliders["stress"].gameObject);}
        void LateUpdate()
        {
            bool visible=game.Trials.Active&&game.Trials.MenuOpen&&game.Gallery==null;
            if(visible!=shown){if(!visible)CommitPending();shown=visible;Ui.gameObject.SetActive(visible);if(visible)Refresh();}
            if(!visible)return;
            game.View.Canvas.gameObject.SetActive(false);game.View.UICamera.gameObject.SetActive(false);
        }
        void BuildStats()
        {
            var settings=JObject.Parse(Resources.Load<TextAsset>("Migration/Settings/settings").text);
            Texture2D Icon(string name)=>Resources.Load<Texture2D>("Migration/Settings/"+Path.GetFileNameWithoutExtension((string)settings["icons"][name]["texture"]));
            foreach(string id in Stats)
            {
                var rect=Node("StatusSlider_"+id,2);var target=rect.gameObject.AddComponent<Image>();target.color=Color.clear;
                var slider=rect.gameObject.AddComponent<SourceSettingsSlider>();slider.targetGraphic=target;slider.transition=Selectable.Transition.None;slider.minValue=id=="health"?1:0;slider.maxValue=id=="health"?(float)game.Session.Body.MaximumHealth:100;
                slider.Configure((JObject)settings["styles"],Icon("grabber"),Icon("grabber_highlight"),Icon("grabber_disabled"));Sliders[id]=slider;
                var sliderDefinition=Ui.Definition(Ui.Nodes.First(p=>p.Value==rect).Key);var tick=Resources.Load<Texture2D>("Migration/Trials/"+Path.GetFileNameWithoutExtension((string)sliderDefinition["tick_icon"]));
                for(int i=0;i<11;i++){var t=NativeSettings.Child(rect,"Tick_"+i);t.anchorMin=t.anchorMax=new Vector2(i/10f,.5f);t.pivot=new Vector2(.5f,1);t.anchoredPosition=new Vector2(8-16*i/10f,-4);t.sizeDelta=new Vector2(tick.width,tick.height);var mark=t.gameObject.AddComponent<RawImage>();mark.texture=tick;mark.raycastTarget=false;}

                slider.onValueChanged.AddListener(value=>Choose(id,value));slider.ExplicitSelection=value=>Choose(id,value);
                var input=Node("StatusNumber_"+id,2).GetComponent<InputField>();input.contentType=InputField.ContentType.Standard;input.characterLimit=32;Numbers[id]=input;
                var numberRect=(RectTransform)input.transform;var definition=Ui.Definition(Ui.Nodes.First(p=>p.Value==numberRect).Key);
                numberRect.GetComponent<SourcePanel>().Style(null);var background=NativeSettings.Child(numberRect,"NumberEditBackground");background.SetAsFirstSibling();background.anchorMin=background.anchorMax=background.pivot=new Vector2(0,1);background.sizeDelta=new Vector2((float)definition["edit_size"][0],(float)definition["edit_size"][1]);
                var panel=background.gameObject.AddComponent<SourcePanel>();panel.Style((JObject)definition["normal"]);panel.raycastTarget=true;input.targetGraphic=panel;input.textComponent.alignment=TextAnchor.MiddleCenter;input.textComponent.rectTransform.offsetMax=new Vector2(-18,0);
                foreach(int direction in new[]{1,-1})
                {
                    string key=direction>0?"up":"down";var area=NativeSettings.Child(numberRect,"Number_"+key);area.anchorMin=area.anchorMax=new Vector2(1,direction>0?1:.5f);area.pivot=new Vector2(1,1);area.sizeDelta=new Vector2(18,19);var hit=area.gameObject.AddComponent<Image>();hit.color=Color.clear;
                    var icon=NativeSettings.Child(area,"Icon");icon.anchorMin=icon.anchorMax=new Vector2(.5f,.5f);icon.sizeDelta=new Vector2(16,8);var image=icon.gameObject.AddComponent<RawImage>();image.raycastTarget=false;image.texture=Resources.Load<Texture2D>("Migration/Trials/"+Path.GetFileNameWithoutExtension((string)definition["spin_icons"][key]));
                    var arrow=area.gameObject.AddComponent<TrialSpinArrow>();arrow.Owner=this;arrow.Stat=id;arrow.Direction=direction;arrow.Icon=image;arrow.Colors=(JObject)definition["spin_colors"];
                }
                input.onValueChanged.AddListener(text=>{if(!syncing)pending[id]=text;});
                input.onSubmit.AddListener(_=>Commit(id,true));
                input.onEndEdit.AddListener(_=>{if(!(input is TrialNumberInput number)||!number.SuppressEndCommit)Commit(id);});
                if(input is TrialNumberInput numeric)numeric.NavigateTab=reverse=>
                {
                    int index=Array.IndexOf(Stats,id);Selectable next=reverse?Sliders[id]:index+1<Stats.Length?Sliders[Stats[index+1]]:bodyParts;
                    if(next!=null&&next.IsInteractable())EventSystem.current.SetSelectedGameObject(next.gameObject);
                };
                var wheel=input.gameObject.AddComponent<TrialNumberScroll>();wheel.Owner=this;wheel.Stat=id;wheel.Field=input;
            }
            var choice=Node("BodyPartSelector",2);string choicePath=Ui.Nodes.First(p=>p.Value==choice).Key;
            bodyParts=SourceChoice.Build(choice,(JObject)Ui.Definition(choicePath)["normal"],game.KoreanFont??Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf"),14,true);
            ((SourceBodyChoice)bodyParts).Configure(Ui);
            bodyIds=game.Session.Body.Parts.Keys.ToArray();bodyParts.ClearOptions();bodyParts.AddOptions(bodyIds.Select(id=>(string)game.Session.BodySnapshot()["parts"][id]["name"]).ToList());
            bodyParts.onValueChanged.AddListener(i=>{if(!syncing){game.SelectTrialBodyPart(bodyIds[i]);Refresh();}});
            Node("BodyDamage10",2).GetComponent<Button>().onClick.AddListener(()=>{game.DamageTrialBodyPart(SelectedPart(),10);Refresh();});
            Node("BodyBlackout",2).GetComponent<Button>().onClick.AddListener(()=>{string id=SelectedPart();game.DamageTrialBodyPart(id,game.Session.Body.Parts[id]);Refresh();});
            Node("BodyReset",2).GetComponent<Button>().onClick.AddListener(()=>{game.ResetTrialBody();Refresh();});
        }
        // SpinBox's Range emits only when its rounded/clamped stored value
        // changes. A boundary click must leave unfinished text untouched.
        public void AdjustNumberRange(string id,double requested)
        {
            var range=Sliders[id];double value=Math.Clamp(Rounded(requested),range.minValue,range.maxValue);
            if(value!=range.value)Choose(id,value);
        }
        public void Choose(string id,double value)
        {
            if(syncing)return;pending.Remove(id);
            if(values.TryGetValue(id,out double previous)&&previous!=value)game.SetTrialStat(id,value);
            Refresh();
        }
        static double Rounded(double value)=>Math.Round(value,MidpointRounding.AwayFromZero);
        public void Commit(string id,bool explicitSubmit=false)
        {
            if(syncing||!values.ContainsKey(id))return;
            string text=pending.TryGetValue(id,out var edit)?edit:Numbers[id].text;
            if(!explicitSubmit&&!pending.ContainsKey(id)&&text.Trim()==Rounded(values[id]).ToString(CultureInfo.InvariantCulture))return;
            double value=values[id];if(double.TryParse(text.Trim(),NumberStyles.Float,CultureInfo.InvariantCulture,out var parsed)&&double.IsFinite(parsed))value=Math.Clamp(Rounded(parsed),Sliders[id].minValue,Sliders[id].maxValue);
            Choose(id,value);
        }
        public void CommitPending(){if(syncing)return;foreach(var arrow in GetComponentsInChildren<TrialSpinArrow>(true))arrow.StopPointerGesture();foreach(string id in Stats)if(Numbers.ContainsKey(id))Commit(id);}
        string SelectedPart()=>game.Session.Body.Parts.ContainsKey(game.Session.Body.SelectedPart)?game.Session.Body.SelectedPart:game.Session.Body.Parts.Keys.First();
        public void Refresh()
        {
            if(Ui==null||game.Session==null)return;syncing=true;
            try
            {
                var snapshot=game.TrialStatusSnapshot();foreach(string id in Stats)
                {
                    values[id]=(double)snapshot[id];if(pending.ContainsKey(id))continue;
                    Sliders[id].SetValueWithoutNotify((float)values[id]);Numbers[id].SetTextWithoutNotify(Rounded(values[id]).ToString(CultureInfo.InvariantCulture));
                    Sliders[id].interactable=Numbers[id].interactable=game.CanAdjustTrialStatus;
                }
                string part=SelectedPart();var state=(JObject)snapshot["body"]["parts"][part];
                bodyParts.SetValueWithoutNotify(Array.IndexOf(bodyIds,part));bodyParts.RefreshShownValue();bodyParts.interactable=game.CanAdjustTrialStatus;
                string conditions=string.Join(" · ",((JObject)state["conditions"]).Properties().Select(p=>(string)game.Catalog.Survival["CONDITION_DISPLAY_NAMES"]?[p.Name]??p.Name));
                Node("BodyPartReadout",2).GetComponentInChildren<Text>().text=$"{Rounded((double)state["health"])} / {Rounded((double)state["max_health"])} · {((bool)state["blacked"]?"회복 불가":"치료 가능")}"+(conditions.Length>0?" · "+conditions:"");
                foreach(string id in new[]{"BodyDamage10","BodyReset"})Node(id,2).GetComponent<Button>().interactable=game.CanAdjustTrialStatus;
                Node("BodyBlackout",2).GetComponent<Button>().interactable=game.CanAdjustTrialStatus&&!(bool)state["blacked"];
                var runnable=new HashSet<string>(game.Trials.RunnableEntries.Select(e=>(string)e["id"]));
                foreach(var pair in Ui.Nodes)
                {
                    var button=pair.Value.GetComponent<Button>();if(button==null)continue;
                    if(featureIds.TryGetValue(pair.Value.name,out var id))button.interactable=runnable.Contains(id);
                    if(pair.Value.name=="TrialAction_0")button.interactable=game.Trials.Active;
                    if(pair.Value.name=="TestStatus")pair.Value.GetComponentInChildren<Text>().text=game.Message;
                }
                var label=Node("TestStatus");if(label!=null)label.GetComponentInChildren<Text>().text=game.Message;
            }
            finally{syncing=false;}
        }
    }
}
