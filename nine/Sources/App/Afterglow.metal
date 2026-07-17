// Afterglow.metal — the win celebration's two layer effects (PRD-1).
// Both run on BoardView's Canvas layer only (digits + grid), never on the
// couchGlass material behind it, so the glass plane stays optically still.
//
// Stitchable functions resolve BY NAME at runtime from the app target's
// default.metallib — a wrong signature is a silent no-op, not a compile
// error. Signatures must stay in lockstep with the ShaderLibrary calls in
// BoardView.swift.
#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

/// Refractive shockwave: a gaussian crest expanding from the winning cell.
/// Content at the crest is sampled back toward the origin (reads as
/// magnification through curved glass) and grid/digit pixels pick up a
/// specular glint proportional to band², both decaying as the wave travels.
[[stitchable]] half4 afterglowWave(
    float2 position,
    SwiftUI::Layer layer,
    float2 origin,
    float progress,
    float maxRadius,
    float amplitude
) {
    float2 delta = position - origin;
    float dist = length(delta);
    float crest = progress * maxRadius;
    // Crest width scales with the board so iPhone and 4K TV read the same.
    float sigma = max(maxRadius * 0.06, 18.0);
    float band = exp(-(dist - crest) * (dist - crest) / (2.0 * sigma * sigma));
    float decay = 1.0 - progress;

    float2 toward = dist > 0.001 ? (delta / dist) : float2(0.0, 0.0);
    float2 sampled = position - toward * (band * amplitude * decay);
    half4 color = layer.sample(sampled);

    // Additive glint, scaled by alpha so it rides the drawn content
    // (digits, grid hairlines) and never fogs empty board.
    half glint = half(band * band * 0.22 * decay);
    color.rgb += glint * color.a;
    return color;
}

/// Specular sheen: a soft diagonal highlight band across the solved board.
/// `sheenPos` slides it along the (1,1) diagonal (0 = top-left corner,
/// 1 = bottom-right); `tilt` shifts the sample point a few points for
/// parallax when the phone steers the light.
[[stitchable]] half4 afterglowSheen(
    float2 position,
    SwiftUI::Layer layer,
    float2 size,
    float sheenPos,
    float2 tilt,
    float strength
) {
    half4 color = layer.sample(position - tilt * 4.0);
    float along = (position.x + position.y) / (size.x + size.y);
    float width = 0.085;
    float band = exp(-(along - sheenPos) * (along - sheenPos) / (2.0 * width * width));
    color.rgb += half(band * strength) * color.a;
    return color;
}
