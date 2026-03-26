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

    // Warp (restored from original)
    constant float2 WARP_Q_OFFSET = float2(5.2, 1.3);
    constant float2 WARP_R_OFFSET_1 = float2(1.7, 9.2);
    constant float2 WARP_R_OFFSET_2 = float2(8.3, 2.8);
    constant float WARP_Q_TIME_SKEW_A = 0.05;
    constant float WARP_Q_TIME_SKEW_B = 0.04;
    constant float WARP_R_TIME_SKEW = 0.02;

    // Motion (restored from original)
    constant float MOTION_Y_AMP = 0.010;
    constant float MOTION_Y_FREQ = 1.20;
    constant float MOTION_X_AMP = 0.006;
    constant float MOTION_X_FREQ = 0.74;
    constant float MOTION_X_Y_SKEW = 1.25;

    // View
    constant float VIEW_PULLBACK = 1.5;
    constant float WARP_SCALE = 0.42;
    constant float WARP_TIME_SCALE = 0.82;
    constant float FBM_NOISE_SCALE = 0.48;
    constant float FBM_WARP_SKEW_BASE = 1.20;
    constant float FBM_TIME_FLOW = 0.14;
    constant float SMOOTHSTEP_LOW = 0.10;
    constant float SMOOTHSTEP_HIGH = 0.92;

    // Micro detail (restored from original)
    constant float MICRO_DETAIL_SCALE = 3.4;
    constant float MICRO_DETAIL_WARP = 0.24;
    constant float MICRO_DETAIL_TIME_FLOW = 0.11;
    constant float MICRO_DETAIL_STRENGTH = 0.055;

    // Blob orbiting system (continuously rearranging, never static)
    constant float ORBIT_RADIUS_X = 0.50;
    constant float ORBIT_RADIUS_Y = 0.16;
    constant float ORBIT_ASPECT_SCALE = 0.35;
    constant float ORBIT_SPEED_A = 0.13;
    constant float ORBIT_SPEED_B = 0.09;
    constant float ORBIT_SPEED_C = 0.11;
    constant float ORBIT_PHASE_A = 0.0;
    constant float ORBIT_PHASE_B = 2.20;
    constant float ORBIT_PHASE_C = 4.10;

    // Blob radii (slight variation, but balanced)
    constant float BLOB_A_RADIUS = 1.0;
    constant float BLOB_B_RADIUS = 1.05;
    constant float BLOB_C_RADIUS = 1.0;

    // Audio drift (visible in capsule)
    constant float DRIFT_AUDIO_AMP = 0.06;
    constant float PULSE_DISPLACEMENT = 0.05;

    // Ownership field
    constant float OWNERSHIP_TEMP = 3.6;
    constant float NOISE_PERTURB_SCALE = 0.9;
    constant float NOISE_PERTURB_AMP = 0.14;
    constant float WARP_OWNERSHIP_INFLUENCE = 0.26;

    // Cloud appearance (restored, but uses blob colors not white)
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
    constant float CLOUD_COLOR_STRENGTH = 0.32;

    // Internal shading
    constant float INTERNAL_SHADE_STRENGTH = 0.16;

    // Shape & center mask (restored from original)
    constant float SHAPE_CORE_Y = 5.0;
    constant float SHAPE_CORE_X = 1.6;
    constant float SHAPE_CENTER_BASE = 0.35;
    constant float SHAPE_CENTER_X_INF = 0.65;
    constant float SHAPE_SIDE_FACTOR = 0.22;
    constant float SHAPE_PUSH_BASE = 0.03;
    constant float SHAPE_PUSH_SKEW = 0.40;
    constant float SHAPE_SPREAD_FACTOR = 0.32;

    // Vortex (restored from original)
    constant float VORTEX_SOFTNESS = 0.14;
    constant float VORTEX_SPIN_BASE = 0.03;
    constant float VORTEX_SPIN_AMP = 0.14;

    // Depth
    constant float DEPTH_SKEW = 0.48;
    constant float DEPTH_BLEND_BASE = 0.74;
    constant float DEPTH_BLEND_AMP = 0.26;

    // Audio
    constant float AUDIO_FLOOR = 0.10;
    constant float AUDIO_BOOST = 1.10;
    constant float AUDIO_POWER = 0.50;
    // (PULSE_DISPLACEMENT moved to blob orbit section)
    constant float PRESENCE_BRIGHT = 0.04;

    // Glow & Final (restored from original)
    constant float GLOW_Y_SKEW = 7.0;
    constant float GLOW_X_SKEW = 1.2;
    constant float3 GLOW_COLOR_BASE = float3(0.12, 0.10, 0.08);
    constant float GLOW_INTENSITY = 0.45;
    constant float3 LIFT_COLOR = float3(0.025, 0.020, 0.016);

    // Sun
    constant float2 SUN_POS_SKEW = float2(0.28, 0.38);
    constant float SUN_SIZE = 0.8;
    constant float3 SUN_COLOR = float3(1.0, 0.98, 0.92);
    constant float SUN_STRENGTH = 0.07;

    // Vignette
    constant float VIGNETTE_START = 0.38;
    constant float VIGNETTE_END = 1.40;
    constant float VIGNETTE_STRENGTH = 0.10;
}

// MARK: - Noise primitives

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

// MARK: - Blob orbit

static float2 blobOrbitCenter(float time, float orbitSpeed, float orbitPhase,
                               float audioAmp, float pulseDisp, float aspectStretch) {
    float angle = time * orbitSpeed + orbitPhase;
    // Orbit X radius stretches with aspect ratio so blobs fill wide capsules
    float radiusX = Config::ORBIT_RADIUS_X + aspectStretch;
    float radiusY = Config::ORBIT_RADIUS_Y;
    return float2(
        radiusX * cos(angle) + audioAmp * sin(angle * 1.7 + orbitPhase),
        radiusY * sin(angle) + audioAmp * cos(angle * 1.3 + orbitPhase)
    ) + float2(
        pulseDisp * sin(time * 3.2 + orbitPhase * 0.7),
        pulseDisp * cos(time * 2.8 + orbitPhase * 1.3)
    );
}

// MARK: - Main shader

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
    half4 colorA_in,
    half4 colorB_in,
    half4 colorC_in
) {
    // --- Coordinate setup ---
    float2 safeSize = float2(max(size.x, 1.0), max(size.y, 1.0));
    float2 uv = position / safeSize;
    float aspect = safeSize.x / safeSize.y;

    float2 pRaw = float2((uv.x - 0.5) * 2.0 * aspect,
                         (uv.y - 0.5) * 2.0) * Config::VIEW_PULLBACK;

    // --- Clamp & derive audio ---
    float detailClamped = clamp(detail, 0.0, 1.0);
    float bodyClamped = clamp(body, 0.0, 1.0);
    float presenceClamped = clamp(presence, 0.0, 1.0);
    float pulseClamped = clamp(pulse, 0.0, 1.0);
    float articulationClamped = clamp(articulation, 0.0, 1.0);

    float talk = clamp(
        Config::AUDIO_FLOOR
        + pow(bodyClamped, Config::AUDIO_POWER) * Config::AUDIO_BOOST
        + pulseClamped * 0.16,
        0.0, 1.0
    );
    // Breath: mix sqrt (lifts low values) with smoothstep (shapes high values)
    float breathSmooth = talk * talk * (3.0 - 2.0 * talk);
    float breathSqrt = sqrt(talk);
    float breath = mix(breathSqrt, breathSmooth, 0.5);

    // Edge/kick: keep smoothstep but add a floor so quiet articulation is visible
    float edge = articulationClamped * articulationClamped * (3.0 - 2.0 * articulationClamped);
    edge = max(edge, articulationClamped * 0.35);
    float kick = pulseClamped * pulseClamped * (3.0 - 2.0 * pulseClamped);
    kick = max(kick, pulseClamped * 0.30);
    float life = max(presenceClamped, 0.18);

    // --- Original motion (restored) ---
    pRaw.y += Config::MOTION_Y_AMP * (0.60 + 0.55 * life) * sin(time * Config::MOTION_Y_FREQ);
    pRaw.x += Config::MOTION_X_AMP * (0.55 + 0.70 * life) * sin(time * Config::MOTION_X_FREQ + pRaw.y * Config::MOTION_X_Y_SKEW);

    // --- Original shape masks (restored for cloud & glow) ---
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

    float bulge = 1.0 - (0.03 * breath + 0.015 * kick) * centerMask;
    float2 p = pRaw * bulge
             + wind * (0.12 + 0.03 * kick)
             + curl * ((0.06 + 0.10 * breath + 0.05 * kick + 0.03 * edge) * detailClamped);

    // --- Domain warp & FBM (restored from original — this is the texture engine) ---
    float2 w;
    float n;
    if (detailClamped < 0.72) {
        w = domainWarpFast(p * (Config::WARP_SCALE + 0.015 * edge), time * Config::WARP_TIME_SCALE * (0.92 + 0.28 * life));
        n = fbmFast(
            p * Config::FBM_NOISE_SCALE
            + w * (0.72 + breath * 0.34 + kick * 0.12)
            + float2(0.0, time * Config::FBM_TIME_FLOW * (0.85 + 0.30 * life))
        );
    } else {
        w = domainWarp(p * (Config::WARP_SCALE + 0.02 * edge), time * Config::WARP_TIME_SCALE * (0.92 + 0.30 * life));
        n = fbm(
            p * Config::FBM_NOISE_SCALE
            + w * (Config::FBM_WARP_SKEW_BASE + breath * 0.56 + kick * 0.14 + edge * 0.08)
            + float2(0.0, time * Config::FBM_TIME_FLOW * (0.88 + 0.34 * life))
        );
    }

    // Micro detail (restored)
    float microDetail = noise2D(
        p * (Config::FBM_NOISE_SCALE * Config::MICRO_DETAIL_SCALE + 0.12 * edge)
        + w * Config::MICRO_DETAIL_WARP
        + float2(
            time * Config::MICRO_DETAIL_TIME_FLOW * (0.82 + 0.18 * life),
            -time * Config::MICRO_DETAIL_TIME_FLOW * (0.68 + 0.16 * breath)
        )
    );
    n += (microDetail - 0.5) * Config::MICRO_DETAIL_STRENGTH * (0.35 + 0.65 * detailClamped);
    n = smoothstep(Config::SMOOTHSTEP_LOW, Config::SMOOTHSTEP_HIGH, n);

    // ============================================================
    // COLOR ASSIGNMENT: Blob ownership (replaces old mask mixing)
    // ============================================================

    // --- Blob centers (orbiting, aspect-aware so they fill wide capsules) ---
    float audioAmp = breath * Config::DRIFT_AUDIO_AMP;
    float pulseDrift = kick * Config::PULSE_DISPLACEMENT;
    float aspectStretch = max(0.0, (aspect - 1.0)) * Config::ORBIT_ASPECT_SCALE;

    float2 centerA = blobOrbitCenter(time, Config::ORBIT_SPEED_A, Config::ORBIT_PHASE_A, audioAmp, pulseDrift, aspectStretch);
    float2 centerB = blobOrbitCenter(time, Config::ORBIT_SPEED_B, Config::ORBIT_PHASE_B, audioAmp, pulseDrift, aspectStretch);
    float2 centerC = blobOrbitCenter(time, Config::ORBIT_SPEED_C, Config::ORBIT_PHASE_C, audioAmp, pulseDrift, aspectStretch);

    // --- Distances with noise perturbation + mild warp influence ---
    float noiseTime = time * 0.03;
    float nPertA = fbmFast(p * Config::NOISE_PERTURB_SCALE + float2( 0.0,  0.0) + noiseTime * 0.9) * Config::NOISE_PERTURB_AMP;
    float nPertB = fbmFast(p * Config::NOISE_PERTURB_SCALE + float2( 5.3,  2.7) + noiseTime * 0.8) * Config::NOISE_PERTURB_AMP;
    float nPertC = fbmFast(p * Config::NOISE_PERTURB_SCALE + float2(10.1,  7.4) + noiseTime * 1.1) * Config::NOISE_PERTURB_AMP;

    // Warp nudges ownership — use different warp components per blob so no one is
    // systematically favored or suppressed
    float warpNudgeX = (w.x - 0.5) * Config::WARP_OWNERSHIP_INFLUENCE;
    float warpNudgeY = (w.y - 0.5) * Config::WARP_OWNERSHIP_INFLUENCE;

    // Aspect-normalized distance: divide X diff by aspect so blobs appear
    // circular on screen, not stretched. This also makes Y movements
    // (which are very visible in the short capsule) properly weighted.
    float invAspect = 1.0 / max(aspect, 1.0);

    float2 diffA = p - centerA;
    diffA.x *= invAspect;
    float dA = length(diffA) / Config::BLOB_A_RADIUS + nPertA + warpNudgeX;

    float2 diffB = p - centerB;
    diffB.x *= invAspect;
    float dB = length(diffB) / Config::BLOB_B_RADIUS + nPertB + warpNudgeY;

    float2 diffC = p - centerC;
    diffC.x *= invAspect;
    float dC = length(diffC) / Config::BLOB_C_RADIUS + nPertC - warpNudgeX;

    // --- Soft ownership weights ---
    float temp = Config::OWNERSHIP_TEMP;
    float wA = exp(-dA * temp);
    float wB = exp(-dB * temp);
    float wC = exp(-dC * temp);
    float wSum = wA + wB + wC + 1e-6;
    wA /= wSum;
    wB /= wSum;
    wC /= wSum;

    // --- Base color from ownership ---
    float3 colA = float3(colorA_in.rgb);
    float3 colB = float3(colorB_in.rgb);
    float3 colC = float3(colorC_in.rgb);

    float3 base = wA * colA + wB * colB + wC * colC;

    // --- Internal shading from fbm (adds depth, stays within blob) ---
    float maxW = max(wA, max(wB, wC));
    float boundaryness = 1.0 - smoothstep(0.36, 0.55, maxW);
    float internalShade = (n - 0.5) * Config::INTERNAL_SHADE_STRENGTH * (0.4 + 0.6 * detailClamped);
    base *= (1.0 + internalShade * (1.0 - boundaryness * 0.5));

    // ============================================================
    // CLOUD LAYER: Uses blob colors instead of white
    // ============================================================

    float cloudDense = smoothstep(Config::CLOUD_DENSE_LOW, Config::CLOUD_DENSE_HIGH,
        n + centerMask * (breath + 0.40 * kick) * 0.06);
    float cloudSoft = smoothstep(Config::CLOUD_SOFT_LOW, Config::CLOUD_SOFT_HIGH,
        Config::CLOUD_SOFT_n_SKEW * n + Config::CLOUD_SOFT_w_SKEW * w.x + 0.08 * edge);
    float cloudLift = smoothstep(Config::CLOUD_LIFT_LOW, Config::CLOUD_LIFT_HIGH,
        Config::CLOUD_LIFT_n_SKEW * n + Config::CLOUD_LIFT_w_SKEW * w.y
        + centerMask * (breath + 0.40 * kick) * Config::CLOUD_LIFT_CENTER_SKEW);

    float cloud = max(cloudDense, cloudSoft * 0.92);
    cloud = max(cloud, cloudLift * (Config::CLOUD_MIX_BASE + Config::CLOUD_MIX_AMP * breath));
    cloud *= (Config::DEPTH_BLEND_BASE + Config::DEPTH_BLEND_AMP * smoothstep(-1.0, 1.0, pRaw.y + (n - 0.5) * Config::DEPTH_SKEW));
    cloud = clamp(cloud, 0.0, 1.0);

    // Wave-layered cloud color: three colors flow in rolling bands like ocean surf
    // Use a slow directional noise field as the "wave position"
    float waveField = fbmFast(
        p * 0.5 + float2(time * 0.025, -time * 0.018)
    ) + p.x * 0.12 + p.y * 0.08;  // slight directional bias for wave flow

    // Map to [0, 3) range and create soft cosine bands for each color
    float waveCycle = fract(waveField * 1.2) * 3.0;
    float bandA = max(0.0, cos((waveCycle - 0.0) * 2.094) * 0.5 + 0.5);  // 2.094 = 2π/3
    float bandB = max(0.0, cos((waveCycle - 1.0) * 2.094) * 0.5 + 0.5);
    float bandC = max(0.0, cos((waveCycle - 2.0) * 2.094) * 0.5 + 0.5);
    float bandSum = bandA + bandB + bandC + 1e-6;
    float3 cloudColor = (bandA * colA + bandB * colB + bandC * colC) / bandSum;

    // Keep cloud color deep — no white dilution
    cloudColor = mix(cloudColor, float3(1.0), 0.05);

    float cloudAmount = cloud * Config::CLOUD_COLOR_STRENGTH * (0.80 + 0.20 * breath);
    base = mix(base, cloudColor, cloudAmount);

    // ============================================================
    // GLOW, SUN, VIGNETTE (restored from original)
    // ============================================================

    float breathGlow = exp(-pRaw.y * pRaw.y * Config::GLOW_Y_SKEW) * exp(-pRaw.x * pRaw.x * Config::GLOW_X_SKEW);
    base += Config::GLOW_COLOR_BASE * breathGlow * (0.55 * breath + 0.85 * kick) * Config::GLOW_INTENSITY;

    float2 sunPos = float2(aspect * Config::SUN_POS_SKEW.x, Config::SUN_POS_SKEW.y);
    float sun = exp(-dot(pRaw - sunPos, pRaw - sunPos) * Config::SUN_SIZE);
    base = mix(base, Config::SUN_COLOR, sun * Config::SUN_STRENGTH);

    float vignette = smoothstep(Config::VIGNETTE_START, Config::VIGNETTE_END, length(pRaw / float2(aspect, 1.0)));
    base *= 1.0 - vignette * Config::VIGNETTE_STRENGTH;

    base += Config::LIFT_COLOR * (0.70 * breath + 0.30 * life);
    base *= (1.0 + Config::PRESENCE_BRIGHT * life);
    base = clamp(base, 0.0, 1.0);

    return half4(half3(base), currentColor.a);
}
