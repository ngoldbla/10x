# CouchKit — Public API Surface

**Contract for the five app threads.** Build against these signatures plus the sources.
`import CouchKit` re-exports `CouchCore`, so one import gives you everything. On
non-Apple platforms only `CouchCore` exists (that is where all algorithms live, and
where you can run logic tests).

```swift
// In your app's Package/project:
.package(path: "../couchkit")   // products: CouchKit (includes CouchCore)
```

Conventions used throughout:

- **Coordinates:** `+x` right, `+y` **up** (GCMicroGamepad convention). Angles in
  degrees, counterclockwise from `+x`, `[0, 360)`.
- **Determinism:** every function that takes a `seed` is a pure function of its
  inputs — same input + seed ⇒ byte-identical output.
- **Dark-first:** no CouchKit component draws an opaque background.

---

## CouchCore — pure algorithms (Foundation only)

### Pixels & colors

```swift
public struct RGB: Hashable, Sendable, Codable {
    public var r, g, b: UInt8
    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8)
    public static let black: RGB
    public static let white: RGB
    public var luminance: Double                          // Rec.709, [0,1]
    public func scaled(by factor: Double) -> RGB
    public func mixed(with other: RGB, t: Double) -> RGB
    public func distanceSquared(to other: RGB) -> Int
}

public struct PixelBuffer: Sendable, Equatable {          // RGBA8, row-major
    public let width: Int
    public let height: Int
    public var rgba: [UInt8]                              // width*height*4
    public init(width: Int, height: Int, rgba: [UInt8])
    public init(width: Int, height: Int, fill: RGB = .black)
    public func pixel(x: Int, y: Int) -> RGB
    public mutating func setPixel(x: Int, y: Int, _ color: RGB)
}
```

### Seeded randomness

```swift
public struct SplitMix64: RandomNumberGenerator, Sendable {
    public init(seed: UInt64)
    public mutating func next() -> UInt64
    public mutating func nextDouble() -> Double                        // [0,1)
    public mutating func nextDouble(in range: ClosedRange<Double>) -> Double
    public mutating func nextInt(below bound: Int) -> Int
}

public enum CouchHash {
    public static func noise(_ x: Int, _ y: Int, seed: UInt64) -> Double  // [0,1)
}
```

### AsciiKit core — the render pipeline

```swift
public enum AsciiStyle: String, CaseIterable, Sendable, Codable, Hashable {
    case terminal, phosphor, pixel, inkline, mosaic       // exactly five
    public var usesGlyphs: Bool                           // false for pixel/mosaic
    public var preferredCellAspect: Double                // 0.5 glyphs, 1.0 tiles
}

public struct GridSpec: Sendable, Equatable {
    public var cols: Int
    public var cellAspect: Double?                        // nil = style default
    public init(cols: Int, cellAspect: Double? = nil)
    public static func fit(cols: Int, cellAspect: Double? = nil) -> GridSpec
    public func rows(imageWidth: Int, imageHeight: Int, style: AsciiStyle) -> Int
}

public struct Cell: Hashable, Sendable, Codable {
    public var symbol: String                             // single grapheme; " " for tiles
    public var foreground: RGB
    public var background: RGB
    public init(symbol: String, foreground: RGB, background: RGB)
}

public struct CellGrid: Sendable, Equatable, Codable {
    public let cols: Int
    public let rows: Int
    public var cells: [Cell]                              // row-major, cols*rows
    public init(cols: Int, rows: Int, cells: [Cell])
    public subscript(x: Int, y: Int) -> Cell { get set }
}

/// Top-level entry: full pipeline, deterministic.
public enum AsciiRenderer {
    public static let densityRamp: [String]               // " .:-=+*#%@"
    public static func render(
        _ buffer: PixelBuffer,
        style: AsciiStyle,
        grid: GridSpec = .fit(cols: 120),
        seed: UInt64 = 0
    ) -> CellGrid
}

/// Individual stages, exposed for Darkroom's puzzle compiler.
public struct CellField: Sendable, Equatable {
    public let cols: Int; public let rows: Int
    public var colors: [RGB]; public var luminance: [Double]
}
public struct EdgeField: Sendable, Equatable {
    public let cols: Int; public let rows: Int
    public var magnitude: [Double]                        // normalized [0,1]
    public var angle: [Double]                            // radians, atan2(gy,gx)
}
public enum AsciiPipeline {
    public static func downsample(_ buffer: PixelBuffer, cols: Int, rows: Int) -> CellField
    public static func edgeField(of field: CellField) -> EdgeField
    public static func quantize(_ colors: [RGB], paletteSize k: Int, seed: UInt64,
                                iterations: Int = 8) -> (palette: [RGB], assignment: [Int])
    public static func nearest(in palette: [RGB], to color: RGB) -> Int
    public static let chunky16: [RGB]                     // .pixel's fixed palette
}
```

### Drift (deterministic Ken Burns)

```swift
public struct DriftState: Sendable, Equatable {
    public var offsetX, offsetY: Double                   // fractions of view size
    public var zoom: Double
    public static let identity: DriftState
}

public struct DriftPath: Sendable, Equatable {
    public let seed: UInt64
    public let maxOffset: Double                          // default 0.045
    public let zoomRange: ClosedRange<Double>             // default 1.03...1.12
    public let period: TimeInterval                       // default 48
    public init(seed: UInt64, maxOffset: Double = 0.045,
                zoomRange: ClosedRange<Double> = 1.03...1.12, period: TimeInterval = 48)
    public func state(at t: TimeInterval) -> DriftState   // pure function of time
}
```

### RemoteKit core — flick math

```swift
public enum Direction4: String, CaseIterable, Sendable, Codable, Hashable {
    case right, up, left, down
}
public enum Direction8OrCenter: String, CaseIterable, Sendable, Codable, Hashable {
    case center, right, upRight, up, upLeft, left, downLeft, down, downRight
}
public enum RemoteCapability: String, Sendable, Codable, Hashable {
    case fourWay, eightWay
}
public enum FlickClassification<Direction: Sendable & Hashable>: Sendable, Hashable {
    case direction(Direction)
    case ambiguous          // inside the forgiveness cone — ignore, never misfire
    case rest               // resting/repositioning thumb — rejected
}

public struct FlickThresholds: Sendable, Equatable {
    public var minDistance: Double          // default 0.25 (pad is ~2.0 across)
    public var minVelocity: Double          // default 1.2 units/s
    public var tapMaxDuration: TimeInterval // default 0.30 s
    public var ambiguityCone: Double        // default 8°
    public init(minDistance: Double = 0.25, minVelocity: Double = 1.2,
                tapMaxDuration: TimeInterval = 0.30, ambiguityCone: Double = 8)
    public static let standard: FlickThresholds
}

public enum FlickClassifier {
    public static func angleDegrees(dx: Double, dy: Double) -> Double
    // Geometry only:
    public static func direction4(dx: Double, dy: Double, cone: Double = 8)
        -> FlickClassification<Direction4>
    public static func direction8(dx: Double, dy: Double, cone: Double = 8)
        -> FlickClassification<Direction8OrCenter>
    // Full gate (rest-touch rejection + tap detection + geometry):
    public static func classify4(dx: Double, dy: Double, duration: TimeInterval,
                                 thresholds: FlickThresholds = .standard)
        -> FlickClassification<Direction4>
    public static func classify8(dx: Double, dy: Double, duration: TimeInterval,
                                 thresholds: FlickThresholds = .standard)
        -> FlickClassification<Direction8OrCenter>       // quick tap ⇒ .center
}

public struct SectorHysteresis: Sendable, Equatable {     // sticky continuous sectors
    public init(sectorCount: Int, marginDegrees: Double = 6)
    public private(set) var current: Int?
    public mutating func classify(angleDegrees: Double) -> Int
    public mutating func reset()
}

public struct CellStepAccumulator: Sendable, Equatable {  // drag-fill streams (Darkroom)
    public init(cellSize: Double = 0.28)
    public mutating func accumulate(dx: Double, dy: Double) -> (x: Int, y: Int)
    public mutating func reset()
}
```

### Sequencing

```swift
public struct SequencePlanner: Sendable {   // no-repeat shuffle, sliding window
    public let count: Int
    public let window: Int                  // clamped to count-1
    public init(count: Int, window: Int = 3, seed: UInt64)
    public mutating func next() -> Int      // never repeats within `window` draws
}
```

### DemoArt — procedural placeholder photos

```swift
public struct DemoArtRecipe: Sendable, Identifiable, Equatable, Hashable {
    public enum Kind: String, Sendable, Codable, Hashable { case gradient, plasma, landscape }
    public let id: String                   // "dunes", "neon-tide", …
    public let title: String                // "Demo · Dunes"
    public let displayDate: Date            // plausible fake capture date
    public let locationLabel: String        // "Mojave"
    public let kind: Kind
    public let seed: UInt64
}

public enum DemoArt {
    public static let recipes: [DemoArtRecipe]            // 9 shipped
    public static func recipe(id: String) -> DemoArtRecipe?
    public static func render(_ recipe: DemoArtRecipe,
                              width: Int = 640, height: Int = 360) -> PixelBuffer
}
```

### Accent math

```swift
public struct HSV: Sendable, Equatable { public var h, s, v: Double }

public enum AccentMath {
    public static func rgbToHSV(_ c: RGB) -> HSV
    public static func hsvToRGB(_ hsv: HSV) -> RGB
    public static func dominantHue(in buffer: PixelBuffer, stride: Int = 5) -> Double?
    public static func accent(for buffer: PixelBuffer) -> RGB   // clamped S/V, safe on glass
}
```

### Store core

```swift
public enum CouchJSON {                                    // sorted keys, ISO-8601 dates
    public static func encode<T: Encodable>(_ value: T, pretty: Bool = false) throws -> Data
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T
}

public struct WriteDebouncer: Sendable, Equatable {        // pure, time-injected
    public let interval: TimeInterval                      // quiet period
    public let maxLatency: TimeInterval                    // starvation backstop
    public var isDirty: Bool { get }
    public init(interval: TimeInterval = 0.6, maxLatency: TimeInterval = 3.0)
    public mutating func recordChange(at now: Date)
    public mutating func shouldFlush(at now: Date) -> Bool // marks clean when true
}

public enum CouchKeyspace {
    public static func namespacedKey(_ key: String, profile: String = "default") -> String
    public static func filename(forKey key: String, profile: String = "default") -> String
    public static func sanitize(_ component: String) -> String
}
```

---

## CouchKit — SwiftUI layer (tvOS; `#if canImport(SwiftUI)`)

### CouchGlass — the Liquid Glass shim

The **only** place in the suite that touches Liquid Glass API. tvOS 26 gets
`.glassEffect`; earlier systems get `.ultraThinMaterial` + hairline stroke.
*If Liquid Glass API names differ in your SDK, fix them in `CouchGlass.swift` only.*

```swift
extension View {
    public func couchGlass(in shape: some Shape) -> some View
    public func couchGlass() -> some View                       // Capsule
    public func couchGlassInteractive(in shape: some Shape) -> some View
}

public struct CouchGlassContainer<Content: View>: View {        // merges adjacent glass
    public init(spacing: CGFloat = 24, @ViewBuilder content: () -> Content)
}
```

### Typography, palette, motion

```swift
public enum CouchTypography {                 // SF Rounded, sized for 3 m
    public static let display: Font           // 96 heavy
    public static let title: Font             // 64 bold
    public static let body: Font              // 38 medium
    public static let caption: Font           // 29 semibold
}
extension View { public func couchText(_ font: Font) -> some View }

public enum CouchPalette {
    public static let void: Color             // true black
    public static let ink: Color
    public static let paper: Color
    public static let fallbackAccent: Color
}
extension Color { public init(_ rgb: RGB) }

public enum AccentDerivation {
    public static func accent(from buffer: PixelBuffer) -> Color
    public static func accent(from grid: CellGrid) -> Color
}

extension Animation {
    public static let couchFast: Animation     // spring ~180 ms — focus/chrome
    public static let couchAmbient: Animation  // spring 2.4 s — drift/crossfade
}
```

### Chrome components

```swift
@MainActor @Observable
public final class ChromeVisibility {          // one per screen; RemoteKit pokes it
    public private(set) var isVisible: Bool
    public private(set) var lastInteraction: Date
    public var idleDelay: TimeInterval         // default 3 s
    public init(idleDelay: TimeInterval = 3)
    public func touch()                        // reveal + restart recede timer
    public func hide()
}

public struct GlassAction: Identifiable {
    public init(id: String? = nil, symbol: String, label: String,
                action: @escaping @MainActor () -> Void)
}

public struct GlassPill: View {                // 1–5 actions, floats near bottom
    public init(actions: [GlassAction], chrome: ChromeVisibility)
}

public struct GlassChip: View {                // "June 2019 · Lake Tahoe"
    public init(_ text: String, systemImage: String? = nil)
}

public struct GlassSheet<Content: View>: View {  // trailing sheet; Back dismisses
    public init(isPresented: Binding<Bool>, @ViewBuilder content: () -> Content)
}

public struct GlassRing: View {                // progress/timer ring
    public init(progress: Double, lineWidth: CGFloat = 10)
}

public struct FocusHalo: ViewModifier { public init() }   // scale 1.03 + specular + shadow
extension View { public func focusHalo() -> some View }

public struct IdleAttract: ViewModifier {
    public init(chrome: ChromeVisibility, drift: DriftPath = DriftPath(seed: 0xCA1F))
}
extension View {
    public func idleAttract(chrome: ChromeVisibility,
                            drift: DriftPath = DriftPath(seed: 0xCA1F)) -> some View
}
```

### RemoteKit — gesture grammar

```swift
public enum CouchGesture: Sendable, Equatable {
    case swipe(Direction4)          // discrete flick (system move command)
    case flick(Direction8OrCenter)  // 3×3 rose; needs eightWay: true
    case click                      // clickpad press
    case holdBegan, holdEnded       // long-press on clickpad
    case playPause
    case playPauseLongPress         // suite-wide prefs sheet (8-way reader only)
    case back                       // only when interceptsBack: true
}

public enum RemoteKit {
    @MainActor public static var capability: RemoteCapability
}

extension View {
    /// Makes the view focusable itself — do not stack your own `.focusable()`.
    public func couchRemote(
        chrome: ChromeVisibility? = nil,     // poked on every gesture
        eightWay: Bool = false,              // run the analog flick reader
        interceptsBack: Bool = false,        // leave false at app root
        onGesture: @escaping @MainActor (CouchGesture) -> Void
    ) -> some View
}
```

The 8-way reader samples the microGamepad's absolute dpad values during a touch
and classifies the released stroke via `FlickClassifier.classify8`. Ambiguous
and rest strokes are dropped, never misfired. Without analog data it fails soft:
you still receive `.swipe` and `capability` reports `.fourWay` (Nine must then
show its click-through rose).

### AsciiEngine

```swift
public enum AsciiEngineError: Error, Sendable { case adapterFailed, emptyImage }

public actor AsciiEngine {
    public static let shared: AsciiEngine
    public init()
    public static let maxCanvas: CGSize                    // 1920×1080 cap (see note)

    public func render(image: CGImage, style: AsciiStyle,
                       grid: GridSpec = .fit(cols: 160), seed: UInt64 = 0) throws -> CGImage
    public func renderGrid(image: CGImage, style: AsciiStyle,
                           grid: GridSpec = .fit(cols: 160), seed: UInt64 = 0) throws -> CellGrid
    public func renderDemo(recipe: DemoArtRecipe, style: AsciiStyle,
                           grid: GridSpec = .fit(cols: 160), seed: UInt64? = nil) throws -> CGImage

    // Adapters (nonisolated):
    public static func pixelBuffer(from image: CGImage, maxDimension: Int = 960) -> PixelBuffer?
    public static func cgImage(from buffer: PixelBuffer) -> CGImage?
    public static func draw(grid: CellGrid, style: AsciiStyle, canvas: CGSize? = nil) -> CGImage?
}

public struct AsciiArtView: View {             // full-bleed display + slow drift
    public init(image: CGImage?, style: AsciiStyle, drift: DriftPath? = nil,
                grid: GridSpec = .fit(cols: 160), seed: UInt64 = 0)
}
```

*Canvas note:* rendering is capped at 1920×1080 — the tvOS compositor upscales to
4K, cell art carries no detail beyond its grid, and glyph rasterization at
3840×2160 quadruples CPU time for nothing visible at three meters.

### PhotoKitPlus

```swift
public enum CouchPhotoError: Error, Sendable { case assetUnavailable, loadFailed }

public struct CuratedPhoto: Identifiable, Sendable, Hashable {
    public enum Source: Sendable, Hashable {
        case demo(recipeID: String)
        case asset(localIdentifier: String)
    }
    public let id: String
    public let displayDate: Date
    public let locationLabel: String?          // demo photos carry fake labels
    public let source: Source
    public func load(maxDimension: Int = 1920) async throws -> CGImage
}

public enum PhotoAccess {
    public static var isAuthorized: Bool
    public static var canPrompt: Bool
    @discardableResult public static func request() async -> Bool
}

/// Every query falls back to DemoArt when unauthorized or empty — apps always work.
public enum CouchPhotos {
    public static func onThisDay(limit: Int = 24) async -> [CuratedPhoto]
    public static func randomMemorable(limit: Int = 24, seed: UInt64 = 0) async -> [CuratedPhoto]
    public static func recentHighlights(limit: Int = 24) async -> [CuratedPhoto]
    public static func album(named name: String, limit: Int = 60) async -> [CuratedPhoto]
    public static func demoPhotos(limit: Int = 24, seed: UInt64 = 0) -> [CuratedPhoto]
}

public struct PhotoPermissionView: View {      // glass, one sentence, one button
    public init(onResolved: @escaping @MainActor (Bool) -> Void = { _ in })
}
```

### CouchStore

```swift
@propertyWrapper
public final class CouchStored<Value: Codable & Sendable> {
    public init(wrappedValue defaultValue: Value,
                _ key: String,
                profile: String = "default",     // tvOS profile namespace
                cloudSynced: Bool = false,       // mirror to NSUbiquitousKeyValueStore
                debounce: TimeInterval = 0.6)
    public var wrappedValue: Value { get set }   // thread-safe, debounced writes
    public var projectedValue: CouchStored<Value> { get }
    public func flushNow() throws                // synchronous write, bypass debounce
}
```

Storage lives in `Application Support/CouchKit/`, one JSON file per key
(`CouchKeyspace.filename`). `cloudSynced` values are recovered from iCloud KVS
when local storage was purged — use it for anything precious (streaks).

---

## Quick start (< 30 lines to the suite look)

```swift
import CouchKit

struct RootView: View {
    @State private var chrome = ChromeVisibility()
    @State private var showPrefs = false
    @State private var photo: CGImage?

    var body: some View {
        AsciiArtView(image: photo, style: .terminal, drift: DriftPath(seed: 9))
            .idleAttract(chrome: chrome)
            .overlay(alignment: .bottom) {
                GlassPill(actions: [
                    GlassAction(symbol: "sparkles", label: "Style") { /* … */ },
                    GlassAction(symbol: "gearshape", label: "Prefs") { showPrefs = true },
                ], chrome: chrome)
                .padding(.bottom, 60)
            }
            .overlay { GlassSheet(isPresented: $showPrefs) { Text("Prefs").couchText(CouchTypography.body) } }
            .couchRemote(chrome: chrome) { gesture in
                if case .playPauseLongPress = gesture { showPrefs = true }
            }
            .background(CouchPalette.void)
            .task {
                let photos = await CouchPhotos.recentHighlights(limit: 1)
                photo = try? await photos.first?.load()
            }
    }
}
```
