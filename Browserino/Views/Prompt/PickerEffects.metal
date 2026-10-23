//
//  PickerEffects.metal
//  Browserino
//
//  Every effect draws nothing at raw 0 and the snapshot unchanged at 1, so the live picker can replace it.
//

#include <metal_stdlib>
using namespace metal;

struct EffectUniforms {
    float2 size;
    float raw;
    float duration;
    float radius;
    float scale;
    float dark;
    int mode;
};

static float progress(constant EffectUniforms &u) { return 1 - pow(1 - u.raw, 3.0); }
static float seconds(constant EffectUniforms &u) { return u.raw * u.duration; }
/// Fades out what only shows while an effect plays, so the last frames match the picker.
static float settle(constant EffectUniforms &u) { return 1 - smoothstep(0.8, 1.0, u.raw); }

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut effectVertex(uint id [[vertex_id]]) {
    float2 corner = float2((id << 1) & 2, id & 2);
    VertexOut out;
    out.position = float4(corner * 2 - 1, 0, 1);
    out.uv = corner;
    return out;
}

static float hash(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float2 hash2(float2 p) { return float2(hash(p), hash(p + 19.19)); }

static float noise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * (3 - 2 * f);
    return mix(mix(hash(i), hash(i + float2(1, 0)), u.x), mix(hash(i + float2(0, 1)), hash(i + float2(1, 1)), u.x), u.y);
}

static float fbm(float2 p) {
    float v = 0, a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * noise(p);
        p = p * 2.03 + float2(17.1, 9.2);
        a *= 0.5;
    }
    return v;
}

static float roundedRect(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

/// Premultiplied content, with uv's y axis pointing up.
static float4 content(texture2d<float> snapshot, float2 uv) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    return snapshot.sample(s, float2(uv.x, 1 - uv.y));
}

/// Same as mixing the composited picker toward `color * k + picker * keep * k`; the background is under the overlay.
static float4 tint(float4 c, float3 color, float k, float keep) {
    float f = 1 - k + k * keep;
    return float4(c.rgb * f + color * k, c.a * f + k * (1 - keep));
}

/// Adds light, which also shows where nothing is drawn yet.
static float4 addLight(float4 c, float3 light) {
    float a = max(c.a, min(max(light.r, max(light.g, light.b)), 1.0));
    return float4(min(c.rgb + light, float3(a)), a);
}

/// The color channels sampled apart, for the refraction and hologram fringes.
static float4 splitRGB(texture2d<float> snapshot, float2 uv, float2 red, float2 blue) {
    float4 c = content(snapshot, uv);
    return float4(content(snapshot, uv + red).r, c.g, content(snapshot, uv + blue).b, c.a);
}

struct Effect {
    float4 overlay;
    float mask;
};

constant float burnAmplitude = 0.32, scorchWidth = 0.2, burnHalo = 0.0096;

/// Where the burning edge is, in uv, before the noise.
static float burnFront(float progress) {
    return mix(-burnAmplitude / 2 - burnHalo * 5, 1 + burnAmplitude / 2 + scorchWidth + 0.02, progress);
}

static Effect restore(texture2d<float> snapshot, float2 uv, float2 q, constant EffectUniforms &u) {
    float time = seconds(u), fade = settle(u);
    float2 np = q * 3;
    float d = uv.y + (fbm(np + float2(0, -time * 0.45)) - 0.5) * burnAmplitude - burnFront(progress(u));
    float reveal = smoothstep(-0.003, 0.003, -d);
    float scorch = (1 - smoothstep(0.0, scorchWidth, -d)) * fade;

    float4 c = content(snapshot, uv);
    float3 sepia = float3(dot(c.rgb, float3(0.393, 0.769, 0.189)), dot(c.rgb, float3(0.349, 0.686, 0.168)), dot(c.rgb, float3(0.272, 0.534, 0.131)));
    c.rgb = mix(c.rgb, sepia * float3(0.95, 0.72, 0.5), smoothstep(0.0, 0.55, scorch));
    c = tint(c, float3(0.42, 0.27, 0.15) * 0.55, smoothstep(0.0, 0.55, scorch) * 0.55, 0);
    c = tint(c, float3(0.07, 0.035, 0.02), smoothstep(0.4, 1.0, scorch) * 0.96, 0);
    float speck = smoothstep(0.6, 0.78, fbm(np * 3.5 + float2(time * 0.9, -time * 1.3))) * (1 - smoothstep(0.0, scorchWidth * 0.5, -d)) * fade;
    c = addLight(c, float3(1, 0.55, 0.15) * speck * 1.08);
    c *= reveal;

    float ad = abs(d);
    float core = exp(-(ad * ad) / (0.0045 * 0.0045)), glow = exp(-ad / burnHalo);
    float3 light = float3(0.85, 0.16, 0.02) * 0.51 * glow + float3(1, 0.55, 0.12) * glow * glow * 1.3 + float3(1, 0.93, 0.7) * core * 1.1;

    // Embers that drift up off the edge; stateless, so each one is a function of time.
    float2 sizePt = u.size / u.scale;
    float2 pt = uv * sizePt;
    for (int i = 0; i < 40; i++) {
        float fi = float(i);
        float spawn = hash(float2(fi, 1.7)) * 0.8;
        float life = 0.3 + 0.4 * hash(float2(fi, 2.3));
        float age = (u.raw - spawn) * u.duration;
        if (age < 0 || age > life) {
            continue;
        }
        float y0 = burnFront(1 - pow(1 - spawn, 3.0)) + (hash(float2(fi, 4.1)) - 0.5) * 0.26;
        if (y0 < 0 || y0 > 1) {
            continue;
        }
        float t = age / life;
        float2 p = float2(hash(float2(fi, 3.1)) * sizePt.x + (hash(float2(fi, 5.3)) - 0.5) * 30 * age,
                          y0 * sizePt.y + (50 + 90 * hash(float2(fi, 6.7))) * age);
        float r = (0.5 + 0.9 * hash(float2(fi, 7.9))) * (1 - t * 0.5);
        float spark = exp(-length_squared(pt - p) / (r * r)) * (1 - t) * fade;
        light += (t < 0.4 ? float3(1, 0.925, 0.705) : float3(1, 0.63, 0.235)) * spark;
    }

    return { addLight(c, light), reveal };
}

static Effect ink(texture2d<float> snapshot, float2 uv, float2 q, float A, constant EffectUniforms &u) {
    float time = seconds(u);
    float2 o = float2(0.5 * A, 0.55);
    float n = fbm(q * 3.2 + float2(time * 0.12, 0)), n2 = fbm(q * 10 - time * 0.1);
    float field = length(q - o) + (n - 0.5) * 0.45 + (n2 - 0.5) * 0.07;
    float inside = mix(-0.3, length(float2(A, 1)) * 0.5 + 0.6, progress(u)) - field;
    float reveal = smoothstep(0.0, 0.03, inside);
    float wet = (1 - smoothstep(0.0, 0.2, inside)) * reveal * settle(u);
    float2 dir = normalize(q - o + 1e-4);
    float4 c = content(snapshot, uv - float2(dir.x / A, dir.y) * wet * 0.014);
    float3 color = u.dark > 0.5 ? float3(0.36, 0.42, 1) : float3(0.13, 0.16, 0.62);
    c = tint(c, color, wet * 0.7, 0);
    c = tint(c, color * 0.55, smoothstep(0.45, 0.7, n2) * wet * 0.5, 0);
    return { c * reveal, reveal };
}

static Effect thaw(texture2d<float> snapshot, float2 uv, float2 q, float A, constant EffectUniforms &u) {
    float appear = smoothstep(0.0, 0.18, u.raw);
    float2 center = float2(0.5 * A, 0.5);
    float melt = fbm(q * 3 + 3.1) * 0.75 + length(q - center) / length(float2(A, 1)) * 0.72;
    float x = saturate((u.raw - 0.15) / 0.85);
    float threshold = mix(0.1, 1.25, 1 - (1 - x) * (1 - x));
    float clear = saturate((threshold - melt) / 0.05);

    float4 blur = 0;
    for (int i = 0; i < 8; i++) {
        float angle = float(i) * 0.785398;
        blur += content(snapshot, uv + float2(cos(angle) / A, sin(angle)) * 0.02);
    }
    float4 frost = tint(blur / 8, float3(0.86, 0.93, 1), u.dark > 0.5 ? 0.42 : 0.5, 0);
    frost = addLight(frost, float3(smoothstep(0.55, 0.78, fbm(float2(q.x * 34 + q.y * 14, q.y * 30 - q.x * 9))) * 0.2));
    frost = tint(frost, float3(0.95, 0.98, 1), smoothstep(0.35, 0.8, length(q - center)) * 0.3, 0);

    float rim = exp(-abs(threshold - melt) / 0.012) * (1 - clear * 0.5);
    float4 c = mix(frost, content(snapshot, uv + float2(0.004, 0.006) * rim), clear);
    c = addLight(c, float3(0.9, 0.97, 1) * rim * 0.35);
    return { c * appear, appear };
}

static Effect crystallize(texture2d<float> snapshot, float2 uv, float2 q, float A, constant EffectUniforms &u) {
    float2 g = q * 5.2, ip = floor(g), fp = fract(g);
    float d1 = 8, d2 = 8;
    float2 site = 0;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            float2 b = float2(i, j);
            float d = length(b + 0.1 + 0.8 * hash2(ip + b) - fp);
            if (d < d1) {
                d2 = d1;
                d1 = d;
                site = ip + b;
            } else if (d < d2) {
                d2 = d;
            }
        }
    }
    float id = hash(site);
    float order = length((site + 0.5) / 5.2 - float2(0.5 * A, 0.5)) / (0.5 * length(float2(A, 1)));
    float t = saturate((u.raw - mix(id, order, 0.55) * 0.4) / 0.5);
    t = 1 - pow(1 - t, 3.0);
    float inCell = smoothstep(t * 1.25, t * 1.25 - 0.05, d1);
    float line = (1 - smoothstep(0.0, 0.07, d2 - d1)) * (1 - t);
    float glint = exp(-abs(d1 - t * 1.25) / 0.035) * (1 - t);

    float3 ice = u.dark > 0.5 ? float3(0.55, 0.75, 1) : float3(0.45, 0.65, 1);
    float4 c = content(snapshot, uv);
    c.rgb *= 1 + (id - 0.5) * 0.25 * (1 - t);
    c = tint(c, ice * 0.6, (1 - t) * 0.7, 0.5);
    c = addLight(c, ice * (line * 0.8 + glint * 0.5));
    return { c * inCell, inCell };
}

static Effect ripple(texture2d<float> snapshot, float2 uv, float2 q, float A, constant EffectUniforms &u) {
    float2 o = float2(0.5 * A, 0.55);
    float dist = length(q - o);
    float x = dist - mix(-0.15, length(float2(A, 1)) * 0.5 + 0.35, progress(u));
    const float w = 0.055;
    float ring = exp(-x * x / (w * w));
    float inside = smoothstep(0.012, -0.012, x);
    float2 dir = (q - o) / max(dist, 1e-4);
    float2 offset = float2(dir.x / A, dir.y) * (x / w) * ring * 0.035;
    float4 c = splitRGB(snapshot, uv + offset, offset * 0.35, -offset * 0.3);
    float mask = max(inside, ring * 0.85);
    c *= mask;
    c = addLight(c, float3(ring * (max(0.0, dot(dir, normalize(float2(-0.5, 0.85)))) * 0.45 + 0.1)));
    return { c, mask };
}

static Effect hologram(texture2d<float> snapshot, float2 uv, float2 px, constant EffectUniforms &u) {
    float time = seconds(u), fade = settle(u);
    float behind = mix(-0.04, 1.12, progress(u)) - (1 - uv.y);
    float reveal = smoothstep(0.0, 0.008, behind);
    float fresh = exp(-max(behind, 0.0) / 0.13) * reveal * fade;
    float jitter = (hash(float2(floor(px.y / (3 * u.scale)), floor(time * 40))) - 0.5) * 0.05 * fresh * fresh;
    float split = 0.007 * fresh;
    float4 c = splitRGB(snapshot, uv + float2(jitter, 0), float2(split, 0), float2(-split, 0));
    c.rgb *= 1 - 0.3 * fresh * (1 - (0.5 + 0.5 * sin(px.y * M_PI_F / (1.5 * u.scale))));
    c.rgb = mix(c.rgb, c.rgb * float3(0.55, 1, 1.15), fresh * 0.65);
    c = addLight(c, float3(0, 0.06, 0.1) * fresh * 0.65);
    float mask = reveal * (1 - 0.25 * fresh * hash(float2(floor(time * 30), 3)));
    c *= mask;
    float beam = exp(-abs(behind) / 0.006) * fade;
    return { addLight(c, float3(0.45, 0.95, 1) * beam * 1.3), mask };
}

static Effect materialize(texture2d<float> snapshot, float2 uv, float2 px, constant EffectUniforms &u) {
    float level = min(floor(progress(u) * 6), 5.0);
    float block = level == 5 ? 1 : exp2(5 - level) * u.scale;
    float2 center = (floor(px / block) + 0.5) * block / u.size;
    float4 c = content(snapshot, float2(center.x, 1 - center.y));
    float age = u.raw * 2.6 - hash(floor(px / (32 * u.scale))) * 0.9;
    float visible = step(1e-4, age);
    c = tint(c, u.dark > 0.5 ? float3(0.75, 0.85, 1) : float3(0.35, 0.5, 0.95), (1 - smoothstep(0.0, 0.22, age)) * 0.5, 0);
    return { c * visible, visible };
}

static Effect effect(float2 uv, texture2d<float> snapshot, constant EffectUniforms &u) {
    float2 px = float2(uv.x, 1 - uv.y) * u.size;
    float A = u.size.x / u.size.y;
    float2 q = float2(uv.x * A, uv.y);
    Effect e;
    switch (u.mode) {
    case 0: e = restore(snapshot, uv, q, u); break;
    case 1: e = ink(snapshot, uv, q, A, u); break;
    case 2: e = thaw(snapshot, uv, q, A, u); break;
    case 3: e = crystallize(snapshot, uv, q, A, u); break;
    case 4: e = ripple(snapshot, uv, q, A, u); break;
    case 5: e = hologram(snapshot, uv, px, u); break;
    case 6: e = materialize(snapshot, uv, px, u); break;
    default: e = { 0, 0 }; break;
    }
    float shape = saturate(0.5 - roundedRect(px - u.size * 0.5, u.size * 0.5, u.radius));
    e.overlay *= shape;
    e.mask *= shape;
    return e;
}

struct EffectOutput {
    float4 overlay [[color(0)]];
    float4 mask [[color(1)]];
};

fragment EffectOutput effectFragment(VertexOut in [[stage_in]], texture2d<float> snapshot [[texture(0)]], constant EffectUniforms &u [[buffer(0)]]) {
    Effect e = effect(in.uv, snapshot, u);
    return { e.overlay, float4(0, 0, 0, e.mask) };
}
