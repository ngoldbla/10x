// ShareCardView.swift — a finished board as a gift (PRD-12 §2).
//
// **Not `BoardView`.** The live board carries the Afterglow's Metal pipeline,
// the rose, selection, error state, pencil marks and 81 accessibility children.
// None of that survives being flattened to a PNG, and all of it would have to
// be reasoned about to be sure of that. This is a fresh Canvas that draws 81
// digits and stops.
//
// **The body is a slot, and that is the architecture (PRD-26).** The comet
// replay is going to become this card's animated body — PROGRAM-2.0 §Pillar C
// says so in as many words — so the chrome here is a layout that takes its
// centre as a generic view. `ShareCardMetrics` owns the body's side length and
// the margins around it, and `SolvedGridThumb` is simply what fills the slot
// today. Swapping in a comet is a change at the call site: no caption moves, no
// margin is re-derived, and the still and the loop are laid out identically
// because they are laid out by the same code.
//
// Rendered at a fixed 1080×1350 in the renderer's own coordinate space, so the
// output is byte-for-byte independent of device and Dynamic Type: a share card
// is a picture, not a screen, and must not reflow. That is also why nothing
// here uses `CouchTypography`, whose sizes are chosen for screens.
//
// No platform fence. `Canvas`, `Text` and `ImageRenderer` all compile on tvOS,
// and PRD-26's tvOS ambient screensaver will want the body. Only `ShareLink` is
// unavailable there, and that lives in `TouchUI`/`MacUI`, which are already
// fenced to their platforms.
import SwiftUI
import CouchKit

/// The share button's words, in the feature's own file rather than in each
/// platform's UI file — `TouchUI` and `MacUI` are fenced to opposite platforms
/// and cannot share a `Phrase` block, and two copies of a string is two things
/// for PRD-20 to find and one of them to miss.
enum ShareCardPhrase {
    static let share = "Share"
    /// Also the share sheet's fallback subject, so it reads as a sentence.
    static let shareLabel = "Share your solve"
}

/// The card's fixed geometry, in one place so a future body inherits exactly
/// the frame the grid had.
enum ShareCardMetrics {
    /// Portrait, sized for feeds (PRD-12 §2).
    static let size = CGSize(width: 1080, height: 1350)
    static let margin: CGFloat = 96
    /// The body slot: square, spanning the card between the margins. PRD-26's
    /// comet gets this frame unchanged.
    static var bodySide: CGFloat { size.width - margin * 2 }
    static let timeSize: CGFloat = 76
    static let creditSize: CGFloat = 40
    static let dailySize: CGFloat = 30
    static let wordmarkSize: CGFloat = 64
    /// Not localized, ever: it is the mark, not a word. It lives here rather
    /// than in a `Phrase` block nested in `ShareCard` because that type is
    /// generic over its body, and Swift has no static stored properties in a
    /// generic type.
    static let wordmark = "NINE"
}

/// The card: a themed backdrop, a square body, the captions, the wordmark.
struct ShareCard<Content: View>: View {
    let facts: SolveCardFacts
    let tones: ThemeTones
    let accent: Color
    /// The card's centre — still today, animated in PRD-26.
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
                .frame(width: ShareCardMetrics.bodySide, height: ShareCardMetrics.bodySide)

            Spacer(minLength: 48)

            VStack(spacing: 14) {
                Text(facts.timeLine)
                    .font(.system(size: ShareCardMetrics.timeSize, weight: .bold, design: .rounded))
                    .foregroundStyle(tones.digitTone)
                Text(facts.creditLine)
                    .font(.system(size: ShareCardMetrics.creditSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(tones.digitTone.opacity(0.62))
                if let dailyLine = facts.dailyLine {
                    Text(dailyLine)
                        .font(.system(size: ShareCardMetrics.dailySize, weight: .medium, design: .rounded))
                        .foregroundStyle(tones.digitTone.opacity(0.42))
                }
            }

            Spacer(minLength: 40)

            // The wordmark is the entire call to action (PRD-12 §2) — no URL,
            // no "get it on the App Store", no QR code. If the picture is not
            // enough of a pitch, a link on it will not fix that.
            Text(ShareCardMetrics.wordmark)
                .font(.system(size: ShareCardMetrics.wordmarkSize, weight: .heavy, design: .rounded))
                .kerning(ShareCardMetrics.wordmarkSize * 0.18)
                .foregroundStyle(accent)
        }
        .padding(ShareCardMetrics.margin)
        .frame(width: ShareCardMetrics.size.width, height: ShareCardMetrics.size.height)
        .background(tones.background)
    }
}

/// The still body: 81 digits on the theme's wash, with the 3×3 structure read
/// from gaps rather than drawn rules — the move `BoardFingerprint` makes at
/// 34 pt, at a size where the digits themselves are the picture.
struct SolvedGridThumb: View {
    let facts: SolveCardFacts
    let tones: ThemeTones
    let accent: Color

    var body: some View {
        Canvas { context, size in
            let boxGap = size.width * 0.018
            let cell = (size.width - boxGap * 2) / 9
            let digitSize = cell * 0.62

            for index in 0..<81 {
                let column = index % 9, row = index / 9
                // Two gaps accumulate across the row, one after each of the
                // first two boxes — so the boxes read without a single rule.
                let box = CGRect(
                    x: CGFloat(column) * cell + CGFloat(column / 3) * boxGap,
                    y: CGFloat(row) * cell + CGFloat(row / 3) * boxGap,
                    width: cell, height: cell
                )
                context.fill(
                    Path(roundedRect: box.insetBy(dx: cell * 0.035, dy: cell * 0.035),
                         cornerRadius: cell * 0.16),
                    with: .color(tones.gridTone.opacity(tones.isLight ? 0.07 : 0.10))
                )

                // Givens in the theme's digit tone, the player's own in the
                // accent — so the card shows how much of the board was theirs,
                // which is the part worth being proud of. Same rule as
                // `BoardFingerprint`, which is what the shelf already taught
                // this player to read.
                let isGiven = facts.givens[index]
                var text = context.resolve(
                    Text("\(facts.digits[index])")
                        .font(.system(size: digitSize,
                                      weight: isGiven ? .medium : .semibold,
                                      design: .rounded))
                )
                text.shading = .color(isGiven ? tones.digitTone.opacity(0.72) : accent)
                context.draw(text, at: CGPoint(x: box.midX, y: box.midY), anchor: .center)
            }
        }
        // One picture, one sentence. 81 digits in the accessibility tree of an
        // image would be unreadable, and the grid is decoration around a
        // caption that already says what happened.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(facts.creditLine)
    }
}

/// Flattens a card to PNG bytes.
@MainActor
enum ShareCardRenderer {

    /// The card as PNG data, or nil if the platform declined to rasterise it.
    ///
    /// `scale = 1` against a 1080-*point* card gives a 1080-*pixel* PNG on every
    /// device. Left at the screen's scale, an iPhone SE and a Pro Max would
    /// produce different files from the same board — and a 3× card is 3240 px
    /// wide, which is a needlessly large thing to hand to a message.
    static func png(facts: SolveCardFacts, tones: ThemeTones, accent: Color) -> Data? {
        let renderer = ImageRenderer(
            content: ShareCard(facts: facts, tones: tones, accent: accent) {
                SolvedGridThumb(facts: facts, tones: tones, accent: accent)
            }
        )
        renderer.scale = 1
        renderer.isOpaque = true
        #if os(macOS)
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
        #else
        return renderer.uiImage?.pngData()
        #endif
    }

    /// Writes the PNG to a uniquely-named temp file and returns its URL.
    ///
    /// A file URL rather than a `Transferable` image: the share sheet then
    /// offers Files, AirDrop and Photos as well as Messages, and the file
    /// arrives with a name. That name is the only text Nine puts in the
    /// recipient's file list, so it is the wordmark and nothing else.
    static func temporaryFile(
        facts: SolveCardFacts, tones: ThemeTones, accent: Color
    ) -> URL? {
        guard let data = png(facts: facts, tones: tones, accent: accent) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Nine-\(UUID().uuidString.prefix(8)).png")
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }
}
