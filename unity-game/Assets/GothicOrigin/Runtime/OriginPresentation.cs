using System;
using UnityEngine;

namespace MusimusihanRpg.GothicOrigin
{
    /// <summary>Budget3D pixels while retaining complete rooms and native-resolution UI.</summary>
    public sealed class OriginPresentation:MonoBehaviour
    {
        Camera world,composition;Canvas canvas;UnityEngine.UI.RawImage surface;RenderTexture scene;
        bool qaConfigured,fullResolutionQa;int outputWidth,outputHeight;
        public RenderTexture Scene=>scene;
        public void Initialize(Camera view,Canvas ui)
        {
            world=view;canvas=ui;world.cullingMask&=~(1<<5);
            var node=new GameObject("DungeonSurface",typeof(RectTransform),typeof(UnityEngine.UI.RawImage));node.layer=5;node.transform.SetParent(canvas.transform,false);node.transform.SetAsFirstSibling();
            var rect=node.GetComponent<RectTransform>();rect.anchorMin=Vector2.zero;rect.anchorMax=Vector2.one;rect.offsetMin=rect.offsetMax=Vector2.zero;surface=node.GetComponent<UnityEngine.UI.RawImage>();surface.raycastTarget=false;
            Resize(Screen.width,Screen.height,false);
        }
        void Resize(int width,int height,bool full)
        {
            width=Mathf.Max(1,width);height=Mathf.Max(1,height);outputWidth=width;outputHeight=height;
            float scale=full?1:Mathf.Min(1,Mathf.Min(1280f/width,900f/height));int w=Mathf.Max(2,Mathf.RoundToInt(width*scale/2)*2),h=Mathf.Max(2,Mathf.RoundToInt(height*scale/2)*2);
            if(scene!=null&&scene.width==w&&scene.height==h)return;
            world.targetTexture=null;if(scene!=null){scene.Release();Destroy(scene);}
            scene=new RenderTexture(w,h,24,RenderTextureFormat.ARGB32){name="BudgetedDungeon",antiAliasing=2,filterMode=FilterMode.Bilinear,useMipMap=false};scene.Create();surface.texture=scene;world.targetTexture=scene;world.aspect=width/(float)height;
        }
        void LateUpdate(){if(!qaConfigured&&(Screen.width!=outputWidth||Screen.height!=outputHeight))Resize(Screen.width,Screen.height,false);}
        internal void ConfigureQa(RenderTexture output,bool full)
        {
            if(!OriginGame.Qa)throw new InvalidOperationException("Capture configuration is QA-only.");qaConfigured=true;fullResolutionQa=full;Resize(output.width,output.height,full);
            var root=new GameObject("UiCaptureCamera");composition=root.AddComponent<Camera>();composition.transform.position=new Vector3(0,-10000,0);composition.cullingMask=1<<5;composition.clearFlags=CameraClearFlags.SolidColor;composition.backgroundColor=Color.black;composition.nearClipPlane=.01f;composition.farClipPlane=3;composition.allowHDR=false;composition.targetTexture=output;composition.enabled=false;world.enabled=false;
            canvas.renderMode=RenderMode.ScreenSpaceCamera;canvas.worldCamera=composition;canvas.planeDistance=1;
        }
        internal void RenderQa(){world.Render();composition.Render();}
        internal string QaResolution=>scene.width+"x"+scene.height+" world, "+outputWidth+"x"+outputHeight+" UI/output";
        void OnDestroy(){if(world!=null)world.targetTexture=null;if(scene!=null){scene.Release();Destroy(scene);}if(composition!=null)Destroy(composition.gameObject);}
    }
}
