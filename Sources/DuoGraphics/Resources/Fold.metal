#include <metal_stdlib>
using namespace metal;

struct FoldUniforms {
    float tilt;
    float eyeDistance;
    float blurSigma;
    float darkness;
    float progress;
    float sourceHeight;
    float perspective;
    float sourceBlend;
};
struct VertexOut { float4 position [[position]]; float2 uv; };

vertex VertexOut foldVertex(uint id [[vertex_id]]) {
    // Oversized triangle: UV origin at top-left, matching ScreenCaptureKit's image.
    float2 p = float2((id << 1) & 2, id & 2);
    return {float4(p * float2(2, -2) + float2(-1, 1), 0, 1), p};
}

kernel void copyLinear(texture2d<float, access::sample> source [[texture(0)]],
                       texture2d<half, access::write> target [[texture(1)]],
                       uint2 p [[thread_position_in_grid]]) {
    if (p.x >= target.get_width() || p.y >= target.get_height()) return;
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 uv = (float2(p) + 0.5) / float2(target.get_width(), target.get_height());
    target.write(half4(half3(source.sample(s, uv).rgb), 1.0h), p);
}

// A Gaussian pyramid is built once per screenshot, not once per animation frame.
// Each new level convolves the previous one with a separable binomial 5x5 kernel.
kernel void gaussianLevel(texture2d<half, access::sample> source [[texture(0)]],
                          texture2d<half, access::write> target [[texture(1)]],
                          uint2 p [[thread_position_in_grid]]) {
    if (p.x >= target.get_width() || p.y >= target.get_height()) return;
    constexpr sampler s(coord::normalized, address::clamp_to_zero, filter::linear);
    const float weights[5] = {1.0/16, 4.0/16, 6.0/16, 4.0/16, 1.0/16};
    float2 texel = 1.0 / float2(source.get_width(), source.get_height());
    float2 uv = (float2(p) + 0.5) / float2(target.get_width(), target.get_height());
    float3 sum = 0;
    for (int y = -2; y <= 2; ++y)
        for (int x = -2; x <= 2; ++x)
            sum += float3(source.sample(s, uv + float2(x, y) * texel).rgb) * weights[x+2] * weights[y+2];
    target.write(half4(half3(sum), 1), p);
}

fragment half4 foldFragment(VertexOut in [[stage_in]],
                            texture2d<half> image [[texture(0)]],
                            texture2d<half> previousImage [[texture(1)]],
                            constant FoldUniforms &u [[buffer(0)]]) {
    constexpr sampler s(coord::normalized, address::clamp_to_zero, filter::linear, mip_filter::linear);
    float d = 1.0 - in.uv.y;
    float gap = d * sin(u.tilt);
    // Both movement directions fold inward visually. Returning to zero restores
    // normal size; opening must never magnify the desktop beyond that size.
    float projectedTilt = clamp(abs(u.tilt) * u.perspective, 0.0, 1.48);
    float projectedGap = d * sin(projectedTilt);
    // World coordinates normalized by screen height; y points down, z toward the viewer.
    // Bottom edge is the fixed hinge. Trace eye -> moving glass -> original UI plane.
    float glassY = 1.0 - d * cos(projectedTilt);
    float t = u.eyeDistance / max(0.01, u.eyeDistance - projectedGap);
    float2 hit = 0.5 + (float2(in.uv.x, glassY) - 0.5) * t;
    // Spatially varying defocus: continuous across pixels and fractional pyramid levels.
    float sigma = u.blurSigma * u.sourceHeight * pow(abs(gap), 0.9);
    float lod = 0.5 * log2(1.0 + 3.0 * sigma * sigma);
    half3 color = image.sample(s, hit, level(lod)).rgb;
    if (u.sourceBlend < 1.0) {
        color = mix(previousImage.sample(s, hit, level(lod)).rgb, color, half(u.sourceBlend));
    }
    // Strong top-down shadow: the hinge stays clear while the far edge reaches black early.
    float transmission = max(0.0, 1.0 - 2.6 * u.darkness * pow(abs(gap), 0.8));
    float absorption = transmission * transmission;
    float shut = 1.0 - smoothstep(0.88, 1.0, u.progress);
    return half4(color * half(absorption * shut), 1);
}
