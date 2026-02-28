#include <metal_stdlib>
using namespace metal;

// Must match the Swift ShaderUniforms struct
struct ShaderUniforms {
    float  time;
    float2 resolution;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// MARK: - Vertex: Full-Screen Triangle
// Generates a single oversized triangle that covers clip space — no vertex buffer needed.
vertex VertexOut vertexPassthrough(uint vertexID [[vertex_id]]) {
    float2 positions[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0)
    };

    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = (positions[vertexID] + 1.0) * 0.5;
    out.uv.y = 1.0 - out.uv.y;
    return out;
}

// MARK: - Fragment: Animated Aurora / Plasma Shader
fragment float4 desktopFragment(VertexOut       in       [[stage_in]],
                                constant ShaderUniforms &uniforms [[buffer(0)]]) {
    float2 uv = in.uv;
    float  t  = uniforms.time;

    // Aspect-corrected centered coordinates
    float aspect = uniforms.resolution.x / uniforms.resolution.y;
    float2 p = (uv - 0.5) * float2(aspect, 1.0);

    // ── Layered aurora-style waves ──────────────────────────────────────
    float wave1 = sin(p.x * 3.5 + t * 0.4) * cos(p.y * 2.8 + t * 0.3);
    float wave2 = sin(p.y * 4.2 - t * 0.5) * cos(p.x * 3.1 + t * 0.35);
    float wave3 = sin(length(p) * 5.0 - t * 0.7);
    float wave4 = sin((p.x * 2.0 + p.y * 3.0) * 2.5 + t * 0.6);

    float plasma = (wave1 + wave2 + wave3 + wave4) * 0.25;

    // ── Rich colour palette — deep blues, teals, purples ────────────────
    float3 col;
    col.r = 0.08 + 0.12 * sin(plasma * 3.14159 + t * 0.15 + 0.0);
    col.g = 0.12 + 0.18 * sin(plasma * 3.14159 + t * 0.15 + 1.8);
    col.b = 0.25 + 0.30 * sin(plasma * 3.14159 + t * 0.15 + 3.2);

    // Subtle bright accent bands
    float accent = smoothstep(0.4, 0.5, plasma) * smoothstep(0.6, 0.5, plasma);
    col += float3(0.05, 0.25, 0.35) * accent * 2.0;

    // Vignette — darken the edges for depth
    float vignette = 1.0 - 0.4 * dot(p, p);
    col *= vignette;

    return float4(saturate(col), 1.0);
}
