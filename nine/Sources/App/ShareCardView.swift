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
import AVFoundation
import CoreVideo

/// The share button's words, in the feature's own file rather than in each
/// platform's UI file — `TouchUI` and `MacUI` are fenced to opposite platforms
/// and cannot share a `Phrase` block, and two copies of a string is two things
/// for PRD-20 to find and one of them to miss.
enum ShareCardPhrase {
    static let share = Strings.string("share.button")
    /// Also the share sheet's fallback subject, so it reads as a sentence.
    static let shareLabel = Strings.string("share.label")
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
            let boxGap = size.width * BoardArt.cardGutter
            let cell = BoardArt.cell(side: size.width, gutter: boxGap)
            // `BoardType.entry`, not a local 0.62. The board sets a digit at
            // 0.56 of its cell and this card was setting the same digit at
            // 0.62, so the artefact a player exports and shows people was a
            // visibly different object from the one they played on.
            let digitSize = cell * BoardType.entry

            for index in 0..<81 {
                let column = index % 9, row = index / 9
                // Two gaps accumulate across the row, one after each of the
                // first two boxes — so the boxes read without a single rule.
                let box = BoardArt.cellRect(column: column, row: row, cell: cell, gutter: boxGap)
                context.fill(
                    Path(roundedRect: box.insetBy(dx: cell * BoardArt.cellInset,
                                                  dy: cell * BoardArt.cellInset),
                         cornerRadius: cell * BoardArt.cellCorner),
                    with: .color(tones.gridTone.opacity(tones.isLight ? 0.07 : 0.10))
                )

                // Givens in the theme's digit tone, the player's own in the
                // accent — so the card shows how much of the board was theirs,
                // which is the part worth being proud of. Same rule as
                // `BoardFingerprint`, which is what the shelf already taught
                // this player to read.
                //
                // **The weights were inverted.** This drew givens `.medium` and
                // entries `.semibold` while `BoardView` draws the opposite, so
                // the app's own share card taught the reverse of the board's
                // colour-and-weight code. `BoardType` owns the pair now, and
                // both sites read it rather than restating it.
                let isGiven = facts.givens[index]
                var text = context.resolve(
                    Text("\(facts.digits[index])")
                        .font(.system(size: digitSize,
                                      weight: isGiven ? BoardType.givenWeight : BoardType.entryWeight,
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

/// The comet in the card's body slot (PRD-26 §2.4).
///
/// The chrome, the margins and every caption are untouched — `ShareCard` is
/// generic over its body at `ShareCardMetrics.bodySide` and this takes that
/// 888 pt square unchanged, which is exactly what that seam was cut for.
struct CometCardBody: View {
    let replay: SolveReplay
    let tones: ThemeTones
    let accent: Color
    /// Where in the loop this frame sits. The exporter walks it; nothing here
    /// reads a clock, so a frame is a pure function of its number.
    let phase: Double

    var body: some View {
        CometView(
            puzzle: replay.puzzle ?? [Int](repeating: 0, count: 81),
            moves: replay.moves,
            tones: tones,
            accent: accent,
            frozenPhase: phase
        )
    }
}

/// A rendered card, ready to hand to `ShareLink`.
///
/// Both halves are needed and neither substitutes for the other: the **URL** is
/// what gets shared, because a file arrives with a name and unlocks Files,
/// AirDrop and Photos as well as Messages; the **preview** is what the share
/// sheet shows above the app row, and without it that row is a blank document
/// icon — the first thing a recipient sees of the card being nothing at all.
struct ShareCardExport {
    let url: URL
    let preview: Image
}

/// Flattens a card to a PNG on disk plus a preview image.
@MainActor
enum ShareCardRenderer {

    /// Render once, and return the file and the preview built from the same
    /// pass — rasterising a 1080×1350 card twice to get two representations of
    /// one picture would be pure waste on the path right after a solve.
    ///
    /// `scale = 1` against a 1080-*point* card gives a 1080-*pixel* PNG on every
    /// device. Left at the screen's scale, an iPhone SE and a Pro Max would
    /// produce different files from the same board — and a 3× card is 3240 px
    /// wide, a needlessly large thing to hand to a message.
    static func export(
        facts: SolveCardFacts, tones: ThemeTones, accent: Color
    ) -> ShareCardExport? {
        let renderer = ImageRenderer(
            content: ShareCard(facts: facts, tones: tones, accent: accent) {
                SolvedGridThumb(facts: facts, tones: tones, accent: accent)
            }
        )
        renderer.scale = 1
        renderer.isOpaque = true

        let data: Data
        let preview: Image
        #if os(macOS)
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        data = png
        preview = Image(nsImage: image)
        #else
        guard let image = renderer.uiImage, let png = image.pngData() else { return nil }
        data = png
        preview = Image(uiImage: image)
        #endif

        // The filename is the only text Nine puts in the recipient's file list,
        // so it is the wordmark and nothing else.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Nine-\(UUID().uuidString.prefix(8)).png")
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return ShareCardExport(url: url, preview: preview)
    }

    // MARK: - The 5 s loop (PRD-26 §2.4)

    /// 30 fps × 5 s = 150 frames. Thirty rather than sixty because the comet is
    /// one slow object on a flat ground: the extra frames cost a doubled export
    /// on the path right after a solve and buy nothing the eye can find.
    static let loopFPS: Int32 = 30
    static var loopFrameCount: Int { Int(loopFPS) * Int(CometTimeline.loopSeconds) }

    /// Render the card with the comet as its body, as an H.264 `.mp4`.
    ///
    /// **One chip, two payloads** (PRD-26 §2.4). The caller falls back to
    /// `export` whenever this returns nil, which is not defensive coding: three
    /// real paths mint no replay at all — a widget solve, a watch solve, and
    /// any board that reached this device over CloudKit, whose log
    /// `SyncedEntry` strips by design. An unconditional loop would have deleted
    /// PRD-12's shipped behaviour on all three.
    ///
    /// MP4 rather than GIF or APNG, and the reason is arithmetic: this card is
    /// 1080×1350, and five seconds of it as a palettised GIF is tens of
    /// megabytes. APNG is small but silently dropped by several of the places
    /// a card actually goes.
    static func exportLoop(
        facts: SolveCardFacts, replay: SolveReplay, tones: ThemeTones, accent: Color
    ) -> ShareCardExport? {
        guard !replay.moves.isEmpty, replay.puzzle != nil else { return nil }
        let size = ShareCardMetrics.size
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Nine-\(UUID().uuidString.prefix(8)).mp4")
        try? FileManager.default.removeItem(at: url)

        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return nil }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height)
            ]
        )
        guard writer.canAdd(input) else { return nil }
        writer.add(input)
        guard writer.startWriting() else { return nil }
        writer.startSession(atSourceTime: .zero)

        var preview: Image?
        for index in 0..<loopFrameCount {
            let phase = Double(index) / Double(loopFrameCount)
            let renderer = ImageRenderer(
                content: ShareCard(facts: facts, tones: tones, accent: accent) {
                    CometCardBody(replay: replay, tones: tones, accent: accent, phase: phase)
                }
            )
            renderer.scale = 1
            renderer.isOpaque = true
            guard let cg = renderer.cgImage,
                  let buffer = pixelBuffer(from: cg, pool: adaptor.pixelBufferPool, size: size)
            else {
                writer.cancelWriting()
                return nil
            }
            // The share sheet's thumbnail is the *last* frame, not the first:
            // frame 0 is a nearly empty board, and a preview of an empty board
            // is a preview of nothing having happened.
            if index == loopFrameCount - 1 {
                #if os(macOS)
                preview = Image(nsImage: NSImage(cgImage: cg, size: size))
                #else
                preview = Image(uiImage: UIImage(cgImage: cg))
                #endif
            }
            // Spin rather than await: `ImageRenderer` is main-actor-bound, so
            // this whole function is, and the writer drains a non-real-time
            // input promptly. 150 frames of a flat card is well under a second.
            while !input.isReadyForMoreMediaData { usleep(200) }
            adaptor.append(
                buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: loopFPS)
            )
        }
        input.markAsFinished()

        // `finishWriting(completionHandler:)` is the only supported spelling,
        // and every caller of this is synchronous, so the semaphore is the
        // bridge. Safe because the completion runs on the writer's own queue
        // and never hops back to the main actor.
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed, let preview else { return nil }
        return ShareCardExport(url: url, preview: preview)
    }

    private static func pixelBuffer(
        from image: CGImage, pool: CVPixelBufferPool?, size: CGSize
    ) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        if let pool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        } else {
            CVPixelBufferCreate(
                nil, Int(size.width), Int(size.height), kCVPixelFormatType_32ARGB,
                [kCVPixelBufferCGImageCompatibilityKey: true] as CFDictionary, &buffer
            )
        }
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return buffer
    }
}
