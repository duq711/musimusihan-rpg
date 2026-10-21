using System;
using System.Collections;
using System.IO;
using Newtonsoft.Json.Linq;
using UnityEngine;

namespace MusimusihanRpg.GothicOrigin
{
    public static partial class OriginQa
    {
        static bool CeilingRequested=>Array.IndexOf(Environment.GetCommandLineArgs(),"-originCeilingQa")>=0;
        static JObject ceilingReport;
        static void CeilingPose(OriginGame g)
        {
            // Read-only fixture from the reported room28 expedition; never load/write the user's save.
            g.Teleport(new Vector3(-.8175742f,.0149998628f,24.4273834f),274.849976f);
            g.Pitch=-39.34999f;g.View.transform.localRotation=Quaternion.Euler(g.Pitch,0,0);g.World.RefreshVisibility();
        }
        static IEnumerator CeilingChecks(OriginGame g,RenderTexture output)
        {
            bool legacy=Environment.GetEnvironmentVariable("ORIGIN_QA_LEGACY_SIDEDNESS")=="1";g.NewGame();g.Playing=false;
            CeilingPose(g);yield return null;Shot(g,"reported-room28-ceiling",output);
            var background=g.View.backgroundColor;g.View.backgroundColor=Color.magenta;
            var scene=g.Presentation.Scene;var pixels=new Texture2D(scene.width,scene.height,TextureFormat.RGB24,false);
            float VoidFraction()
            {
                g.World.RefreshVisibility();g.View.Render();var prior=RenderTexture.active;RenderTexture.active=scene;
                pixels.ReadPixels(new Rect(0,0,scene.width,scene.height),0,0,false);RenderTexture.active=prior;
                var data=pixels.GetPixels32();int missing=0,total=0;
                // Sample the full image on a regular4px grid. Magenta is the camera clear colour,
                // so dark painted joints and shadows cannot be mistaken for missing geometry.
                for(int y=2;y<scene.height;y+=4)for(int x=2;x<scene.width;x+=4)
                {var c=data[y*scene.width+x];total++;if(c.r>240&&c.g<15&&c.b>240)missing++;}
                return missing/(float)total;
            }
            float reported=VoidFraction();Check(legacy?reported>.1f:reported<.002f,legacy?"old shader reproduces room28 ceiling void":"reported room28 ceiling is closed");
            var samples=new JArray();int affected=0;
            for(int room=1;room<=35;room++)
            {
                var at=g.ClearPoint(room);
                foreach(float pitch in new[]{-65f,-85f})foreach(float yaw in new[]{0f,90f,180f,270f})
                {
                    g.Teleport(at,yaw);g.Pitch=pitch;g.View.transform.localRotation=Quaternion.Euler(pitch,0,0);
                    float empty=VoidFraction();if(empty>=.002f)affected++;
                    samples.Add(new JObject{["room"]=room,["feet"]=at.ToString("R"),["yaw"]=yaw,["pitch"]=pitch,["uncoveredFraction"]=empty});
                    if(!legacy&&empty<.002f)Check(true,"closed upward view room "+room+" / "+yaw+" / "+pitch);
                    if(!legacy&&empty>=.002f){Shot(g,"void-room"+room+"-"+yaw+"-"+pitch,output);UnityEngine.Debug.Log("CEILING_VOID "+room+" "+yaw+" "+pitch+" "+empty);}
                    if(pitch==-65&&yaw==90&&(room==1||room==8||room==16||room==28||room==33||room==35))
                    {g.View.backgroundColor=background;Shot(g,"ceiling-room"+room,output);g.View.backgroundColor=Color.magenta;}
                    yield return null;
                }
            }
            ceilingReport=new JObject{["legacyBackFaceOnly"]=legacy,["reportedRoom28VoidFraction"]=reported,["rooms"]=35,["views"]=samples.Count,["viewsWithVoid"]=affected,["thresholdFraction"]=.002,["method"]="Magenta clear-colour coverage,4px grid over complete1280x804 world render;65/85deg upward at4 headings, plus reported pose",["samples"]=samples};
            File.WriteAllText(Path.Combine(folder,"ceilings.json"),ceilingReport.ToString());
            g.View.backgroundColor=background;UnityEngine.Object.Destroy(pixels);g.NewGame();
            if(!legacy)Check(affected==0,"all35 rooms retain closed ceilings");
        }
    }
}
