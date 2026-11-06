// Finance 1.10: edge refraction of a rounded «liquid glass» pane.
//
// Used as a backdrop image filter after a blur. Near the edge the pane bends
// light like a rounded lens: each pixel shows the backdrop from a little
// further inside, so shapes passing under the rim are pulled and squeezed.
// The middle of the pane shows the backdrop as it is. A light saturation
// boost makes colors under the glass look richer.
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;      // set by the engine: input texture size, px
uniform float uRadius;   // corner radius, px
uniform float uBevel;    // width of the refracting rim, px
uniform float uAmount;   // largest shift at the very edge, px
uniform float uSaturation;
uniform sampler2D uTexture;

out vec4 fragColor;

// Signed distance to the rounded rectangle filling the texture (negative
// inside) and the outward normal there.
float roundedBox(vec2 p, out vec2 n) {
  vec2 half_ = uSize * 0.5;
  vec2 d = p - half_;
  float r = min(uRadius, min(half_.x, half_.y));
  vec2 q = abs(d) - (half_ - vec2(r));
  float outside = length(max(q, 0.0));
  float inside = min(max(q.x, q.y), 0.0);
  if (q.x > 0.0 && q.y > 0.0) {
    n = normalize(q) * sign(d);
  } else if (q.x > q.y) {
    n = vec2(sign(d.x), 0.0);
  } else {
    n = vec2(0.0, sign(d.y));
  }
  return outside + inside - r;
}

vec4 sampleAt(vec2 p) {
  vec2 uv = clamp(p, vec2(0.5), uSize - vec2(0.5)) / uSize;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  return texture(uTexture, uv);
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  vec2 n;
  float inward = -roundedBox(p, n);
  vec2 shift = vec2(0.0);
  if (inward > 0.0 && inward < uBevel) {
    // Circular lens profile: no shift where the rim meets the flat middle,
    // the largest shift at the very edge.
    float x = 1.0 - inward / uBevel;
    shift = -n * uAmount * (1.0 - sqrt(max(1.0 - x * x, 0.0)));
  }
  vec4 c = sampleAt(p + shift);
  float luma = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
  c.rgb = mix(vec3(luma), c.rgb, uSaturation);
  fragColor = c;
}
