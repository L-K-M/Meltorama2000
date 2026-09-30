#version 150
// explicitly: sampler2D defaults to in GLSL ES, which would
// quantize the float displacement field to 8-bit steps.
uniform sampler2D u_field;
// The state a RECALL stamp blends TOWARD (proposal 0008, ADR 0003): a
// keyframe's field, materialized by replaying its revision. Bound for
// every stamp, sampled only by mode 11 — a sampler that is declared and
// never read is free, while branching on whether one is bound is not
// expressible here.
uniform sampler2D u_target;
uniform vec2 u_center;      // stamp center, UV
uniform vec2 u_delta;       // content displacement, UV delta
uniform float u_radius;     // aspect-space radius
uniform float u_strength;
uniform float u_aspect;     // image width / height
uniform int u_mode;         // StampMode.shaderId
uniform int u_profile;      // FalloffProfile.shaderId
uniform int u_guarded;      // StampMode.respectsFreeze
uniform vec2 u_fieldTexel;  // 1 / field dimensions
// Taffy Pins (proposal 0016). xy = source control, zw = target control;
// u_pinWeight is the per-control multiplier that lets the implicit frame
// corners argue more quietly than a pin the user placed. Sized to
// RigidMls.MAX_CONTROLS, so the loop cost never depends on the document.
uniform vec4 u_pin[10];
uniform float u_pinWeight[10];
uniform int u_pinCount;
uniform float u_pinReach;
uniform float u_pinRubber;
in vec2 v_uv;
out vec4 o_field;

// BrushFalloff.weight: smoothstep(1 -> 0), C1 at both ends.
float base(float d) {
    if (d <= 0.0) return 1.0;
    if (d >= 1.0) return 0.0;
    float t = 1.0 - d;
    return t * t * (3.0 - 2.0 * t);
}

// BrushFalloff.weight(d, profile).
float falloff(float d) {
    if (u_profile == 1) { float w = base(d); return w * w; }
    if (u_profile == 2) return d <= 0.7 ? 1.0 : base((d - 0.7) / 0.3);
    return base(d);
}

// BrushFalloff.centerRamp.
float centerRamp(float d) {
    float t = clamp(d / 0.08, 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

// smoothOdd (DisplacementField): odd, C1, zero at 0, ±1 by |x| = 1.
float smoothOdd(float x) {
    float a = min(abs(x), 1.0);
    float shaped = a * a * (3.0 - 2.0 * a);
    return x < 0.0 ? -shaped : shaped;
}

// sign() that is +1 at zero, matching the Kotlin helper.
float signPos(float x) { return x < 0.0 ? -1.0 : 1.0; }

// RigidMls.sourceAt, transliterated. Backward map: given an output point
// it returns where to sample, so the controls are read target-as-source
// (p = zw, q = xy) exactly as `inverse = true` does on the Kotlin side.
//
// 1e-12 = RigidMls.EPSILON_SQ, 1e-6 = RigidMls.EPSILON. Two guards, not
// one: the exact-hit branch returns instead of dividing, and the length
// comparisons use the unsquared floor.
vec2 pinSourceAt(vec2 x) {
    float sumW = 0.0;
    vec2 pStar = vec2(0.0);
    vec2 qStar = vec2(0.0);
    float w[10];
    for (int i = 0; i < 10; i++) {
        if (i >= u_pinCount) break;
        vec2 p = u_pin[i].zw;
        vec2 d = vec2((x.x - p.x) * u_aspect, x.y - p.y);
        float d2 = dot(d, d);
        if (d2 <= 1e-12) return u_pin[i].xy;
        float wi = u_pinWeight[i] / pow(d2, u_pinReach);
        w[i] = wi;
        sumW += wi;
        pStar += wi * p;
        qStar += wi * u_pin[i].xy;
    }
    if (sumW <= 0.0) return x;
    pStar /= sumW;
    qStar /= sumW;
    vec2 vv = vec2((x.x - pStar.x) * u_aspect, x.y - pStar.y);
    vec2 f = vec2(0.0);
    float muS = 0.0;
    for (int i = 0; i < 10; i++) {
        if (i >= u_pinCount) break;
        vec2 ph = vec2((u_pin[i].z - pStar.x) * u_aspect, u_pin[i].w - pStar.y);
        vec2 qh = vec2((u_pin[i].x - qStar.x) * u_aspect, u_pin[i].y - qStar.y);
        muS += w[i] * dot(ph, ph);
        float a = dot(ph, vv);
        float b = ph.x * vv.y - ph.y * vv.x;
        f += w[i] * vec2(qh.x * a - qh.y * b, qh.x * b + qh.y * a);
    }
    float vLen = length(vv);
    float fLen = length(f);
    vec2 rigid = fLen <= 1e-6 ? vv : f / fLen * vLen;
    vec2 sim = muS <= 1e-6 ? vv : f / muS;
    vec2 outv = mix(rigid, sim, u_pinRubber);
    return vec2(qStar.x + outv.x / u_aspect, qStar.y + outv.y);
}

void main() {
    // A pin pull is not a stamp: no disc, no falloff, no delta. It is
    // one analytic pass over the whole field, so it returns before any
    // of the brush machinery below runs.
    if (u_mode == 12) {         // PINWARP
        vec2 src = pinSourceAt(v_uv);
        vec2 wv = src - v_uv;
        // D'(x) = w(x) + D(x + w(x)) — the engine's warp-of-warp rule.
        // Reading the old field at the PREWARPED position is what makes
        // the pull act on the picture as it currently looks, and it
        // carries the Fusion mask and the varnish along for free.
        vec4 prev = texture(u_field, src);
        o_field = vec4(wv + prev.xy, prev.z, prev.w);
        return;
    }
    vec2 fromCenter = v_uv - u_center;
    fromCenter.x *= u_aspect;
    // FalloffProfile.DRIP (3) compresses the distance BELOW the center
    // so the lobe reaches downward; every other profile is radial.
    // 0.45 = BrushDynamics.DRIP_LOBE.
    vec2 metric = fromCenter;
    if (u_profile == 3 && metric.y > 0.0) metric.y *= 0.45;
    float distA = length(metric);
    float d = distA / u_radius;
    // Field texel: xy = displacement, z = Fusion mask, w = Freeze mask
    // (DisplacementField — CHANNELS is 4; the field is now full).
    // Read BEFORE the weight, which needs the varnish out of w.
    vec4 cur = texture(u_field, v_uv);
    // The varnish (proposal 0002) scales every stamp weight, which is
    // what aims the whole palette from one mode. Read in DOCUMENT space
    // — never through the warp lookup — because "this stays here" is a
    // statement about the document. 0.0 = GUARD and ERASE, which apply
    // and remove varnish and so must not be braked by it.
    float guard = u_guarded == 0 ? 1.0 : 1.0 - clamp(cur.w, 0.0, 1.0);
    float w = falloff(d) * u_strength * guard;
    // The radial direction is measured on the TRUE offset, not the
    // anisotropic metric — only the weight is reshaped.
    float distR = length(fromCenter);
    vec4 next;
    if (u_mode == 5) {              // FUSE: mask flow, displacement as-is
        // 0.3  = BrushDynamics.FUSE_STEP (0.22 below = BLEND_STEP) —
        // documented-duplication convention, keep in sync.
        next = vec4(cur.xy, clamp(cur.z + w * 0.3, 0.0, 1.0), cur.w);
    } else if (u_mode == 10) {      // GUARD: varnish flow, rest as-is
        // 0.18 = BrushDynamics.FREEZE_STEP.
        next = vec4(cur.xyz, clamp(cur.w + w * 0.18, 0.0, 1.0));
    } else if (u_mode == 3) {       // RELAX
        vec3 blur = 0.25 * (
            texture(u_field, v_uv + vec2(u_fieldTexel.x, 0.0)).xyz +
            texture(u_field, v_uv - vec2(u_fieldTexel.x, 0.0)).xyz +
            texture(u_field, v_uv + vec2(0.0, u_fieldTexel.y)).xyz +
            texture(u_field, v_uv - vec2(0.0, u_fieldTexel.y)).xyz);
        // Smoothing the goo must not erode the varnish: w passes through.
        next = vec4(mix(cur.xyz, blur, w * 0.22), cur.w);
    } else if (u_mode == 11) {      // RECALL
        // RELAX's branch with the blur replaced by one read from the
        // target field. 0.22 = BrushDynamics.BLEND_STEP, the same rate
        // UnGoo dissolves at, because this IS UnGoo aimed somewhere
        // else.
        //
        // The whole vec4 is mixed, unlike RELAX: a Rewind restores the
        // Fusion mask and the varnish as they were at that frame too.
        // The varnish is deliberately included — Rewind is not exempt
        // from the brake (it respects freeze), so a varnished region is
        // protected FROM being rewound, while what does get rewound
        // carries that frame's varnish with it.
        next = mix(cur, texture(u_target, v_uv), w * 0.22);
    } else if (u_mode == 4) {       // ERASE (un-fuses AND thaws)
        next = cur * (1.0 - w * 0.22);
    } else {                        // warp modes: b(p) then warp-of-warp
        vec2 b;
        if (u_mode == 0) {          // DIRECTIONAL
            b = -u_delta * w;
        } else if (u_mode == 7) {   // COMB: teeth cut across the drag
            // 3.0 = BrushDynamics.COMB_TEETH, 6.2831855 = TAU.
            vec2 a = vec2(u_delta.x * u_aspect, u_delta.y);
            float len = length(a);
            if (len < 1e-9) {
                b = vec2(0.0);
            } else {
                vec2 across = vec2(-a.y / len, a.x / len);
                float s = dot(fromCenter, across) / u_radius;
                float teeth = 0.5 + 0.5 * cos(6.2831855 * s * 3.0);
                b = -u_delta * w * teeth;
            }
        } else if (u_mode == 9) {   // FAULT: opposed shear across the seam
            // 0.01 = BrushDynamics.FAULT_STEP_UV.
            vec2 a = vec2(u_delta.x * u_aspect, u_delta.y);
            float len = length(a);
            if (len < 1e-9) {
                b = vec2(0.0);
            } else {
                vec2 t = a / len;
                float side = smoothOdd(dot(fromCenter, vec2(-t.y, t.x)) / u_radius);
                float m = side * w * 0.01;
                b = vec2((t.x / u_aspect) * m, t.y * m);
            }
        } else {                    // radial family: 1, 2, 6, 8
            // 0.004 = RADIAL_STEP_UV, 0.0035 = SWIRL_STEP_UV,
            // 0.01 = RIPPLE_STEP_UV, 3.0 = RIPPLE_BANDS.
            float ramp = w * centerRamp(d);
            if (distR < 1e-6) {
                b = vec2(0.0);
            } else if (u_mode == 6) {           // VORTEX
                vec2 t = vec2(-fromCenter.y / distR, fromCenter.x / distR);
                float m = ramp * 0.0035 * signPos(u_delta.x);
                b = vec2((t.x / u_aspect) * m, t.y * m);
            } else {
                vec2 outward =
                    vec2((fromCenter.x / distR) / u_aspect, fromCenter.y / distR);
                if (u_mode == 8) {              // RIPPLE
                    b = outward * (ramp * 0.01 * sin(6.2831855 * 3.0 * d));
                } else {                        // INFLATE (1) / DEFLATE (2)
                    b = (u_mode == 1 ? -1.0 : 1.0) * outward * (ramp * 0.004);
                }
            }
        }
        // The fusion mask rides the same lookup — painted fusion moves
        // with the goo. The varnish does NOT: it is pinned to the
        // document, so it comes from this texel, not the warped one.
        vec3 prev = texture(u_field, v_uv + b).xyz;
        next = vec4(b + prev.xy, prev.z, cur.w);
    }
    o_field = next;
}
