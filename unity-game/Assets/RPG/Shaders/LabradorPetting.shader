Shader "RPG/Labrador Petting"
{
    Properties
    {
        _MainTex ("Coat color", 2D) = "white" {}
        _BumpMap ("Coat normal", 2D) = "bump" {}
        _BumpScale ("Normal strength", Range(0, 1)) = 0
        _MetallicGlossMap ("Metallic and smoothness", 2D) = "white" {}
        _GlossMapScale ("Smoothness scale", Range(0, 1)) = 1
        _PetStrokeOrigin ("Stroke world point", Vector) = (0,0,0,0)
        _PetStrokeDirection ("Stroke world direction", Vector) = (0,0,0,0)
        _PetStrokeStrength ("Stroke strength", Range(0, 1)) = 0
        _PetStrokeRadius ("Stroke radius in metres", Float) = 0.065
        _PetCoatMask ("Use authored coat vertex mask", Float) = 1
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        Cull Off
        LOD 300
        CGPROGRAM
        #pragma surface surf Standard fullforwardshadows vertex:combCoat addshadow
        #pragma target 3.0
        #include "UnityCG.cginc"
        sampler2D _MainTex, _BumpMap, _MetallicGlossMap;
        half _BumpScale, _GlossMapScale, _PetStrokeStrength, _PetCoatMask;
        float _PetStrokeRadius;
        float4 _PetStrokeOrigin, _PetStrokeDirection;
        struct Input
        {
            float2 uv_MainTex;
            float2 uv_BumpMap;
            float2 uv_MetallicGlossMap;
            half petWeight;
            half2 petComb;
            float facing : VFACE;
        };
        void combCoat(inout appdata_full v, out Input o)
        {
            UNITY_INITIALIZE_OUTPUT(Input, o);
            float3 world = mul(unity_ObjectToWorld, v.vertex).xyz;
            float3 normal = UnityObjectToWorldNormal(v.normal);
            float3 direction = _PetStrokeDirection.xyz;
            direction -= normal * dot(direction, normal);
            direction /= max(length(direction), 0.0001);
            float radius = max(_PetStrokeRadius, 0.005);
            float d = saturate(distance(world, _PetStrokeOrigin.xyz) / radius);
            float mask = lerp(1, saturate(v.color.r), saturate(_PetCoatMask));
            float weight = (1-d*d) * (1-d*d) * saturate(_PetStrokeStrength) * mask;
            // Short Labrador coat: under one millimetre of tangent displacement.
            v.vertex.xyz += mul((float3x3)unity_WorldToObject, direction * weight * 0.0009);
            float3 tangent = UnityObjectToWorldDir(v.tangent.xyz);
            float3 bitangent = cross(normal, tangent) * v.tangent.w * unity_WorldTransformParams.w;
            o.petWeight = weight;
            o.petComb = half2(dot(direction,tangent), dot(direction,bitangent));
        }
        void surf(Input i, inout SurfaceOutputStandard o)
        {
            fixed4 color = tex2D(_MainTex, i.uv_MainTex);
            half4 metal = tex2D(_MetallicGlossMap, i.uv_MetallicGlossMap);
            half3 normal = UnpackScaleNormal(tex2D(_BumpMap, i.uv_BumpMap), _BumpScale);
            normal.xy += i.petComb * i.petWeight * 0.035;
            o.Albedo = color.rgb;
            o.Normal = normalize(normal) * (i.facing >= 0 ? 1 : -1);
            o.Metallic = metal.r;
            o.Smoothness = metal.a * _GlossMapScale;
            o.Occlusion = 1;
            o.Alpha = 1;
        }
        ENDCG
    }
    FallBack "Standard"
}
