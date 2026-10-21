using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using GLTFast;
using Newtonsoft.Json;
using UnityEngine;

namespace MusimusihanRpg.GothicOrigin
{
    public sealed class OriginGame : MonoBehaviour
    {
        [Serializable] public sealed class SaveData
        {
            public int version=1,potions=3;public float health=100,stamina=100,x,y,z,yaw,pitch;public bool won;
            public List<int> dead=new List<int>(),looted=new List<int>(),visited=new List<int>();
        }
        public sealed class Foe
        {
            public int id,room;public string name;public Transform root,visual;public CharacterController body;public float hp=90,cooldown=1.6f,windup,flash;public bool dead;public Vector3 home;
        }
        public sealed class Cache {public int id,room;public Transform root;public bool taken;}
        public static bool Qa=>Environment.GetCommandLineArgs().Contains("-originQa");
        public static string SavePath=>Qa?Path.Combine(Environment.GetEnvironmentVariable("ORIGIN_QA_DIR")??Path.GetTempPath(),"qa-save.json"):Path.Combine(Application.persistentDataPath,"gothic-origin-v1.json");
        public OriginDungeonWorld World {get;private set;}
        public Camera View {get;private set;}
        public CharacterController Body {get;private set;}
        public OriginUi Ui {get;private set;}
        public OriginPresentation Presentation {get;private set;}
        public OriginSculpt.Gear Gear {get;private set;}
        public readonly List<Foe> Foes=new List<Foe>();public readonly List<Cache> Caches=new List<Cache>();
        readonly List<GltfImport> imports=new List<GltfImport>();readonly HashSet<int> visited=new HashSet<int>();
        public bool Ready,Playing,Won,Dead,Blocking;public string Panel="title",Message="";public float Health=100,Stamina=100,Pitch,Yaw,Volume=.35f;
        public int Potions=3,CurrentRoom=35;
        public int Relics=>Foes.Count(f=>(f.room==1||f.room==23||f.room==30)&&f.dead);
        float vertical,attackTime,attackCooldown,messageUntil,saveAt;int attackSerial;Vector3 swordHome,shieldHome;AudioSource sound;AudioClip hitClip;
        public string Objective=>Relics<3?$"세 봉인을 회수하세요  {Relics} / 3":"35번 보급실의 귀환 표식으로 돌아가세요";
        public IEnumerable<int> Visited=>visited;
        public static readonly Dictionary<int,string> Names=new Dictionary<int,string>{{1,"대예배당"},{6,"높은 도서관"},{15,"작은 석상 제단실"},{23,"큰 묘실"},{26,"작은 촛불 가구방"},{30,"하단 책장실"},{31,"나무 통 보관실"},{32,"나무 작업대실"},{33,"생활관"},{34,"회랑 안쪽"},{35,"보급실 · 귀환 지점"}};
        public static string RoomName(int id)=>Names.TryGetValue(id,out var n)?n:id==0?"지하 회랑":$"던전 {id:00}번 방";
        async void Start()
        {
            Application.runInBackground=true;Application.targetFrameRate=60;QualitySettings.vSyncCount=0;Volume=Mathf.Clamp01(PlayerPrefs.GetFloat("OriginVolume",.35f));AudioListener.volume=Qa?0:Volume;
            var player=new GameObject("Player");Body=player.AddComponent<CharacterController>();Body.height=1.72f;Body.radius=.25f;Body.center=new Vector3(0,.88f,0);Body.stepOffset=.25f;Body.slopeLimit=50;Body.skinWidth=.035f;
            var camera=new GameObject("ExpeditionCamera");camera.transform.SetParent(player.transform,false);camera.transform.localPosition=Vector3.up*1.6f;View=camera.AddComponent<Camera>();View.nearClipPlane=.045f;View.fieldOfView=72;View.allowHDR=false;View.allowMSAA=true;camera.AddComponent<AudioListener>();sound=camera.AddComponent<AudioSource>();
            Ui=gameObject.AddComponent<OriginUi>();Ui.Initialize(this);Presentation=gameObject.AddComponent<OriginPresentation>();Presentation.Initialize(View,Ui.Canvas);Ui.Loading("35개의 방을 불러오고 있습니다",0);
            try
            {
                World=await OriginDungeonWorld.Load(p=>Ui.Loading("기존 던전과 가구를 불러오고 있습니다",p*.8f));World.Activate(View);
                StartPoint=ClearPoint(35);Teleport(StartPoint,World.SpawnRotation.eulerAngles.y);Gear=OriginSculpt.Hands(View.transform);swordHome=Gear.Sword.localPosition;shieldHome=Gear.Shield.localPosition;
                await CreateActors();CreateCaches();CreateReturnMarker();hitClip=MakeTone();Ready=true;Ui.Show("title");
                if(Qa)StartCoroutine(OriginQa.Run(this));
            }
            catch(Exception e){Debug.LogException(e);Ui.Failure(e.Message);if(Qa)Application.Quit(2);}
        }
        async Task CreateActors()
        {
            int[] rooms={30,23,1,6,15,26};string[] files={"folded_penitent","knot_pilgrim","hollow_bell_keeper"};string[] names={"접힌 참회자","매듭 순례자","공허한 종지기"};
            for(int i=0;i<rooms.Length;i++)
            {
                var importer=new GltfImport();imports.Add(importer);var path=Path.Combine(Application.streamingAssetsPath,"GothicActors",files[i%3]+".glb");if(!await importer.Load(path))throw new IOException("Creature load failed: "+files[i%3]);
                var root=new GameObject("Guardian_"+rooms[i]);var visual=new GameObject("AuthoredGothicCreature");visual.transform.SetParent(root.transform,false);await importer.InstantiateMainSceneAsync(visual.transform);OriginPaint.Apply(visual);
                var rr=visual.GetComponentsInChildren<Renderer>();var bounds=rr[0].bounds;foreach(var r in rr)bounds.Encapsulate(r.bounds);float scale=1.95f/bounds.size.y;visual.transform.localScale=Vector3.one*scale;visual.transform.localPosition=new Vector3(-bounds.center.x,-bounds.min.y,-bounds.center.z)*scale;
                var at=ClearPoint(rooms[i]);root.transform.position=at;root.layer=9;var body=root.AddComponent<CharacterController>();body.height=1.9f;body.center=Vector3.up*.96f;body.radius=.31f;body.stepOffset=.2f;body.slopeLimit=50;
                Foes.Add(new Foe{id=i,room=rooms[i],name=names[i%3],root=root.transform,visual=visual.transform,body=body,home=at});Ui.Loading("고딕의 주민들을 깨우고 있습니다",.8f+(i+1)/6f*.2f);
            }
        }
        public Vector3 ClearPoint(int room)
        {
            var center=World.RoomCenter(room);for(int ring=0;ring<9;ring++)for(int d=0;d<12;d++)
            {
                var p=center+new Vector3(Mathf.Sin(d*Mathf.PI/6)*ring*.45f,0,Mathf.Cos(d*Mathf.PI/6)*ring*.45f);
                if(!Physics.Raycast(p+Vector3.up*.7f,Vector3.down,out var floor,1.4f,1<<OriginDungeonWorld.WorldLayer)||floor.normal.y<.7f)continue;
                p.y=floor.point.y+.06f;if(p.y>.65f||p.y<-.5f)continue;
                if(!Physics.CheckCapsule(p+Vector3.up*.4f,p+Vector3.up*1.5f,.3f,1<<OriginDungeonWorld.WorldLayer))return p;
            }
            center.y=.1f;return center;
        }
        void CreateCaches()
        {
            int[] rooms={35,31,32,33,34,3,9,18,27};var paper=OriginPaint.Solid("Ochre supply seal",new Color(.8f,.61f,.28f));
            for(int i=0;i<rooms.Length;i++)
            {
                var p=ClearPoint(rooms[i]);p+=new Vector3(.6f,.3f,.3f);var node=GameObject.CreatePrimitive(PrimitiveType.Cube);node.name="Supply seal "+rooms[i];Destroy(node.GetComponent<Collider>());node.transform.position=p;node.transform.localScale=new Vector3(.24f,.3f,.08f);node.GetComponent<Renderer>().sharedMaterial=paper;Caches.Add(new Cache{id=i,room=rooms[i],root=node.transform});
            }
        }
        public Transform ReturnMarker;public Vector3 StartPoint;
        void CreateReturnMarker()
        {
            var node=GameObject.CreatePrimitive(PrimitiveType.Cylinder);node.name="Return seal";Destroy(node.GetComponent<Collider>());node.transform.position=StartPoint+Vector3.up*.04f;node.transform.localScale=new Vector3(.9f,.025f,.9f);node.GetComponent<Renderer>().sharedMaterial=OriginPaint.Solid("Sanctuary gold",new Color(.8f,.61f,.3f),.4f);ReturnMarker=node.transform;
        }
        void Update()
        {
            if(!Ready)return;if(!Qa)ReadInput();float dt=Mathf.Min(Time.deltaTime,.05f);
            if(Playing&&Panel==""&&!Dead&&!Won){if(!Qa)Move(dt);Simulate(dt);if(Time.unscaledTime>saveAt){Save();saveAt=Time.unscaledTime+12;}}
            AnimateGear(dt);if(Time.unscaledTime>messageUntil)Message="";Ui.Tick();
        }
        void ReadInput()
        {
            if(Input.GetKeyDown(KeyCode.Escape)){if(Panel=="")OpenPanel("pause");else if(Panel!="title"&&Panel!="dead"&&Panel!="win")Resume();return;}
            if(!Playing||Dead||Won)return;
            if(Input.GetKeyDown(KeyCode.Tab)){if(Panel=="inventory")Resume();else OpenPanel("inventory");}
            if(Input.GetKeyDown(KeyCode.M)){if(Panel=="map")Resume();else OpenPanel("map");}
            if(Input.GetKeyDown(KeyCode.J)){if(Panel=="journal")Resume();else OpenPanel("journal");}
            if(Panel!="")return;
            if(Cursor.lockState!=CursorLockMode.Locked){if(Input.GetMouseButtonDown(0))Capture();return;}
            Yaw+=Input.GetAxisRaw("Mouse X")*2;Pitch=Mathf.Clamp(Pitch-Input.GetAxisRaw("Mouse Y")*2,-78,78);Body.transform.rotation=Quaternion.Euler(0,Yaw,0);View.transform.localRotation=Quaternion.Euler(Pitch,0,0);
            Blocking=Input.GetMouseButton(1)&&Stamina>3;if(Input.GetMouseButtonDown(0))Attack();if(Input.GetKeyDown(KeyCode.E))Interact();if(Input.GetKeyDown(KeyCode.Q))Drink();
        }
        void Move(float dt)
        {
            var input=Vector2.ClampMagnitude(new Vector2(Input.GetAxisRaw("Horizontal"),Input.GetAxisRaw("Vertical")),1);bool sprint=Input.GetKey(KeyCode.LeftShift)&&Stamina>5&&input.y>0&&!Blocking;
            float speed=Blocking?1.45f:sprint?4.4f:2.7f;if(sprint)Stamina=Mathf.Max(0,Stamina-19*dt);
            if(Body.isGrounded&&vertical<0)vertical=-2;vertical-=18*dt;Body.Move((Body.transform.right*input.x+Body.transform.forward*input.y)*speed*dt+Vector3.up*vertical*dt);
            if(Body.transform.position.y<-4){Teleport(StartPoint,World.SpawnRotation.eulerAngles.y);Damage(20,null);Notify("발을 헛디뎠습니다. 보급실로 돌아왔습니다.");}
        }
        public void Simulate(float dt)
        {
            if(Panel!=""||Dead||Won)return;World.Gate.Advance(dt);attackCooldown=Mathf.Max(0,attackCooldown-dt);attackTime=Mathf.Max(0,attackTime-dt);Stamina=Mathf.Min(100,Stamina+(Blocking?5:14)*dt);
            CurrentRoom=FindRoom(Body.transform.position);if(CurrentRoom>0)visited.Add(CurrentRoom);
            foreach(var f in Foes)
            {
                if(f.dead)continue;var delta=Body.transform.position-f.root.position;delta.y=0;float distance=delta.magnitude;f.cooldown-=dt;
                f.flash=Mathf.Max(0,f.flash-dt);f.visual.localRotation=Quaternion.Euler(f.windup>0?-18:Mathf.Sin(Time.time*2+f.id)*2,0,Mathf.Sin(Time.time*1.8f+f.id)*2);
                if(f.windup>0){f.windup-=dt;if(f.windup<=0&&distance<2.05f&&Visible(f.root.position+Vector3.up,View.transform.position))Damage(18,f);continue;}
                if(distance>10||!Visible(f.root.position+Vector3.up,View.transform.position))continue;
                if(distance>.01f)f.root.rotation=Quaternion.Slerp(f.root.rotation,Quaternion.LookRotation(delta),dt*5);
                if(distance>1.55f&&Vector3.Distance(f.root.position,f.home)<10)f.body.Move(delta.normalized*1.05f*dt+Vector3.down*2*dt);
                if(distance<1.85f&&f.cooldown<=0){f.windup=.65f;f.cooldown=2.5f;Notify(f.name+"의 공격 — 방패를 드세요");}
            }
        }
        public int FindRoom(Vector3 at)
        {
            int best=0;float area=float.MaxValue;foreach(var pair in World.RoomBounds){if(pair.Key==0)continue;var b=pair.Value;var test=at;test.y=b.center.y;if(!b.Contains(test))continue;float a=b.size.x*b.size.z;if(a<area){best=pair.Key;area=a;}}return best;
        }
        static bool Visible(Vector3 a,Vector3 b)=>!Physics.Linecast(a,b,1<<OriginDungeonWorld.WorldLayer);
        public bool Attack()
        {
            if(Panel!=""||Dead||Won||attackCooldown>0||Stamina<19)return false;Stamina-=19;attackTime=.42f;attackCooldown=.52f;attackSerial++;Tone(.75f);
            Foe target=null;float best=3.0f;foreach(var f in Foes){if(f.dead)continue;var delta=f.root.position+Vector3.up*1.0f-View.transform.position;float d=delta.magnitude;if(d<best&&Vector3.Dot(View.transform.forward,delta.normalized)>.68f&&Visible(View.transform.position,f.root.position+Vector3.up)){best=d;target=f;}}
            if(target!=null){Hurt(target,34);Notify(target.dead?target.name+"의 봉인이 풀렸습니다":target.name+"  −34");}return true;
        }
        public void Hurt(Foe f,float damage)
        {if(f.dead)return;f.hp-=damage;f.flash=.2f;if(f.hp<=0){f.dead=true;f.body.enabled=false;f.visual.localRotation=Quaternion.Euler(75,0,12);f.root.gameObject.SetActive(false);Health=Mathf.Min(100,Health+12);Save();}}
        public void Damage(float damage,Foe source)
        {
            if(Dead||Won)return;bool frontal=source==null||Vector3.Dot(Body.transform.forward,(source.root.position-Body.transform.position).normalized)>.25f;
            if(Blocking&&frontal&&Stamina>=12){Stamina-=12;damage*=.12f;Notify("방패로 막았습니다");Tone(.45f);}Health=Mathf.Max(0,Health-damage);Ui.Flash();
            if(Health<=0){Dead=true;OpenPanel("dead");}
        }
        public bool Drink(){if(Panel!=""||Potions<1||Health>=100||Dead||Won)return false;Potions--;Health=Mathf.Min(100,Health+42);Notify("회복약을 마셨습니다  +42");Save();return true;}
        public string Prompt()
        {
            var p=Body.transform.position;
            if(Relics==3&&Vector3.Distance(p,ReturnMarker.position)<1.7f)return "E  세 봉인을 들고 귀환";
            var cache=Caches.FirstOrDefault(c=>!c.taken&&Vector3.Distance(p,c.root.position)<1.8f);if(cache!=null)return "E  봉인된 보급품 조사";
            if(Vector3.Distance(p,World.Gate.transform.position)<3.2f)return World.Gate.Open?"E  철문 닫기":"E  철문 열기";
            return Vector3.Distance(p,ReturnMarker.position)<1.7f?"귀환 표식 · 세 봉인이 필요합니다":"";
        }
        public bool Interact()
        {
            if(Panel!=""||Dead||Won)return false;var p=Body.transform.position;
            if(Vector3.Distance(p,ReturnMarker.position)<1.7f&&Relics==3){Won=true;Save();OpenPanel("win");return true;}
            var c=Caches.FirstOrDefault(v=>!v.taken&&Vector3.Distance(p,v.root.position)<1.8f);
            if(c!=null){c.taken=true;c.root.gameObject.SetActive(false);Potions++;Notify("보급품에서 회복약 1개를 찾았습니다");Save();return true;}
            if(Vector3.Distance(p,World.Gate.transform.position)<3.2f){if(World.Gate.Toggle(p))return true;Notify("문에서 한 걸음 물러서세요");}
            return false;
        }
        public void NewGame()
        {
            World.Gate.ResetClosed();
            Health=Stamina=100;Potions=3;Won=Dead=false;visited.Clear();foreach(var f in Foes){f.dead=false;f.hp=90;f.cooldown=2;f.windup=0;f.body.enabled=false;f.root.position=f.home;f.body.enabled=true;f.visual.localRotation=Quaternion.identity;f.root.gameObject.SetActive(true);}foreach(var c in Caches){c.taken=false;c.root.gameObject.SetActive(true);}Teleport(StartPoint,World.SpawnRotation.eulerAngles.y);Playing=true;Resume();Notify("세 봉인을 찾아, 이 지하에서 살아 돌아오세요.");Save();
        }
        public void Teleport(Vector3 feet,float yaw)
        {Body.enabled=false;Body.transform.position=feet;Body.transform.rotation=Quaternion.Euler(0,yaw,0);Yaw=yaw;Pitch=0;vertical=0;View.transform.localRotation=Quaternion.identity;Body.enabled=true;if(World!=null&&World.Ready)World.RefreshVisibility();}
        public void OpenPanel(string panel){Panel=panel;Blocking=false;Release();Ui.Show(panel);}
        public void Resume(){Panel="";Ui.Show("");Capture();}
        void Capture(){if(Qa)return;Cursor.lockState=CursorLockMode.Locked;Cursor.visible=false;}
        void Release(){if(Qa)return;Cursor.lockState=CursorLockMode.None;Cursor.visible=true;}
        public void Notify(string message){Message=message;messageUntil=Time.unscaledTime+3.2f;}
        public void Save()
        {
            if(!Ready||!Playing||Dead)return;var p=Body.transform.position;var s=new SaveData{health=Health,stamina=Stamina,potions=Potions,x=p.x,y=p.y,z=p.z,yaw=Yaw,pitch=Pitch,won=Won,dead=Foes.Where(f=>f.dead).Select(f=>f.id).ToList(),looted=Caches.Where(c=>c.taken).Select(c=>c.id).ToList(),visited=visited.ToList()};
            try{Directory.CreateDirectory(Path.GetDirectoryName(SavePath));File.WriteAllText(SavePath+".tmp",JsonConvert.SerializeObject(s));if(File.Exists(SavePath))File.Delete(SavePath);File.Move(SavePath+".tmp",SavePath);}catch(Exception e){Debug.LogWarning("Save failed: "+e.Message);Notify("저장하지 못했습니다. 저장 공간을 확인하세요.");}
        }
        public bool Continue()
        {
            try{var s=JsonConvert.DeserializeObject<SaveData>(File.ReadAllText(SavePath));if(s==null||s.version!=1||!float.IsFinite(s.x)||!float.IsFinite(s.z))throw new IOException("Unknown save");NewGame();Health=Mathf.Clamp(s.health,1,100);Stamina=Mathf.Clamp(s.stamina,0,100);Potions=Mathf.Max(0,s.potions);foreach(var f in Foes){f.dead=s.dead.Contains(f.id);f.root.gameObject.SetActive(!f.dead);f.body.enabled=!f.dead;}foreach(var c in Caches){c.taken=s.looted.Contains(c.id);c.root.gameObject.SetActive(!c.taken);}foreach(int r in s.visited)visited.Add(r);Teleport(new Vector3(s.x,s.y,s.z),s.yaw);Pitch=Mathf.Clamp(s.pitch,-78,78);View.transform.localRotation=Quaternion.Euler(Pitch,0,0);Won=s.won;if(Won)OpenPanel("win");Save();return true;}catch(Exception e){Debug.LogWarning(e);OpenPanel("title");Notify("저장 파일을 읽지 못했습니다");return false;}
        }
        void AnimateGear(float dt)
        {
            if(Gear==null)return;Gear.Root.gameObject.SetActive(Playing&&Panel=="");float a=attackTime>0?Mathf.Sin((1-attackTime/.42f)*Mathf.PI):0;Gear.Sword.localPosition=swordHome+new Vector3(-a*.36f,a*.05f,a*.18f);Gear.Sword.localRotation=Quaternion.Euler(-a*70,0,-10+a*70);Gear.Shield.localPosition=Vector3.Lerp(Gear.Shield.localPosition,shieldHome+(Blocking?new Vector3(.2f,.16f,.12f):Vector3.zero),1-Mathf.Exp(-dt*18));
        }
        static AudioClip MakeTone(){var clip=AudioClip.Create("Ink strike",4800,1,24000,false);var data=new float[4800];var random=new System.Random(73);for(int i=0;i<data.Length;i++){float t=i/24000f;data[i]=(float)(Math.Sin(t*980)*.35+(random.NextDouble()-.5)*.5)*Mathf.Exp(-t*28)*.3f;}clip.SetData(data,0);return clip;}
        void Tone(float pitch){if(Qa||hitClip==null)return;sound.pitch=pitch;sound.PlayOneShot(hitClip,.4f);}
        public void ToTitle(){Save();Playing=false;OpenPanel("title");}
        public void Quit(){Save();Application.Quit();}
        void OnApplicationFocus(bool focus){if(!focus&&!Qa&&Playing&&Panel=="")OpenPanel("pause");}
        void OnApplicationQuit(){Save();}
        void OnDestroy(){foreach(var i in imports)i.Dispose();}
    }
}
