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
    float deltaTime;
    float inputLevel;
    float2 padding;
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
    float processingMix;
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

    // Keep the existing processing treatment connected to the v5 volume fields.
    float bodyField = broadBody;
    float foamMix = edgeFoam;
    float bodyFade = deepMix;
    float surfaceFade = foamLayer;
    float cottonMask = cloudMask;

    // Processing remains an explicit visual state, independent of audio motion gain.
    float processingGate = clamp(uniforms.processingMix, 0.0, 1.0);
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
