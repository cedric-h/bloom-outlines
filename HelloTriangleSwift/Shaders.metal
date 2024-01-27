#include <metal_stdlib>
#include <simd/simd.h>
#include "ShaderTypes.h"

using namespace metal;

typedef struct {
    float4 pos [[position]];
    float4 color;
} RasterizerData;

vertex RasterizerData vertexShader(
    uint vertexID [[vertex_id]],
    constant Vertex *vertices [[buffer(VertexInputIndexVertices)]]
) {
    RasterizerData out;
    
    out.pos   = vertices[vertexID].pos;
    out.color = vertices[vertexID].color;
    
    return out;
}

fragment float4 fragmentShader(
    RasterizerData in [[stage_in]]
) {
    return in.color;
}
