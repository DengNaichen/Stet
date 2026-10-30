// Material port from StetVisuals/Prototypes/WatercolorOrb/index.html.
// Base flow: Rare UI / Swami Malode, https://www.rareui.com/components/fluidorb
// For the native glass/trajectory study; fixed tone and no microphone input.
#include <metal_stdlib>
using namespace metal;


float hash(float2 p) {
  return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123);
}
float noise(float2 p) {
  float2 i = floor(p);
  float2 f = fract(p);
  float2 u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash(i + float2(0.0, 0.0)), hash(i + float2(1.0, 0.0)), u.x),
    mix(hash(i + float2(0.0, 1.0)), hash(i + float2(1.0, 1.0)), u.x),
    u.y
  );
}
float fbm(float2 p) {
  float v = 0.0;
  float a = 0.6;
  for (int i = 0; i < 3; i++) {
    v += a * noise(p);
    p *= 2.0;
    a *= 0.5;
  }
  return v;
}
// Irregular pigment grains: soft overlapping deposits with varying size/mass.
// Evaluating neighbouring cells avoids the square patches of thresholded noise.
float granulation(float2 p) {
  float2 cell = floor(p);
  float2 local = fract(p);
  float mass = 0.0;
  for (int y = -1; y <= 1; y++) {
    for (int x = -1; x <= 1; x++) {
      float2 neighbour = float2(float(x), float(y));
      float2 key = cell + neighbour;
      float2 centre = float2(hash(key + 17.3), hash(key + 91.7));
      float seed = hash(key + 31.6);
      float2 d = local - neighbour - centre;
      float radius = 0.30 + 0.23 * seed;
      mass += exp(-dot(d, d) / (radius * radius)) * (0.65 + seed * 0.75);
    }
  }
  return mass * 1.65;
}
// Two broad, counter-turning eddies carry the color fields across each other.
float2 turnField(float2 point, float2 centre, float angle) {
  float2 delta = point - centre;
  float turn = angle * exp(-dot(delta, delta) * 7.0);
  float c = cos(turn), s = sin(turn);
  return centre + float2x2(c, -s, s, c) * delta;
}
[[ stitchable ]] half4 labWatercolor(float2 position, half4 color, float2 size, float time) {
  float2 u_resolution = size;
  float u_time = time;
  float u_shape = 0.0;
  float u_weave = 0.52;
  float u_tone = 0.12;
  float u_grain = 0.08;
  float u_pixelRatio = 1.0;
  float3 u_color = float3(6.0, 161.0, 247.0) / 255.0;
  float3 u_idleWave = float3(0.0);
  float2 uv = float2(position.x, size.y-position.y) / u_resolution.xy;
  float t = u_time * 0.22;
  float2 drift = float2(
    sin(t) + 0.6 * sin(t * 1.7 + 1.3),
    cos(t * 0.8) + 0.6 * cos(t * 1.3 + 2.1)
  );
  float2 carried = turnField(uv,
    float2(0.32 + 0.10 * sin(t * 0.7), 0.43 + 0.09 * cos(t * 0.9)),
    1.7 * sin(t * 0.85 + 0.8));
  carried = turnField(carried,
    float2(0.67 + 0.08 * cos(t * 0.6), 0.58 + 0.08 * sin(t * 0.8)),
    -1.9 * sin(t * 0.72 + 1.7));
  float2 flowUV = mix(uv, carried, u_weave);
  // An additive, broad travelling swell for silence only. Both waves move in
  // the same direction; when amplitudes are zero the original field is intact.
  float wavePhase = uv.x * 6.283185 - u_idleWave.z;
  float swell = u_idleWave.x * sin(wavePhase)
              + u_idleWave.y * sin(uv.x * 10.053096 - u_idleWave.z * 1.1 + 1.2);
  float shore = smoothstep(0.08,0.30,uv.y) * (1.0-smoothstep(0.80,0.98,uv.y));
  flowUV.y += swell * shore;
  flowUV.x += u_idleWave.x * 0.30 * cos(wavePhase) * shore;
  float2 p = float2(flowUV.x * 1.8, flowUV.y) + drift * 0.7;
  float2 q = float2(fbm(p + drift), fbm(p + float2(3.2, 1.5) - drift));
  float2 material = p + 1.2 * q;
  float f = fbm(material);
  float g = clamp(1.0 - flowUV.y, 0.0, 1.0);
  float anchor = smoothstep(0.0, 0.3, uv.y);
  float shade = clamp(g + (f - 0.5) * 0.8 * anchor, 0.0, 1.0);
  // Granules share the flow's drift and bend, with restrained local stretching.
  // Full domain warping at this scale would turn small deposits into long hairs.
  float2 grainFlow = uv + drift * float2(0.28, 0.20) + (q - 0.5) * 0.045;
  float2 pigmentSpace = grainFlow * (u_resolution.x / u_pixelRatio / 350.0);
  float pools = 0.65 * noise(pigmentSpace * 32.0 + float2(13.2, 7.7))
              + 0.35 * noise(pigmentSpace * 67.0 + float2(4.6, 37.1));
  float grains = granulation(pigmentSpace * 185.0 + float2(41.7, 19.3));

  // The same deposits modify the wet edge before the color bands are formed.
  // Dilute pigment seeps farther, while dense clusters leave a ragged margin.
  float seep = (pools - 0.5) * 0.028 + (min(grains, 1.5) - 0.75) * 0.012;
  float wetShade = shade + u_grain * seep;
  float wash = smoothstep(0.48 - 0.05 * u_weave, 0.65 + 0.06 * u_weave, wetShade);
  float body = smoothstep(0.58, 0.92, wetShade);
  float wetEdge = 4.0 * wash * (1.0 - wash);
  // A continuous dilute wash carries denser aggregates. Granules are most
  // exposed in thin paint, and partly submerged inside the saturated blue.
  float deposits = (grains - 0.92) * (0.18 + 0.34 * pools);
  deposits *= 1.0 - 0.40 * body;
  float concentration = 0.53 + 0.95 * pools + deposits;
  concentration += wetEdge * pools * 0.12;
  concentration = clamp(concentration, 0.30, 2.2);

  // The pale ground remains visible above an independent white interlayer.
  // All three layers follow the broad fluid contour, with soft overlaps.
  float3 white = float3(0.998, 0.999, 0.991);
  float groundLight = noise(uv * 1.7 + drift * 0.12 + float2(6.1, 2.7));
  float3 ground = mix(float3(0.80, 0.943, 0.976), float3(0.88, 0.977, 0.992), groundLight);
  float whiteBand = smoothstep(0.18, 0.32, shade)
                  * (1.0 - smoothstep(0.50, 0.67, shade));
  // A separately moving wash enters the blue, instead of staying a separator.
  float2 ribbonUV = turnField(flowUV, float2(0.55, 0.46), 0.8 * sin(t * 0.9 + 2.0));
  float ribbonLine = ribbonUV.y - 0.48 + 0.16 * sin(ribbonUV.x * 5.0 + t * 0.8);
  float ribbon = exp(-ribbonLine * ribbonLine / 0.018);
  whiteBand = mix(whiteBand, ribbon * 0.92, u_weave * 0.8);
  float3 underpaint = mix(ground, white, whiteBand);

  // Large blue regions carry the tonal response; the hue of the whole orb
  // does not pulse uniformly. Increasing voice energy expands dense pigment.
  float blueCurrent = noise(material * float2(0.65, 0.55) + float2(9.3, 4.1));
  float blueDepth = clamp(0.38 + (blueCurrent - 0.5) * 0.65 + body * 0.42, 0.0, 1.0);
  float deepRegion = smoothstep(0.52 - u_tone * 0.18, 0.89 - u_tone * 0.10, blueDepth);
  float3 lightBlue = float3(0.075, 0.725, 0.985);
  float3 denseBlue = float3(0.012, 0.455, 0.895);
  float3 blue = mix(lightBlue, u_color, body * 0.65);
  blue = mix(blue, denseBlue, deepRegion * (0.45 + u_tone * 0.45));

  // Granulation redistributes blue pigment before compositing the paint.
  // The clean white band and pale ground are separate from pigment deposits.
  float3 pigmentMass = -log(clamp(blue / white, float3(0.001), float3(1.0)));
  pigmentMass *= mix(1.0, concentration, u_grain);
  float3 bluePaint = white * exp(-pigmentMass);
  float3 col = mix(underpaint, bluePaint, wash);
  col = mix(col, white, u_weave * ribbon * 0.48 * smoothstep(0.25, 0.75, wash));
  float edge = 1.0 - smoothstep(0.49, 0.5, distance(uv, float2(0.5)));
  if (u_shape > 0.5) {
    float aspect = u_resolution.x / u_resolution.y;
    float2 point = (uv - 0.5) * float2(aspect, 1.0);
    point.x = max(abs(point.x) - (aspect * 0.5 - 0.5), 0.0);
    float distanceToEdge = length(point) - 0.5;
    edge = 1.0 - smoothstep(-1.0 / u_resolution.y, 0.0, distanceToEdge);
  }
  return half4(half3(col) * half(edge) * color.a, half(edge) * color.a);
}
