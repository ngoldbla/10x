// Reading a digit out of ink, pinned (PRD-31).
//
// **The honest caveat, stated first because it bounds everything below: no
// Apple Pencil has ever written a digit into Nine.** There is no Pencil in a
// simulator and no way to synthesize a real one, so every glyph in this file is
// constructed. The mitigation is that they are constructed *differently from
// the templates* — different control points, different stroke splits, a shear,
// a rotation and per-point jitter — so a template that only matches its own
// coordinates fails here. It is not the same thing as a hand, and DEVIATIONS
// says so.
import XCTest
@testable import NineShared

final class HandwritingTests: XCTestCase {

    // MARK: A hand that is not the template's

    /// Deterministic jitter. `Hashable` is seeded per process in Swift, and a
    /// test whose input changes every run is not a test — the same reason
    /// `EXECUTING-A-PRD.md` §3 forbids folding `hashValue` into a seed.
    private struct Pen {
        var state: UInt64
        init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double((state >> 33) & 0xFFFF) / 65535.0
        }
        /// ±`amount`, uniform.
        mutating func wobble(_ amount: Double) -> Double { (next() - 0.5) * 2 * amount }
    }

    /// Put a glyph through what a hand does to it: slant it, turn it a little,
    /// wobble every point, then move and resize it into some arbitrary corner
    /// of some arbitrary cell. Nothing here may change which digit it is.
    private func handwritten(
        _ strokes: [[(Double, Double)]],
        seed: UInt64,
        shear: Double = 0.16,
        rotation: Double = -0.06,
        wobble: Double = 0.012,
        scale: Double = 41.0,
        origin: (Double, Double) = (137.5, 402.25)
    ) -> InkGlyph {
        var pen = Pen(seed: seed)
        let cosine = cos(rotation), sine = sin(rotation)
        return InkGlyph(strokes: strokes.map { stroke in
            stroke.map { point in
                let sheared = (x: point.0 + shear * (1 - point.1), y: point.1)
                let turned = (x: sheared.x * cosine - sheared.y * sine,
                              y: sheared.x * sine + sheared.y * cosine)
                return InkPoint(
                    x: origin.0 + scale * (turned.x + pen.wobble(wobble)),
                    y: origin.1 + scale * (turned.y + pen.wobble(wobble))
                )
            }
        })
    }

    /// Densify a control polygon the way a pen samples it — many more points
    /// than the template's own `steps`, and unevenly, since a hand slows into
    /// corners.
    private func trace(_ points: [(Double, Double)], per: Int = 9) -> [(Double, Double)] {
        guard points.count >= 2 else { return points }
        var out: [(Double, Double)] = [points[0]]
        for (a, b) in zip(points, points.dropFirst()) {
            for step in 1...per {
                let t = Double(step) / Double(per)
                let eased = t * t * (3 - 2 * t)   // slow into the corners
                out.append((a.0 + eased * (b.0 - a.0), a.1 + eased * (b.1 - a.1)))
            }
        }
        return out
    }

    private func curve(
        _ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double,
        _ from: Double, _ to: Double, steps: Int = 34
    ) -> [(Double, Double)] {
        (0...steps).map { step in
            let degrees = from + (to - from) * Double(step) / Double(steps)
            let radians = degrees * .pi / 180
            return (cx + rx * cos(radians), cy + ry * sin(radians))
        }
    }

    /// Nine hands, none of them the template's coordinates. Each is written the
    /// way the digit is actually taught, with proportions deliberately off the
    /// authored ones (ellipses instead of circles, different apex heights,
    /// different bowl depths).
    private func strokesFor(_ digit: Int) -> [[(Double, Double)]] {
        switch digit {
        case 1:
            return [trace([(0.34, 0.26), (0.55, 0.04), (0.55, 0.96)])]
        case 2:
            return [curve(0.46, 0.29, 0.30, 0.24, 195, 348)
                + trace([(0.75, 0.24), (0.13, 0.93)])
                + trace([(0.13, 0.93), (0.91, 0.92)])]
        case 3:
            return [curve(0.44, 0.26, 0.27, 0.22, 205, 445)
                + curve(0.46, 0.71, 0.31, 0.26, 268, 528)]
        case 4:
            return [trace([(0.58, 0.03), (0.09, 0.66), (0.95, 0.65)]),
                    trace([(0.70, 0.10), (0.64, 0.97)])]
        case 5:
            return [trace([(0.81, 0.07), (0.23, 0.11), (0.19, 0.50)]),
                    curve(0.48, 0.69, 0.32, 0.27, 222, 505)]
        case 6:
            return [curve(0.60, 0.42, 0.37, 0.36, 282, 158)
                + curve(0.48, 0.72, 0.30, 0.25, 178, 543)]
        case 7:
            return [trace([(0.11, 0.08), (0.89, 0.12), (0.33, 0.96)])]
        case 8:
            return [curve(0.48, 0.26, 0.24, 0.21, 272, 632)
                + curve(0.50, 0.74, 0.29, 0.25, 268, 628)]
        default:
            return [curve(0.48, 0.28, 0.27, 0.24, 4, 366),
                    trace([(0.74, 0.27), (0.66, 0.96)])]
        }
    }

    private func hand(for digit: Int, seed: UInt64) -> InkGlyph {
        handwritten(strokesFor(digit), seed: seed)
    }

    // MARK: The claim the feature rests on

    /// Every digit, written five different ways, read correctly and confidently
    /// enough to place a mark. This is the test that decides whether the
    /// feature exists.
    func testEveryDigitIsReadFromAHandThatIsNotTheTemplate() {
        for digit in 1...9 {
            for seed in UInt64(1)...5 {
                let glyph = hand(for: digit, seed: seed &* 977 &+ UInt64(digit))
                guard let reading = DigitHand.read(glyph) else {
                    return XCTFail("digit \(digit), seed \(seed): read nothing")
                }
                XCTAssertEqual(reading.digit, digit,
                               "seed \(seed) read \(reading.digit) at \(reading.score)")
                XCTAssertTrue(DigitHand.commits(reading),
                              "digit \(digit) seed \(seed): score \(reading.score), "
                              + "margin \(reading.margin)")
            }
        }
    }

    /// Where the ink lands and how big it is must not change what it says. Nine
    /// writes into cells of wildly different sizes — a 200pt board on an iPhone
    /// SE, a 1000pt one on an external display — and the same hand at both.
    func testSizeAndPlacementDoNotChangeTheReading() {
        for digit in 1...9 {
            let small = handwritten(strokesFor(digit), seed: 7, scale: 12, origin: (4, 900))
            let large = handwritten(strokesFor(digit), seed: 7, scale: 96, origin: (611, 12))
            XCTAssertEqual(DigitHand.read(small)?.digit, digit, "small \(digit)")
            XCTAssertEqual(DigitHand.read(large)?.digit, digit, "large \(digit)")
        }
    }

    // MARK: What must never be read as a digit

    /// The board is covered in ink the player did not mean as a digit: a rested
    /// wrist, a stray dash, a scribbled-out mistake, a tap. Every one of these
    /// would silently edit a cell if it were allowed to commit, and a wrong
    /// pencil mark that appears from nowhere is the single worst failure this
    /// feature can have.
    func testNonDigitsAreRefusedRatherThanGuessed() {
        let dash = InkGlyph(strokes: [DigitTemplates.line((0.1, 0.5), (0.9, 0.52))])
        let dot = InkGlyph(strokes: [DigitTemplates.line((0.5, 0.5), (0.502, 0.501))])
        let scribble = InkGlyph(strokes: [
            DigitTemplates.polyline([(0.1, 0.2), (0.9, 0.8), (0.1, 0.8), (0.9, 0.2),
                                     (0.1, 0.5), (0.9, 0.5), (0.2, 0.1), (0.8, 0.9)])
        ])
        let blank = InkGlyph(strokes: [])
        for (name, glyph) in [("dash", dash), ("dot", dot),
                              ("scribble", scribble), ("blank", blank)] {
            let reading = DigitHand.read(glyph)
            XCTAssertFalse(reading.map(DigitHand.commits) ?? false,
                           "\(name) committed as \(reading?.digit ?? 0) "
                           + "at \(reading?.score ?? 0)")
        }
    }

    /// The adopt bar is strictly harder than the commit bar, and the code says
    /// so rather than the comment. If these ever cross, a merely-plausible
    /// reading starts rewriting the player's specimen.
    func testAdoptingAGlyphIsStrictlyHarderThanPlacingAMark() {
        XCTAssertGreaterThan(DigitHand.adoptScore, DigitHand.commitScore)
        for digit in 1...9 {
            let reading = DigitHand.read(hand(for: digit, seed: 11))
            if let reading, DigitHand.adopts(reading) {
                XCTAssertTrue(DigitHand.commits(reading), "digit \(digit)")
            }
        }
    }

    // MARK: Where the commit bar came from

    /// Hands written badly enough that the matcher gets them *wrong*. Each one
    /// is a real way to write the digit — a 7 whose hook barely leaves the
    /// stem, a 4 whose crossbar is a stub, a 3 with flat bumps, an S-shaped 5.
    /// They are here to be *refused*, not to be read: a feature that guesses
    /// under pressure edits the board behind the player's back.
    /// Each carries the digit it was *meant* to be, because that is the only
    /// thing that makes "right" and "wrong" measurable. Two of these the
    /// matcher does read correctly, and folding them into a wrong-answer bucket
    /// by which list they came from is how a calibration measures its own
    /// labelling instead of the recognizer — which is what the first draft of
    /// these tests did, and what it took a failing assertion to notice.
    private var degradedHands: [(name: String, intended: Int, glyph: InkGlyph)] {
        [("7 with a hook too small", 7,
          InkGlyph(strokes: [DigitTemplates.polyline([(0.30, 0.10), (0.70, 0.10), (0.45, 0.95)])])),
         ("4 with a stub crossbar", 4,
          InkGlyph(strokes: [DigitTemplates.polyline([(0.60, 0.20), (0.40, 0.60), (0.85, 0.60)]),
                             DigitTemplates.line((0.62, 0.20), (0.62, 0.95))])),
         ("3 with flat bumps", 3,
          InkGlyph(strokes: [DigitTemplates.polyline([(0.2, 0.1), (0.8, 0.1), (0.45, 0.5),
                                                      (0.8, 0.6), (0.45, 0.9), (0.2, 0.85)])])),
         ("5 written as an S", 5,
          InkGlyph(strokes: [DigitTemplates.arc(0.5, 0.28, 0.25, 20, 250)
              + DigitTemplates.arc(0.5, 0.72, 0.25, 250, 470)])),
         ("9 with no tail at all", 9,
          InkGlyph(strokes: [DigitTemplates.arc(0.5, 0.35, 0.28, 0, 360),
                             DigitTemplates.line((0.78, 0.35), (0.77, 0.60))]))]
    }

    /// The whole corpus — 45 ordinary hands and five bad ones — with what each
    /// was meant to say.
    private var corpus: [(name: String, intended: Int, reading: DigitHand.Reading?)] {
        var rows: [(String, Int, DigitHand.Reading?)] = []
        for digit in 1...9 {
            for seed in UInt64(1)...5 {
                let glyph = hand(for: digit, seed: seed &* 977 &+ UInt64(digit))
                rows.append(("\(digit)/seed \(seed)", digit, DigitHand.read(glyph)))
            }
        }
        for hand in degradedHands {
            rows.append((hand.name, hand.intended, DigitHand.read(hand.glyph)))
        }
        return rows
    }

    /// **The bar's actual job: no wrong reading ever clears it.** A pencil mark
    /// that appears in a cell the player did not mean is the worst failure this
    /// feature has — it edits the board behind their back, and unlike a
    /// mis-tapped petal there is no gesture they can point at as the cause. So
    /// the bar sits above the best *wrong* score in the corpus, not at the
    /// crossover point.
    func testNoWrongReadingEverClearsTheCommitBar() {
        var bestWrong = 0.0
        var worst = "none"
        for row in corpus {
            guard let reading = row.reading, reading.digit != row.intended else { continue }
            if reading.score > bestWrong { bestWrong = reading.score; worst = row.name }
        }
        XCTAssertLessThan(bestWrong, DigitHand.commitScore,
                          "\(worst) was read wrongly at \(bestWrong)")
    }

    /// …and the price of that, stated out loud rather than discovered later.
    ///
    /// The two populations **overlap** on badly-formed hands: the best wrong
    /// reading scores ~0.39 and the worst right one ~0.30, so a bar safe enough
    /// to refuse the first also refuses the second. A 3 with flat bumps is a
    /// real way to write a 3, it is read correctly, and it is thrown away
    /// anyway. That is the deliberate trade — the ink fades, nothing is placed,
    /// and the player writes it again — and it is a cost, not a free win.
    func testTheSafeBarAlsoRefusesSomeCorrectReadings() {
        let refusedButRight = corpus.filter { row in
            guard let reading = row.reading else { return false }
            return reading.digit == row.intended && !DigitHand.commits(reading)
        }
        XCTAssertFalse(refusedButRight.isEmpty,
                       "no correct reading is refused any more — the bar may now be able to "
                       + "come down, which would make more badly-written digits land")
        // Every one of them is a degraded hand, never an ordinary one: the
        // 45 hands in `testEveryDigitIsReadFromAHandThatIsNotTheTemplate` all
        // commit, and if an ordinary hand ever lands here that test fails too.
        for row in refusedButRight {
            XCTAssertTrue(degradedHands.contains { $0.name == row.name },
                          "\(row.name) is an ordinary hand and was refused")
        }
    }

    /// The margin between the best digit and the runner-up was going to be a
    /// second bar, on the reasoning that a guess which barely beats its rival is
    /// a coin toss. It is not that the idea is wrong — it is that **the score
    /// bar has already rejected everything the margin bar could reject.**
    /// Across the whole corpus, every reading that clears `commitScore` is
    /// correct, so any second bar can only ever take a right answer away.
    ///
    /// Kept as a test rather than deleted with the constant, because this is
    /// the sort of thing that stops being true quietly. The day a wrong reading
    /// clears the score bar, this fails, and a margin bar becomes worth having
    /// again — with a number that came from somewhere.
    func testTheMarginBarWouldHaveNothingLeftToReject() {
        for row in corpus {
            guard let reading = row.reading, DigitHand.commits(reading) else { continue }
            XCTAssertEqual(reading.digit, row.intended,
                           "\(row.name) cleared the score bar reading \(reading.digit) "
                           + "at \(reading.score), margin \(reading.margin) — a margin bar "
                           + "would now have work to do")
        }
    }

    // MARK: The specimen store

    /// A glyph survives the round trip through the wire format well enough to
    /// draw: within half a percent of the note slot, which at Nine's largest
    /// cell (a 1000pt board, 111pt cells) is under a third of a point.
    func testAGlyphSurvivesPackingWellEnoughToDraw() {
        var hand = HandGlyphs()
        hand.learn(self.hand(for: 4, seed: 21), as: 4)
        let data = try! JSONEncoder().encode(hand)
        let restored = try! JSONDecoder().decode(HandGlyphs.self, from: data)
        guard let before = hand.glyph(for: 4), let after = restored.glyph(for: 4) else {
            return XCTFail("nothing came back")
        }
        XCTAssertEqual(before.strokes.count, after.strokes.count)
        for (a, b) in zip(before.strokes, after.strokes) {
            XCTAssertEqual(a.count, b.count)
            for (p, q) in zip(a, b) {
                XCTAssertEqual(p.x, q.x, accuracy: 0.005)
                XCTAssertEqual(p.y, q.y, accuracy: 0.005)
            }
        }
    }

    /// The whole hand has to fit in KVS beside the streak, the archive and the
    /// coach's progress. PRD-25's `CoachProgress` measures its own budget
    /// rather than trusting it, for the reason PRD-26 found when a third `Bool`
    /// pushed it over; this does the same.
    func testAFullHandFitsTheKeyValueBudget() {
        var hand = HandGlyphs()
        for digit in 1...9 { hand.learn(self.hand(for: digit, seed: UInt64(digit)), as: digit) }
        XCTAssertEqual(hand.digitsLearned, Array(1...9))
        let bytes = try! JSONEncoder().encode(hand).count
        XCTAssertLessThan(bytes, 4096, "a full hand packs to \(bytes) bytes")
    }

    /// Garbage in the blob costs one digit, never the hand. `CouchStored`
    /// discards the whole blob when decode throws, so this decode must not.
    func testAnUnreadableEntryCostsOneDigitAndNotTheBlob() {
        var hand = HandGlyphs()
        hand.learn(self.hand(for: 2, seed: 5), as: 2)
        hand.learn(self.hand(for: 7, seed: 5), as: 7)
        var object = try! JSONSerialization.jsonObject(
            with: try! JSONEncoder().encode(hand)) as! [String: Any]
        var glyphs = object["g"] as! [String: String]
        glyphs["7"] = "!!!! not base64 !!!!"
        glyphs["12"] = glyphs["2"]           // a digit that cannot exist
        object["g"] = glyphs
        let data = try! JSONSerialization.data(withJSONObject: object)
        let restored = try! JSONDecoder().decode(HandGlyphs.self, from: data)
        XCTAssertEqual(restored.digitsLearned, [2])
    }

    /// A blob from a build that never heard of handwriting decodes to an empty
    /// hand rather than throwing — the `NinePrefs` rule, applied to a type that
    /// did not exist yet.
    func testAnEmptyOrForeignBlobDecodesToNoHand() {
        for json in ["{}", "{\"g\":{}}", "{\"something\":1}"] {
            let hand = try? JSONDecoder().decode(HandGlyphs.self, from: Data(json.utf8))
            XCTAssertEqual(hand?.isEmpty, true, json)
        }
    }

    /// The stored glyph keeps its strokes apart. A 4 flattened into one stroke
    /// renders with a stem joining the crossbar to the vertical — a shape no
    /// one wrote.
    func testStrokesAreNotWeldedTogetherByStorage() {
        var hand = HandGlyphs()
        hand.learn(self.hand(for: 4, seed: 31), as: 4)
        XCTAssertEqual(hand.glyph(for: 4)?.strokes.count, 2)
    }

    /// Every stored glyph sits inside the unit box the renderer scales from —
    /// so a note can never paint outside its own slot and into the cell beside
    /// it.
    func testAStoredGlyphNeverLeavesItsBox() {
        var hand = HandGlyphs()
        for digit in 1...9 { hand.learn(self.hand(for: digit, seed: 99), as: digit) }
        for digit in 1...9 {
            for point in hand.glyph(for: digit)!.strokes.flatMap({ $0 }) {
                XCTAssertTrue((0...1).contains(point.x), "digit \(digit) x \(point.x)")
                XCTAssertTrue((0...1).contains(point.y), "digit \(digit) y \(point.y)")
            }
        }
    }
}
