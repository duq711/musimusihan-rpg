using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using TMPro;
using UnityEngine;
using UnityEngine.EventSystems;

namespace MusimusihanRpg.GothicOrigin
{
    public sealed class OriginUi : MonoBehaviour
    {
        OriginGame game;public Canvas Canvas;RectTransform screen,hud,overlay,design;TMP_FontAsset sans,serif,display;
        TextMeshProUGUI health,stamina,potions,room,quest,prompt,message;UnityEngine.UI.Image healthFill,staminaFill,damage;
        readonly Color paper=new Color(.87f,.81f,.66f),gold=new Color(.68f,.51f,.28f),ink=new Color(.025f,.041f,.05f),red=new Color(.63f,.20f,.18f);float flash;
        public int ButtonCount=>overlay.GetComponentsInChildren<UnityEngine.UI.Button>().Length;
        public void Initialize(OriginGame owner)
        {
            game=owner;sans=Resources.Load<TMP_FontAsset>("OriginSans");serif=Resources.Load<TMP_FontAsset>("OriginSerif");display=Resources.Load<TMP_FontAsset>("OriginDisplay");
            var root=new GameObject("GothicCanvas",typeof(RectTransform),typeof(Canvas),typeof(UnityEngine.UI.CanvasScaler),typeof(UnityEngine.UI.GraphicRaycaster));root.layer=5;Canvas=root.GetComponent<Canvas>();Canvas.renderMode=RenderMode.ScreenSpaceOverlay;Canvas.sortingOrder=10;
            var scaler=root.GetComponent<UnityEngine.UI.CanvasScaler>();scaler.uiScaleMode=UnityEngine.UI.CanvasScaler.ScaleMode.ConstantPixelSize;scaler.scaleFactor=1;
            var content=new GameObject("Fitted1920Layout",typeof(RectTransform));design=content.GetComponent<RectTransform>();design.SetParent(root.transform,false);design.anchorMin=design.anchorMax=design.pivot=new Vector2(.5f,.5f);design.sizeDelta=new Vector2(1920,1080);screen=design;Fit();
            if(FindFirstObjectByType<EventSystem>()==null)new GameObject("EventSystem",typeof(EventSystem),typeof(StandaloneInputModule));
            hud=Box(screen,"HUD",0,0,1920,1080,Color.clear);BuildHud();overlay=Box(screen,"Menus",0,0,1920,1080,Color.clear);
        }
        void Fit(){if(design==null)return;var available=((RectTransform)Canvas.transform).rect.size;float scale=Mathf.Min(available.x/1920,available.y/1080);design.localScale=Vector3.one*scale;}
        void LateUpdate()=>Fit();
        RectTransform Box(Transform parent,string name,float x,float y,float w,float h,Color color)
        {
            var n=new GameObject(name,typeof(RectTransform),typeof(UnityEngine.UI.Image));n.layer=5;var r=n.GetComponent<RectTransform>();r.SetParent(parent,false);r.anchorMin=r.anchorMax=new Vector2(0,1);r.pivot=new Vector2(0,1);r.anchoredPosition=new Vector2(x,-y);r.sizeDelta=new Vector2(w,h);var image=n.GetComponent<UnityEngine.UI.Image>();image.color=color;image.raycastTarget=false;return r;
        }
        TextMeshProUGUI Text(Transform parent,string value,float x,float y,float w,float h,float size=24,TMP_FontAsset font=null,Color? color=null,TextAlignmentOptions align=TextAlignmentOptions.TopLeft)
        {
            var n=new GameObject("Text",typeof(RectTransform),typeof(TextMeshProUGUI));n.layer=5;var r=n.GetComponent<RectTransform>();r.SetParent(parent,false);r.anchorMin=r.anchorMax=new Vector2(0,1);r.pivot=new Vector2(0,1);r.anchoredPosition=new Vector2(x,-y);r.sizeDelta=new Vector2(w,h);var t=n.GetComponent<TextMeshProUGUI>();t.font=font??sans;t.text=value;t.fontSize=size;t.color=color??paper;t.alignment=align;t.textWrappingMode=TextWrappingModes.Normal;t.raycastTarget=false;return t;
        }
        void Line(Transform p,float x,float y,float w,Color? color=null)=>Box(p,"Rule",x,y,w,1,color??gold);
        void Button(Transform p,string label,float x,float y,float w,Action action,bool primary=false,bool enabled=true)
        {
            var r=Box(p,"Button "+label,x,y,w,58,primary?paper:new Color(.11f,.15f,.16f,.98f));var b=r.gameObject.AddComponent<UnityEngine.UI.Button>();b.targetGraphic=r.GetComponent<UnityEngine.UI.Image>();b.targetGraphic.raycastTarget=true;var colors=b.colors;colors.normalColor=Color.white;colors.highlightedColor=new Color(1.1f,1.06f,.94f);colors.pressedColor=new Color(.67f,.6f,.48f);b.colors=colors;b.interactable=enabled;b.onClick.AddListener(()=>action());Text(r,label,22,12,w-40,38,23,color:primary?ink:paper);if(!enabled)b.targetGraphic.color=new Color(.10f,.12f,.13f,.6f);
        }
        void Clear(){foreach(Transform n in overlay)Destroy(n.gameObject);}
        void BuildHud()
        {
            var vitals=Box(hud,"Vitals",42,927,425,112,new Color(ink.r,ink.g,ink.b,.86f));Line(vitals,0,0,425);health=Text(vitals,"",18,14,190,24,18);stamina=Text(vitals,"",223,14,180,24,18);Box(vitals,"Health track",18,49,180,7,new Color(.25f,.16f,.14f));healthFill=Box(vitals,"Health",18,49,180,7,red).GetComponent<UnityEngine.UI.Image>();Box(vitals,"Stamina track",223,49,180,7,new Color(.16f,.2f,.18f));staminaFill=Box(vitals,"Stamina",223,49,180,7,new Color(.58f,.62f,.43f)).GetComponent<UnityEngine.UI.Image>();potions=Text(vitals,"",18,75,385,25,18);
            room=Text(hud,"",45,35,600,35,25,serif);quest=Text(hud,"",45,77,900,30,19,color:paper*.9f);Text(hud,"+",945,517,30,35,23,align:TextAlignmentOptions.Center);
            prompt=Text(hud,"",560,820,800,55,25,align:TextAlignmentOptions.Center);message=Text(hud,"",510,145,900,65,26,serif,align:TextAlignmentOptions.Center);
            Text(hud,"Tab 가방    M 지도    J 기록    Esc 메뉴",1260,995,610,35,19,align:TextAlignmentOptions.Right);
            damage=Box(hud,"Damage",0,0,1920,1080,new Color(.5f,0,0,0)).GetComponent<UnityEngine.UI.Image>();
        }
        public void Loading(string label,float progress)
        {
            Clear();var p=Box(overlay,"Loading",0,0,1920,1080,ink);Text(p,"MUSIMUSIHAN",240,270,1450,110,89,display);Text(p,"고딕의 기원",245,390,1000,90,54,serif);Text(p,label,250,690,1250,55,25);Box(p,"Progress track",250,768,1420,3,new Color(.15f,.2f,.21f));Box(p,"Progress",250,768,1420*Mathf.Clamp01(progress),3,gold);Text(p,"UNITY  ·  지하던전 원정",250,810,1200,30,19,color:gold);
        }
        public void Failure(string reason){Clear();var p=Box(overlay,"LoadFailure",0,0,1920,1080,ink);Text(p,"던전을 불러오지 못했습니다",200,300,1500,90,56,serif);Text(p,reason,205,430,1450,240,23);Button(p,"종료",205,740,350,game.Quit);}
        public void Show(string panel)
        {
            Clear();hud.gameObject.SetActive(panel=="");if(panel=="")return;
            if(panel=="title"){Title();return;}if(panel=="map"){Map();return;}
            var shade=Box(overlay,"Shade",0,0,1920,1080,new Color(.015f,.025f,.03f,.86f));var p=Box(shade,"Panel",440,110,1040,870,ink);Line(p,50,55,940);Line(p,50,814,940);
            string title=panel=="pause"?"잠시, 숨을 고르다":panel=="inventory"?"순례자의 가방":panel=="journal"?"돌아오기 위한 기록":panel=="settings"?"설정":panel=="dead"?"이 원정은 여기서 끝났다":panel=="win"?"세 봉인과 함께, 귀환": "원정 안내";
            Text(p,title,60,87,920,82,46,serif);Text(p,"MUSIMUSIHAN  /  GOTHIC ORIGIN",63,175,900,35,17,display,gold);
            if(panel=="pause")
            {Button(p,"원정 계속",60,257,920,game.Resume,true);Button(p,"설정",60,339,920,()=>game.OpenPanel("settings"));Button(p,"저장하고 첫 화면",60,421,920,game.ToTitle);Button(p,"게임 종료",60,503,920,game.Quit);Text(p,"WASD 이동 · Shift 달리기 · 좌클릭 베기 · 우클릭 방패\nE 조사 / 문 · Q 회복약 · Tab 가방 · M 지도 · J 기록",60,635,920,120,23);}
            else if(panel=="inventory")
            {Text(p,$"회복약                         {game.Potions}개\n\n철제 장검                     장착 중\n나무 방패                     장착 중\n\n회수한 봉인                   {game.Relics} / 3\n탐사한 방                      {game.Visited.Count()} / 35",70,265,890,390,28);Button(p,"회복약 사용",60,696,440,()=>{game.Resume();game.Drink();game.OpenPanel("inventory");},true,game.Potions>0&&game.Health<100);Button(p,"원정으로",520,696,460,game.Resume);}
            else if(panel=="journal")
            {Text(p,"우리는 세 개의 봉인을 두고 왔다.\n하단 책장실, 큰 묘실, 대예배당.\n그들을 잠재우고 35번 보급실로 돌아와야 한다.",65,267,900,175,30,serif);Text(p,$"30번  접힌 참회자       {Status(30)}\n23번  매듭 순례자       {Status(23)}\n01번  공허한 종지기    {Status(1)}",65,475,900,160,26);Button(p,"기록 덮기",60,696,920,game.Resume,true);}
            else if(panel=="settings")
            {Text(p,"주 음량",65,265,900,40,26);Button(p,"−",65,325,140,()=>SetVolume(-.1f));Text(p,$"{Mathf.RoundToInt(game.Volume*100)} %",240,339,200,45,25);Button(p,"+",440,325,140,()=>SetVolume(.1f));Button(p,Screen.fullScreen?"창 모드로 전환":"전체 화면으로 전환",65,430,900,()=>{Screen.fullScreen=!Screen.fullScreen;});Text(p,"60 FPS 목표 · 화면 1280 × 900\n설정과 메뉴에서는 전투가 멈춥니다.",65,535,900,110,24);Button(p,"완료",60,696,920,game.Resume,true);}
            else if(panel=="dead")
            {Text(p,"아래에서는 누구도 오래 기다려주지 않는다.\n마지막 저장에서 다시 발을 내딛을 수 있다.",65,280,900,170,30,serif);Button(p,"마지막 저장에서 다시",60,510,920,()=>game.Continue(),true,File.Exists(OriginGame.SavePath));Button(p,"새 원정",60,592,920,game.NewGame);Button(p,"첫 화면",60,674,920,game.ToTitle);}
            else if(panel=="win")
            {Text(p,$"회수한 봉인    3 / 3\n\n탐사한 방       {game.Visited.Count()} / 35\n\n지하의 목소리를 뒤로하고, 빛으로 돌아왔다.",65,265,900,330,31,serif);Button(p,"새 원정",60,614,920,game.NewGame,true);Button(p,"첫 화면",60,696,920,game.ToTitle);}
            else
            {Text(p,"WASD  이동          마우스  시점\nShift  달리기        좌클릭  검 베기\n우클릭  방패         E  조사 / 문 열기\nQ  회복약             Tab  가방\nM  던전 지도         J  원정 기록\nEsc  일시정지",65,260,900,330,29);Button(p,"돌아가기",60,696,920,()=>game.OpenPanel(game.Playing?"pause":"title"),true);}
        }
        string Status(int room)=>game.Foes.First(f=>f.room==room).dead?"회수 완료":"미회수";
        void SetVolume(float add){game.Volume=Mathf.Clamp01(game.Volume+add);AudioListener.volume=OriginGame.Qa?0:game.Volume;PlayerPrefs.SetFloat("OriginVolume",game.Volume);Show("settings");}
        void Title()
        {
            var p=Box(overlay,"Title",0,0,870,1080,new Color(ink.r,ink.g,ink.b,.96f));Box(p,"Gold edge",868,0,2,1080,gold);Text(p,"AN UNDERGROUND CHRONICLE",87,91,730,40,19,display,gold);Text(p,"MUSI\nMUSIHAN",80,193,760,250,104,display);Text(p,"무시무시한 RPG",90,467,690,82,48,serif);Text(p,"고딕의 기원",93,547,690,45,29,serif,gold);Line(p,93,628,670);Text(p,"서른다섯 개의 방. 세 개의 봉인.\n이 지하에서 살아 돌아오십시오.",93,662,680,100,26,serif);Button(p,"새 원정 시작",93,797,670,game.NewGame,true);Button(p,"이어서 하기",93,873,325,()=>game.Continue(),enabled:File.Exists(OriginGame.SavePath));Button(p,"조작 안내",438,873,325,()=>game.OpenPanel("controls"));Button(p,"종료",93,949,670,game.Quit);Text(overlay,"01  /  GOTHIC ORIGIN",1320,1010,530,35,18,display,paper,TextAlignmentOptions.Right);
        }
        void Map()
        {
            var p=Box(overlay,"DungeonMap",60,60,1800,960,ink);Line(p,45,48,1710);Text(p,"지하던전",55,75,1200,75,48,serif);Text(p,"기존 35개 방과 회랑의 배치",58,160,1200,35,23,color:gold);Text(p,"● 현재 위치   ◇ 봉인   ■ 탐사한 방",58,845,1300,45,22);Button(p,"지도 덮기",1340,830,400,game.Resume,true);
            float minX=game.World.RoomBounds.Where(x=>x.Key>0).Min(x=>x.Value.center.x),maxX=game.World.RoomBounds.Where(x=>x.Key>0).Max(x=>x.Value.center.x),minZ=game.World.RoomBounds.Where(x=>x.Key>0).Min(x=>x.Value.center.z),maxZ=game.World.RoomBounds.Where(x=>x.Key>0).Max(x=>x.Value.center.z);
            float scale=Mathf.Min(1480/(maxX-minX+14),560/(maxZ-minZ+14));Vector2 Project(Vector3 at)=>new Vector2(135+(at.x-minX+7)*scale,220+(maxZ-at.z+7)*scale);
            // Exact corridor boundary segments from the preserved map, reflected on X.
            foreach(var segment in game.World.Manifest["corridor"]["boundary_segments"])
            {var a=Project(new Vector3(-(float)segment[0][0],0,(float)segment[0][1]));var b=Project(new Vector3(-(float)segment[1][0],0,(float)segment[1][1]));var r=Box(p,"Corridor",a.x,a.y,Vector2.Distance(a,b),2,new Color(.3f,.34f,.32f));r.localRotation=Quaternion.Euler(0,0,-Mathf.Atan2(b.y-a.y,b.x-a.x)*Mathf.Rad2Deg);}
            foreach(var entry in game.World.RoomBounds.Where(e=>e.Key>0))
            {int id=entry.Key;var at=Project(entry.Value.center);bool seen=game.Visited.Contains(id);var r=Box(p,"Room "+id,at.x-22,at.y-18,44,36,seen?gold:new Color(.15f,.2f,.21f));Text(r,id.ToString("00"),0,3,44,30,18,color:seen?ink:paper,align:TextAlignmentOptions.Center);if(id==1||id==23||id==30)Text(p,"◇",at.x+25,at.y-19,30,30,24,color:gold);}
            var player=Project(game.Body.transform.position);Text(p,"●",player.x-11,player.y-13,28,28,23,color:new Color(.86f,.34f,.23f));
        }
        public void Flash(){flash=.28f;}
        public void Tick()
        {
            if(health==null)return;health.text=$"생명  {Mathf.CeilToInt(game.Health)} / 100";stamina.text=$"기력  {Mathf.CeilToInt(game.Stamina)} / 100";healthFill.rectTransform.SetSizeWithCurrentAnchors(RectTransform.Axis.Horizontal,180*game.Health/100);staminaFill.rectTransform.SetSizeWithCurrentAnchors(RectTransform.Axis.Horizontal,180*game.Stamina/100);potions.text=$"Q  회복약 {game.Potions}개     봉인 {game.Relics} / 3";room.text=OriginGame.RoomName(game.CurrentRoom);quest.text=game.Objective;prompt.text=game.Ready?game.Prompt():"";message.text=game.Message;flash=Mathf.Max(0,flash-Time.unscaledDeltaTime);damage.color=new Color(.55f,.05f,.03f,flash*.55f);
        }
    }
}
