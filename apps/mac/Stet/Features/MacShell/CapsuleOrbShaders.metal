#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float noise2D(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);

    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));

    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float fbm(float2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * noise2D(p);
        float2 rp = float2(
            p.x * 0.80 + p.y * 0.60,
           -p.x * 0.60 + p.y * 0.80
        );
        p = rp * 2.0 + float2(10.0);
        a *= 0.5;
    }
    return v;
}

static float2 domainWarp(float2 p, float t) {
    float2 q = float2(
        fbm(p + float2(0.0, 0.0) + t * 0.05),
        fbm(p + float2(5.2, 1.3) - t * 0.04)
    );
    float2 r = float2(
        fbm(p + 3.0 * q + float2(1.7, 9.2) + t * 0.02),
        fbm(p + 3.0 * q + float2(8.3, 2.8) - t * 0.02)
    );
    return r;
}

// Capsule shader for the floating voice pill.
[[ stitchable ]] half4 cloudOrbGlassWide(
    float2 position,
    half4 currentColor,
    float2 size,
    float time,
    float audio
) {
    float2 safeSize = float2(max(size.x, 1.0), max(size.y, 1.0));
    float2 uv = position / safeSize;
    float aspect = safeSize.x / safeSize.y;

    float2 p = float2((uv.x - 0.5) * 2.0 * aspect,
                      (uv.y - 0.5) * 2.0);

    p.y += (0.015 + audio * 0.025) * sin(time * 6.28318 / 4.0);

    float warpSpeed = 1.0 + audio * 0.4;
    float warpStrength = 1.2 + audio * 0.5;
    float2 w = domainWarp(p * 0.5, time * warpSpeed);
    float n = fbm(p * 0.8 + w * warpStrength + float2(0.0, time * 0.06));
    n = smoothstep(0.15, 0.95, n);

    float h = smoothstep(-1.0, 1.0, p.y + (n - 0.5) * 0.55);

    float3 top = float3(0.929, 0.549, 0.325);
    float3 mid = float3(0.855, 0.596, 0.855);
    float3 low = float3(0.702, 0.745, 0.980);

    float3 base = mix(low, top, h);
    base = mix(base, mid, 0.38 * (1.0 - h));

    float cloud = smoothstep(0.55, 0.90, n) * (0.55 + 0.45 * h);
    base = mix(base, float3(1.0), cloud * (0.55 + audio * 0.15));

    float2 sunPos = float2(aspect * 0.3, 0.4);
    float sun = exp(-dot(p - sunPos, p - sunPos) * 0.8);
    base = mix(base, float3(1.0, 0.98, 0.92), sun * 0.10);

    float vignette = smoothstep(0.3, 1.3, length(p / float2(aspect, 1.0)));
    base *= 1.0 - vignette * 0.10;

    base += float3(0.08, 0.06, 0.03) * audio;
    base = clamp(base, 0.0, 1.0);

    return half4(half3(base), half(float(currentColor.a)));
}
