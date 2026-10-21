// Preserves the existing map geometry, static batching and exact collision pipeline.
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using Newtonsoft.Json.Linq;
using UnityEngine;
using UnityEngine.Rendering;

namespace MusimusihanRpg.GothicOrigin
{
    public sealed partial class OriginDungeonWorld
    {
        readonly List<(MeshRenderer renderer,int room,Bounds bounds,bool structure)> batches=new List<(MeshRenderer,int,Bounds,bool)>();
        readonly List<Mesh> ownedMeshes=new List<Mesh>();
        bool legacyDistanceCullingForQa;
        internal void SetLegacyDistanceCullingForQa(bool enabled)
        {
            if(!OriginGame.Qa)throw new InvalidOperationException("Legacy distance culling is restricted to the isolated QA player.");
            legacyDistanceCullingForQa=enabled;UpdateVisibility(true);
        }
        static readonly Regex minor=new Regex(@"^(book_|scroll_)|rug|runner|water|damp_floor|ritual_floor|ivy|banner|shavings|candle|sconce|bottle|drinking_cup|bowl|quill|shackles|chain|collar|bone|skull|mallet|chisel",RegexOptions.IgnoreCase);
        static bool MinorProp(string alias)=>minor.IsMatch(alias);
        static bool Ink(Material material)=>Regex.IsMatch(material.name,"ink|contour|outline",RegexOptions.IgnoreCase);
        static string Identity(UnityEngine.Object value)
        {
            if(value==null)return "none";
#if UNITY_6000_6_OR_NEWER
            return value.GetEntityId().ToString();
#else
            return value.GetInstanceID().ToString();
#endif
        }
        static bool GatePart(Transform node){for(var t=node;t!=null;t=t.parent)if(t.name.StartsWith("Gate_Leaf_"))return true;return false;}
        MeshRenderer[] AuthoredRenderers()=>sources.SelectMany(r=>r.GetComponentsInChildren<MeshRenderer>(true)).Distinct().ToArray();
        string MaterialKey(Material material)
        {
            var s=new System.Text.StringBuilder(material.shader.name+"/"+material.renderQueue+"/"+string.Join(",",material.shaderKeywords.OrderBy(k=>k)));
            for(int i=0;i<material.shader.GetPropertyCount();i++)
            {
                string key=material.shader.GetPropertyName(i);s.Append('/').Append(key).Append('=');
                switch(material.shader.GetPropertyType(i))
                {
                    case ShaderPropertyType.Color:s.Append(material.GetColor(key).ToString("R"));break;
                    case ShaderPropertyType.Vector:s.Append(material.GetVector(key).ToString("R"));break;
                    case ShaderPropertyType.Texture:s.Append(Identity(material.GetTexture(key))).Append(material.GetTextureScale(key).ToString("R")).Append(material.GetTextureOffset(key).ToString("R"));break;
                    default:s.Append(material.GetFloat(key).ToString("R",System.Globalization.CultureInfo.InvariantCulture));break;
                }
            }
            return s.ToString();
        }
        void BuildBatches()
        {
            var canonical=new Dictionary<string,Material>();var groups=new Dictionary<string,(int room,Material material,bool structure,List<CombineInstance> instances)>();
            foreach(var renderer in AuthoredRenderers())
            {
                var filter=renderer.GetComponent<MeshFilter>();if(filter==null||filter.sharedMesh==null)continue;
                var mesh=filter.sharedMesh;int room=renderer.GetComponentInParent<GothicDungeonRegion>(true)?.Room??0;
                RenderTriangles+=Enumerable.Range(0,mesh.subMeshCount).Sum(i=>(long)mesh.GetIndexCount(i)/3);
                if(GatePart(renderer.transform))continue;
                bool structure=renderer.GetComponentInParent<GothicDungeonProp>(true)==null&&!renderer.name.StartsWith("Prop_",StringComparison.Ordinal);var center=ExactBounds(renderer).center;
                for(int slot=0;slot<mesh.subMeshCount;slot++)
                {
                    var mat=renderer.sharedMaterials[Mathf.Min(slot,renderer.sharedMaterials.Length-1)];string signature=MaterialKey(mat);
                    if(!canonical.TryGetValue(signature,out var material)){material=mat;canonical[signature]=material;}
                    string key=room+":"+structure+":"+Mathf.FloorToInt(center.x/8)+":"+Mathf.FloorToInt(center.z/8)+":"+Identity(material);
                    if(!groups.TryGetValue(key,out var group)){group=(room,material,structure,new List<CombineInstance>());groups[key]=group;}
                    group.instances.Add(new CombineInstance{mesh=mesh,subMeshIndex=slot,transform=renderer.transform.localToWorldMatrix});
                }
                renderer.enabled=false;
            }
            foreach(var group in groups.Values)
            foreach(var chunk in Chunks(group.instances))
            {
                var mesh=Combine(chunk,"DungeonRender");var node=new GameObject("RenderBatch_R"+group.room);node.layer=WorldLayer;node.transform.SetParent(transform,false);
                node.AddComponent<MeshFilter>().sharedMesh=mesh;var renderer=node.AddComponent<MeshRenderer>();renderer.sharedMaterial=group.material;
                renderer.shadowCastingMode=ShadowCastingMode.Off;renderer.receiveShadows=false;renderer.lightProbeUsage=LightProbeUsage.Off;renderer.reflectionProbeUsage=ReflectionProbeUsage.Off;
                batches.Add((renderer,group.room,mesh.bounds,group.structure));mesh.UploadMeshData(true);
            }
        }
        static IEnumerable<CombineInstance[]> Chunks(List<CombineInstance> parts)
        {
            var chunk=new List<CombineInstance>();int vertices=0;
            foreach(var part in parts){if(vertices+part.mesh.vertexCount>60000&&chunk.Count>0){yield return chunk.ToArray();chunk.Clear();vertices=0;}chunk.Add(part);vertices+=part.mesh.vertexCount;}
            if(chunk.Count>0)yield return chunk.ToArray();
        }
        Mesh Combine(CombineInstance[] parts,string label)
        {var mesh=new Mesh{name=label,indexFormat=IndexFormat.UInt32};mesh.CombineMeshes(parts,true,true);mesh.RecalculateBounds();ownedMeshes.Add(mesh);return mesh;}
        void BuildColliders()
        {
            var groups=new Dictionary<string,List<CombineInstance>>();
            foreach(var renderer in AuthoredRenderers())
            {
                var filter=renderer.GetComponent<MeshFilter>();if(filter==null||filter.sharedMesh==null)continue;var prop=renderer.GetComponentInParent<GothicDungeonProp>(true);
                if(prop!=null&&!prop.Collision||ExactBounds(renderer).min.y>3.5f)continue;
                if(renderer.GetComponentsInParent<Transform>(true).Any(t=>t.name.StartsWith("Gothic_Torch_")||t.name.Contains("Flame")||t.name.Contains("Smoke")))continue;
                var mesh=filter.sharedMesh;bool moving=GatePart(renderer.transform);
                for(int slot=0;slot<mesh.subMeshCount;slot++)
                {
                    if(Ink(renderer.sharedMaterials[Mathf.Min(slot,renderer.sharedMaterials.Length-1)]))continue;
                    CollisionTriangles+=mesh.GetIndexCount(slot)/3;
                    if(moving){var single=new Mesh{name="GateCollision",indexFormat=IndexFormat.UInt32};single.vertices=mesh.vertices;single.triangles=mesh.GetTriangles(slot);single.RecalculateBounds();ownedMeshes.Add(single);renderer.gameObject.AddComponent<MeshCollider>().sharedMesh=single;continue;}
                    var at=ExactBounds(renderer).center;string key=Mathf.FloorToInt(at.x/12)+":"+Mathf.FloorToInt(at.z/12);
                    if(!groups.TryGetValue(key,out var parts)){parts=new List<CombineInstance>();groups[key]=parts;}
                    parts.Add(new CombineInstance{mesh=mesh,subMeshIndex=slot,transform=renderer.transform.localToWorldMatrix});
                }
            }
            foreach(var parts in groups.Values)foreach(var chunk in Chunks(parts))
            {var node=new GameObject("ExactDungeonCollider");node.layer=WorldLayer;node.transform.SetParent(transform,false);var collider=node.AddComponent<MeshCollider>();collider.cookingOptions=MeshColliderCookingOptions.CookForFasterSimulation|MeshColliderCookingOptions.EnableMeshCleaning|MeshColliderCookingOptions.WeldColocatedVertices|MeshColliderCookingOptions.UseFastMidphase;collider.sharedMesh=Combine(chunk,"DungeonCollision");}
        }
        public int RoomBatchCount(int room)=>batches.Count(b=>b.room==room);
        void DisposeBatches(){foreach(var mesh in ownedMeshes)if(mesh!=null)Destroy(mesh);}
        void CompactSources(GameObject templates)
        {
            // Keep source files, placement markers and gate motion. Static runtime
            // drawing/collision now belongs to the already built exact batches.
            gate.Left.SetParent(gate.transform,true);gate.Right.SetParent(gate.transform,true);gate.Rebase();
            foreach(var source in sources)
            {
                if(source.GetComponent<GothicDungeonProp>()!=null){foreach(Transform child in source.transform)Destroy(child.gameObject);}
                else Destroy(source);
            }
            sources.Clear();Destroy(templates);
            var gateMeshes=new HashSet<Mesh>(gate.GetComponentsInChildren<MeshFilter>(true).Select(f=>f.sharedMesh));
            foreach(var import in imports)foreach(var mesh in import.Meshes)if(mesh!=null&&!gateMeshes.Contains(mesh))Destroy(mesh);
            var canonicalTextures=new HashSet<Texture>(sharedTextures.Values);
            foreach(var texture in sharedTextures.Keys)if(texture!=null&&!canonicalTextures.Contains(texture))Destroy(texture);
            sharedTextures.Clear();textureDigests.Clear();
        }
        GameObject Primitive(JObject rec,Transform parent)
        {
            var root=new GameObject("Procedural_"+rec["procedural"]);root.transform.SetParent(parent,false);
            var material=OriginPaint.Solid("Gothic iron",new Color(.40f,.39f,.35f));float w=(float)rec["width"],h=(float)rec["height"],d=(float)rec["depth"];
            GameObject Box(float x,float y,float z,float width,float height,float depth)
            {var cube=GameObject.CreatePrimitive(PrimitiveType.Cube);cube.transform.SetParent(root.transform,false);cube.transform.localPosition=new Vector3(x,y,z);cube.transform.localScale=new Vector3(width,height,depth);cube.GetComponent<MeshRenderer>().sharedMaterial=material;Destroy(cube.GetComponent<Collider>());return cube;}
            if((string)rec["procedural"]=="stone_dais")
            {
                var authored=sources.SelectMany(s=>s.GetComponentsInChildren<MeshRenderer>(true)).FirstOrDefault(r=>r.name.Contains("Room01_wall"));if(authored!=null)material=authored.sharedMaterial;
                Box(0,(h-.01f)/2,0,w,h-.01f,d);
                for(int i=0;i<3;i++){var cube=Box(-w/2+(i+.5f)*w/3,h/2,0,w/3-.008f,h,d);var mesh=Instantiate(cube.GetComponent<MeshFilter>().sharedMesh);var uv=mesh.uv;for(int v=0;v<uv.Length;v++)uv[v]=new Vector2(.35f+uv[v].x*.28f,.84f+uv[v].y*.12f);mesh.uv=uv;ownedMeshes.Add(mesh);cube.GetComponent<MeshFilter>().sharedMesh=mesh;}
            }
            else
            {
                float Top(float x)=>h*.63f+h*.37f*Mathf.Sqrt(Mathf.Max(0,1-Mathf.Abs(2*x/w)));
                for(int i=0;i<=12;i++){float x=-w/2+w*i/12,top=Top(x);Box(x,top/2,0,.045f,top,d);}
                foreach(float y in new[]{.15f,h*.34f,h*.59f})Box(0,y,0,w,.07f,d+.025f);
                for(int sign=-1;sign<=1;sign+=2)Box(sign*(w/2+.12f),h*.315f,0,.24f,h*.63f,.34f);
                for(int i=0;i<24;i++){float x0=-w/2+w*i/24,x1=-w/2+w*(i+1)/24,y0=Top(x0),y1=Top(x1),dx=x1-x0,dy=y1-y0;Box((x0+x1)/2,(y0+y1)/2,0,Mathf.Sqrt(dx*dx+dy*dy)+.015f,.24f,.34f).transform.localRotation=Quaternion.Euler(0,0,Mathf.Atan2(dy,dx)*Mathf.Rad2Deg);}
            }
            return root;
        }
        struct Portal {public int room;public Vector3 at,inward;public float halfWidth;}
        List<Portal> visibilityPortals;
        readonly Dictionary<int,bool> visiblePropRooms=new Dictionary<int,bool>();
        readonly Dictionary<int,float> visibleUntil=new Dictionary<int,float>();
        readonly Plane[] visibilityPlanes=new Plane[6];
        Vector3 lastVisibilityEye;Quaternion lastVisibilityRotation;bool visibilityPrepared;
        void UpdatePropVisibility(Vector3 camera,bool force)
        {
            if(!force&&visibilityPrepared&&(camera-lastVisibilityEye).sqrMagnitude<.0004f&&Quaternion.Angle(view.transform.rotation,lastVisibilityRotation)<.2f)return;
            lastVisibilityEye=camera;lastVisibilityRotation=view.transform.rotation;visibilityPrepared=true;
            if(visibilityPortals==null)
            {
                visibilityPortals=new List<Portal>();foreach(var p in Manifest["corridor"]["room_ports"])
                    visibilityPortals.Add(new Portal{room=(int)p["room_id"],at=Point(p["position"]),inward=Point(p["forward"]),halfWidth=((float?)p["clear_width"]??2)*.5f});
            }
            GeometryUtility.CalculateFrustumPlanes(view,visibilityPlanes);visiblePropRooms.Clear();
            foreach(var pair in roomBounds)
            {
                if(pair.Key==0)continue;bool visible=pair.Value.SqrDistance(camera)<64;
                if(!visible&&GeometryUtility.TestPlanesAABB(visibilityPlanes,pair.Value))
                foreach(var portal in visibilityPortals)
                {
                    if(portal.room!=pair.Key||!GeometryUtility.TestPlanesAABB(visibilityPlanes,new Bounds(portal.at+Vector3.up*1.8f,new Vector3(5,5,5))))continue;
                    var side=new Vector3(portal.inward.z,0,-portal.inward.x);
                    for(int x=-1;x<=1&&!visible;x++)for(int y=0;y<3&&!visible;y++)
                    {
                        var target=portal.at-portal.inward*.2f+side*(x*portal.halfWidth*.85f)+Vector3.up*(.4f+y*1.2f);
                        visible=!Physics.Linecast(camera,target,1<<WorldLayer);
                    }
                    if(visible)break;
                }
                if(visible)visibleUntil[pair.Key]=Time.unscaledTime+.35f;
                else if(visibleUntil.TryGetValue(pair.Key,out var until)&&Time.unscaledTime<until)visible=true;
                visiblePropRooms[pair.Key]=visible;
            }
            foreach(var batch in batches)
            {
                // Shells, floors and ceilings stay intact, including baked architecture.
                // Only distant loose props hidden by solid geometry are skipped.
                bool visible=batch.structure||batch.room==0||!visiblePropRooms.TryGetValue(batch.room,out var props)||props;
                if(batch.renderer.gameObject.activeSelf!=visible)batch.renderer.gameObject.SetActive(visible);
            }
        }
        void UpdateVisibility(bool force)
        {
            if(view==null)return;var camera=view.transform.position;
            if(legacyDistanceCullingForQa)
            {
                // Isolated before/after reproduction only. Normal gameplay never
                // uses room-distance or approximate doorway culling.
                var planes=GeometryUtility.CalculateFrustumPlanes(view);int inside=0;
                foreach(JObject room in Manifest["decorated"]["rooms"])
                {int id=(int)room["id"];var local=roomFrames[id].InverseTransformPoint(camera);if(Mathf.Abs(local.x)<(float)room["width"]/2-.6f&&local.z<-.6f&&local.z>-(float)room["depth"]+.6f){inside=id;break;}}
                if(inside==0)foreach(var pair in roomBounds)if(pair.Key>=30&&pair.Value.Contains(camera)){inside=pair.Key;break;}
                var ports=Manifest["corridor"]["room_ports"]??Manifest["corridor"]["ports"];
                bool portalVisible=inside==0||ports.Any(p=>(int)(p["room_id"]??p["id"])==inside&&GeometryUtility.TestPlanesAABB(planes,new Bounds(Point(p["position"])+Vector3.up*2,Vector3.one*4)));
                foreach(var batch in batches)
                {
                    bool enabled=portalVisible||batch.room==inside;
                    if(enabled&&batch.room!=0&&roomBounds.TryGetValue(batch.room,out var bounds))enabled=bounds.SqrDistance(camera)<25;
                    if(batch.renderer.gameObject.activeSelf!=enabled)batch.renderer.gameObject.SetActive(enabled);
                }
            }
            else
            {
                UpdatePropVisibility(camera,force);
            }
            if(!force&&Time.unscaledTime<nextLightUpdate)return;nextLightUpdate=Time.unscaledTime+.3f;
            var nearest=lamps.OrderBy(l=>(l.position-camera).sqrMagnitude).Take(8).ToArray();
            for(int i=0;i<nearbyLights.Length;i++){var light=nearbyLights[i];light.enabled=i<nearest.Length;if(i>=nearest.Length)continue;var source=nearest[i];light.transform.position=source.position;light.color=source.color;light.intensity=Mathf.Min(6,source.intensity*.65f);light.range=source.range;}
        }
        public JObject VisibilitySnapshot(int room)
        {
            var relevant=batches.Where(b=>b.room==room).ToArray();
            return new JObject{["camera"]=view.transform.position.ToString("R"),["roomFrame"]=roomFrames[room].position.ToString("R"),["roomBounds"]=roomBounds[room].ToString(),["enabledBatches"]=relevant.Count(b=>b.renderer.gameObject.activeInHierarchy),["totalBatches"]=relevant.Length,["firstBatch"]=relevant.Length>0?relevant[0].renderer.bounds.ToString():"none",["cameraMask"]=view.cullingMask,["statueMaterials"]=new JArray(batches.Select(b=>b.renderer.sharedMaterial).Distinct().Where(m=>m.name.Contains("Graphic stone")).Select(m=>new JObject{["shader"]=m.shader.name,["properties"]=new JArray(m.GetTexturePropertyNames().Select(k=>k+"="+(m.GetTexture(k)?.name??"null"))),["factor"]=m.HasProperty("baseColorFactor")?m.GetColor("baseColorFactor").ToString("R"):"none"}))};
        }
        public Vector3 RoomCenter(int room){var p=roomBounds[room].center;p.y=0;return p;}
        internal JObject RoomVisibilityForQa(int room)
        {
            var planes=GeometryUtility.CalculateFrustumPlanes(view);var relevant=batches.Where(b=>b.room==room&&GeometryUtility.TestPlanesAABB(planes,b.bounds)).ToArray();
            return new JObject{["room"]=room,["distanceFromBounds"]=Mathf.Sqrt(roomBounds[room].SqrDistance(view.transform.position)),["inFrustumBatches"]=relevant.Length,["hiddenInFrustumBatches"]=relevant.Count(b=>!b.renderer.gameObject.activeInHierarchy),["legacyDistanceCulling"]=legacyDistanceCullingForQa};
        }
        public void RefreshVisibility()=>UpdateVisibility(true);
    }
}
