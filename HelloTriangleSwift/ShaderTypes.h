//
//  ShaderTypes.h
//  HelloTriangleSwift
//
//  Created by Peter Edmonston on 10/7/18.
//  Copyright © 2018 com.peteredmonston. All rights reserved.
//

#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

// Buffer index values shared between shader and C code to ensure Metal shader buffer inputs match
//   Metal API buffer set calls
typedef enum VertexInputIndex
{
    VertexInputIndexVertices     = 0,
} VertexInputIndex;

typedef struct
{
    // Positions in pixel space
    // (e.g. a value of 100 indicates 100 pixels from the center)
    vector_float4 pos;

    // Floating-point RGBA colors
    vector_float4 color;
} OutlineVertex;

typedef struct
{
    vector_float2 pos;
    vector_float2 uv;
} FullscreenVertex;

#endif
