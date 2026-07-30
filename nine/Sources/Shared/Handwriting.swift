// Handwriting.swift — reading a digit out of Apple Pencil ink, and keeping the
// player's own glyph so the board can draw notes in their hand (PRD-31).
//
// This is the release's one new input concept, and it spends the craft
// charter's whole budget for 2.0. Two things had to be true for it to be worth
// spending:
//
//   1. **A stroke has to become a real pencil mark**, not a doodle layer. What
//      you write goes through `NineGame.togglePencil` like every other note, so
//      same-number highlight, auto-notes pruning, undo, the stats drawer's
//      count, VoiceOver's spoken value and the replay log all see it without
//      knowing ink exists. Anything less would be a drawing app wearing a
//      sudoku costume.
//   2. **Recognition has to be deterministic and testable without a device.**
//      Nine's load-bearing machinery is pure functions with frozen behaviour —
//      the golden corpus, `RoseLens`, `BoardSpeech`. A model would be neither
//      Linux-testable nor stable across OS versions, which is precisely the
//      property `GoldenCorpusTests` exists to forbid. So: $P, a point-cloud
//      matcher against authored templates, ~150 lines, no training data, and
//      the same answer on every device forever.
//
// Linux-clean, no SwiftUI, no CoreGraphics — `Sources/App` converts CGPoint at
// the boundary, the way it already does for `RoseLens`.
import Foundation

// MARK: - Ink

/// A point in whatever space the caller is using. Normalization is explicit
/// and happens once, in `normalized()`.
public struct InkPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// One handwritten mark: the strokes that made it, in order.
///
/// Stroke *order* and *direction* are recorded but never read by the matcher —
/// $P is invariant to both, which is the whole reason it was chosen over a
/// sequence matcher. People write a 5 top-bar-first and bowl-first in roughly
/// equal numbers, and a 7 left-to-right or right-to-left, and none of them are
/// wrong.
public struct InkGlyph: Equatable, Sendable {
    public var strokes: [[InkPoint]]

    public init(strokes: [[InkPoint]]) {
        self.strokes = strokes
    }

    public var pointCount: Int { strokes.reduce(0) { $0 + $1.count } }

    /// Axis-aligned bounds, or nil for empty ink.
    public var bounds: (minX: Double, minY: Double, maxX: Double, maxY: Double)? {
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        for stroke in strokes {
            for point in stroke {
                minX = Swift.min(minX, point.x); maxX = Swift.max(maxX, point.x)
                minY = Swift.min(minY, point.y); maxY = Swift.max(maxY, point.y)
            }
        }
        return minX.isFinite ? (minX, minY, maxX, maxY) : nil
    }

    /// Total path length across all strokes; the pen-up jumps between strokes
    /// are not counted.
    public var pathLength: Double {
        strokes.reduce(0) { total, stroke in
            total + zip(stroke, stroke.dropFirst()).reduce(0) { sum, pair in
                sum + hypot(pair.1.x - pair.0.x, pair.1.y - pair.0.y)
            }
        }
    }

    /// $P's normalization, with one deliberate change.
    ///
    /// Stock $P scales to a **non-uniform** unit bounding box, which is fine
    /// for gestures and fatal for digits: a `1` is a vertical line of zero
    /// width, and dividing by that width is either a crash or a cloud that
    /// looks like every other stroke. Scaling **uniformly by the larger
    /// dimension** keeps a 1 thin, keeps an 8 tall, and keeps the aspect ratio
    /// doing the classification work it is very good at here.
    ///
    /// Returns nil for ink too small to have a shape at all — a tap, a dot,
    /// the flick of a hand resting on the glass.
    public func normalized(into count: Int = DigitHand.cloudSize) -> [InkPoint]? {
        guard let bounds, pointCount >= 2 else { return nil }
        let width = bounds.maxX - bounds.minX
        let height = bounds.maxY - bounds.minY
        let extent = Swift.max(width, height)
        guard extent > 0 else { return nil }

        let resampled = resampled(into: count)
        guard resampled.count >= 2 else { return nil }

        var scaled = resampled.map {
            InkPoint(x: ($0.x - bounds.minX) / extent, y: ($0.y - bounds.minY) / extent)
        }
        let centroidX = scaled.reduce(0) { $0 + $1.x } / Double(scaled.count)
        let centroidY = scaled.reduce(0) { $0 + $1.y } / Double(scaled.count)
        for index in scaled.indices {
            scaled[index].x -= centroidX
            scaled[index].y -= centroidY
        }
        return scaled
    }

    /// `count` points spread by arc length, with each stroke's share of the
    /// points proportional to its share of the ink and a floor of two — so a
    /// 7's crossbar is not resampled out of existence by its own long diagonal.
    func resampled(into count: Int) -> [InkPoint] {
        let usable = strokes.filter { $0.count >= 2 }
        guard !usable.isEmpty else { return strokes.flatMap { $0 } }
        let lengths = usable.map { stroke in
            Swift.max(zip(stroke, stroke.dropFirst()).reduce(0) {
                $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y)
            }, 1e-9)
        }
        let total = lengths.reduce(0, +)
        var budgets = lengths.map { Swift.max(2, Int((Double(count) * $0 / total).rounded())) }
        // Spend exactly `count` points: trim from the longest stroke, which is
        // the one that can least notice losing one.
        while budgets.reduce(0, +) > count, let index = budgets.firstIndex(of: budgets.max()!),
              budgets[index] > 2 {
            budgets[index] -= 1
        }
        while budgets.reduce(0, +) < count, let index = budgets.firstIndex(of: budgets.max()!) {
            budgets[index] += 1
        }
        return zip(usable, budgets).flatMap { Self.resample($0, into: $1) }
    }

    /// Even arc-length resampling of one stroke.
    static func resample(_ stroke: [InkPoint], into count: Int) -> [InkPoint] {
        guard count >= 2, stroke.count >= 2 else { return stroke }
        let length = zip(stroke, stroke.dropFirst()).reduce(0.0) {
            $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y)
        }
        guard length > 0 else { return Array(repeating: stroke[0], count: count) }
        let interval = length / Double(count - 1)
        var output = [stroke[0]]
        var accumulated = 0.0
        var points = stroke
        var index = 1
        while index < points.count {
            let previous = points[index - 1], current = points[index]
            let segment = hypot(current.x - previous.x, current.y - previous.y)
            if accumulated + segment >= interval, segment > 0 {
                let ratio = (interval - accumulated) / segment
                let split = InkPoint(x: previous.x + ratio * (current.x - previous.x),
                                     y: previous.y + ratio * (current.y - previous.y))
                output.append(split)
                points.insert(split, at: index)
                accumulated = 0
            } else {
                accumulated += segment
            }
            index += 1
        }
        // Floating-point drift can leave the last point one short.
        while output.count < count { output.append(stroke[stroke.count - 1]) }
        return Array(output.prefix(count))
    }
}

// MARK: - Reading a digit

public enum DigitHand {

    /// Points in the matched cloud. 32 is $P's own working figure and it is
    /// also what makes the packed specimen fit KVS: 32 points is 64 bytes.
    public static let cloudSize = 32

    public struct Reading: Equatable, Sendable {
        public let digit: Int
        /// 0…1, $P's `(2 − distance) / 2`.
        public let score: Double
        /// How far clear of the runner-up, in the same units.
        ///
        /// **Reported, never thresholded, and that is a measurement rather than
        /// an oversight.** A margin bar was written first, on the reasoning that
        /// a best guess which barely beats its rival is a coin toss. Measured
        /// against 45 synthesized hands and nine deliberately degraded ones, it
        /// separates nothing: correct readings carry margins from 0.16 to 0.58
        /// and *incorrect* ones from 0.09 to 0.18, so every bar that rejects
        /// the worst wrong answer also rejects a right one.
        /// `theMarginCannotSeparateRightFromWrong` pins that overlap, because a
        /// constant nobody can defend is worse than no constant — and the next
        /// person to reach for this idea should find the number, not the idea.
        public let margin: Double
    }

    /// Below this the ink is not a digit — it is a doodle, a resting palm, or a
    /// digit written so badly nobody could read it either.
    ///
    /// **Measured, not chosen, and it is set for safety rather than at the
    /// crossover.** On the corpus in `HandwritingTests`, garbage (a dash, a
    /// box, a scribble, a cross, a circle) tops out at **0.033**; 45 ordinary
    /// hands all read correctly at **0.58** and up; the best *wrong* reading of
    /// a badly-formed hand is **0.391** — a 7 whose hook is so small it is a 1.
    ///
    /// Those last two populations **overlap**: a 3 with flat bumps reads
    /// correctly at **0.303**, below the worst wrong answer. There is no bar
    /// that keeps every right reading and drops every wrong one, so this one is
    /// placed above the wrong answers and pays for it in refused right ones. A
    /// mark that appears in a cell the player did not mean is the worst failure
    /// this feature has; a stroke that fades and has to be written again is the
    /// mildest. `testTheSafeBarAlsoRefusesSomeCorrectReadings` pins the price.
    public static let commitScore = 0.45
    /// The stricter bar for *adopting* a glyph as the player's specimen. A
    /// mark placed on a merely-good reading is recoverable — write it again to
    /// toggle it off. A specimen adopted on a merely-good reading is worn by
    /// every future note of that digit, so it takes a better one.
    public static let adoptScore = 0.60

    /// The best digit this ink could be, or nil if it is not confidently any of
    /// them. Absence is a designed answer here, not a failure: the craft
    /// charter's "honest absence over fake data" applied to input.
    public static func read(_ glyph: InkGlyph) -> Reading? {
        guard let cloud = glyph.normalized() else { return nil }
        var best = (digit: 0, score: -Double.infinity)
        var runnerUp = -Double.infinity
        for template in DigitTemplates.all {
            let distance = greedyMatch(cloud, template.cloud)
            let score = Swift.max(0, (2 - distance) / 2)
            if score > best.score {
                if best.digit != template.digit { runnerUp = Swift.max(runnerUp, best.score) }
                best = (template.digit, score)
            } else if template.digit != best.digit {
                runnerUp = Swift.max(runnerUp, score)
            }
        }
        guard best.digit != 0 else { return nil }
        return Reading(digit: best.digit,
                       score: best.score,
                       margin: best.score - Swift.max(0, runnerUp))
    }

    /// Does this reading clear the bar for placing a mark?
    public static func commits(_ reading: Reading) -> Bool { reading.score >= commitScore }

    /// …and the stricter bar for becoming the player's glyph for that digit.
    public static func adopts(_ reading: Reading) -> Bool { reading.score >= adoptScore }

    // MARK: $P

    static func greedyMatch(_ a: [InkPoint], _ b: [InkPoint]) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return .infinity }
        // ε = 0.5, so √n starting points rather than all n — $P's own
        // recommendation, and the difference between 1k and 33k distance
        // evaluations per template.
        let step = Swift.max(1, Int(Double(a.count).squareRoot().rounded(.down)))
        var best = Double.infinity
        for start in stride(from: 0, to: a.count, by: step) {
            best = Swift.min(best, cloudDistance(a, b, startingAt: start))
            best = Swift.min(best, cloudDistance(b, a, startingAt: Swift.min(start, b.count - 1)))
        }
        return best
    }

    static func cloudDistance(_ a: [InkPoint], _ b: [InkPoint], startingAt start: Int) -> Double {
        var matched = [Bool](repeating: false, count: b.count)
        var sum = 0.0
        var i = start
        var visited = 0
        repeat {
            var minimum = Double.infinity
            var index = -1
            for j in b.indices where !matched[j] {
                let distance = hypot(a[i].x - b[j].x, a[i].y - b[j].y)
                if distance < minimum { minimum = distance; index = j }
            }
            if index >= 0 { matched[index] = true } else { minimum = 0 }
            // Points nearer the start count for more, which is what makes the
            // greedy walk's early (and therefore best) matches dominate.
            let weight = 1 - Double(visited) / Double(a.count)
            sum += weight * minimum
            i = (i + 1) % a.count
            visited += 1
        } while visited < a.count
        return sum
    }
}

// MARK: - The player's own hand

/// One accepted glyph per digit — the specimen the board draws notes with.
///
/// **One glyph per digit, not one per mark.** Storing the ink of every note
/// would be per-board state, which `EXECUTING-A-PRD.md` §2 makes expensive and
/// dangerous (a new `LibraryEntry` field is erased by any older build's next
/// autosave, and field-level preservation was measured at 1515 ms and
/// reverted). A specimen is a property of the *player*: ~850 bytes for all
/// nine, its own top-level blob, KVS-synced beside the streak, and it needs no
/// schema change to a single board.
///
/// It is also the better product. Every pencil mark renders in your hand —
/// including the ones you place with the rose, on the phone, with no Pencil in
/// the room — so the board looks like one person wrote it rather than like nine
/// unrelated scrawls. Your hand is what tentative looks like; the app's
/// typeface is what committed looks like. Placed digits are never inked.
///
/// **Last confident stroke wins.** First-wins would enshrine the one bad 4 you
/// wrote while the pen skipped, with no way back short of a settings row nobody
/// should have to find. Last-wins self-heals silently, and the retroactive
/// change is invisible in practice because your two 4s look alike — which is
/// the entire premise of handwriting.
public struct HandGlyphs: Codable, Sendable, Equatable {
    /// digit (1…9) → its normalized glyph, strokes preserved.
    private var glyphs: [Int: InkGlyph]

    public init() { glyphs = [:] }

    public var isEmpty: Bool { glyphs.isEmpty }
    public var digitsLearned: [Int] { glyphs.keys.sorted() }

    public func glyph(for digit: Int) -> InkGlyph? { glyphs[digit] }

    /// Store `glyph` as the player's digit, normalized into the unit box the
    /// renderer draws from. Strokes are kept apart — a 4 drawn as two strokes
    /// must not render with a stem joining the crossbar to the vertical.
    public mutating func learn(_ glyph: InkGlyph, as digit: Int) {
        guard (1...9).contains(digit), let boxed = Self.boxed(glyph) else { return }
        glyphs[digit] = boxed
    }

    public mutating func forget(_ digit: Int) { glyphs[digit] = nil }

    /// Fit the ink into a unit box, uniformly, centred — the space
    /// `BoardView` scales into a note slot. Uniform for the same reason the
    /// matcher is: a 1 stretched to fill a square is not a 1.
    static func boxed(_ glyph: InkGlyph) -> InkGlyph? {
        guard let bounds = glyph.bounds else { return nil }
        let width = bounds.maxX - bounds.minX
        let height = bounds.maxY - bounds.minY
        let extent = max(width, height)
        guard extent > 0 else { return nil }
        let offsetX = (extent - width) / 2, offsetY = (extent - height) / 2
        let strokes = glyph.strokes
            .map { stroke in InkGlyph.resample(stroke, into: min(stroke.count, 24)) }
            .filter { $0.count >= 2 }
            .map { stroke in
                stroke.map {
                    InkPoint(x: ($0.x - bounds.minX + offsetX) / extent,
                             y: ($0.y - bounds.minY + offsetY) / extent)
                }
            }
        return strokes.isEmpty ? nil : InkGlyph(strokes: strokes)
    }

    // MARK: Wire format

    // Packed, not `[Int: InkGlyph]` through the synthesized coder: a glyph is
    // ~70 doubles, and JSON spells a double as up to 20 characters. Packed it
    // is one byte per coordinate over a unit box — 1/255 of a note slot, which
    // is well under a tenth of a point at any board size Nine draws.
    //
    // Decoding is tolerant in the way `CouchStored` demands: an entry that does
    // not unpack is *dropped*, never thrown, because a throw out of here
    // discards the whole blob and with it the eight digits that were fine.
    private enum CodingKeys: String, CodingKey { case glyphs = "g" }

    public init(from decoder: Decoder) throws {
        glyphs = [:]
        guard let container = try? decoder.container(keyedBy: CodingKeys.self),
              let packed = try? container.decodeIfPresent([String: String].self, forKey: .glyphs)
        else { return }
        for (key, value) in packed {
            guard let digit = Int(key), (1...9).contains(digit),
                  let data = Data(base64Encoded: value),
                  let glyph = Self.unpack(data) else { continue }
            glyphs[digit] = glyph
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var packed: [String: String] = [:]
        for (digit, glyph) in glyphs {
            packed["\(digit)"] = Self.pack(glyph).base64EncodedString()
        }
        try container.encode(packed, forKey: .glyphs)
    }

    static func pack(_ glyph: InkGlyph) -> Data {
        var bytes: [UInt8] = [UInt8(min(255, glyph.strokes.count))]
        for stroke in glyph.strokes.prefix(255) {
            let clipped = Array(stroke.prefix(255))
            bytes.append(UInt8(clipped.count))
            for point in clipped {
                bytes.append(UInt8(max(0, min(255, (point.x * 255).rounded()))))
                bytes.append(UInt8(max(0, min(255, (point.y * 255).rounded()))))
            }
        }
        return Data(bytes)
    }

    static func unpack(_ data: Data) -> InkGlyph? {
        let bytes = [UInt8](data)
        var index = 0
        guard index < bytes.count else { return nil }
        let strokeCount = Int(bytes[index]); index += 1
        var strokes: [[InkPoint]] = []
        for _ in 0..<strokeCount {
            guard index < bytes.count else { return nil }
            let count = Int(bytes[index]); index += 1
            guard index + count * 2 <= bytes.count else { return nil }
            var stroke: [InkPoint] = []
            stroke.reserveCapacity(count)
            for _ in 0..<count {
                stroke.append(InkPoint(x: Double(bytes[index]) / 255,
                                       y: Double(bytes[index + 1]) / 255))
                index += 2
            }
            if stroke.count >= 2 { strokes.append(stroke) }
        }
        return strokes.isEmpty ? nil : InkGlyph(strokes: strokes)
    }
}

// MARK: - Templates

/// The authored digit shapes the matcher compares against.
///
/// **Templates are authored and stay authored — the player's specimen is a
/// rendering fact, never a matching one.** Feeding accepted glyphs back in as
/// templates is the obvious next move and it is a trap: the day the matcher
/// reads your 4 as a 9, that 4-shape becomes the 9 template, and every
/// subsequent 4 reads as a 9 more confidently than the last. A recognizer that
/// degrades in exactly the direction of its own mistakes is worse than one that
/// never learns, so this one never learns.
enum DigitTemplates {

    struct Template {
        let digit: Int
        let cloud: [InkPoint]
    }

    static let all: [Template] = shapes.compactMap { digit, glyph in
        glyph.normalized().map { Template(digit: digit, cloud: $0) }
    }

    /// Several renditions per digit where people genuinely differ: an open and
    /// a closed 4, a 7 with and without its crossbar, a 1 bare and flagged.
    /// These are the differences that change the *shape*, not the ones that
    /// change the slant or the size — normalization already handles those.
    static let shapes: [(Int, InkGlyph)] = [
        // 1 — bare stem, flagged stem, flagged stem with a base serif.
        (1, InkGlyph(strokes: [line((0.50, 0.06), (0.50, 0.94))])),
        (1, InkGlyph(strokes: [polyline([(0.30, 0.22), (0.52, 0.06), (0.52, 0.94)])])),
        (1, InkGlyph(strokes: [polyline([(0.30, 0.22), (0.52, 0.06), (0.52, 0.94)]),
                               line((0.26, 0.94), (0.78, 0.94))])),
        // 2 — the cap arc, the diagonal, the base.
        (2, InkGlyph(strokes: [arc(0.50, 0.32, 0.26, 190, 350)
            + polyline([(0.76, 0.28), (0.16, 0.90)])
            + line((0.16, 0.90), (0.88, 0.90))])),
        (2, InkGlyph(strokes: [arc(0.48, 0.30, 0.24, 200, 360)
            + polyline([(0.72, 0.32), (0.20, 0.88)])
            + line((0.14, 0.90), (0.86, 0.90))])),
        // 3 — two right-facing bowls.
        (3, InkGlyph(strokes: [arc(0.48, 0.28, 0.25, 200, 450)
            + arc(0.48, 0.70, 0.28, 270, 520)])),
        // 4 — open (crossbar and stem meet at the apex) and closed.
        (4, InkGlyph(strokes: [polyline([(0.62, 0.06), (0.12, 0.62), (0.92, 0.62)]),
                               line((0.66, 0.06), (0.66, 0.95))])),
        (4, InkGlyph(strokes: [polyline([(0.66, 0.08), (0.12, 0.62), (0.90, 0.62)]),
                               line((0.66, 0.30), (0.66, 0.95))])),
        // 5 — cap and stem, then the bowl.
        (5, InkGlyph(strokes: [polyline([(0.78, 0.10), (0.26, 0.10), (0.22, 0.46)]),
                               arc(0.50, 0.66, 0.29, 225, 500)])),
        (5, InkGlyph(strokes: [polyline([(0.76, 0.09), (0.28, 0.09), (0.24, 0.48)])
            + arc(0.50, 0.66, 0.28, 230, 495)])),
        // 6 — the descending spine and the closed loop.
        (6, InkGlyph(strokes: [arc(0.58, 0.40, 0.34, 280, 160)
            + arc(0.50, 0.70, 0.28, 180, 540)])),
        // 8 — two loops, one stroke.
        (8, InkGlyph(strokes: [arc(0.50, 0.28, 0.22, 270, 630)
            + arc(0.50, 0.72, 0.26, 270, 630)])),
        // 7 — bare and crossed.
        (7, InkGlyph(strokes: [polyline([(0.14, 0.10), (0.86, 0.10), (0.36, 0.94)])])),
        (7, InkGlyph(strokes: [polyline([(0.14, 0.10), (0.86, 0.10), (0.36, 0.94)]),
                               line((0.28, 0.54), (0.70, 0.54))])),
        // 9 — the bowl and the tail, apart and joined.
        (9, InkGlyph(strokes: [arc(0.50, 0.30, 0.25, 0, 360),
                               polyline([(0.75, 0.30), (0.70, 0.94)])])),
        (9, InkGlyph(strokes: [arc(0.50, 0.30, 0.25, 20, 380)
            + polyline([(0.74, 0.34), (0.68, 0.94)])])),
    ]

    // MARK: Shape helpers

    static func line(_ a: (Double, Double), _ b: (Double, Double), steps: Int = 14) -> [InkPoint] {
        (0...steps).map { step in
            let t = Double(step) / Double(steps)
            return InkPoint(x: a.0 + t * (b.0 - a.0), y: a.1 + t * (b.1 - a.1))
        }
    }

    static func polyline(_ points: [(Double, Double)], steps: Int = 12) -> [InkPoint] {
        zip(points, points.dropFirst()).flatMap { line($0, $1, steps: steps) }
    }

    /// Angles in degrees, y **down** — so 270° is the top of the circle and 90°
    /// its bottom, which is what makes the digit shapes above read the way they
    /// are written. `to` may exceed `from` by more than 360 to wrap.
    static func arc(
        _ cx: Double, _ cy: Double, _ r: Double,
        _ from: Double, _ to: Double, steps: Int = 28
    ) -> [InkPoint] {
        (0...steps).map { step in
            let degrees = from + (to - from) * Double(step) / Double(steps)
            let radians = degrees * .pi / 180
            return InkPoint(x: cx + r * cos(radians), y: cy + r * sin(radians))
        }
    }
}
