#include <metal_stdlib>
using namespace metal;

struct AudioBandFeatureGPU {
    float2 position;
    float weight;
    float padding;
};

struct AudioFieldComputeUniformsGPU {
    uint gridSize;
    uint bandCount;
    float sigmaX;
    float sigmaY;
    float fieldBlurSigma;
    float gradientBlurSigma;
    float fieldGain;
    float motionGain;
};

struct AudioFieldSummaryGPU {
    float level;
    float flowX;
    float flowY;
    float padding;
    float4 groupedBands;
};

struct AudioFieldRenderUniformsGPU {
    float2 size;
    float time;
    float motionGain;
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

kernel void audioFieldSplatKernel(
    texture2d<half, access::write> densityTexture [[texture(0)]],
    constant AudioBandFeatureGPU* features [[buffer(0)]],
    constant AudioFieldComputeUniformsGPU& uniforms [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uniforms.gridSize || gid.y >= uniforms.gridSize) {
        return;
    }

    float gx = uniforms.gridSize <= 1 ? 0.0 : float(gid.x) / float(uniforms.gridSize - 1);
    float gy = uniforms.gridSize <= 1 ? 0.0 : float(gid.y) / float(uniforms.gridSize - 1);
    float value = 0.0;

    for (uint index = 0; index < uniforms.bandCount; ++index) {
        AudioBandFeatureGPU feature = features[index];
        if (feature.weight <= 1e-8) {
            continue;
        }

        float dx = gx - feature.position.x;
        float dy = gy - feature.position.y;
        value += feature.weight * uniforms.fieldGain * exp(
            -(dx * dx) / (2.0 * uniforms.sigmaX * uniforms.sigmaX)
            - (dy * dy) / (2.0 * uniforms.sigmaY * uniforms.sigmaY)
        );
    }

    densityTexture.write(half4(half(value), 0.0h, 0.0h, 1.0h), gid);
}

kernel void audioFieldBlurKernel(
    texture2d<half, access::read> inputTexture [[texture(0)]],
    texture2d<half, access::write> outputTexture [[texture(1)]],
    constant AudioFieldComputeUniformsGPU& uniforms [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uniforms.gridSize || gid.y >= uniforms.gridSize) {
        return;
    }

    int radius = max(1, int(ceil(uniforms.fieldBlurSigma * 2.0)));
    float sigma = max(uniforms.fieldBlurSigma, 0.001);
    float totalWeight = 0.0;
    float blurred = 0.0;

    for (int offsetY = -radius; offsetY <= radius; ++offsetY) {
        for (int offsetX = -radius; offsetX <= radius; ++offsetX) {
            int sampleX = clamp(int(gid.x) + offsetX, 0, int(uniforms.gridSize) - 1);
            int sampleY = clamp(int(gid.y) + offsetY, 0, int(uniforms.gridSize) - 1);
            float distance2 = float(offsetX * offsetX + offsetY * offsetY);
            float weight = exp(-distance2 / (2.0 * sigma * sigma));
            blurred += float(inputTexture.read(uint2(sampleX, sampleY)).x) * weight;
            totalWeight += weight;
        }
    }

    float value = totalWeight <= 1e-10 ? 0.0 : blurred / totalWeight;
    outputTexture.write(half4(half(value), 0.0h, 0.0h, 1.0h), gid);
}

kernel void audioFieldGradientKernel(
    texture2d<half, access::read> fieldTexture [[texture(0)]],
    texture2d<half, access::write> gradientTexture [[texture(1)]],
    constant AudioFieldComputeUniformsGPU& uniforms [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uniforms.gridSize || gid.y >= uniforms.gridSize) {
        return;
    }

    float step = uniforms.gridSize <= 1 ? 1.0 : 1.0 / float(uniforms.gridSize - 1);
    int leftX = max(int(gid.x) - 1, 0);
    int rightX = min(int(gid.x) + 1, int(uniforms.gridSize) - 1);
    int upY = max(int(gid.y) - 1, 0);
    int downY = min(int(gid.y) + 1, int(uniforms.gridSize) - 1);

    float left = float(fieldTexture.read(uint2(leftX, gid.y)).x);
    float right = float(fieldTexture.read(uint2(rightX, gid.y)).x);
    float up = float(fieldTexture.read(uint2(gid.x, upY)).x);
    float down = float(fieldTexture.read(uint2(gid.x, downY)).x);

    float gradX = (right - left) / (2.0 * step);
    float gradY = (down - up) / (2.0 * step);
    gradientTexture.write(half4(half(gradX), half(gradY), 0.0h, 1.0h), gid);
}

kernel void audioFieldSummaryKernel(
    texture2d<half, access::read> fieldTexture [[texture(0)]],
    texture2d<half, access::read> gradientTexture [[texture(1)]],
    constant AudioBandFeatureGPU* features [[buffer(0)]],
    constant AudioFieldComputeUniformsGPU& uniforms [[buffer(1)]],
    constant AudioFieldSummaryGPU* previousSummary [[buffer(2)]],
    device AudioFieldSummaryGPU* nextSummary [[buffer(3)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid > 0) {
        return;
    }

    float fieldMax = 0.0;
    float weightedForceX = 0.0;
    float weightedForceY = 0.0;
    float weightSum = 0.0;

    for (uint y = 0; y < uniforms.gridSize; ++y) {
        for (uint x = 0; x < uniforms.gridSize; ++x) {
            float weight = float(fieldTexture.read(uint2(x, y)).x);
            float2 gradient = float2(gradientTexture.read(uint2(x, y)).xy);
            fieldMax = max(fieldMax, weight);
            weightedForceX += gradient.x * weight;
            weightedForceY += gradient.y * weight;
            weightSum += weight;
        }
    }

    float forceX = weightSum > 1e-10 ? weightedForceX / weightSum : 0.0;
    float forceY = weightSum > 1e-10 ? weightedForceY / weightSum : 0.0;

    float4 groupedBands = float4(0.0);
    for (uint index = 0; index < uniforms.bandCount; ++index) {
        uint bucket = min(uint(3), index / 3);
        groupedBands[bucket] += features[index].weight;
    }

    float rawLevel = min(1.0, fieldMax * 4.5) * uniforms.motionGain;
    float rawFlowX = forceX * 0.85 * uniforms.motionGain;
    float rawFlowY = forceY * 1.1 * uniforms.motionGain;

    AudioFieldSummaryGPU previous = previousSummary[0];
    AudioFieldSummaryGPU result;
    result.level = smoothToward(previous.level, rawLevel, 0.045, 0.011);
    result.flowX = smoothToward(previous.flowX, rawFlowX, 0.035, 0.009);
    result.flowY = smoothToward(previous.flowY, rawFlowY, 0.032, 0.008);
    result.padding = 0.0;
    result.groupedBands = float4(
        smoothToward(previous.groupedBands.x, groupedBands.x, 0.045, 0.011),
        smoothToward(previous.groupedBands.y, groupedBands.y, 0.045, 0.011),
        smoothToward(previous.groupedBands.z, groupedBands.z, 0.045, 0.011),
        smoothToward(previous.groupedBands.w, groupedBands.w, 0.045, 0.011)
    );
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
    float2 p = in.uv * 2.0 - 1.0;
    p *= 1.08;
    float3 colCottonFoam = uniforms.cottonFoam;
    float3 colWaveTop = uniforms.waveTop;
    float3 colDeepSea = uniforms.deepSea;
    float3 bgLightBlue = mix(colCottonFoam, colWaveTop, 0.36);

    float level = clamp(summary.level, 0.0, 1.0);
    float2 flow = float2(summary.flowX, summary.flowY);
    float4 bands = summary.groupedBands;

    float motionMix = level;
    float tilt = flow.x * (0.66 + 0.22 * level) + (bands.z - bands.x) * 0.08;
    float basinCurve = 0.15 + 0.08 * bands.x;
    float surfaceHeight = -0.24 + p.x * tilt - abs(p.x * p.x) * basinCurve + flow.y * 0.48;
    float depth = p.y - surfaceHeight;

    float2 audioWarp = float2(
        flow.x * (0.46 + 0.30 * abs(p.y)) + (bands.z - bands.x) * 0.12,
        flow.y * (0.82 + 0.56 * abs(p.x)) + (bands.w - bands.y) * 0.18
    );

    float2 pScale = float2(
        p.x * (1.18 + 0.12 * bands.z) - uniforms.time * motionMix * (0.06 + 0.10 * bands.y),
        p.y * (1.18 + 0.18 * bands.x) + uniforms.time * motionMix * (0.06 + 0.10 * bands.w)
    );
    pScale += audioWarp;

    float2 q = float2(
        fbmValue(pScale + float2(0.0, uniforms.time * motionMix * 0.05 + bands.x * 1.9)),
        fbmValue(pScale + float2(5.2, 1.3) + uniforms.time * motionMix * 0.025 + audioWarp * 1.6)
    );

    float2 r = float2(
        fbmValue(pScale + 2.0 * q + float2(1.7, 9.2) - uniforms.time * motionMix * (0.018 + 0.04 * bands.z)),
        fbmValue(pScale + 2.0 * q + float2(8.3, 2.8) + uniforms.time * motionMix * (0.018 + 0.03 * bands.w))
    );

    float bodyField = fbmValue(pScale + r * (0.95 + 0.35 * level) + audioWarp * 1.35);
    float shimmerField = fbmValue(pScale * 1.35 - q * 0.65 + audioWarp * 2.2 + float2(6.0, 2.0));

    float distortedDepth = depth - bodyField * (1.05 + 0.9 * level);
    float cottonMask = smoothstep(0.34, -0.10, distortedDepth);

    float bodyFade = smoothstep(-0.55, -1.45 - bands.x * 0.3, distortedDepth);
    float3 liquidColor = mix(colWaveTop, colDeepSea, bodyFade);

    float foamMix = smoothstep(0.22, 0.82, shimmerField + level * 0.45);
    float surfaceFade = smoothstep(-0.08, -0.72 - 0.15 * bands.y, distortedDepth);
    liquidColor = mix(colCottonFoam, liquidColor, surfaceFade);
    liquidColor = mix(liquidColor, colCottonFoam, foamMix * 0.08 * level);

    float3 color = mix(bgLightBlue, liquidColor, cottonMask);
    color += float3(0.04 + 0.05 * level) * smoothstep(0.32, -0.08, distortedDepth);

    // Processing fill: only becomes visible when the existing motionGain gate
    // indicates the processing state. This keeps the current base visual intact
    // and swaps only the processing treatment to a blue-white wave fill.
    float processingGate = smoothstep(9.9995, 10.0, uniforms.motionGain);
    float processingProgress = min(0.95, 1.0 - exp(-uniforms.time * 1.15));
    float progressEdge = mix(-1.0, 1.0, processingProgress);

    float edgeNoiseA = fbmValue(
        float2(in.uv.x * 4.2 - uniforms.time * 0.05, in.uv.y * 6.6 + uniforms.time * 0.08)
    );
    float edgeNoiseB = noiseValue(
        float2(in.uv.x * 9.4 + uniforms.time * 0.04, in.uv.y * 11.8 - uniforms.time * 0.03)
    );
    float edgeNoise = ((edgeNoiseA * 0.72 + edgeNoiseB * 0.28) - 0.5) * 0.13;
    float noisyEdge = progressEdge + edgeNoise;
    float fillAmount = smoothstep(noisyEdge + 0.14, noisyEdge - 0.14, p.x) * processingGate;

    float3 mistGray = mix(colCottonFoam, float3(0.70, 0.74, 0.78), 0.60);
    float3 steelBlue = mix(colDeepSea, float3(0.43, 0.54, 0.66), 0.74);
    float3 frostBlue = mix(colWaveTop, float3(0.74, 0.86, 0.95), 0.68);
    float3 frontFoam = mix(colCottonFoam, float3(0.96, 0.98, 1.0), 0.42);

    float fillSpan = max(noisyEdge + 1.0, 0.001);
    float pushCoord = clamp((p.x + 1.0) / fillSpan, 0.0, 1.0);
    float frontPressure = smoothstep(0.50, 1.0, pushCoord);
    float rearSettle = 1.0 - smoothstep(0.18, 0.72, pushCoord);

    float pushField = fbmValue(
        float2(
            p.x * 1.55 - uniforms.time * 0.12 + flow.x * 1.1 + pushCoord * 1.8,
            p.y * 1.10 + uniforms.time * 0.03 + bodyField * 0.55
        )
    );
    float pushFoam = smoothstep(0.50, 0.84, pushField + frontPressure * 0.28 + foamMix * 0.12);

    float3 processingBase = mix(steelBlue, mistGray, rearSettle * 0.55 + 0.12);
    processingBase = mix(processingBase, frostBlue, frontPressure * 0.30);

    float3 processingBody = mix(steelBlue, frostBlue, bodyFade * 0.58 + frontPressure * 0.26);
    processingBody = mix(mistGray, processingBody, surfaceFade);
    processingBody = mix(processingBody, frontFoam, pushFoam * (0.16 + frontPressure * 0.22));
    processingBody = mix(processingBody, frostBlue, frontPressure * 0.18);

    float3 processingColor = mix(processingBase, processingBody, cottonMask);
    processingColor += float3(0.03, 0.04, 0.05) * smoothstep(0.32, -0.08, distortedDepth);

    float edgeHighlight = smoothstep(0.16, 0.02, abs(p.x - noisyEdge)) * processingGate;
    float edgeGlow = smoothstep(0.26, 0.0, abs(p.x - noisyEdge)) * processingGate;

    color = mix(color, processingColor, fillAmount);
    color += colCottonFoam * edgeHighlight * 0.16;
    color += mix(colWaveTop, colCottonFoam, 0.65) * edgeGlow * 0.08;

    return float4(color, 1.0);
}
