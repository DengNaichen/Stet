// Adapted from Rare UI / Swami Malode's Fluid Orb (MIT).
// https://www.rareui.com/components/fluidorb — see RareUI-LICENSE.txt.
// Stet additions: interleaved washes, pigment concentration, voice tone,
// anchored Thinking deformation, and silence-only travelling waves.
#include <metal_stdlib>
using namespace metal;

namespace stet_watercolor {
float hash(float2 p) { return fract(sin(dot(p, float2(127.1,311.7))) * 43758.5453123); }
float noise(float2 p) {
  float2 i = floor(p), f = fract(p), u = f*f*(3.0-2.0*f);
  return mix(mix(hash(i), hash(i+float2(1.0,0.0)), u.x), mix(hash(i+float2(0.0,1.0)), hash(i+float2(1.0)), u.x), u.y);
}
float fbm(float2 p) {
  float v = 0.0, a = 0.6;
  for (int i=0; i<3; i++) { v += a*noise(p); p *= 2.0; a *= 0.5; }
  return v;
}
float granulation(float2 p) {
  float2 cell=floor(p), local=fract(p);
  float mass=0.0;
  for (int y=-1; y<=1; y++) {
    for (int x=-1; x<=1; x++) {
      float2 neighbour=float2(float(x),float(y)), key=cell+neighbour;
      float2 centre=float2(hash(key+17.3),hash(key+91.7));
      float seed=hash(key+31.6), radius=0.30+0.23*seed;
      float2 d=local-neighbour-centre;
      mass += exp(-dot(d,d)/(radius*radius))*(0.65+seed*0.75);
    }
  }
  return mass*1.65;
}
float2 turnField(float2 point, float2 centre, float angle) {
  float2 delta=point-centre;
  float turn=angle*exp(-dot(delta,delta)*7.0), c=cos(turn), s=sin(turn);
  return centre+float2x2(c,-s,s,c)*delta;
}
float2 driftAt(float t) {
  return float2(sin(t)+0.6*sin(t*1.7+1.3),cos(t*0.8)+0.6*cos(t*1.3+2.1));
}
float2 leftCenter(float t) {
  return float2(0.32+0.10*sin(t*0.7),0.43+0.09*cos(t*0.9));
}
float2 rightCenter(float t) {
  return float2(0.67+0.08*cos(t*0.6),0.58+0.08*sin(t*0.8));
}
float3 paint(float2 uv, float u_time, float u_anchor, float u_motion, float u_tone, float u_diameter, float weave, float grain, float3 idleWave, float3 groundLow, float3 groundHigh, float3 interlayer, float3 lightPigment, float3 pigment, float3 densePigment) {
  float t=u_time*0.22;
  float anchor=u_anchor*0.22;
  float2 drift=mix(driftAt(anchor),driftAt(t),u_motion);
  float2 carried=turnField(uv,mix(leftCenter(anchor),leftCenter(t),u_motion),mix(1.7*sin(anchor*0.85+0.8),1.7*sin(t*0.85+0.8),u_motion));
  carried=turnField(carried,mix(rightCenter(anchor),rightCenter(t),u_motion),mix(-1.9*sin(anchor*0.72+1.7),-1.9*sin(t*0.72+1.7),u_motion));
  float2 flowUV=mix(uv,carried,weave);
  // Broad, same-direction waves blend in only during sustained listening silence.
  float wavePhase = uv.x * 6.283185 - idleWave.z;
  float swell = idleWave.x * sin(wavePhase)
              + idleWave.y * sin(uv.x * 10.053096 - idleWave.z * 1.1 + 1.2);
  float shore = smoothstep(0.08, 0.30, uv.y) * (1.0 - smoothstep(0.80, 0.98, uv.y));
  flowUV.y += swell * shore;
  flowUV.x += idleWave.x * 0.30 * cos(wavePhase) * shore;

  float2 p=float2(flowUV.x*1.8,flowUV.y)+drift*0.7;
  float2 q=float2(fbm(p+drift),fbm(p+float2(3.2,1.5)-drift));
  float2 material=p+1.2*q;
  float f=fbm(material), g=clamp(1.0-flowUV.y,0.0,1.0);
  float shade=clamp(g+(f-0.5)*0.8*smoothstep(0.0,0.3,uv.y),0.0,1.0);
  float2 grainFlow=uv+drift*float2(0.28,0.20)+(q-0.5)*0.045;
  float2 pigmentSpace=grainFlow*(u_diameter/350.0);
  float pools=0.65*noise(pigmentSpace*32.0+float2(13.2,7.7))+0.35*noise(pigmentSpace*67.0+float2(4.6,37.1));
  float grains=granulation(pigmentSpace*185.0+float2(41.7,19.3));
  float seep=(pools-0.5)*0.028+(min(grains,1.5)-0.75)*0.012;
  float wetShade=shade+grain*seep;
  float wash=smoothstep(0.48-0.05*weave,0.65+0.06*weave,wetShade);
  float body=smoothstep(0.58,0.92,wetShade);
  float wetEdge=4.0*wash*(1.0-wash);
  float deposits=(grains-0.92)*(0.18+0.34*pools)*(1.0-0.40*body);
  float concentration=clamp(0.53+0.95*pools+deposits+wetEdge*pools*0.12,0.30,2.2);
  float3 white=float3(0.998,0.999,0.991);
  float groundLight=noise(uv*1.7+drift*0.12+float2(6.1,2.7));
  float3 ground=mix(groundLow,groundHigh,groundLight);
  float whiteBand=smoothstep(0.18,0.32,shade)*(1.0-smoothstep(0.50,0.67,shade));
  float ribbonTurn=mix(0.8*sin(anchor*0.9+2.0),0.8*sin(t*0.9+2.0),u_motion);
  float2 ribbonUV=turnField(flowUV,float2(0.55,0.46),ribbonTurn);
  float ribbonSwell=mix(sin(ribbonUV.x*5.0+anchor*0.8),sin(ribbonUV.x*5.0+t*0.8),u_motion);
  float ribbonLine=ribbonUV.y-0.48+0.16*ribbonSwell;
  float ribbon=exp(-ribbonLine*ribbonLine/0.018);
  whiteBand=mix(whiteBand,ribbon*0.92,weave*0.8);
  float3 underpaint=mix(ground,interlayer,whiteBand);
  float blueCurrent=noise(material*float2(0.65,0.55)+float2(9.3,4.1));
  float blueDepth=clamp(0.38+(blueCurrent-0.5)*0.65+body*0.42,0.0,1.0);
  float deepRegion=smoothstep(0.52-u_tone*0.18,0.89-u_tone*0.10,blueDepth);
  float3 blue=mix(lightPigment,pigment,body*0.65);
  blue=mix(blue,densePigment,deepRegion*(0.45+u_tone*0.45));
  float3 pigmentMass=-log(clamp(blue/white,float3(0.001),float3(1.0)));
  pigmentMass *= mix(1.0,concentration,grain);
  float3 col=mix(underpaint,white*exp(-pigmentMass),wash);
  col=mix(col,interlayer,weave*ribbon*0.48*smoothstep(0.25,0.75,wash));

  return col;
}
}

[[ stitchable ]] half4 stetWatercolorOrb(
    float2 position, half4 color, float2 size,
    float time, float anchor, float motion, float tone,
    float weave, float grain, float3 idleWave,
    float3 groundLow, float3 groundHigh, float3 interlayer,
    float3 lightPigment, float3 pigment, float3 densePigment
) {
    float2 uv = float2(position.x, size.y - position.y) / size;
    float3 paint = stet_watercolor::paint(uv, time, anchor, motion, tone, size.x, weave, grain, idleWave, groundLow, groundHigh, interlayer, lightPigment, pigment, densePigment);
    float edge = 1.0 - smoothstep(0.49, 0.50, distance(uv, float2(0.5)));
    half alpha = half(edge) * color.a;
    return half4(half3(paint) * alpha, alpha);
}
