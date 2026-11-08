
#version 460 core
#include <flutter/runtime_effect.glsl>

// RGB color-key preview with cumulative (confirmed) alpha stages.
// Floats: size(0,1), key RGB(2..4), similarity(5), blend(6),
//         has mask(7), current draft enabled(8).
// Samplers: original frame(0), committed alpha mask(1).
uniform vec2 uSize;
uniform vec3 uKey;
uniform float uSimilarity;
uniform float uBlend;
uniform float uHasCommittedMask;
uniform float uDraftEnabled;
uniform sampler2D uVideoFrame;
uniform sampler2D uCommittedMask;

out vec4 fragColor;

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;
    vec4 pixel = texture(uVideoFrame, uv);
    float priorKeep = uHasCommittedMask > 0.5
        ? texture(uCommittedMask, uv).r : 1.0;
    float currentKeep = 1.0;
    if (uDraftEnabled > 0.5) {
        float distance = length(pixel.rgb - uKey) / 1.7320508075688772;
        currentKeep = uBlend > 0.0001
            ? clamp((distance - uSimilarity) / uBlend, 0.0, 1.0)
            : (distance > uSimilarity ? 1.0 : 0.0);
    }
    // Multiplication makes removal irreversible across confirmed passes.
    float alpha = pixel.a * priorKeep * currentKeep;
    fragColor = vec4(pixel.rgb * alpha, alpha);
}
