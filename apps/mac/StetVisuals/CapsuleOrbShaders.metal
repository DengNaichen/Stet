#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

// MARK: - Constants
namespace Config {
    // Noise & FBM
    constant float2 HASH_VEC = float2(123.34, 456.21);
    constant float HASH_OFFSET = 45.32;
    constant int FBM_OCTAVES = 5;
    constant float FBM_INITIAL_AMP = 0.5;
    constant float FBM_AMP_DECAY = 0.5;
    constant float FBM_DOMAIN_OFFSET = 10.0;
    constant float2 FBM_ROT_ROW1 = float2(0.80, 0.60);
    constant float2 FBM_ROT_ROW2 = float2(-0.60, 0.80);
    constant float FBM_SCALE = 2.0;
    
    // Warp
    constant float2 WARP_Q_OFFSET = float2(5.2, 1.3);
    constant float2 WARP_R_OFFSET_1 = float2(1.7, 9.2);
    constant float2 WARP_R_OFFSET_2 = float2(8.3, 2.8);
    constant float WARP_Q_TIME_SKEW_A = 0.05;
    constant float WARP_Q_TIME_SKEW_B = 0.04;
    constant float WARP_R_TIME_SKEW = 0.02;
    
    // Motion
    constant float MOTION_Y_AMP = 0.010;
    constant float MOTION_Y_FREQ = 1.20;
    constant float MOTION_X_AMP = 0.006;
    constant float MOTION_X_FREQ = 0.74;
    constant float MOTION_X_Y_SKEW = 1.25;
    
    // Shape & Masking
    constant float SHAPE_CORE_Y = 5.0;
    constant float SHAPE_CORE_X = 1.6;
    constant float SHAPE_CENTER_BASE = 0.35;
    constant float SHAPE_CENTER_X_INF = 0.65;
    constant float SHAPE_SIDE_FACTOR = 0.22;
    constant float SHAPE_PUSH_BASE = 0.05;
    constant float SHAPE_PUSH_SKEW = 0.72;
    constant float SHAPE_SPREAD_FACTOR = 0.32;
    
    // Vortex
    constant float VORTEX_SOFTNESS = 0.14;
    constant float VORTEX_SPIN_BASE = 0.04;
    constant float VORTEX_SPIN_AMP = 0.28;
    
    // Rendering Params
    constant float WARP_SCALE = 0.42;
    constant float WARP_TIME_SCALE = 0.82;
    constant float FBM_NOISE_SCALE = 0.48;
    constant float FBM_WARP_SKEW_BASE = 1.20;
    constant float FBM_TIME_FLOW = 0.14;
    constant float SMOOTHSTEP_LOW = 0.10;
    constant float SMOOTHSTEP_HIGH = 0.92;
    
    // Colors & Fluid
    constant float FLUID_Y_BIAS = 0.78;
    constant float FLUID_WARP_BIAS = 0.95;
    constant float COLOR_LIFT_FACTOR = 0.08;
    constant float MASK_BLUE_LOW = 0.12;
    constant float MASK_BLUE_HIGH = 0.62;
    constant float MASK_BLUE_SKEW = 0.34;
    constant float MASK_ORANGE_LOW = 0.10;
    constant float MASK_ORANGE_HIGH = 0.60;
    constant float MASK_ORANGE_SKEW = 0.30;
    
    // Depth
    constant float DEPTH_SKEW = 0.48;
    constant float DEPTH_BLEND_BASE = 0.74;
    constant float DEPTH_BLEND_AMP = 0.26;
    
    // Cloud Appearance
    constant float CLOUD_DENSE_LOW = 0.32;
    constant float CLOUD_DENSE_HIGH = 0.80;
    constant float CLOUD_SOFT_LOW = 0.20;
    constant float CLOUD_SOFT_HIGH = 0.68;
    constant float CLOUD_SOFT_n_SKEW = 0.65;
    constant float CLOUD_SOFT_w_SKEW = 0.35;
    constant float CLOUD_LIFT_LOW = 0.28;
    constant float CLOUD_LIFT_HIGH = 0.82;
    constant float CLOUD_LIFT_n_SKEW = 0.55;
    constant float CLOUD_LIFT_w_SKEW = 0.45;
    constant float CLOUD_LIFT_CENTER_SKEW = 0.15;
    constant float CLOUD_MIX_BASE = 0.58;
    constant float CLOUD_MIX_AMP = 0.42;
    constant float CLOUD_WHITE_BASE = 0.68;
    constant float CLOUD_WHITE_AMP = 0.06;
    
    // Glow & Final
    constant float GLOW_Y_SKEW = 7.0;
    constant float GLOW_X_SKEW = 1.2;
    constant float3 GLOW_COLOR_BASE = float3(0.12, 0.10, 0.08);
    constant float GLOW_INTENSITY = 0.45;
    constant float3 LIFT_COLOR = float3(0.045, 0.038, 0.032);
    constant float AUDIO_FLOOR = 0.05;
    constant float AUDIO_BOOST = 1.18;
    constant float AUDIO_POWER = 0.82;
    
    // Sun
    constant float2 SUN_POS_SKEW = float2(0.28, 0.38);
    constant float SUN_SIZE = 0.8;
    constant float3 SUN_COLOR = float3(1.0, 0.98, 0.92);
    constant float SUN_STRENGTH = 0.07;
    
    // Vignette
    constant float VIGNETTE_START = 0.28;
    constant float VIGNETTE_END = 1.28;
    constant float VIGNETTE_STRENGTH = 0.10;
}

static float hash21(float2 p) {
    p = fract(p * Config::HASH_VEC);
    p += dot(p, p + Config::HASH_OFFSET);
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
    float a = Config::FBM_INITIAL_AMP;
    for (int i = 0; i < Config::FBM_OCTAVES; i++) {
        v += a * noise2D(p);
        float2 rp = float2(
            p.x * Config::FBM_ROT_ROW1.x + p.y * Config::FBM_ROT_ROW1.y,
            p.x * Config::FBM_ROT_ROW2.x + p.y * Config::FBM_ROT_ROW2.y
        );
        p = rp * Config::FBM_SCALE + float2(Config::FBM_DOMAIN_OFFSET);
        a *= Config::FBM_AMP_DECAY;
    }
    return v;
}

static float fbmFast(float2 p) {
    float v = 0.0;
    float a = Config::FBM_INITIAL_AMP;
    for (int i = 0; i < 3; i++) {
        v += a * noise2D(p);
        float2 rp = float2(
            p.x * Config::FBM_ROT_ROW1.x + p.y * Config::FBM_ROT_ROW1.y,
            p.x * Config::FBM_ROT_ROW2.x + p.y * Config::FBM_ROT_ROW2.y
        );
        p = rp * Config::FBM_SCALE + float2(Config::FBM_DOMAIN_OFFSET);
        a *= Config::FBM_AMP_DECAY;
    }
    return v;
}

static float2 domainWarp(float2 p, float t) {
    float2 q = float2(
        fbm(p + float2(0.0, 0.0) + t * Config::WARP_Q_TIME_SKEW_A),
        fbm(p + Config::WARP_Q_OFFSET - t * Config::WARP_Q_TIME_SKEW_B)
    );
    float2 r = float2(
        fbm(p + 3.0 * q + Config::WARP_R_OFFSET_1 + t * Config::WARP_R_TIME_SKEW),
        fbm(p + 3.0 * q + Config::WARP_R_OFFSET_2 - t * Config::WARP_R_TIME_SKEW)
    );
    return r;
}

static float2 domainWarpFast(float2 p, float t) {
    return float2(
        noise2D(p + float2(0.0, 0.0) + t * Config::WARP_Q_TIME_SKEW_A),
        noise2D(p + Config::WARP_Q_OFFSET - t * Config::WARP_Q_TIME_SKEW_B)
    );
}

static float2 vortexField(float2 p, float2 center, float strength) {
    float2 d = p - center;
    float inv = 1.0 / (Config::VORTEX_SOFTNESS + dot(d, d));
    return strength * inv * float2(-d.y, d.x);
}

[[ stitchable ]] half4 cloudOrbGlassWide(
    float2 position,
    half4 currentColor,
    float2 size,
    float time,
    float body,
    float presence,
    float pulse,
    float articulation,
    float detail,
    half4 colorTop,
    half4 colorMid,
    half4 colorLow
) {
    float2 safeSize = float2(max(size.x, 1.0), max(size.y, 1.0));
    float2 uv = position / safeSize;
    float aspect = safeSize.x / safeSize.y;

    float2 pRaw = float2((uv.x - 0.5) * 2.0 * aspect,
                         (uv.y - 0.5) * 2.0);

    float detailClamped = clamp(detail, 0.0, 1.0);
    float bodyClamped = clamp(body, 0.0, 1.0);
    float presenceClamped = clamp(presence, 0.0, 1.0);
    float pulseClamped = clamp(pulse, 0.0, 1.0);
    float articulationClamped = clamp(articulation, 0.0, 1.0);

    float talk = clamp(
        Config::AUDIO_FLOOR
        + pow(bodyClamped, Config::AUDIO_POWER) * Config::AUDIO_BOOST
        + pulseClamped * 0.16,
        0.0,
        1.0
    );
    float breath = talk * talk * (3.0 - 2.0 * talk);
    float edge = articulationClamped * articulationClamped * (3.0 - 2.0 * articulationClamped);
    float kick = pulseClamped * pulseClamped * (3.0 - 2.0 * pulseClamped);
    float life = max(presenceClamped, 0.18);

    pRaw.y += Config::MOTION_Y_AMP * (0.60 + 0.55 * life) * sin(time * Config::MOTION_Y_FREQ);
    pRaw.x += Config::MOTION_X_AMP * (0.55 + 0.70 * life) * sin(time * Config::MOTION_X_FREQ + pRaw.y * Config::MOTION_X_Y_SKEW);

    float coreY = exp(-pRaw.y * pRaw.y * Config::SHAPE_CORE_Y);
    float coreX = exp(-pRaw.x * pRaw.x * Config::SHAPE_CORE_X);
    float centerMask = coreY * (Config::SHAPE_CENTER_BASE + Config::SHAPE_CENTER_X_INF * coreX);

    float side = pRaw.x / (abs(pRaw.x) + Config::SHAPE_SIDE_FACTOR);
    float centerPush = (
        Config::SHAPE_PUSH_BASE
        + Config::SHAPE_PUSH_SKEW * breath
        + 0.12 * kick
    ) * coreY * exp(-abs(pRaw.x) * (1.20 + 0.35 * edge));
    float2 wind = float2(side * centerPush, 0.0);

    float spread = aspect * Config::SHAPE_SPREAD_FACTOR;
    float spin = Config::VORTEX_SPIN_BASE + Config::VORTEX_SPIN_AMP * (0.65 * breath + 0.35 * kick);
    float2 curl = float2(0.0);
    if (detailClamped > 0.60) {
        curl = vortexField(pRaw, float2(-spread, 0.0),  spin)
             + vortexField(pRaw, float2( spread, 0.0), -spin);
    }

    float bulge = 1.0 - (0.06 * breath + 0.03 * kick) * centerMask;
    float2 p = pRaw * bulge
             + wind * (0.18 + 0.10 * kick)
             + curl * ((0.08 + 0.20 * breath + 0.24 * kick + 0.10 * edge) * detailClamped);

    float2 w;
    float n;
    if (detailClamped < 0.72) {
        w = domainWarpFast(p * (Config::WARP_SCALE + 0.03 * edge), time * Config::WARP_TIME_SCALE * (0.92 + 0.28 * life));
        n = fbmFast(
            p * Config::FBM_NOISE_SCALE
            + w * (0.72 + breath * 0.34 + kick * 0.26)
            + float2(0.0, time * Config::FBM_TIME_FLOW * (0.85 + 0.30 * life))
        );
    } else {
        w = domainWarp(p * (Config::WARP_SCALE + 0.04 * edge), time * Config::WARP_TIME_SCALE * (0.92 + 0.30 * life));
        n = fbm(
            p * Config::FBM_NOISE_SCALE
            + w * (Config::FBM_WARP_SKEW_BASE + breath * 0.56 + kick * 0.30 + edge * 0.22)
            + float2(0.0, time * Config::FBM_TIME_FLOW * (0.88 + 0.34 * life))
        );
    }
    n = smoothstep(Config::SMOOTHSTEP_LOW, Config::SMOOTHSTEP_HIGH, n);

    float3 top = float3(colorTop.rgb);
    float3 mid = float3(colorMid.rgb);
    float3 low = float3(colorLow.rgb);

    float fluidBias = p.y * Config::FLUID_Y_BIAS + (w.y - 0.5) * (Config::FLUID_WARP_BIAS + 0.16 * edge);
    float colorLift = centerMask * (breath + 0.55 * kick) * Config::COLOR_LIFT_FACTOR;

    float maskBlue = smoothstep(
        Config::MASK_BLUE_LOW,
        Config::MASK_BLUE_HIGH,
        n - fluidBias * (Config::MASK_BLUE_SKEW + 0.06 * edge) - colorLift
    );
    float maskOrange = smoothstep(
        Config::MASK_ORANGE_LOW,
        Config::MASK_ORANGE_HIGH,
        w.x + fluidBias * Config::MASK_ORANGE_SKEW + colorLift + edge * 0.06
    );

    float3 base = mid;
    base = mix(base, low, maskBlue);
    base = mix(base, top, maskOrange);

    float depth = smoothstep(-1.0, 1.0, pRaw.y + (n - 0.5) * Config::DEPTH_SKEW);

    float cloudDense = smoothstep(Config::CLOUD_DENSE_LOW, Config::CLOUD_DENSE_HIGH, n + centerMask * (breath + 0.40 * kick) * Config::COLOR_LIFT_FACTOR);
    float cloudSoft = smoothstep(Config::CLOUD_SOFT_LOW, Config::CLOUD_SOFT_HIGH, Config::CLOUD_SOFT_n_SKEW * n + Config::CLOUD_SOFT_w_SKEW * w.x + 0.08 * edge);
    float cloudLift = smoothstep(Config::CLOUD_LIFT_LOW, Config::CLOUD_LIFT_HIGH, Config::CLOUD_LIFT_n_SKEW * n + Config::CLOUD_LIFT_w_SKEW * w.y + centerMask * (breath + 0.40 * kick) * Config::CLOUD_LIFT_CENTER_SKEW);

    float cloud = max(cloudDense, cloudSoft * 0.92);
    cloud = max(cloud, cloudLift * (Config::CLOUD_MIX_BASE + Config::CLOUD_MIX_AMP * breath));
    cloud *= (Config::DEPTH_BLEND_BASE + Config::DEPTH_BLEND_AMP * depth);
    cloud = clamp(cloud, 0.0, 1.0);

    base = mix(base, float3(1.0), cloud * (Config::CLOUD_WHITE_BASE + Config::CLOUD_WHITE_AMP * (0.80 * breath + 0.20 * edge)));

    float breathGlow = exp(-pRaw.y * pRaw.y * Config::GLOW_Y_SKEW) * exp(-pRaw.x * pRaw.x * Config::GLOW_X_SKEW);
    base += Config::GLOW_COLOR_BASE * breathGlow * (0.55 * breath + 0.85 * kick) * Config::GLOW_INTENSITY;

    float2 sunPos = float2(aspect * Config::SUN_POS_SKEW.x, Config::SUN_POS_SKEW.y);
    float sun = exp(-dot(pRaw - sunPos, pRaw - sunPos) * Config::SUN_SIZE);
    base = mix(base, Config::SUN_COLOR, sun * Config::SUN_STRENGTH);

    float vignette = smoothstep(Config::VIGNETTE_START, Config::VIGNETTE_END, length(pRaw / float2(aspect, 1.0)));
    base *= 1.0 - vignette * Config::VIGNETTE_STRENGTH;

    base += Config::LIFT_COLOR * (0.70 * breath + 0.30 * life);
    base = clamp(base, 0.0, 1.0);

    return half4(half3(base), currentColor.a);
}
