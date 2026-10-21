using System;
using System.Collections;
using System.IO;
using System.Linq;
using Newtonsoft.Json.Linq;
using UnityEngine;

namespace MusimusihanRpg.GothicOrigin
{
    public static partial class OriginQa
    {
        static bool VisibilityRequested=>Environment.GetCommandLineArgs().Contains("-originVisibilityQa");
        static JObject visibilityReport;
        // Captured expedition pose reproducing the reported room35 doorway hole.
        static readonly Vector3 reportedFeet=new Vector3(25.51904f,.0149998628f,45.84665f);
        static void ReproductionPose(OriginGame g)
        {
            g.Teleport(reportedFeet,24.2500763f);g.Pitch=15.6499853f;g.View.transform.localRotation=Quaternion.Euler(g.Pitch,0,0);g.World.RefreshVisibility();
        }
        static IEnumerator VisibilityChecks(OriginGame g,RenderTexture rt)
        {
            bool legacy=Environment.GetEnvironmentVariable("ORIGIN_QA_LEGACY_VISIBILITY")=="1";g.NewGame();
            // The original gate is open in the user's reported view.
            g.World.Gate.Toggle(g.World.Gate.transform.position+Vector3.forward*2.1f);for(int i=0;i<60;i++)g.World.Gate.Advance(1f/60);
            Check(g.World.Gate.Open,"reported gate is open");ReproductionPose(g);yield return null;g.World.RefreshVisibility();var reproduction=g.World.RoomVisibilityForQa(35);Shot(g,"reported-room35",rt);
            Check((int)reproduction["inFrustumBatches"]>0,"reported room35 geometry intersects the camera frustum");
            Check((float)reproduction["distanceFromBounds"]>5,"reported room35 camera crosses the former5m threshold");
            Check(legacy?(int)reproduction["hiddenInFrustumBatches"]>0:(int)reproduction["hiddenInFrustumBatches"]==0,legacy?"old5m rule reproduces the missing room":"reported doorway retains all visible room35 batches");
            var observations=new JArray();int skipped=0,hidden=0;var seen=new System.Collections.Generic.HashSet<int>();
            foreach(var port in g.World.Manifest["corridor"]["room_ports"])
            foreach(float distance in new[]{2f,4.9f,5.1f,8f,12f})
            foreach(float angle in new[]{-20f,0f,20f})
            {
                int room=(int)port["room_id"];var door=OriginDungeonWorld.Point(port["position"]);var inward=OriginDungeonWorld.Point(port["forward"]);var from=door-Quaternion.Euler(0,angle,0)*inward*distance;
                if(!Physics.Raycast(from+Vector3.up*.7f,Vector3.down,out var floor,1.4f,1<<OriginDungeonWorld.WorldLayer)||floor.normal.y<.7f){skipped++;continue;}
                from.y=floor.point.y+.05f;var eye=from+Vector3.up*1.6f;var target=door+Vector3.up*1.6f;
                if(Physics.Linecast(eye,target,1<<OriginDungeonWorld.WorldLayer)){skipped++;continue;}
                g.Teleport(from,Quaternion.LookRotation(target-eye).eulerAngles.y);g.World.RefreshVisibility();var sample=g.World.RoomVisibilityForQa(room);
                sample["port"]=(string)port["port_id"];sample["approachDistance"]=distance;sample["approachAngle"]=angle;
                if((int)sample["inFrustumBatches"]==0){skipped++;continue;}
                observations.Add(sample);seen.Add(room);int missing=(int)sample["hiddenInFrustumBatches"];hidden+=missing;
                if(!legacy)Check(missing==0,"visible doorway geometry retained "+port["port_id"]+" / "+distance+"m / "+angle+"deg");
                if(observations.Count%12==0)yield return null;
            }
            Check(observations.Count>=35,"visibility sweep contains representative supported unobstructed doorway poses");Check(seen.Count>=25,"visibility sweep covers at least25 authored rooms");
            // Cross the actual old bound threshold repeatedly, looking through room35's gate.
            var entry=g.World.Manifest["corridor"]["room_ports"].First(p=>(int)p["room_id"]==35);var point=OriginDungeonWorld.Point(entry["position"]);var forward=OriginDungeonWorld.Point(entry["forward"]);var crossing=new JArray();
            foreach(float d in new[]{4.8f,4.95f,5.05f,5.2f,6f,5.2f,5.05f,4.95f,4.8f})
            {
                var at=point-forward*d;at.y=.05f;g.Teleport(at,Quaternion.LookRotation(forward).eulerAngles.y);g.World.RefreshVisibility();var sample=g.World.RoomVisibilityForQa(35);sample["approachDistance"]=d;crossing.Add(sample);
                if(!legacy)Check((int)sample["hiddenInFrustumBatches"]==0,"room35 survives former distance boundary "+d+"m");yield return null;
            }
            visibilityReport=new JObject{["legacy5mRule"]=legacy,["reportedPose"]=reproduction,["doorwaySamples"]=observations.Count,["roomsCovered"]=seen.Count,["skippedOccludedOrUnsupported"]=skipped,["hiddenVisibleBatchObservations"]=hidden,["thresholdCrossings"]=crossing,["samples"]=observations};
            File.WriteAllText(Path.Combine(folder,"visibility.json"),visibilityReport.ToString());g.NewGame();g.World.Gate.Toggle(g.World.Gate.transform.position+Vector3.forward*2.1f);for(int i=0;i<60;i++)g.World.Gate.Advance(1f/60);
        }
    }
}
