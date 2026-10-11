#include <metal_stdlib>
using namespace metal;

// Toolchain probe: one triangle that covers the whole render target, filled with a fixed
// colour. It shows that the package's Metal sources compile and run; the preview's shaders are
// in Preview.metal.

struct ProbeVertexOut {
    float4 position [[position]];
};

vertex ProbeVertexOut probeVertex(uint vertexID [[vertex_id]]) {
    // (0,0), (2,0), (0,2) in unit space: after mapping to clip space the triangle
    // covers the whole viewport.
    float2 unit = float2((vertexID << 1) & 2, vertexID & 2);
    ProbeVertexOut out;
    out.position = float4(unit * 2.0 - 1.0, 0.0, 1.0);
    return out;
}

fragment float4 probeFragment(ProbeVertexOut in [[stage_in]]) {
    return float4(1.0, 0.5, 0.0, 1.0);
}
