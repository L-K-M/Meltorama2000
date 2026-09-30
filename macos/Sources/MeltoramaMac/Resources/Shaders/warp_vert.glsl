#version 150
in vec2 a_pos;   // shared quad VBO: NDC corners in [-1,1]²
uniform vec4 u_rectPx;                // image quad in pixels: x, y = top-left, z, w = size
uniform vec2 u_viewport;              // render target size in pixels
uniform vec4 u_view;                  // pixel-space similarity: a, b, tx, ty
out vec2 v_uv;
void main() {
    vec2 unit = a_pos * 0.5 + 0.5;               // [0,1]², origin bottom-left
    v_uv = vec2(unit.x, 1.0 - unit.y);           // image UV, origin top-left
    // Pixel position, y-down to match v_uv's row order.
    vec2 px = vec2(u_rectPx.x + unit.x * u_rectPx.z,
                   u_rectPx.y + (1.0 - unit.y) * u_rectPx.w);
    vec2 tp = vec2(u_view.x * px.x - u_view.y * px.y + u_view.z,
                   u_view.y * px.x + u_view.x * px.y + u_view.w);
    gl_Position = vec4(tp.x / u_viewport.x * 2.0 - 1.0,
                       1.0 - tp.y / u_viewport.y * 2.0, 0.0, 1.0);
}
