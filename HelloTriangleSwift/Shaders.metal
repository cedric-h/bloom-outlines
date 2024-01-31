#include <metal_stdlib>
#include <simd/simd.h>
#include "ShaderTypes.h"

using namespace metal;

/* =================== OUTLINE RENDER SHADERS =================== */
typedef struct {
    float4 pos [[position]];
    float4 color;
} OutlineRasterizerData;

vertex OutlineRasterizerData outlineVertexShader(
    uint vertexID [[vertex_id]],
    constant OutlineVertex *vertices [[buffer(VertexInputIndexVertices)]]
) {
    OutlineRasterizerData out;
    
    out.pos   = vertices[vertexID].pos;
    out.color = vertices[vertexID].color;
    
    return out;
}

struct OutlineFragmentOut {
    float4 raw   [[ color(0) ]];
    float4 bloom [[ color(1) ]];
};

fragment OutlineFragmentOut outlineFragmentShader(
    OutlineRasterizerData in [[stage_in]]
) {
    return (OutlineFragmentOut) {
        .raw = in.color * (in.color.a == 1.0),
        .bloom = in.color
    };
}
/* =================== OUTLINE RENDER SHADERS =================== */

/* =================== FULLSCREEN RENDER SHADERS =================== */
typedef struct {
    float4 pos [[position]];
    float2 uv;
} FullscreenRasterizerData;

vertex FullscreenRasterizerData fullscreenVertexShader(
    uint vertexID [[vertex_id]],
    constant FullscreenVertex *vertices [[buffer(VertexInputIndexVertices)]]
) {
    FullscreenRasterizerData out;
    
    out.pos = float4(vertices[vertexID].pos, 0.0, 1.0);
    out.uv = vertices[vertexID].uv;
    
    return out;
}

float linear_to_srgb(float x)
{
    if (x <= 0.0031308f) {
        return 12.92f * x;
    }
    return 1.055f * pow(x, 1.f / 2.4f) - 0.055f;
}

fragment float4 fullscreenFragmentShader(
    FullscreenRasterizerData in [[stage_in]],
    texture2d<float, access::sample> rawTexture [[ texture(0) ]],
    texture2d<float, access::sample> bloomTexture [[ texture(1) ]]
) {
    constexpr sampler ts (mag_filter::linear,
                                      min_filter::linear);
    
    float4 out = 1.0*bloomTexture.sample(ts, in.uv) + rawTexture.sample(ts, in.uv);
    out.x = linear_to_srgb(out.x);
    out.y = linear_to_srgb(out.y);
    out.z = linear_to_srgb(out.z);
    return out;
}
/* =================== FULLSCREEN RENDER SHADERS =================== */
