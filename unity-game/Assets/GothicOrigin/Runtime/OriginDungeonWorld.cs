// Standalone adaptation of the existing native map loader. Original map sources are preserved.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Threading.Tasks;
using GLTFast;
using GLTFast.Materials;
using Newtonsoft.Json.Linq;
using UnityEngine;
using UnityEngine.Rendering;

namespace MusimusihanRpg.GothicOrigin
{
    /// <summary>The authored35-room dungeon, loaded offline into the real expedition.</summary>
    public sealed partial class OriginDungeonWorld : MonoBehaviour
    {
        public const int WorldLayer=8;
        public const string PackageFolder="GothicDungeon";
        public static string PackagePath=>Path.Combine(Application.streamingAssetsPath,PackageFolder);
        public static bool Available=>File.Exists(Path.Combine(PackagePath,"manifest.json"))&&Environment.GetEnvironmentVariable("RPG_GOTHIC_DUNGEON")!="0";
        public bool Ready {get;private set;}
        public JObject Manifest {get;private set;}
        public long RenderTriangles {get;private set;}
        public long CollisionTriangles {get;private set;}
        public int StatueCount {get;private set;}
        public int RoomCount=>35;
        readonly List<GltfImport> imports=new List<GltfImport>();
        readonly List<GameObject> sources=new List<GameObject>();
        readonly Dictionary<int,Transform> roomFrames=new Dictionary<int,Transform>();
        readonly Dictionary<int,Bounds> roomBounds=new Dictionary<int,Bounds>();
        readonly Dictionary<Texture,Texture> sharedTextures=new Dictionary<Texture,Texture>();
        readonly Dictionary<string,Texture> textureDigests=new Dictionary<string,Texture>();
        readonly List<(Vector3 position,Color color,float intensity,float range)> lamps=new List<(Vector3,Color,float,float)>();
        readonly Light[] nearbyLights=new Light[8];
        readonly List<(Light light,bool enabled)> externalLights=new List<(Light,bool)>();
        public Camera View=>view;
        public OriginDungeonGate Gate=>gate;
        public IReadOnlyDictionary<int,Bounds> RoomBounds=>roomBounds;
        public IReadOnlyDictionary<int,Transform> RoomFrames=>roomFrames;
        Camera view;float nextLightUpdate;OriginDungeonGate gate;AssetBundle styleBundle;Shader unlitShader;
        sealed class DungeonMaterials:BuiltInMaterialGenerator
        {
            readonly Shader unlit;public DungeonMaterials(Shader shader){unlit=shader;}
            protected override Shader FindShaderUnlit()=>unlit;
        }
        static Vector3 Raw(JToken a)=>new Vector3((float)a[0],(float)a[1],(float)a[2]);
        public static Vector3 Point(JToken a)=>new Vector3(-(float)a[0],(float)a[1],(float)a[2]);
        static Quaternion Yaw(float angle)=>Quaternion.Euler(0,-angle,0);
        static string Sha(byte[] bytes){using var sha=SHA256.Create();return BitConverter.ToString(sha.ComputeHash(bytes)).Replace("-","").ToLowerInvariant();}
        static Bounds BoundsOf(GameObject root)
        {
            var renderers=root.GetComponentsInChildren<Renderer>(true);if(renderers.Length==0)throw new InvalidDataException("Empty dungeon geometry: "+root.name);
            var bounds=ExactBounds(renderers[0]);foreach(var r in renderers.Skip(1))bounds.Encapsulate(ExactBounds(r));return bounds;
        }
        static Bounds ExactBounds(Renderer renderer)
        {
            var filter=renderer.GetComponent<MeshFilter>();if(filter==null||filter.sharedMesh==null)return renderer.bounds;
            var local=filter.sharedMesh.bounds;var matrix=renderer.transform.localToWorldMatrix;var result=new Bounds(matrix.MultiplyPoint3x4(local.min),Vector3.zero);
            for(int i=0;i<8;i++)result.Encapsulate(matrix.MultiplyPoint3x4(local.center+Vector3.Scale(local.extents,new Vector3((i&1)==0?-1:1,(i&2)==0?-1:1,(i&4)==0?-1:1))));return result;
        }
        Transform Frame(int id,JToken pose)
        {
            if(roomFrames.TryGetValue(id,out var prior))return prior;
            var root=new GameObject("Room"+id.ToString("00"));root.transform.SetParent(transform,false);
            root.transform.localPosition=Point(pose["position"]);root.transform.localRotation=Yaw((float)pose["yawDegrees"]);roomFrames[id]=root.transform;return root.transform;
        }
        async Task<GameObject> Import(JObject record,Transform parent)
        {
            var path=Path.Combine(PackagePath,(string)record["file"]);var bytes=await File.ReadAllBytesAsync(path);
            if(Sha(bytes)!=(string)record["sha256"])throw new InvalidDataException("Dungeon asset hash mismatch: "+record["file"]);
            var gltf=new GltfImport(materialGenerator:new DungeonMaterials(unlitShader));imports.Add(gltf);
            if(!await gltf.LoadGltfBinary(bytes,new Uri(path),new ImportSettings{GenerateMipMaps=true,AnisotropicFilterLevel=4,AnimationMethod=AnimationMethod.Legacy}))throw new InvalidDataException("Dungeon GLB import failed: "+record["file"]);
            var root=new GameObject("Imported_"+imports.Count);root.transform.SetParent(parent,false);
            if(!await gltf.InstantiateMainSceneAsync(root.transform))throw new InvalidDataException("Dungeon GLB has no scene");
            foreach(var animation in root.GetComponentsInChildren<Animation>(true)){animation.Stop();animation.enabled=false;}
            // Identical embedded atlases share GPU storage, matching the browser.
            int jsonLength=BitConverter.ToInt32(bytes,12),bin=28+jsonLength;var json=JObject.Parse(System.Text.Encoding.UTF8.GetString(bytes,20,jsonLength));
            for(int i=0;i<(json["textures"]?.Count()??0);i++)
            {
                var image=json["images"]?[(int)json["textures"][i]["source"]];if(image?["bufferView"]==null)continue;
                var buffer=json["bufferViews"][(int)image["bufferView"]];var encoded=new byte[(int)buffer["byteLength"]];Buffer.BlockCopy(bytes,bin+(int?)buffer["byteOffset"]??bin,encoded,0,encoded.Length);
                var texture=gltf.GetTexture(i);if(texture==null)continue;string key=Sha(encoded)+"/"+texture.graphicsFormat+"/"+texture.wrapMode+"/"+texture.filterMode;
                if(!textureDigests.TryGetValue(key,out var canonical)){canonical=texture;textureDigests[key]=texture;}sharedTextures[texture]=canonical;
            }
            foreach(var renderer in root.GetComponentsInChildren<MeshRenderer>(true))
            {
                renderer.shadowCastingMode=ShadowCastingMode.Off;renderer.receiveShadows=false;
                foreach(var material in renderer.sharedMaterials)
                foreach(string property in material.GetTexturePropertyNames())
                {var texture=material.GetTexture(property);if(texture!=null&&sharedTextures.TryGetValue(texture,out var canonical))material.SetTexture(property,canonical);}
            }
            var sides=new Dictionary<Material,bool>();
            for(int i=0;i<(json["materials"]?.Count()??0);i++)
            {var material=gltf.GetMaterial(i);if(material!=null)sides[material]=(bool?)json["materials"][i]["doubleSided"]??false;}
            OriginPaint.Apply(root,sides);
            return root;
        }
        public static async Task<OriginDungeonWorld> Load(Action<float> progress)
        {
            var root=new GameObject("GothicDungeon35");root.SetActive(false);var world=root.AddComponent<OriginDungeonWorld>();
            try{await world.Build(progress);world.Ready=true;return world;}catch{Destroy(root);throw;}
        }
        async Task Build(Action<float> progress)
        {
            Manifest=JObject.Parse(await File.ReadAllTextAsync(Path.Combine(PackagePath,"manifest.json")));
            unlitShader=Resources.Load<Material>("MapUnlit").shader;
            var decorated=(JObject)Manifest["decorated"];var corridor=Manifest["corridor"];int loaded=0,total=((JArray)Manifest["models"]).Count+decorated["assets"].Count()+2;
            foreach(JObject model in Manifest["models"])
            {int id=(int)model["id"];var node=await Import((JObject)model["model"],Frame(id,model["transform"]));sources.Add(node);RegisterSource(node,id);if(id==0){var storage=node.GetComponentsInChildren<Transform>(true).FirstOrDefault(t=>t.name=="Room35_Assembly");if(storage!=null)RegisterSource(storage.gameObject,35);}AddLights(model["lights"],roomFrames[id]);progress?.Invoke(++loaded/(float)total*.8f);}
            var shell=await Import((JObject)decorated["shells"],transform);sources.Add(shell);
            foreach(Transform node in shell.GetComponentsInChildren<Transform>(true))
            {if(!node.name.StartsWith("Room")||!node.name.EndsWith("_Shell"))continue;if(int.TryParse(node.name.Substring(4,2),out int id))RegisterSource(node.gameObject,id);}
            var templatesRoot=new GameObject("SourceTemplates");templatesRoot.transform.SetParent(transform,false);templatesRoot.SetActive(false);
            var templates=new Dictionary<string,GameObject>();
            foreach(var entry in ((JObject)decorated["assets"]).Properties())
            {var rec=(JObject)entry.Value;var source=rec["procedural"]!=null?Primitive(rec,templatesRoot.transform):await Import(rec,templatesRoot.transform);templates[entry.Name]=source;progress?.Invoke(++loaded/(float)total*.8f);}
            foreach(JObject room in decorated["rooms"])
            {
                int id=(int)room["id"];var frame=Frame(id,new JObject{["position"]=room["position"].DeepClone(),["yawDegrees"]=room["yawDegrees"]});var placed=new Dictionary<string,Bounds>();
                foreach(JObject prop in room["props"])
                {
                    string alias=(string)prop["asset"];var holder=new GameObject("Prop_R"+id+"_"+prop["id"]);var source=Instantiate(templates[alias],holder.transform);source.SetActive(true);
                    if(prop["rotation"] is JArray rotation){var r=Raw(rotation);source.transform.localRotation=Quaternion.AngleAxis(r.x,Vector3.right)*Quaternion.AngleAxis(-r.y,Vector3.up)*Quaternion.AngleAxis(-r.z,Vector3.forward);}
                    holder.transform.rotation=Yaw((float?)prop["yaw"]??0);var box=BoundsOf(holder);float scale=prop["height"]!=null?(float)prop["height"]/box.size.y:(float?)prop["scale"]??1;
                    source.transform.localScale=Vector3.Scale(source.transform.localScale,new Vector3(scale,scale*((float?)prop["scaleY"]??1),scale));box=BoundsOf(holder);
                    float y=(float)prop["position"][1];if(prop["support"]!=null)y=placed[(string)prop["support"]].max.y+((float?)prop["supportOffset"]??0);
                    var p=Point(prop["position"]);holder.transform.position=new Vector3(p.x-box.center.x,y-box.min.y,p.z-box.center.z);placed[(string)prop["id"]]=BoundsOf(holder);
                    holder.transform.SetParent(frame,false);sources.Add(holder);RegisterSource(holder,id);
                    var marker=holder.AddComponent<GothicDungeonProp>();marker.Asset=alias;marker.Room=id;marker.Collision=(bool?)prop["collision"]!=false&&!MinorProp(alias);
                    if(alias=="veiled_listener_statue")StatueCount++;
                }
                AddLights(room["lights"],frame);
            }
            AddLights(corridor["lights"],transform);
            foreach(var torch in corridor["gothic_torches"]??new JArray())
            {var at=torch["fire_position"]??torch["position"];if(at is JArray)lamps.Add((Point(at),new Color(1,.45f,.18f),3.2f,9));}
            foreach(var source in sources)foreach(Transform node in source.GetComponentsInChildren<Transform>(true))node.gameObject.layer=WorldLayer;
            PrepareGate(corridor);AddVaultJointBackings();progress?.Invoke(.82f);await Task.Yield();BuildBatches();progress?.Invoke(.94f);await Task.Yield();BuildColliders();CompactSources(templatesRoot);progress?.Invoke(.98f);
            for(int i=0;i<nearbyLights.Length;i++){var node=new GameObject("NearbyDungeonLight"+i);node.transform.SetParent(transform,false);var light=node.AddComponent<Light>();light.type=LightType.Point;light.shadows=LightShadows.None;light.cullingMask=1<<WorldLayer;nearbyLights[i]=light;}
            var fill=new GameObject("InteriorBounce");fill.transform.SetParent(transform,false);var sun=fill.AddComponent<Light>();sun.type=LightType.Directional;sun.color=new Color(.96f,.86f,.71f);sun.intensity=1.2f;sun.shadows=LightShadows.None;sun.cullingMask=1<<WorldLayer;fill.transform.rotation=Quaternion.Euler(60,-35,0);
            Physics.SyncTransforms();progress?.Invoke(1);
        }
        void RegisterSource(GameObject source,int room)
        {
            var marker=source.GetComponent<GothicDungeonRegion>()??source.AddComponent<GothicDungeonRegion>();marker.Room=room;
            var bounds=BoundsOf(source);if(roomBounds.TryGetValue(room,out var prior)){prior.Encapsulate(bounds);bounds=prior;}roomBounds[room]=bounds;
        }
        void AddLights(JToken definitions,Transform frame)
        {
            foreach(var lamp in definitions??new JArray())
            {if(lamp["position"]==null)continue;var color=lamp["color"] is JArray c?new Color((float)c[0],(float)c[1],(float)c[2]):new Color(1,.62f,.31f);lamps.Add((frame.TransformPoint(Point(lamp["position"])),color,(float?)lamp["intensity"]??3.2f,(float?)lamp["distance"]??9));}
        }
        public Vector3 Spawn {get {var p=Point(Manifest["corridor"]["spawn"]["position"]);p.y=.05f;return p;}}
        public Quaternion SpawnRotation=>Quaternion.LookRotation(Point(Manifest["corridor"]["spawn"]["forward"]));
        public void Activate(Camera camera)
        {
            view=camera;gameObject.SetActive(true);
            RenderSettings.ambientMode=AmbientMode.Flat;RenderSettings.ambientLight=new Color(.25f,.3f,.35f);
            RenderSettings.fog=false;RenderSettings.reflectionIntensity=0;
            RenderSettings.skybox=null;view.clearFlags=CameraClearFlags.SolidColor;view.farClipPlane=100;view.backgroundColor=new Color(.025f,.035f,.04f);
            UpdateVisibility(true);
        }
        void LateUpdate(){if(Ready&&view!=null){UpdateVisibility(false);OriginPaint.SetView(view.transform.position,nearbyLights);}}
        void OnDisable(){foreach(var entry in externalLights)if(entry.light!=null)entry.light.enabled=entry.enabled;externalLights.Clear();}
        void OnDestroy(){foreach(var gltf in imports)gltf.Dispose();DisposeBatches();if(styleBundle!=null)styleBundle.Unload(true);}
    }
    public sealed class GothicDungeonRegion:MonoBehaviour {public int Room;}
    public sealed class GothicDungeonProp:MonoBehaviour {public string Asset;public int Room;public bool Collision;}
}
