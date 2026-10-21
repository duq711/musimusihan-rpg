using System.Collections.Generic;
using System.Linq;
using UnityEngine;
using UnityEngine.Rendering;

namespace MusimusihanRpg.GothicOrigin
{
    /// <summary>New graphic first-person equipment, authored without realistic arm assets.</summary>
    public static class OriginSculpt
    {
        static Mesh bevel;
        static Mesh BevelBox()
        {
            if(bevel!=null)return bevel;var vertices=new List<Vector3>();var triangles=new List<int>();
            void Face(params Vector3[] points){var normal=Vector3.Cross(points[1]-points[0],points[2]-points[0]);var center=points.Aggregate(Vector3.zero,(a,b)=>a+b)/points.Length;if(Vector3.Dot(normal,center)<0)System.Array.Reverse(points);int at=vertices.Count;vertices.AddRange(points);for(int i=1;i<points.Length-1;i++){triangles.Add(at);triangles.Add(at+i);triangles.Add(at+i+1);}}
            const float a=.5f,b=.38f;
            for(int axis=0;axis<3;axis++)for(int sign=-1;sign<=1;sign+=2){var p=new Vector3[4];for(int i=0;i<4;i++){p[i][axis]=sign*a;p[i][(axis+1)%3]=(i==0||i==3?-b:b);p[i][(axis+2)%3]=(i<2?-b:b);}Face(p);}
            for(int axis=0;axis<3;axis++)for(int s=-1;s<=1;s+=2)for(int t=-1;t<=1;t+=2){var p=new Vector3[4];for(int i=0;i<4;i++){p[i][axis]=i<2?-b:b;p[i][(axis+1)%3]=s*(i==0||i==3?a:b);p[i][(axis+2)%3]=t*(i==0||i==3?b:a);}Face(p);}
            for(int x=-1;x<=1;x+=2)for(int y=-1;y<=1;y+=2)for(int z=-1;z<=1;z+=2)Face(new Vector3(x*a,y*b,z*b),new Vector3(x*b,y*a,z*b),new Vector3(x*b,y*b,z*a));
            bevel=new Mesh{name="Bevelled graphic armour"};bevel.SetVertices(vertices);bevel.SetTriangles(triangles,0);bevel.RecalculateNormals();bevel.RecalculateBounds();return bevel;
        }
        static void Batch(Transform hand)
        {
            foreach(var group in hand.GetComponentsInChildren<MeshRenderer>().GroupBy(r=>r.sharedMaterial))
            {
                var parts=group.ToArray();var combined=new Mesh{name="Gothic equipment batch"};combined.CombineMeshes(parts.Select(r=>new CombineInstance{mesh=r.GetComponent<MeshFilter>().sharedMesh,transform=hand.worldToLocalMatrix*r.transform.localToWorldMatrix}).ToArray(),true,true);combined.RecalculateBounds();var node=new GameObject("Painted equipment");node.transform.SetParent(hand,false);node.AddComponent<MeshFilter>().sharedMesh=combined;var renderer=node.AddComponent<MeshRenderer>();renderer.sharedMaterial=group.Key;renderer.shadowCastingMode=ShadowCastingMode.Off;renderer.receiveShadows=false;combined.UploadMeshData(true);foreach(var part in parts){part.enabled=false;Object.Destroy(part.gameObject);}
            }
        }
        public sealed class Gear {public Transform Root,Sword,Shield;}
        static GameObject Part(Transform parent,PrimitiveType shape,Vector3 at,Vector3 size,Material material,Vector3 angles=default)
        {
            var node=GameObject.CreatePrimitive(shape);node.transform.SetParent(parent,false);node.transform.localPosition=at;node.transform.localScale=size;node.transform.localEulerAngles=angles;
            if(shape==PrimitiveType.Cube)node.GetComponent<MeshFilter>().sharedMesh=BevelBox();
            Object.Destroy(node.GetComponent<Collider>());var r=node.GetComponent<MeshRenderer>();r.sharedMaterial=material;r.shadowCastingMode=ShadowCastingMode.Off;r.receiveShadows=false;return node;
        }
        public static Gear Hands(Transform camera)
        {
            var root=new GameObject("NewGothicEquipment").transform;root.SetParent(camera,false);root.localPosition=new Vector3(0,-.32f,.8f);root.localScale=Vector3.one*.5f;
            var right=new GameObject("SwordHand").transform;right.SetParent(root,false);right.localPosition=new Vector3(.44f,-.12f,0);right.localEulerAngles=new Vector3(0,0,-10);
            var left=new GameObject("ShieldHand").transform;left.SetParent(root,false);left.localPosition=new Vector3(-.42f,-.12f,0);
            var leather=OriginPaint.Solid("Oxblood ink leather",new Color(.28f,.16f,.16f));var gold=OriginPaint.Solid("Aged ochre iron",new Color(.54f,.39f,.19f));var steel=OriginPaint.Solid("Painted silver",new Color(.68f,.72f,.66f));var ink=OriginPaint.Solid("Warm black rim",new Color(.035f,.045f,.06f));var wood=OriginPaint.Solid("Painted walnut",new Color(.32f,.22f,.16f));
            foreach(var hand in new[]{right,left})
            {
                Part(hand,PrimitiveType.Cube,new Vector3(.02f,-.23f,-.15f),new Vector3(.17f,.38f,.2f),ink,new Vector3(-25,0,0));
                Part(hand,PrimitiveType.Cube,Vector3.zero,new Vector3(.18f,.2f,.16f),leather);
                for(int i=0;i<4;i++)Part(hand,PrimitiveType.Cube,new Vector3(-.065f+i*.043f,.025f,.095f),new Vector3(.035f,.085f,.05f),gold);
            }
            Part(right,PrimitiveType.Cylinder,new Vector3(0,.1f,0),new Vector3(.075f,.15f,.075f),wood);
            Part(right,PrimitiveType.Cube,new Vector3(0,.25f,0),new Vector3(.43f,.055f,.09f),ink);
            Part(right,PrimitiveType.Cube,new Vector3(0,.265f,-.01f),new Vector3(.4f,.035f,.07f),gold);
            // A tapered diamond section gives the blade graphic light planes.
            var blade=new GameObject("ForgedBlade");blade.transform.SetParent(right,false);var mesh=new Mesh();
            var v=new[]{new Vector3(-.08f,.29f,0),new Vector3(.08f,.29f,0),new Vector3(0,.29f,-.035f),new Vector3(0,1.34f,0),new Vector3(0,.29f,.035f)};
            mesh.vertices=v;mesh.triangles=new[]{0,3,2,2,3,1,1,3,4,4,3,0};mesh.RecalculateNormals();mesh.RecalculateBounds();blade.AddComponent<MeshFilter>().sharedMesh=mesh;blade.AddComponent<MeshRenderer>().sharedMaterial=steel;
            Part(right,PrimitiveType.Sphere,new Vector3(0,-.13f,0),new Vector3(.12f,.1f,.1f),gold);
            Part(left,PrimitiveType.Cylinder,new Vector3(0,.02f,.1f),new Vector3(.62f,.045f,.62f),ink,new Vector3(90,0,0));
            Part(left,PrimitiveType.Cylinder,new Vector3(0,.02f,.135f),new Vector3(.55f,.035f,.55f),wood,new Vector3(90,0,0));
            Part(left,PrimitiveType.Sphere,new Vector3(0,.02f,.18f),new Vector3(.14f,.14f,.09f),gold);
            for(int i=0;i<8;i++){float a=i*Mathf.PI/4;Part(left,PrimitiveType.Sphere,new Vector3(Mathf.Sin(a)*.287f,.02f+Mathf.Cos(a)*.287f,.145f),Vector3.one*.028f,gold);}
            if(System.Environment.GetEnvironmentVariable("ORIGIN_UNBATCHED_GEAR")!="1"){Batch(right);Batch(left);}return new Gear{Root=root,Sword=right,Shield=left};
        }
    }
}
