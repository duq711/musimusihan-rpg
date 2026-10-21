using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;
using UnityEngine.Rendering;

namespace MusimusihanRpg.GothicOrigin
{
    /// <summary>One authored paint shader for the reused map, gothic actors and new equipment.</summary>
    public static class OriginPaint
    {
        static readonly Dictionary<Material,Material> converted=new Dictionary<Material,Material>();
        static readonly Vector4[] positions=new Vector4[4],colours=new Vector4[4];
        public static Shader Shader=>Resources.Load<Shader>("OriginInkPaint");
        public static Material Solid(string name,Color color,float emissive=0)
        {
            var material=new Material(Shader){name=name};material.SetColor("_Color",color);
            material.SetFloat("_Emissive",emissive);return material;
        }
        public static void Apply(GameObject root)
        {
            foreach(var renderer in root.GetComponentsInChildren<MeshRenderer>(true))
            {
                var originals=renderer.sharedMaterials;var materials=new Material[originals.Length];
                for(int i=0;i<originals.Length;i++)
                {
                    var source=originals[i];if(source==null)continue;
                    if(!converted.TryGetValue(source,out var material))
                    {
                        Color color=Color.white;Texture texture=Texture2D.whiteTexture;Vector2 scale=Vector2.one,offset=Vector2.zero;
                        foreach(string p in new[]{"baseColorFactor","_BaseColor","_Color"})if(source.HasProperty(p)){color=source.GetColor(p);break;}
                        foreach(string p in new[]{"baseColorTexture","_BaseMap","_MainTex"})if(source.HasProperty(p)&&source.GetTexture(p)!=null){texture=source.GetTexture(p);scale=source.GetTextureScale(p);offset=source.GetTextureOffset(p);break;}
                        material=Solid(source.name,color);material.SetTexture("_MainTex",texture);material.SetTextureScale("_MainTex",scale);material.SetTextureOffset("_MainTex",offset);
                        bool ink=source.name.IndexOf("ink",StringComparison.OrdinalIgnoreCase)>=0||source.name.IndexOf("outline",StringComparison.OrdinalIgnoreCase)>=0;
                        material.SetFloat("_Ink",ink?1:0);
                        if(source.renderQueue>=3000){material.renderQueue=3000;material.SetInt("_SrcBlend",(int)BlendMode.SrcAlpha);material.SetInt("_DstBlend",(int)BlendMode.OneMinusSrcAlpha);material.SetInt("_ZWrite",0);}
                        converted[source]=material;
                    }
                    materials[i]=material;
                }
                renderer.sharedMaterials=materials;renderer.shadowCastingMode=ShadowCastingMode.Off;renderer.receiveShadows=false;
            }
        }
        public static void SetView(Vector3 eye,Light[] lights)
        {
            UnityEngine.Shader.SetGlobalVector("_InkEye",eye);
            for(int i=0;i<4;i++){var light=i<lights.Length?lights[i]:null;positions[i]=light!=null&&light.enabled?new Vector4(light.transform.position.x,light.transform.position.y,light.transform.position.z,1):Vector4.zero;colours[i]=light!=null?(Vector4)(light.color*.8f):Vector4.zero;}
            UnityEngine.Shader.SetGlobalVectorArray("_InkLamps",positions);UnityEngine.Shader.SetGlobalVectorArray("_InkLampColors",colours);
        }
    }
}
