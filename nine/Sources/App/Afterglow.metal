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

/// Per-petal refraction (PRD-22) — the rose's petals as true glass.
///
/// A `layerEffect` cannot sample behind its own layer, so glassifying the petal
/// *views* was never going to lens anything: a shader attached to a petal can
/// only see the petal. Bending the layer *underneath* is the way round it. This
/// runs on the board's Canvas, so the board's own digits and grid magnify and
/// bend under each petal, and SwiftUI draws only a glyph and a rim above.
///
/// The nine centres are derived here rather than passed in, from the same ring
/// pitch `RoseLens` hands the petals — nine uniforms would be nine chances for
/// the bend to drift from the paint, and the ring is a rigid 3x3 grid by
/// construction. `bloom` is the petals' own spring (0 closed, 1 open) so the
/// lens grows with them.
[[stitchable]] half4 rosePetalLens(
    float2 position,
    SwiftUI::Layer layer,
    float2 centre,
    float spacing,
    float radius,
    float magnification,
    float bloom
) {
    if (bloom <= 0.001 || radius <= 0.001) { return layer.sample(position); }

    // `FlickRoseView` blooms the whole ring with `.scaleEffect(0.35 -> 1.0)`
    // and `.opacity(0 -> 1)`, so the lens has to grow from 0.35 too — starting
    // it at zero would slide the bend outward across the board while the
    // petals grew in place. The refraction *strength* ramps from nothing
    // separately (`ramp` below), which is the opacity half.
    float geometry = 0.35 + 0.65 * bloom;
    float ramp = bloom;
    float pitch = spacing * geometry;
    float r = radius * geometry;

    // Nearest petal on the 3x3 grid. Componentwise rounding finds it exactly —
    // on an axis-aligned uniform lattice the nearest point separates per axis —
    // so this is O(1) per pixel rather than nine distance tests. And the
    // nearest centre is the *only* one whose lens can claim a pixel: the ring's
    // pitch (126 * scale) is wider than a petal (116 * scale), so the discs
    // never overlap.
    float2 snapped = clamp(round((position - centre) / pitch), float2(-1.0), float2(1.0));
    float2 petal = centre + snapped * pitch;
    float dist = distance(position, petal);

    if (dist >= r) { return layer.sample(position); }

    float2 delta = position - petal;
    float t = dist / r;                    // 0 at the petal's centre, 1 at its rim

    // A spherical lens. The core magnifies uniformly — sampling from a smaller
    // neighbourhood is what magnification *is* — and the last fifth compresses,
    // the way the meniscus of a real lens crushes the world into a ring at its
    // edge. That compressed band is what makes glass read as glass rather than
    // as a zoom.
    //
    // The band is deliberately narrow and shallow. The first version ran
    // `smoothstep(0.74, 1.0)` to 1.85 and the screenshot is why it does not:
    // a board digit caught in a quarter-radius-wide band that steep smears into
    // a double image, which reads as an artifact rather than as glass — and a
    // board that draws attention to itself under your thumb is the one thing
    // the idle-pixel test exists to stop.
    float rim = smoothstep(0.80, 1.0, t);
    float squeeze = mix(1.0, mix(1.0 / max(magnification, 0.001), 1.42, rim), ramp);
    half4 color = layer.sample(petal + delta * squeeze);

    // A thin specular arc just inside the rim, scaled by alpha so it rides the
    // drawn content and never fogs empty board — the same rule the Afterglow
    // wave's glint follows two functions up.
    float arc = exp(-(t - 0.93) * (t - 0.93) / (2.0 * 0.045 * 0.045));
    color.rgb += half(arc * 0.13 * ramp) * color.a;
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
