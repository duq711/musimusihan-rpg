Shader "GothicOrigin/InkPaint"
{
    Properties
    {
        _Color("Pigment",Color)=(1,1,1,1)
        _MainTex("Authored colour",2D)="white"{}
        _Ink("Ink surface",Float)=0
        _Emissive("Ember",Float)=0
        _Cutoff("Cutout",Range(0,1))=.08
        [Enum(UnityEngine.Rendering.BlendMode)] _SrcBlend("Source",Int)=1
        [Enum(UnityEngine.Rendering.BlendMode)] _DstBlend("Destination",Int)=0
        [Enum(Off,0,On,1)] _ZWrite("Depth",Int)=1
        [Enum(UnityEngine.Rendering.CullMode)] _Cull("Authored face culling",Int)=2
    }
    SubShader
    {
        Tags {"RenderType"="Opaque" "Queue"="Geometry"}
        Pass
        {
            Blend [_SrcBlend] [_DstBlend]
            ZWrite [_ZWrite]
            Cull [_Cull]
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0
            #include "UnityCG.cginc"
            sampler2D _MainTex;float4 _MainTex_ST,_Color,_InkEye,_InkLamps[4],_InkLampColors[4];float _Ink,_Emissive,_Cutoff;
            struct appdata {float4 vertex:POSITION;float3 normal:NORMAL;float2 uv:TEXCOORD0;float4 color:COLOR;};
            struct v2f {float4 vertex:SV_POSITION;float3 world:TEXCOORD0;float3 normal:TEXCOORD1;float2 uv:TEXCOORD2;float4 color:COLOR;};
            v2f vert(appdata v){v2f o;o.vertex=UnityObjectToClipPos(v.vertex);o.world=mul(unity_ObjectToWorld,v.vertex).xyz;o.normal=UnityObjectToWorldNormal(v.normal);o.uv=TRANSFORM_TEX(v.uv,_MainTex);o.color=v.color;return o;}
            fixed4 frag(v2f i,fixed facing:VFACE):SV_Target
            {
                float4 pigment=tex2D(_MainTex,i.uv)*_Color*i.color;clip(pigment.a-_Cutoff);
                float3 n=normalize(i.normal)*(facing>=0?1:-1);float key=dot(n,normalize(float3(-.45,1,.32)))*.5+.5;
                float band=key<.36?.27:(key<.72?.59:1.0);
                float brush=sin(i.world.x*2.1+i.world.y*2.7)*sin(i.world.z*3.7+i.world.y*.9)*.025;
                float3 c=pigment.rgb*(band+brush);
                float carry=exp(-distance(i.world,_InkEye.xyz)*.45)*max(.12,dot(n,normalize(_InkEye.xyz+float3(-.4,.1,.2)-i.world)));
                c+=float3(.085,.037,.012)*carry;
                [unroll]for(int k=0;k<4;k++){float d=distance(i.world,_InkLamps[k].xyz);c+=_InkLampColors[k].rgb*exp(-d*.5)*max(.08,dot(n,normalize(_InkLamps[k].xyz-i.world)))*.075*_InkLamps[k].w;}
                c=lerp(c,pigment.rgb*.3,_Ink);c=lerp(c,pigment.rgb*1.3,_Emissive);
                float fog=1-exp(-max(0,distance(i.world,_InkEye.xyz)-10)*.018);c=lerp(c,float3(.035,.055,.07),fog);
                return float4(c,pigment.a);
            }
            ENDCG
        }
    }
}
