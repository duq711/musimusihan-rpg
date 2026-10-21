using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using Newtonsoft.Json.Linq;
using TMPro;
using Unity.Profiling;
using UnityEngine;

namespace MusimusihanRpg.GothicOrigin
{
    public static partial class OriginQa
    {
        static readonly List<string> passed=new List<string>();static string folder;
        static void Check(bool ok,string label){if(!ok)throw new InvalidOperationException("QA FAIL: "+label);passed.Add(label);UnityEngine.Debug.Log("ORIGIN_CHECK "+label);}
        static void Pose(OriginGame game,int room)
        {
            if(room==-35){ReproductionPose(game);return;}
            var at=game.ClearPoint(room);var foe=game.Foes.FirstOrDefault(f=>f.room==room&&!f.dead);var focus=foe!=null?foe.home+Vector3.up*1.3f:game.World.RoomCenter(room)+Vector3.up*1.3f;
            if(foe!=null)
            {
                bool found=false;for(float radius=3.5f;radius<7&&!found;radius+=.5f)for(int d=0;d<16;d++)
                {
                    var p=foe.home+new Vector3(Mathf.Sin(d*Mathf.PI/8)*radius,0,Mathf.Cos(d*Mathf.PI/8)*radius);
                    if(!Physics.Raycast(p+Vector3.up*.7f,Vector3.down,out var floor,1.4f,1<<OriginDungeonWorld.WorldLayer)||floor.normal.y<.7f)continue;p.y=floor.point.y+.06f;
                    if(Physics.CheckCapsule(p+Vector3.up*.4f,p+Vector3.up*1.5f,.35f,1<<OriginDungeonWorld.WorldLayer)||Physics.Linecast(p+Vector3.up*1.6f,focus,1<<OriginDungeonWorld.WorldLayer))continue;at=p;found=true;break;
                }
                if(!found)throw new InvalidOperationException("No representative creature view for "+room);
            }
            var look=focus-(at+Vector3.up*1.6f);if(look.sqrMagnitude<.5f)look=game.World.RoomFrames.TryGetValue(room,out var frame)?frame.forward:game.World.SpawnRotation*Vector3.forward;
            game.Teleport(at,Quaternion.LookRotation(look).eulerAngles.y);game.World.RefreshVisibility();
        }

        static void Shot(OriginGame g,string name,RenderTexture target)
        {
            g.Presentation.RenderQa();var prior=RenderTexture.active;RenderTexture.active=target;var tex=new Texture2D(target.width,target.height,TextureFormat.RGB24,false);tex.ReadPixels(new Rect(0,0,target.width,target.height),0,0);tex.Apply();File.WriteAllBytes(Path.Combine(folder,name+".png"),tex.EncodeToPNG());UnityEngine.Object.Destroy(tex);RenderTexture.active=prior;
        }
        public static IEnumerator Run(OriginGame g)
        {
            var iterator=RunCore(g);
            while(true)
            {
                bool next=false;Exception error=null;try{next=iterator.MoveNext();}catch(Exception e){error=e;}
                if(error!=null){UnityEngine.Debug.LogException(error);Directory.CreateDirectory(folder);File.WriteAllText(Path.Combine(folder,"summary.json"),new JObject{["failure"]=error.ToString(),["passed"]=new JArray(passed),["checkCount"]=passed.Count}.ToString());Application.Quit(1);yield break;}
                if(!next)yield break;yield return iterator.Current;
            }
        }
        static IEnumerator RunCore(OriginGame g)
        {
            folder=Environment.GetEnvironmentVariable("ORIGIN_QA_DIR")??Path.Combine(Path.GetTempPath(),"origin-native-qa");Directory.CreateDirectory(folder);AudioListener.pause=true;AudioListener.volume=0;QualitySettings.vSyncCount=0;Application.targetFrameRate=-1;
            int qaWidth=int.TryParse(Environment.GetEnvironmentVariable("ORIGIN_QA_WIDTH"),out var w)?Mathf.Clamp(w,640,4096):1280;int qaHeight=int.TryParse(Environment.GetEnvironmentVariable("ORIGIN_QA_HEIGHT"),out var h)?Mathf.Clamp(h,480,4096):900;
            var rt=new RenderTexture(qaWidth,qaHeight,24,RenderTextureFormat.ARGB32){antiAliasing=2};rt.Create();g.Presentation.ConfigureQa(rt,Environment.GetEnvironmentVariable("ORIGIN_QA_FULL_RESOLUTION")=="1");
            var sync=new Texture2D(1,1,TextureFormat.RGB24,false);var results=new JObject();var performance=new JArray();Exception failure=null;
            if(VisibilityRequested)g.World.SetLegacyDistanceCullingForQa(Environment.GetEnvironmentVariable("ORIGIN_QA_LEGACY_VISIBILITY")=="1");
            var sequences=VisibilityRequested?new[]{Functional(g,rt),VisibilityChecks(g,rt)}:new[]{Functional(g,rt)};
            foreach(var checks in sequences){while(true){bool next=false;try{next=checks.MoveNext();}catch(Exception e){failure=e;}if(failure!=null||!next)break;yield return checks.Current;}if(failure!=null)break;}
            if(failure==null)
            {
                foreach(int room in VisibilityRequested?new[]{35,33,1,30,-35}:new[]{35,33,1,30})
                {
                    Pose(g,room);g.Resume();for(int i=0;i<90;i++){g.Presentation.RenderQa();yield return null;}
                    var times=new List<double>();var gpu=new List<double>();var cpu=new List<double>();long maxDraws=0,maxTriangles=0;using(var draw=ProfilerRecorder.StartNew(ProfilerCategory.Render,"Draw Calls Count",16))using(var tris=ProfilerRecorder.StartNew(ProfilerCategory.Render,"Triangles Count",16))
                    {
                        var clock=Stopwatch.StartNew();double previous=clock.Elapsed.TotalMilliseconds;var origin=g.Body.transform.position;
                        for(int i=0;i<600;i++)
                        {
                            // Real controller motion against the furnished map, with a small repeatable turn.
                            float phase=i/60f;var desired=origin+new Vector3(Mathf.Sin(phase)*.65f,0,Mathf.Sin(phase*.5f)*.55f);var move=desired-g.Body.transform.position;move.y=-.06f;g.Body.Move(Vector3.ClampMagnitude(move,.07f));g.Body.transform.rotation=Quaternion.Euler(0,g.Yaw+Mathf.Sin(phase)*38,0);g.Health=100;g.World.RefreshVisibility();g.Presentation.RenderQa();var prior=RenderTexture.active;RenderTexture.active=rt;sync.ReadPixels(new Rect(0,0,1,1),0,0,false);RenderTexture.active=prior;FrameTimingManager.CaptureFrameTimings();yield return null;
                            double now=clock.Elapsed.TotalMilliseconds;times.Add(now-previous);previous=now;var timing=new FrameTiming[1];if(FrameTimingManager.GetLatestTimings(1,timing)>0){if(timing[0].gpuFrameTime>0)gpu.Add(timing[0].gpuFrameTime);if(timing[0].cpuFrameTime>0)cpu.Add(timing[0].cpuFrameTime);}maxDraws=Math.Max(maxDraws,draw.LastValue);maxTriangles=Math.Max(maxTriangles,tris.LastValue);
                        }
                    }
                    times.Sort();performance.Add(new JObject{["room"]=room,["samples"]=times.Count,["meanMs"]=times.Average(),["p95Ms"]=times[(int)(times.Count*.95)],["p99Ms"]=times[(int)(times.Count*.99)],["over16_67Percent"]=times.Count(v=>v>16.67)*100.0/times.Count,["over20Percent"]=times.Count(v=>v>20)*100.0/times.Count,["maxDrawCalls"]=maxDraws>0?(JToken)maxDraws:JValue.CreateNull(),["maxTriangles"]=maxTriangles>0?(JToken)maxTriangles:JValue.CreateNull(),["submissionEstimate"]=Estimate(g),["gpuMeanMs"]=gpu.Count>0?(JToken)gpu.Average():JValue.CreateNull(),["cpuMeanMs"]=cpu.Count>0?(JToken)cpu.Average():JValue.CreateNull()});Shot(g,"room"+room,rt);
                }
            }
            results["renderResolution"]=g.Presentation.QaResolution;results["visibility"]=visibilityReport;results["engine"]=Application.unityVersion;results["graphics"]=SystemInfo.graphicsDeviceName+" / "+SystemInfo.graphicsDeviceType;results["resolution"]=rt.width+"x"+rt.height+" offscreen with real Metal, UI, exact collision, animated creatures";results["frameLimit"]="uncapped explicit camera render +1px synchronous GPU readback per sample, conservative capacity; not foreground constant60";results["gearBatching"]=Environment.GetEnvironmentVariable("ORIGIN_UNBATCHED_GEAR")!="1";results["passed"]=new JArray(passed);results["checkCount"]=passed.Count;results["failure"]=failure==null?JValue.CreateNull():failure.ToString();results["performance"]=performance;results["renderTrianglesAuthored"]=g.World.RenderTriangles;results["collisionTriangles"]=g.World.CollisionTriangles;File.WriteAllText(Path.Combine(folder,"summary.json"),results.ToString());UnityEngine.Debug.Log("ORIGIN_QA_DONE "+(failure==null?"PASS":"FAIL "+failure));g.Playing=false;g.View.targetTexture=null;UnityEngine.Object.Destroy(sync);rt.Release();UnityEngine.Object.Destroy(rt);Application.Quit(failure==null?0:1);
        }
        static JObject Estimate(OriginGame g)
        {
            var planes=GeometryUtility.CalculateFrustumPlanes(g.View);int draws=0;long triangles=0;
            foreach(var r in UnityEngine.Object.FindObjectsByType<MeshRenderer>(FindObjectsSortMode.None))
            {if(!r.enabled||!r.gameObject.activeInHierarchy||!GeometryUtility.TestPlanesAABB(planes,r.bounds))continue;var mesh=r.GetComponent<MeshFilter>()?.sharedMesh;if(mesh==null)continue;draws+=mesh.subMeshCount;for(int i=0;i<mesh.subMeshCount;i++)triangles+=(long)mesh.GetIndexCount(i)/3;}
            return new JObject{["frustumMeshDraws"]=draws,["frustumTriangles"]=triangles,["scope"]="Enabled mesh/submesh estimate after frustum culling, excludes Canvas and driver passes; counters are null if unavailable"};
        }
        static IEnumerator Functional(OriginGame g,RenderTexture rt)
        {
            Check(g.World.RoomCount==35,"35-room original native dungeon loaded");Check(g.World.RenderTriangles>100000,"authored geometry used");Check(g.World.CollisionTriangles>100000,"exact authored mesh collision used");Check(g.World.StatueCount>0,"existing furnished props present");Check(g.Foes.Count==6,"six gothic creatures loaded from production originals");Check(g.Ui.ButtonCount==4,"native title buttons");yield return null;Shot(g,"title",rt);
            for(int room=1;room<=35;room++){Check(g.World.RoomBounds.ContainsKey(room),"room bounds "+room);var p=g.ClearPoint(room);Check(Physics.Raycast(p+Vector3.up*.5f,Vector3.down,1.2f,1<<OriginDungeonWorld.WorldLayer),"walkable floor "+room);}
            var start=g.Ui.Canvas.GetComponentsInChildren<UnityEngine.UI.Button>().First(b=>b.name=="Button 새 원정 시작");UnityEngine.EventSystems.ExecuteEvents.Execute(start.gameObject,new UnityEngine.EventSystems.PointerEventData(UnityEngine.EventSystems.EventSystem.current){button=UnityEngine.EventSystems.PointerEventData.InputButton.Left},UnityEngine.EventSystems.ExecuteEvents.pointerClickHandler);
            yield return null;Check(g.Playing&&g.Panel==""&&g.Health==100,"native start button starts expedition");Check(g.Body.height>1.6f&&g.View.transform.parent==g.Body.transform,"native first-person controller");Check(Cursor.lockState!=CursorLockMode.Locked,"QA does not capture pointer");Shot(g,"start",rt);
            var before=g.Body.transform.position;g.Body.Move(g.Body.transform.forward*.3f);Check(Vector3.Distance(before,g.Body.transform.position)>.1f,"controller actually walks on original map");
            var cache=g.Caches.First(c=>c.room==31);g.Teleport(cache.root.position+Vector3.back*.65f,0);int pots=g.Potions;Check(g.Interact()&&g.Potions==pots+1&&cache.taken,"existing-room supply pickup");Check(!g.Interact(),"supply cannot be duplicated");
            g.Health=40;Check(g.Drink()&&g.Health==82,"potion restores42 health");g.Health=100;Check(!g.Drink(),"full health does not consume potion");
            g.OpenPanel("pause");float stamina=g.Stamina;var foe=g.Foes[0];var old=foe.root.position;g.Simulate(2);Check(g.Stamina==stamina&&foe.root.position==old,"pause freezes simulation");Check(!g.Attack()&&!g.Drink()&&!g.Interact(),"pause blocks gameplay actions");
            foreach(string panel in new[]{"inventory","map","journal","settings","controls"}){g.OpenPanel(panel);yield return null;Check(g.Ui.ButtonCount>0,"working native "+panel+" panel");if(panel=="map")Shot(g,"map",rt);}
            g.Resume();g.Health=100;g.Stamina=100;g.Blocking=true;g.Damage(18,null);Check(Mathf.Abs(g.Health-97.84f)<.01f&&g.Stamina==88,"shield reduces damage and costs stamina");g.Blocking=false;
            foreach(var f in g.Foes.Take(3))
            {
                Vector3 at=f.home+Vector3.forward*1.6f;for(int j=0;j<12;j++){var delta=new Vector3(Mathf.Sin(j*Mathf.PI/6),0,Mathf.Cos(j*Mathf.PI/6));var candidate=f.home+delta*1.6f;if(!Physics.Linecast(candidate+Vector3.up*1.6f,f.home+Vector3.up,1<<OriginDungeonWorld.WorldLayer)){at=candidate;break;}}
                g.Teleport(at,Quaternion.LookRotation(f.home-at).eulerAngles.y);g.Stamina=100;g.Health=100;
                for(int j=0;j<3;j++){g.Simulate(.6f);Check(g.Attack(),"native sword attack "+f.room+" / "+j);}
                Check(f.dead,"guardian defeated in room "+f.room);
            }
            Check(g.Relics==3,"three relics recovered");g.Health=67;g.Potions=4;g.Save();Check(File.Exists(OriginGame.SavePath),"isolated native save written");g.Health=20;Check(g.Continue()&&g.Health==67&&g.Potions==4&&g.Relics==3,"save restores expedition and guardians");
            g.Damage(1000,null);Check(g.Dead&&g.Panel=="dead","death opens retry panel");Check(g.Continue()&&!g.Dead&&g.Health==67,"retry restores checkpoint");g.Teleport(g.StartPoint,g.World.SpawnRotation.eulerAngles.y);Check(g.Interact()&&g.Won&&g.Panel=="win","return seal completes expedition");Shot(g,"win",rt);
            g.NewGame();Check(g.Relics==0&&g.Potions==3&&g.Foes.All(f=>!f.dead),"new expedition resets guardians and supplies");
            var gate=g.World.Gate;var position=gate.transform.position+gate.transform.forward*2.1f;Check(gate.Toggle(position),"original iron gate interaction");for(int i=0;i<60;i++)g.Simulate(.02f);Check(gate.Open,"original iron gate rotates open");
            var texts=UnityEngine.Object.FindObjectsByType<TextMeshProUGUI>(FindObjectsSortMode.None);Check(texts.All(t=>t.font!=null),"all native text has TMP font");Check(UnityEngine.Object.FindObjectsByType<UnityEngine.EventSystems.EventSystem>(FindObjectsSortMode.None).Length==1,"one native input event system");
            g.Health=100;g.OpenPanel("pause");g.Resume();yield return null;
        }
    }
}
