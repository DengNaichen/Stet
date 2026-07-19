#include <metal_stdlib>
using namespace metal;

struct AudioFieldComputeUniformsGPU {
    float motionGain;
    float deltaTime;
    float inputLevel;
    float padding;
    float4 inputGroupedBands;
};

struct AudioFieldSummaryGPU {
    float level;
    float flowX;
    float flowY;
    float padding;
    float4 groupedBands;
    float2 transport;
    float2 padding2;
};

struct AudioFieldRenderUniformsGPU {
    float2 size;
    float time;
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

static float smoothToward(float current, float target, float attack, float release) {
    float rate = target > current ? attack : release;
    return current + (target - current) * rate;
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
    float targetLevel = pow(clamp(uniforms.inputLevel, 0.0, 1.0), 0.72);
    result.level = smoothToward(previous.level, targetLevel, 0.14, 0.065);
    result.padding = 0.0;
    result.groupedBands = float4(
        smoothToward(previous.groupedBands.x, uniforms.inputGroupedBands.x, 0.18, 0.055),
        smoothToward(previous.groupedBands.y, uniforms.inputGroupedBands.y, 0.18, 0.055),
        smoothToward(previous.groupedBands.z, uniforms.inputGroupedBands.z, 0.18, 0.055),
        smoothToward(previous.groupedBands.w, uniforms.inputGroupedBands.w, 0.18, 0.055)
    );

    float targetFlowX = 0.055 + (
        result.level * 0.15 + result.groupedBands.z * 0.045
    ) * uniforms.motionGain;
    float targetFlowY = (
        (result.groupedBands.w - result.groupedBands.x) * 0.055
        + (result.groupedBands.z - result.groupedBands.y) * 0.022
    ) * uniforms.motionGain;
    float forwardResponse = 1.0 - exp(-uniforms.deltaTime * 1.9);
    float verticalResponse = 1.0 - exp(-uniforms.deltaTime * 1.15);
    result.flowX = mix(previous.flowX, targetFlowX, forwardResponse);
    result.flowY = mix(previous.flowY, targetFlowY, verticalResponse);
    result.transport = previous.transport + float2(result.flowX, result.flowY) * uniforms.deltaTime;
    result.padding2 = float2(0.0);
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
    float2 p = float2(centered.x * aspect * 0.68, centered.y) * 1.06;
    float3 colCottonFoam = uniforms.cottonFoam;
    float3 colWaveTop = uniforms.waveTop;
    float3 colDeepSea = uniforms.deepSea;

    float level = clamp(summary.level, 0.0, 1.0);
    float2 flow = float2(summary.flowX, summary.flowY);
    float2 transport = summary.transport;
    float4 bands = summary.groupedBands;
    float2 flowDirection = normalize(float2(1.0, clamp(flow.y * 0.7, -0.42, 0.42)));
    float2 advected = p - transport;
    advected += float2(sin(uniforms.time * 0.13), cos(uniforms.time * 0.17)) * (0.035 + level * 0.035);
    float turn = sin(uniforms.time * 0.16 + flow.y * 0.45) * (0.045 + level * 0.055);
    float2x2 flowTurn = float2x2(
        float2(cos(turn), -sin(turn)),
        float2(sin(turn), cos(turn))
    );
    advected = flowTurn * advected;
    advected.y += sin(p.x * 0.72 - uniforms.time * 0.27) * (0.055 + level * 0.075);

    float2 q = float2(
        fbmValue(advected + float2(0.0, uniforms.time * 0.115 + bands.x * 0.34)),
        fbmValue(advected + float2(5.2, 1.3) - flowDirection * uniforms.time * 0.092)
    );

    float2 r = float2(
        fbmValue(advected + q * (1.55 + level * 0.42) + float2(1.7, 9.2) - uniforms.time * float2(0.10, 0.045)),
        fbmValue(advected + q * (1.72 + bands.y * 0.36) + float2(8.3, 2.8) + uniforms.time * float2(0.055, 0.085))
    );

    float2 rolled = advected + (q - 0.5) * (0.50 + level * 0.28) + (r - 0.5) * (0.34 + bands.z * 0.24);
    float broadBody = fbmValue(rolled * float2(0.92, 1.08));
    float edgeBody = fbmValue(rolled * 2.65 + q * 1.35 - flowDirection * uniforms.time * 0.27);
    float microBody = fbmValue(rolled * 5.1 - r * 0.8 + float2(6.0, 2.0));

    float tilt = (bands.z - bands.x) * 0.12 + flow.y * 0.22;
    float surfaceHeight = -0.24 + p.x * tilt - p.x * p.x * 0.045;
    surfaceHeight += sin(p.x * 0.82 - uniforms.time * 0.28) * (0.08 + level * 0.075);
    float depth = p.y - surfaceHeight;

    float cloudLift = broadBody * (1.10 + level * 0.82);
    float boundaryZone = 1.0 - smoothstep(0.12, 0.64, abs(depth - cloudLift * 0.72));
    float feather = (edgeBody - 0.5) * (0.18 + level * 0.22) * boundaryZone;
    feather += (microBody - 0.5) * (0.055 + bands.w * 0.12) * boundaryZone;
    float distortedDepth = depth - cloudLift - feather;

    float cloudMask = 1.0 - smoothstep(-0.08, 0.30, distortedDepth);
    float deepMix = 1.0 - smoothstep(-1.52 - bands.x * 0.22, -0.46, distortedDepth);
    float foamLayer = 1.0 - smoothstep(-0.66 - bands.y * 0.12, -0.04, distortedDepth);
    float edgeFoam = smoothstep(0.46, 0.84, edgeBody + level * 0.18) * boundaryZone;

    float3 sky = mix(colCottonFoam, colWaveTop, 0.30);
    float3 volumeColor = mix(colWaveTop, colDeepSea, deepMix);
    volumeColor = mix(colCottonFoam, volumeColor, foamLayer);
    volumeColor = mix(volumeColor, colCottonFoam, edgeFoam * (0.12 + level * 0.16));

    float3 color = mix(sky, volumeColor, cloudMask);
    float softGlow = (1.0 - smoothstep(-0.06, 0.26, distortedDepth)) * (0.035 + level * 0.045);
    color += float3(softGlow);

    return float4(color, 1.0);
}
