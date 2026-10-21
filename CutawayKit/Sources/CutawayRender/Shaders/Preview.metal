#include <metal_stdlib>
using namespace metal;

// The preview: each layer is a quad given in homogeneous clip space by the scene, drawn with
// its image, a tint when highlighted, and a border; then the marks over all of them. Colours
// are premultiplied.

struct LayerVertex {
    float4 position;
    float2 uv;
};

struct LayerVertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex LayerVertexOut layerVertex(
    uint vertexID [[vertex_id]], const device LayerVertex *vertices [[buffer(0)]]
) {
    LayerVertexOut out;
    out.position = vertices[vertexID].position;
    out.uv = vertices[vertexID].uv;
    return out;
}

// The image times the layer's opacity, clamped to 0...1 because the wire does not bound it.
fragment float4 layerTextureFragment(
    LayerVertexOut in [[stage_in]], texture2d<float> image [[texture(0)]],
    sampler imageSampler [[sampler(0)]], constant float &opacity [[buffer(0)]]
) {
    return image.sample(imageSampler, in.uv) * clamp(opacity, 0.0, 1.0);
}

fragment float4 layerColorFragment(
    LayerVertexOut in [[stage_in]], constant float4 &color [[buffer(0)]]
) {
    return color;
}

// Matches `HatchSettings` in Renderer.swift.
struct HatchSettings {
    float4 color;
    float4 alternate;
    // One stripe's width across, in pixels.
    float width;
    float opacity;
};

// Stripes at 45° of two colours in turn, placed by the pixel on the target so that they are
// as wide at every zoom and every turn of the camera (C-REND-11).
fragment float4 hatchFragment(
    LayerVertexOut in [[stage_in]], constant HatchSettings &hatch [[buffer(0)]]
) {
    float across = (in.position.x + in.position.y) * M_SQRT1_2_F;
    bool first = fmod(floor(across / max(hatch.width, 1.0)), 2.0) == 0.0;
    return (first ? hatch.color : hatch.alternate) * clamp(hatch.opacity, 0.0, 1.0);
}

// A line: one instance for each pair of ends in the vertex buffer, drawn as a strip of four
// corners around it on the screen. Each pixel takes as much of the line's colour as the line
// covers of it, so that a line at any angle is smooth instead of stepping from pixel to pixel.
// Each end's uv.x is its distance in viewport points from the start of the line, for the
// dashes. Both are carried without perspective correction: they are measured on the screen.
struct LineVertexOut {
    float4 position [[position]];
    float across [[center_no_perspective]];
    float distance [[center_no_perspective]];
    float halfWidth [[flat]];
};

// Matches `LineSettings` in Renderer.swift.
struct LineSettings {
    // Half the target's size in pixels.
    float2 halfTarget;
    // Half the line's width in pixels.
    float halfWidth;
    // Whether lines straight across or down the screen lie on whole pixels.
    uint snaps;
    // Whether the lines go round a shape, each from where the one before it ends.
    uint closed;
};

vertex LineVertexOut lineVertex(
    uint vertexID [[vertex_id]], uint instanceID [[instance_id]],
    const device LayerVertex *vertices [[buffer(0)]],
    constant LineSettings &settings [[buffer(1)]]
) {
    LayerVertex from = vertices[2 * instanceID], to = vertices[2 * instanceID + 1];
    bool atEnd = (vertexID & 1) != 0;
    float side = vertexID < 2 ? -1.0 : 1.0;
    float4 position = atEnd ? to.position : from.position;
    float2 halfTarget = settings.halfTarget;
    float halfWidth = settings.halfWidth;
    // The strip reaches a pixel past the line, for the pixels it covers only in part.
    float reach = halfWidth + 1.0;

    LineVertexOut out;
    out.across = side * reach;
    out.halfWidth = halfWidth;
    // An end at or behind the eye has no place on the screen: the line is left out.
    if (from.position.w <= 1e-6 || to.position.w <= 1e-6) {
        out.position = float4(0, 0, 0, 1);
        out.distance = 0;
        return out;
    }
    float2 a = from.position.xy / from.position.w * halfTarget;
    float2 b = to.position.xy / to.position.w * halfTarget;
    // In 2D a line straight across or down the screen lies on whole pixels, as crisp as it
    // can be: one of an odd number of pixels wide through their middle, otherwise along their
    // edges. Nothing moves there but by panning and zooming. A line seen at an angle in 3D is
    // left where it is, so that it glides as the view turns instead of jumping a pixel.
    if (settings.snaps != 0) {
        float offset = fmod(round(2.0 * halfWidth), 2.0) == 1.0 ? 0.5 : 0.0;
        if (abs(b.x - a.x) < 0.01) {
            a.x = b.x = floor(a.x + halfTarget.x) + offset - halfTarget.x;
        }
        if (abs(b.y - a.y) < 0.01) {
            a.y = b.y = floor(a.y + halfTarget.y) + offset - halfTarget.y;
        }
    }
    float2 along = b - a;
    float length = metal::length(along);
    float2 direction = length > 0 ? along / length : float2(1, 0);
    float2 normal = float2(-direction.y, direction.x);
    // A line on its own goes on past each end by half its width, so that it is square at both.
    // Round a shape, each line starts half a width early and ends half a width short: the
    // square at each corner is covered by one line only, and is not darker where two
    // translucent lines would overlap. The distance moves with the ends, or the dashes would
    // stretch over the strip.
    float before = halfWidth, after = settings.closed != 0 ? -halfWidth : halfWidth;
    float2 placed = (atEnd ? b : a) + normal * side * reach
        + direction * (atEnd ? after : -before);
    float pointsPerPixel = length > 0 ? (to.uv.x - from.uv.x) / length : 0;
    out.distance = atEnd ? to.uv.x + after * pointsPerPixel : from.uv.x - before * pointsPerPixel;
    out.position = float4(placed / halfTarget * position.w, position.z, position.w);
    return out;
}

// How much of a pixel this far across a line of this half width the line covers: the overlap
// of the pixel's span with the line's.
static float lineCoverage(float across, float halfWidth) {
    float d = abs(across);
    return clamp(min(d + 0.5, halfWidth) - max(d - 0.5, -halfWidth), 0.0, 1.0);
}

fragment float4 lineFragment(LineVertexOut in [[stage_in]], constant float4 &color [[buffer(0)]]) {
    return color * lineCoverage(in.across, in.halfWidth);
}

// 4 points drawn, 3 left out, starting with a dash at the start of the line.
fragment float4 dashFragment(LineVertexOut in [[stage_in]], constant float4 &color [[buffer(0)]]) {
    if (fmod(in.distance, 7.0) >= 4.0) {
        discard_fragment();
    }
    return color * lineCoverage(in.across, in.halfWidth);
}

// 1.5 points drawn, 2.5 left out, starting with a dot at the start of the line: finer than
// the dashes, for the links between a measured box and its copy on another level (C-REND-09).
fragment float4 dotFragment(LineVertexOut in [[stage_in]], constant float4 &color [[buffer(0)]]) {
    if (fmod(in.distance, 4.0) >= 1.5) {
        discard_fragment();
    }
    return color * lineCoverage(in.across, in.halfWidth);
}
