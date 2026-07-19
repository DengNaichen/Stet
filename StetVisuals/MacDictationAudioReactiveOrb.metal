#include <metal_stdlib>
using namespace metal;

struct AudioFieldComputeUniformsGPU {
    float deltaTime;
    float inputLevel;
    float2 padding;
};

struct AudioFieldSummaryGPU {
    float energy;
    float slowEnergy;
    float onset;
    float phase;
    float amplitude;
    float warp;
    float light;
    float padding;
};

struct AudioFieldRenderUniformsGPU {
    float2 size;
    float paddingTime;
    float3 cottonFoam;
    float padding0;
    float3 waveTop;
    float padding1;
    float3 deepSea;
    float padding2;
};

struct RasterizerData {
    float4 position [[position]];
    float2 uv;
};

static float smoothWithTimeConstants(
    float current,
    float target,
    float deltaTime,
    float attackTime,
    float releaseTime
) {
    float timeConstant = target > current ? attackTime : releaseTime;
    float response = 1.0 - exp(-deltaTime / max(timeConstant, 0.0001));
    return mix(current, target, clamp(response, 0.0, 1.0));
}

kernel void audioFieldSummaryKernel(
    constant AudioFieldComputeUniformsGPU& uniforms [[buffer(0)]],
    constant AudioFieldSummaryGPU* previousSummary [[buffer(1)]],
    device AudioFieldSummaryGPU* nextSummary [[buffer(2)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid > 0) {
        return;
    }

    AudioFieldSummaryGPU previous = previousSummary[0];
    AudioFieldSummaryGPU result;

    float targetEnergy = pow(clamp(uniforms.inputLevel, 0.0, 1.0), 0.72);
    result.energy = smoothWithTimeConstants(
        previous.energy,
        targetEnergy,
        uniforms.deltaTime,
        0.07,
        0.34
    );
    result.slowEnergy = smoothWithTimeConstants(
        previous.slowEnergy,
        targetEnergy,
        uniforms.deltaTime,
        0.42,
        0.42
    );

    float targetOnset = clamp((result.energy - result.slowEnergy) * 3.4, 0.0, 1.0);
    result.onset = smoothWithTimeConstants(
        previous.onset,
        targetOnset,
        uniforms.deltaTime,
        0.035,
        0.16
    );

    float speed = 0.40 + result.energy * 0.30 + result.onset * 0.12;
    result.phase = previous.phase + uniforms.deltaTime * speed;
    result.amplitude = 1.22 + result.energy * 0.42;
    result.warp = clamp(result.onset * 0.48 + result.energy * 0.52, 0.0, 1.0);
    result.light = clamp(result.onset * 0.65 + result.energy * 0.35, 0.0, 1.0);
    result.padding = 0.0;

    nextSummary[0] = result;
}

vertex RasterizerData audioReactiveOrbVertex(uint vertexID [[vertex_id]]) {
    float2 positions[3] = {
        float2(-1.0, -1.0),
        float2(3.0, -1.0),
        float2(-1.0, 3.0)
    };

    RasterizerData out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = positions[vertexID] * 0.5 + 0.5;
    return out;
}

static float randomValue(float2 st) {
    return fract(sin(dot(st.xy, float2(12.9898, 78.233))) * 43758.5453123);
}

static float noiseValue(float2 st) {
    float2 i = floor(st);
    float2 f = fract(st);
    float a = randomValue(i);
    float b = randomValue(i + float2(1.0, 0.0));
    float c = randomValue(i + float2(0.0, 1.0));
    float d = randomValue(i + float2(1.0, 1.0));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

static float fbmValue(float2 x) {
    float value = 0.0;
    float amplitude = 0.5;
    float2 shift = float2(100.0);
    float2x2 rotation = float2x2(
        float2(cos(0.5), sin(0.5)),
        float2(-sin(0.5), cos(0.5))
    );
    for (int index = 0; index < 5; ++index) {
        value += amplitude * noiseValue(x);
        x = rotation * x * 2.0 + shift;
        amplitude *= 0.5;
    }
    return value;
}

fragment float4 audioReactiveOrbFragment(
    RasterizerData in [[stage_in]],
    constant AudioFieldRenderUniformsGPU& uniforms [[buffer(0)]],
    constant AudioFieldSummaryGPU& summary [[buffer(1)]]
) {
    float2 centered = in.uv * 2.0 - 1.0;
    float aspect = uniforms.size.x / max(uniforms.size.y, 1.0);
    float horizontalScale = max(1.0, aspect * 0.68);
    float2 p = float2(centered.x * horizontalScale, centered.y) * 1.08;

    float3 colCottonFoam = uniforms.cottonFoam;
    float3 colWaveTop = uniforms.waveTop;
    float3 colDeepSea = uniforms.deepSea;

    float energy = clamp(summary.energy, 0.0, 1.0);
    float3 background = mix(colCottonFoam, colWaveTop, 0.36);
    float surfaceHeight = -0.24 - abs(p.x * p.x) * 0.15;
    float depth = p.y - surfaceHeight;
    float2 scaledPosition = p * 1.18;

    // Keep the motion autonomous. Voice energy only steers its pace,
    // displacement, internal curl, and highlight intensity.
    float phase = summary.phase;
    float2 drift = float2(
        sin(phase) + 0.6 * sin(phase * 1.7 + 1.3),
        cos(phase * 0.8) + 0.6 * cos(phase * 1.3 + 2.1)
    );
    drift *= summary.amplitude;

    float2 movingScale = scaledPosition + drift * 0.7;
    float warpStrength = 1.0 + summary.warp * 0.48;
    float2 q = float2(
        fbmValue(movingScale + drift * warpStrength),
        fbmValue(movingScale + float2(5.2, 1.3) - drift * warpStrength)
    );

    float2 r = float2(
        fbmValue(movingScale + 2.0 * q + float2(1.7, 9.2)),
        fbmValue(movingScale + 2.0 * q + float2(8.3, 2.8))
    );

    float bodyField = fbmValue(movingScale + r * 0.95);
    float distortedDepth = depth - bodyField * 1.05;
    float cottonMask = 1.0 - smoothstep(-0.10, 0.34, distortedDepth);

    float deepLift = 0.07 + energy * 0.10;
    float bodyFade = 1.0 - smoothstep(
        -1.45 + deepLift,
        -0.55 + deepLift,
        distortedDepth
    );
    float3 liquidColor = mix(colWaveTop, colDeepSea, bodyFade);
    float surfaceFade = 1.0 - smoothstep(-0.72, -0.08, distortedDepth);
    liquidColor = mix(colCottonFoam, liquidColor, surfaceFade);

    float grain = noiseValue(movingScale * 30.0) - 0.5;
    float deepColorMask = smoothstep(0.20, 0.75, bodyFade);
    float grainStrength = 0.05 + energy * 0.03;
    liquidColor *= 1.0 + grain * grainStrength * deepColorMask;

    float3 color = mix(background, liquidColor, cottonMask);
    color += float3(0.04 + summary.light * 0.055)
        * (1.0 - smoothstep(-0.08, 0.32, distortedDepth));

    return float4(color, 1.0);
}
