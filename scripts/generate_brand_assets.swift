#!/usr/bin/env swift
// generate_brand_assets.swift — deterministic tvOS brand assets for the Couch Suite.
//
// Renders each app's "App Icon & Top Shelf Image" brand asset (layered parallax
// icon stacks, Top Shelf banners) plus a Launch Image into
// <app>/Assets.xcassets. Pure CoreGraphics; run on macOS:
//
//   swift scripts/generate_brand_assets.swift            # all five apps
//   swift scripts/generate_brand_assets.swift nine       # one app
//
// Art direction ("pixels under glass"): Back = deep color field, Middle = faint
// pixel grid, Front = a chunky pixel glyph in the app's in-app accent color.
// Glyphs are the string maps below — '#' accent, '+' secondary, '.' empty.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct RGB {
    let r: CGFloat, g: CGFloat, b: CGFloat
    var cg: CGColor { CGColor(red: r, green: g, blue: b, alpha: 1) }
    func alpha(_ a: CGFloat) -> CGColor { CGColor(red: r, green: g, blue: b, alpha: a) }
}

struct AppSpec {
    let folder: String
    let backTop: RGB    // gradient start (top)
    let backBottom: RGB // gradient end (bottom)
    let grid: RGB       // middle-layer pixel grid
    let accent: RGB     // glyph '#'
    let secondary: RGB  // glyph '+'
    // Apps that also ship an iOS build get a flat square AppIcon.appiconset
    // (single-size 1024, opaque RGB — the App Store rejects alpha).
    var iosIcon: Bool = false
    // Apps that also ship a macOS build get a margined, rounded-rect
    // AppIcon-macOS.appiconset (PRD-4 §1): the mac idiom expects the icon to
    // carry its own HIG margin + rounded shape (transparency is fine here,
    // unlike iOS).
    var macIcon: Bool = false
    let glyph: [String]
}

let specs: [AppSpec] = [
    // Rabbit Ears — TV set with antennae, phosphor green on green-black.
    AppSpec(
        folder: "rabbit-ears",
        backTop: RGB(r: 0.010, g: 0.030, b: 0.016), backBottom: RGB(r: 0.016, g: 0.078, b: 0.039),
        grid: RGB(r: 0.24, g: 0.94, b: 0.42),
        accent: RGB(r: 0.24, g: 0.94, b: 0.42), secondary: RGB(r: 0.08, g: 0.30, b: 0.14),
        glyph: [
            "..#.........#..",
            "...#.......#...",
            "....#.....#....",
            ".....#...#.....",
            "......#.#......",
            "..###########..",
            "..#+++++++++#..",
            "..#+++++++++#..",
            "..#+++++++++#..",
            "..#+++++++++#..",
            "..###########..",
        ]),
    // Darkroom — a picross grid mid-development, signal red under safelight.
    AppSpec(
        folder: "darkroom",
        backTop: RGB(r: 0.040, g: 0.014, b: 0.020), backBottom: RGB(r: 0.100, g: 0.026, b: 0.045),
        grid: RGB(r: 0.84, g: 0.22, b: 0.28),
        accent: RGB(r: 0.84, g: 0.22, b: 0.28), secondary: RGB(r: 0.26, g: 0.08, b: 0.11),
        glyph: [
            "#+#+#+#+#",
            "+#+#..#.+",
            "#.###.##+",
            "+####.#.#",
            "#.###..#+",
            "+..###..#",
            "#+.+#+.+#",
            "+#+#+#+#+",
        ]),
    // Nine — the 3×3 flick rose, lilac with a coral center.
    AppSpec(
        folder: "nine",
        backTop: RGB(r: 0.030, g: 0.030, b: 0.090), backBottom: RGB(r: 0.080, g: 0.070, b: 0.180),
        grid: RGB(r: 0.76, g: 0.70, b: 0.94),
        accent: RGB(r: 0.76, g: 0.70, b: 0.94), secondary: RGB(r: 1.0, g: 0.45, b: 0.38),
        iosIcon: true,
        macIcon: true,
        glyph: [
            "##...##...##",
            "##...##...##",
            "............",
            "............",
            "##...++...##",
            "##...++...##",
            "............",
            "............",
            "##...##...##",
            "##...##...##",
        ]),
    // Blockhead — four swipe-direction arrows around the podium dot, stage gold.
    AppSpec(
        folder: "blockhead",
        backTop: RGB(r: 0.040, g: 0.050, b: 0.110), backBottom: RGB(r: 0.100, g: 0.150, b: 0.300),
        grid: RGB(r: 1.0, g: 0.72, b: 0.25),
        accent: RGB(r: 1.0, g: 0.72, b: 0.25), secondary: RGB(r: 0.55, g: 0.65, b: 0.95),
        glyph: [
            "......#......",
            ".....###.....",
            "....#####....",
            ".............",
            "..#.......#..",
            ".##...+...##.",
            "..#.......#..",
            ".............",
            "....#####....",
            ".....###.....",
            "......#......",
        ]),
    // Cartridge — a game cart with a label window, arcade mint.
    AppSpec(
        folder: "cartridge",
        backTop: RGB(r: 0.012, g: 0.045, b: 0.042), backBottom: RGB(r: 0.030, g: 0.110, b: 0.100),
        grid: RGB(r: 0.30, g: 0.90, b: 0.75),
        accent: RGB(r: 0.30, g: 0.90, b: 0.75), secondary: RGB(r: 0.08, g: 0.30, b: 0.26),
        glyph: [
            ".###########.",
            ".###########.",
            ".##+++++++##.",
            ".##+++++++##.",
            ".##+++++++##.",
            ".##+++++++##.",
            ".###########.",
            "..#########..",
            "..#########..",
        ]),
]

// MARK: - Rendering

func context(w: Int, h: Int) -> CGContext {
    CGContext(
        data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func writePNG(_ ctx: CGContext, to url: URL) {
    try! FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let img = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("PNG write failed: \(url.path)") }
}

/// Back layer: vertical gradient, fully opaque (Apple requires an opaque bottom layer).
func renderBack(_ s: AppSpec, w: Int, h: Int) -> CGContext {
    let ctx = context(w: w, h: h)
    let colors = [s.backTop.cg, s.backBottom.cg] as CFArray
    let grad = CGGradient(colorsSpace: ctx.colorSpace, colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(
        grad, start: CGPoint(x: 0, y: CGFloat(h)), end: CGPoint(x: 0, y: 0), options: [])
    return ctx
}

/// Middle layer: faint pixel grid of small squares, transparent elsewhere.
func renderMiddle(_ s: AppSpec, w: Int, h: Int) -> CGContext {
    let ctx = context(w: w, h: h)
    let cell = max(8, min(w, h) / 24)          // grid pitch scales with asset size
    let dot = max(1, cell / 8)                 // small square at each grid point
    ctx.setFillColor(s.grid.alpha(0.10))
    var y = cell / 2
    while y < h {
        var x = cell / 2
        while x < w {
            ctx.fill(CGRect(x: x, y: y, width: dot, height: dot))
            x += cell
        }
        y += cell
    }
    return ctx
}

/// Front layer: the glyph map, centered, integer pixel size for crisp edges.
func renderFront(_ s: AppSpec, w: Int, h: Int, coverage: CGFloat = 0.62) -> CGContext {
    let ctx = context(w: w, h: h)
    drawGlyph(s, into: ctx, w: w, h: h, coverage: coverage, dim: 1.0)
    return ctx
}

func drawGlyph(_ s: AppSpec, into ctx: CGContext, w: Int, h: Int, coverage: CGFloat, dim: CGFloat) {
    let rows = s.glyph.count
    let cols = s.glyph.map(\.count).max()!
    let px = max(1, Int(min(CGFloat(w) / CGFloat(cols), CGFloat(h) / CGFloat(rows)) * coverage))
    let x0 = (w - cols * px) / 2
    let y0 = (h - rows * px) / 2
    for (r, row) in s.glyph.enumerated() {
        for (c, ch) in row.enumerated() {
            let color: RGB
            switch ch {
            case "#": color = s.accent
            case "+": color = s.secondary
            default: continue
            }
            ctx.setFillColor(color.alpha(dim))
            // Flip r: CoreGraphics origin is bottom-left; glyph maps read top-down.
            ctx.fill(CGRect(
                x: x0 + c * px, y: y0 + (rows - 1 - r) * px, width: px, height: px))
        }
    }
}

/// Flattened composition (Top Shelf, Launch): back + grid + glyph in one opaque PNG.
func renderFlat(_ s: AppSpec, w: Int, h: Int, coverage: CGFloat, glyphDim: CGFloat = 1.0) -> CGContext {
    let ctx = renderBack(s, w: w, h: h)
    let cell = max(8, min(w, h) / 24)
    let dot = max(1, cell / 8)
    ctx.setFillColor(s.grid.alpha(0.08))
    var y = cell / 2
    while y < h {
        var x = cell / 2
        while x < w {
            ctx.fill(CGRect(x: x, y: y, width: dot, height: dot))
            x += cell
        }
        y += cell
    }
    drawGlyph(s, into: ctx, w: w, h: h, coverage: coverage, dim: glyphDim)
    return ctx
}

// MARK: - Asset catalog plumbing

let info = "\"info\" : { \"author\" : \"xcode\", \"version\" : 1 }"

func write(_ text: String, _ url: URL) {
    try! FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! text.data(using: .utf8)!.write(to: url)
}

/// One parallax layer folder: Name.imagestacklayer/Content.imageset/<pngs>
func emitLayer(
    _ s: AppSpec, name: String, stack: URL, w: Int, h: Int, scales: [Int],
    render: (AppSpec, Int, Int) -> CGContext
) {
    let layerDir = stack.appendingPathComponent("\(name).imagestacklayer")
    write("{ \(info) }", layerDir.appendingPathComponent("Contents.json"))
    let setDir = layerDir.appendingPathComponent("Content.imageset")
    var entries: [String] = []
    for scale in scales {
        let file = scale == 1 ? "\(name.lowercased()).png" : "\(name.lowercased())@\(scale)x.png"
        entries.append(
            "{ \"filename\" : \"\(file)\", \"idiom\" : \"tv\", \"scale\" : \"\(scale)x\" }")
        writePNG(render(s, w * scale, h * scale), to: setDir.appendingPathComponent(file))
    }
    write(
        "{ \"images\" : [ \(entries.joined(separator: ", ")) ], \(info) }",
        setDir.appendingPathComponent("Contents.json"))
}

func emitStack(_ s: AppSpec, name: String, brand: URL, w: Int, h: Int, scales: [Int]) {
    let stack = brand.appendingPathComponent("\(name).imagestack")
    let layers = ["Front", "Middle", "Back"]
    write(
        "{ \"layers\" : [ "
            + layers.map { "{ \"filename\" : \"\($0).imagestacklayer\" }" }.joined(separator: ", ")
            + " ], \(info) }",
        stack.appendingPathComponent("Contents.json"))
    emitLayer(s, name: "Front", stack: stack, w: w, h: h, scales: scales) {
        renderFront($0, w: $1, h: $2)
    }
    emitLayer(s, name: "Middle", stack: stack, w: w, h: h, scales: scales) {
        renderMiddle($0, w: $1, h: $2)
    }
    emitLayer(s, name: "Back", stack: stack, w: w, h: h, scales: scales) {
        renderBack($0, w: $1, h: $2)
    }
}

func emitImageset(_ s: AppSpec, name: String, brand: URL, w: Int, h: Int, coverage: CGFloat) {
    let setDir = brand.appendingPathComponent("\(name).imageset")
    var entries: [String] = []
    for scale in [1, 2] {
        let file = scale == 1 ? "shelf.png" : "shelf@\(scale)x.png"
        entries.append(
            "{ \"filename\" : \"\(file)\", \"idiom\" : \"tv\", \"scale\" : \"\(scale)x\" }")
        writePNG(
            renderFlat(s, w: w * scale, h: h * scale, coverage: coverage),
            to: setDir.appendingPathComponent(file))
    }
    write(
        "{ \"images\" : [ \(entries.joined(separator: ", ")) ], \(info) }",
        setDir.appendingPathComponent("Contents.json"))
}

func emitLaunchImage(_ s: AppSpec, catalog: URL) {
    let dir = catalog.appendingPathComponent("Launch Image.launchimage")
    var entries: [String] = []
    for scale in [1, 2] {
        let file = scale == 1 ? "launch.png" : "launch@\(scale)x.png"
        entries.append("""
            { "extent" : "full-screen", "filename" : "\(file)", "idiom" : "tv", \
            "minimum-system-version" : "11.0", "orientation" : "landscape", \
            "scale" : "\(scale)x" }
            """)
        // Launch is deliberately quiet: dark field, dim glyph — apps open into black rooms.
        writePNG(
            renderFlat(s, w: 1920 * scale, h: 1080 * scale, coverage: 0.28, glyphDim: 0.5),
            to: dir.appendingPathComponent(file))
    }
    write(
        "{ \"images\" : [ \(entries.joined(separator: ", ")) ], \(info) }",
        dir.appendingPathComponent("Contents.json"))
}

/// iOS app icon: the flat composition (back + grid + glyph) in an OPAQUE
/// bitmap — the App Store rejects icons that carry an alpha channel.
func renderIOSIcon(_ s: AppSpec, size: Int) -> CGContext {
    let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let colors = [s.backTop.cg, s.backBottom.cg] as CFArray
    let grad = CGGradient(colorsSpace: ctx.colorSpace, colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(
        grad, start: CGPoint(x: 0, y: CGFloat(size)), end: CGPoint(x: 0, y: 0), options: [])
    let cell = max(8, size / 24)
    let dot = max(1, cell / 8)
    ctx.setFillColor(s.grid.alpha(0.08))
    var y = cell / 2
    while y < size {
        var x = cell / 2
        while x < size {
            ctx.fill(CGRect(x: x, y: y, width: dot, height: dot))
            x += cell
        }
        y += cell
    }
    drawGlyph(s, into: ctx, w: size, h: size, coverage: 0.66, dim: 1.0)
    return ctx
}

/// Single-size icon set: Xcode derives every device size from the 1024.
func emitIOSAppIcon(_ s: AppSpec, catalog: URL) {
    let dir = catalog.appendingPathComponent("AppIcon.appiconset")
    writePNG(renderIOSIcon(s, size: 1024), to: dir.appendingPathComponent("AppIcon-1024.png"))
    write(
        "{ \"images\" : [ { \"filename\" : \"AppIcon-1024.png\", \"idiom\" : \"universal\", "
            + "\"platform\" : \"ios\", \"size\" : \"1024x1024\" } ], \(info) }",
        dir.appendingPathComponent("Contents.json"))
}

/// macOS app icon: the flat composition clipped to a rounded-rect with a HIG
/// margin (PRD-4 §1). Transparency IS expected here (the margin + corners),
/// unlike the opaque iOS icon.
func renderMacIcon(_ s: AppSpec, size: Int) -> CGContext {
    let ctx = context(w: size, h: size)          // premultipliedLast: transparent
    let fsize = CGFloat(size)
    let margin = fsize * 0.10                     // ~10% HIG margin all around
    let inner = CGRect(x: margin, y: margin, width: fsize - 2 * margin, height: fsize - 2 * margin)
    let radius = inner.width * 0.2237             // the macOS continuous-corner ratio
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: inner, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()
    let colors = [s.backTop.cg, s.backBottom.cg] as CFArray
    let grad = CGGradient(colorsSpace: ctx.colorSpace!, colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(
        grad, start: CGPoint(x: 0, y: fsize), end: CGPoint(x: 0, y: 0), options: [])
    let cell = max(8, size / 24)
    let dot = max(1, cell / 8)
    ctx.setFillColor(s.grid.alpha(0.08))
    var y = cell / 2
    while y < size {
        var x = cell / 2
        while x < size {
            ctx.fill(CGRect(x: x, y: y, width: dot, height: dot))
            x += cell
        }
        y += cell
    }
    ctx.restoreGState()
    // Glyph centered over the whole canvas; the reduced coverage keeps it
    // inside the margin.
    drawGlyph(s, into: ctx, w: size, h: size, coverage: 0.50, dim: 1.0)
    return ctx
}

/// The full mac idiom icon set (16…512 at 1x/2x); Xcode assembles the .icns.
func emitMacAppIcon(_ s: AppSpec, catalog: URL) {
    let dir = catalog.appendingPathComponent("AppIcon-macOS.appiconset")
    let sizes: [(pt: Int, scale: Int)] = [
        (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
        (256, 1), (256, 2), (512, 1), (512, 2),
    ]
    var entries: [String] = []
    for item in sizes {
        let file = "icon_\(item.pt)x\(item.pt)@\(item.scale)x.png"
        entries.append(
            "{ \"size\" : \"\(item.pt)x\(item.pt)\", \"idiom\" : \"mac\", "
                + "\"filename\" : \"\(file)\", \"scale\" : \"\(item.scale)x\" }")
        writePNG(renderMacIcon(s, size: item.pt * item.scale), to: dir.appendingPathComponent(file))
    }
    write(
        "{ \"images\" : [ \(entries.joined(separator: ", ")) ], \(info) }",
        dir.appendingPathComponent("Contents.json"))
}

// MARK: - Main

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0])
    .resolvingSymlinksInPath().deletingLastPathComponent()
let rootDir = scriptDir.deletingLastPathComponent()
let requested = Array(CommandLine.arguments.dropFirst())
let selected = requested.isEmpty ? specs : specs.filter { requested.contains($0.folder) }
guard !selected.isEmpty else {
    FileHandle.standardError.write("No matching app. Folders: \(specs.map(\.folder))\n".data(using: .utf8)!)
    exit(1)
}

for s in selected {
    let catalog = rootDir.appendingPathComponent("\(s.folder)/Assets.xcassets")
    try? FileManager.default.removeItem(at: catalog)
    write("{ \(info) }", catalog.appendingPathComponent("Contents.json"))

    let brand = catalog.appendingPathComponent("App Icon & Top Shelf Image.brandassets")
    write("""
        { "assets" : [ \
        { "filename" : "App Icon - App Store.imagestack", "idiom" : "tv", "role" : "primary-app-icon", "size" : "1280x768" }, \
        { "filename" : "App Icon.imagestack", "idiom" : "tv", "role" : "primary-app-icon", "size" : "400x240" }, \
        { "filename" : "Top Shelf Image Wide.imageset", "idiom" : "tv", "role" : "top-shelf-image-wide", "size" : "2320x720" }, \
        { "filename" : "Top Shelf Image.imageset", "idiom" : "tv", "role" : "top-shelf-image", "size" : "1920x720" } \
        ], \(info) }
        """, brand.appendingPathComponent("Contents.json"))

    emitStack(s, name: "App Icon", brand: brand, w: 400, h: 240, scales: [1, 2])
    emitStack(s, name: "App Icon - App Store", brand: brand, w: 1280, h: 768, scales: [1])
    emitImageset(s, name: "Top Shelf Image", brand: brand, w: 1920, h: 720, coverage: 0.55)
    emitImageset(s, name: "Top Shelf Image Wide", brand: brand, w: 2320, h: 720, coverage: 0.55)
    emitLaunchImage(s, catalog: catalog)
    if s.iosIcon { emitIOSAppIcon(s, catalog: catalog) }
    if s.macIcon { emitMacAppIcon(s, catalog: catalog) }
    print("✓ \(s.folder)/Assets.xcassets")
}
