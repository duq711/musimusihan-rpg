using System.Linq;
using Newtonsoft.Json.Linq;
using UnityEngine;

namespace MusimusihanRpg.GothicOrigin
{
    public sealed partial class OriginDungeonWorld
    {
        void PrepareGate(JToken corridor)
        {
            var definition=corridor["gate"]??corridor["room35"]?["gate"]??new JObject();
            var nodes=sources.SelectMany(s=>s.GetComponentsInChildren<Transform>(true)).Distinct().ToArray();
            var left=nodes.FirstOrDefault(t=>t.name==((string)definition["leftNode"]??"Gate_Leaf_Left"));var right=nodes.FirstOrDefault(t=>t.name==((string)definition["rightNode"]??"Gate_Leaf_Right"));
            if(left==null||right==null)throw new System.IO.InvalidDataException("Room35 gate leaves missing");
            var root=new GameObject("GothicRoom35Gate");root.transform.SetParent(transform,false);
            root.transform.position=definition["position"]!=null?Point(definition["position"]):(left.position+right.position)/2;
            gate=root.AddComponent<OriginDungeonGate>();gate.Left=left;gate.Right=right;gate.Initialize();
        }
    }
    public sealed class OriginDungeonGate:MonoBehaviour
    {
        public Transform Left,Right;
        Quaternion closedLeft,closedRight;float value,target;
        public bool Open=>value>.99f;
        public bool Busy=>Mathf.Abs(value-target)>.001f;
        public void Initialize(){closedLeft=Left.localRotation;closedRight=Right.localRotation;}
        public void Rebase(){closedLeft=Left.localRotation;closedRight=Right.localRotation;}
        public void ResetClosed(){value=target=0;Left.localRotation=closedLeft;Right.localRotation=closedRight;}
        public bool Toggle(Vector3 actor)
        {
            if(Busy||Vector3.Distance(actor,transform.position)<1.3f)return false;
            target=Open?0:1;return true;
        }
        public void Advance(float dt)
        {
            value=Mathf.MoveTowards(value,target,dt/.85f);float eased=value*value*(3-2*value);
            Left.localRotation=closedLeft*Quaternion.Euler(0,83*eased,0);
            Right.localRotation=closedRight*Quaternion.Euler(0,-83*eased,0);
        }
    }
}
