#version 150
// int explicitly: fragment shaders predeclare int (GLSL ES
// §4.5.4), which the spec only guarantees 16 bits — the integer hash
// below would collapse (h >> 16 ≡ 0, products wrap at 2^16) on 16-bit-ALU
// GPUs. int is exactly 32-bit, matching Kotlin UInt bit for bit.
uniform sampler2D u_image;
// highp: see STAMP_FRAG — the field must not be read at lowp.
uniform sampler2D u_field;
// GOOvie tween pair (PLAN.md §4.1: tweening two fields is mix(D1,D2,t)).
// Outside a scrub u_tween is 0 and u_fieldB is bound to the live field,
// so mix() degenerates to the plain read.
uniform sampler2D u_fieldB;
uniform float u_tween;
// Fusion (PLAN.md §3): photo B, cover-cropped to A's UV space at upload,
// revealed by the field's z-channel mask. u_hasB gates stale masks when
// no B is loaded.
uniform sampler2D u_imageB;
uniform float u_hasB;
uniform float u_gAspect;   // image width / height
uniform float u_g[6];
// Placed warps (proposal 0006). Fixed-size pack, so the pass cost never
// depends on the document: xy = center UV, z = radius (aspect space),
// w = strength. u_lensType carries LensType.shaderId.
uniform vec4 u_lens[4];
uniform int u_lensType[4];
uniform int u_lensCount;
// Frost sheen over the freeze mask (proposal 0002); preview-only, and
// never set for an export, so the varnish can never be rendered into a
// saved picture.
uniform float u_showFreeze;
in vec2 v_uv;
out vec4 o_color;

float hash(uint x, uint y, uint seed) {
    uint h = x * 1664525u + y * 1013904223u + seed * 2654435761u;
    h = h ^ (h >> 16);
    h *= 2246822519u;
    h = h ^ (h >> 13);
    return float(h & 0x00FFFFFFu) / 16777216.0;
}

float valueNoise(float x, float y, uint seed) {
    float xf = floor(x);
    float yf = floor(y);
    int x0 = int(xf);
    int y0 = int(yf);
    float fx = x - xf;
    float fy = y - yf;
    float sx = fx * fx * (3.0 - 2.0 * fx);
    float sy = fy * fy * (3.0 - 2.0 * fy);
    float a = hash(uint(x0), uint(y0), seed);
    float b = hash(uint(x0 + 1), uint(y0), seed);
    float c = hash(uint(x0), uint(y0 + 1), seed);
    float d = hash(uint(x0 + 1), uint(y0 + 1), seed);
    float top = a + (b - a) * sx;
    float bottom = c + (d - c) * sx;
    return top + (bottom - top) * sy;
}

float smoothShape(float t) { return t * t * (3.0 - 2.0 * t); }

// A cold blue-white, at the strength that reads as varnish rather than
// as paint. Chrome only — see u_showFreeze.
const vec3 FROST = vec3(0.62, 0.83, 1.0);
const float FROST_ALPHA = 0.38;

// GlobalField.displacement, line for line.
vec2 globalDisp(vec2 uv) {
    float ax = (uv.x - 0.5) * u_gAspect;
    float ay = uv.y - 0.5;
    float r = sqrt(ax * ax + ay * ay);
    float rMax = sqrt(u_gAspect * u_gAspect + 1.0) * 0.5;
    float shape = smoothShape(1.0 - clamp(r / rMax, 0.0, 1.0));
    float dx = 0.0;
    float dy = 0.0;
    if (u_g[0] != 0.0 && r > 1e-6) {
        float m = -u_g[0] * 0.35 * shape * r / rMax;
        dx += (ax / r) * m;
        dy += (ay / r) * m;
    }
    if (u_g[1] != 0.0) {
        float theta = u_g[1] * 2.5 * shape;
        float c = cos(theta);
        float s = sin(theta);
        dx += ax * c - ay * s - ax;
        dy += ax * s + ay * c - ay;
    }
    if (u_g[2] != 0.0) {
        dx += ax * u_g[2] * 0.3;
        dy += -ay * u_g[2] * 0.3 * 0.5;
    }
    if (u_g[3] != 0.0) {
        dy += -ay * u_g[3] * 0.3;
    }
    if (u_g[4] != 0.0 && r > 1e-6) {
        float phi = atan(ay, ax);
        float m = u_g[4] * 0.08 * shape * sin(8.0 * phi);
        dx += (ax / r) * m;
        dy += (ay / r) * m;
    }
    if (u_g[5] != 0.0) {
        float nx = valueNoise(uv.x * 24.0, uv.y * 24.0, 1u);
        float ny = valueNoise(uv.x * 24.0, uv.y * 24.0, 2u);
        dx += (nx * 2.0 - 1.0) * u_g[5] * 0.05;
        dy += (ny * 2.0 - 1.0) * u_g[5] * 0.05;
    }
    // Placed warps, on top of the frame-centered ones — same aspect
    // space, so they sum in before the one conversion back to UV.
    for (int i = 0; i < 4; i++) {
        if (i >= u_lensCount) break;
        vec4 lens = u_lens[i];
        float lx = (uv.x - lens.x) * u_gAspect;
        float ly = uv.y - lens.y;
        float d = sqrt(lx * lx + ly * ly);
        if (d >= lens.z) continue;
        float window = smoothShape(1.0 - d / lens.z);
        int type = u_lensType[i];
        if (type == 3) {
            float theta = lens.w * 2.0 * window;
            float c = cos(theta);
            float s = sin(theta);
            dx += lx * c - ly * s - lx;
            dy += lx * s + ly * c - ly;
        } else if (d > 1e-6) {
            float ramp = type == 2
                ? min(d / (lens.z * 0.35), 1.0)
                : d / lens.z;
            float dir = type == 1 ? 1.0 : -1.0;
            float m = dir * lens.w * 0.5 * lens.z * window * ramp;
            dx += (lx / d) * m;
            dy += (ly / d) * m;
        }
    }

    return vec2(dx / u_gAspect, dy);
}

void main() {
    // xy = displacement, z = fusion mask, w = freeze mask; the vec4 mix
    // tweens all of them, so GOOvies animate fusion reveals and keep a
    // frozen eye frozen across a tween with no extra machinery.
    vec4 fa = texture(u_field, v_uv);
    vec4 fb = texture(u_fieldB, v_uv);
    vec4 f = mix(fa, fb, u_tween);
    // The varnish scales the analytic warps too. Stamped displacement
    // was already guarded when it was stamped, but levers and lenses are
    // evaluated here and now — without this multiply, "frozen" would
    // stop meaning anything the moment someone pulled the Twirl lever.
    float thawed = 1.0 - clamp(f.w, 0.0, 1.0);
    vec2 disp = f.xy + globalDisp(v_uv) * thawed;
    vec2 src = v_uv + disp;
    vec4 colorA = texture(u_image, src);
    vec4 colorB = texture(u_imageB, src);
    o_color = mix(colorA, colorB, clamp(f.z, 0.0, 1.0) * u_hasB);
    // The frost sheen is CHROME, not document: a way to see the mask
    // while the tool is armed. u_showFreeze is 0 for every export, so it
    // can never be rendered into a saved picture.
    o_color = mix(o_color, vec4(FROST, o_color.a),
                  clamp(f.w, 0.0, 1.0) * u_showFreeze * FROST_ALPHA);
}
