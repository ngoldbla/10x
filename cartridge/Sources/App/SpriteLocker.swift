// SpriteLocker — photos → pixel-art actor sprites and mosaic backdrops.
// Deterministic per (photo, day): a great sprite day is shareable by
// screenshot. Sprites are art only; hitboxes never see them.
import SwiftUI
import CouchKit
import CoreGraphics

@MainActor @Observable
final class SpriteLocker {
    static let actorCount = 7        // slot 0 = hero, 1…6 = supporting cast
    static let actorGridCols = 24    // chunky by design
    static let backdropGridCols = 96

    private(set) var actors: [CGImage] = []
    private(set) var backdrops: [CGImage] = []
    private(set) var isReady = false

    /// Rebuild the locker for a day + lane. Falls back to DemoArt whenever
    /// the library is unauthorized or thin — the app always works.
    func build(day: DayStamp, lane: SpriteLane) async {
        let photos: [CuratedPhoto]
        switch lane {
        case .demo:
            photos = CouchPhotos.demoPhotos(limit: 12, seed: day.seed)
        case .photos:
            photos = await CouchPhotos.randomMemorable(limit: 12, seed: day.seed)
        }

        var newActors: [CGImage] = []
        var newBackdrops: [CGImage] = []
        for photo in photos {
            guard let image = try? await photo.load(maxDimension: 720) else { continue }
            let seed = day.seed ^ Self.stableSeed(photo.id)
            if newActors.count < Self.actorCount {
                if let sprite = await Self.actorSprite(from: image, seed: seed) {
                    newActors.append(sprite)
                }
            } else if newBackdrops.count < 4, image.width >= image.height {
                if let backdrop = await Self.backdrop(from: image, seed: seed) {
                    newBackdrops.append(backdrop)
                }
            }
            if newActors.count >= Self.actorCount && newBackdrops.count >= 4 { break }
        }
        // Thin libraries: reuse actor sources as backdrops rather than none.
        if newBackdrops.isEmpty {
            for photo in photos.prefix(2) {
                guard let image = try? await photo.load(maxDimension: 720) else { continue }
                if let backdrop = await Self.backdrop(
                    from: image, seed: day.seed ^ Self.stableSeed(photo.id)
                ) {
                    newBackdrops.append(backdrop)
                }
            }
        }
        actors = newActors
        backdrops = newBackdrops
        isReady = !newActors.isEmpty
    }

    func actor(slot: Int) -> CGImage? {
        guard !actors.isEmpty, slot >= 0 else { return nil }
        return actors[slot % actors.count]
    }

    func backdrop(paletteID: Int) -> CGImage? {
        guard !backdrops.isEmpty else { return nil }
        return backdrops[paletteID % backdrops.count]
    }

    // MARK: Pipeline

    /// Actor: center-crop square → 24×24 `.pixel` render → circular knockout.
    /// (Saliency subject detection is a v2 ask; center-crop + mask reads
    /// great at arcade sizes and is deterministic.)
    private static func actorSprite(from image: CGImage, seed: UInt64) async -> CGImage? {
        let cropped = centerCropSquare(image)
        guard let grid = try? await AsciiEngine.shared.renderGrid(
            image: cropped, style: .pixel,
            grid: .fit(cols: actorGridCols), seed: seed
        ) else { return nil }
        guard let frame = AsciiEngine.draw(
            grid: grid, style: .pixel, canvas: CGSize(width: 240, height: 240)
        ) else { return nil }
        return circularKnockout(frame)
    }

    /// Backdrop: full-frame `.mosaic` — the gentlest style, so gameplay
    /// stays readable on top.
    private static func backdrop(from image: CGImage, seed: UInt64) async -> CGImage? {
        try? await AsciiEngine.shared.render(
            image: image, style: .mosaic,
            grid: .fit(cols: backdropGridCols), seed: seed
        )
    }

    private static func centerCropSquare(_ image: CGImage) -> CGImage {
        let side = min(image.width, image.height)
        let rect = CGRect(
            x: (image.width - side) / 2,
            y: (image.height - side) / 2,
            width: side, height: side
        )
        return image.cropping(to: rect) ?? image
    }

    /// Clip to a circle so actors read as game pieces, not photo rectangles.
    private static func circularKnockout(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.addEllipse(in: rect.insetBy(dx: 1, dy: 1))
        context.clip()
        context.draw(image, in: rect)
        return context.makeImage()
    }

    private static func stableSeed(_ id: String) -> UInt64 {
        var z: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in id.utf8 {
            z ^= UInt64(byte)
            z = z &* 0x1000_0000_01B3
        }
        return z
    }
}
