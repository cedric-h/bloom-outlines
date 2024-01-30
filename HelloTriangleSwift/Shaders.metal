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

fragment float4 outlineFragmentShader(
    OutlineRasterizerData in [[stage_in]]
) {
    return in.color;
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

fragment float4 fullscreenFragmentShader(
    FullscreenRasterizerData in [[stage_in]],
    texture2d<float, access::sample> colorTexture [[ texture(0) ]]
) {
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear);
    
    return colorTexture.sample(textureSampler, in.uv);
}
/* =================== FULLSCREEN RENDER SHADERS =================== */
