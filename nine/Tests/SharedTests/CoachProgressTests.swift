// CoachProgressTests — the blob that remembers which techniques a player has
// met (PRD-25 §2.5).
//
// Two things are being defended, and neither is arithmetic:
//
//   1. **`CouchStored` discards the whole blob when a decode throws**, so
//      nothing in here may throw. A player who has met nine techniques must not
//      lose all nine because one row was written by a build that knew something
//      this one does not.
//   2. **It is keyed by raw-value strings, not by the enum**, so a build from
//      before PRD-25 carries `swordfish` verbatim instead of dropping it. That
//      is the same rule `nine.history`'s `band` sibling exists for, and the
//      downgrade drill below is the same drill.
import Testing
import Foundation
@testable import NineShared
@testable import NineEngine

@Suite("CoachProgress")
struct CoachProgressTests {

    @Test func aTechniqueNobodyHasMetReadsAsUnmet() {
        let progress = CoachProgress()
        #expect(!progress.hasMet(.xWing))
        #expect(progress.record(for: .xWing).explained == 0)
        #expect(progress.record(for: .xWing).lessonDone == false)
        #expect(progress.count == 0)
    }

    @Test func explainingATechniqueMeetsIt() {
        var progress = CoachProgress()
        progress.recordExplanation(of: .nakedPair)
        #expect(progress.hasMet(.nakedPair))
        #expect(progress.record(for: .nakedPair).explained == 1)
        progress.recordExplanation(of: .nakedPair)
        #expect(progress.record(for: .nakedPair).explained == 2)
    }

    /// A lesson finished counts as met even though nothing was ever narrated on
    /// a live board — the two doors into a technique are equal.
    @Test func finishingALessonMeetsItToo() {
        var progress = CoachProgress()
        progress.recordLessonFinished(.xWing)
        #expect(progress.hasMet(.xWing))
        #expect(progress.record(for: .xWing).explained == 0)
    }

    @Test func metCountIsOverTheTechniquesAsked() {
        var progress = CoachProgress()
        progress.recordExplanation(of: .nakedSingle)
        progress.recordLessonFinished(.xWing)
        let classic = Technique.allCases.filter(\.isClassic)
        #expect(progress.metCount(of: classic) == 2)
        #expect(progress.metCount(of: [.nakedSingle]) == 1)
        #expect(progress.metCount(of: [.hiddenPair]) == 0)
    }

    // MARK: - Ordering

    /// **One lesson moves, not the list.** A curriculum that re-sorts itself
    /// under someone who is reading it is worse than one that never moves, so
    /// the rule is: float the first unmet technique to the top and leave
    /// everything else exactly where it was.
    @Test func theFirstUnmetLessonFloatsAndNothingElseMoves() {
        var progress = CoachProgress()
        let order: [Technique] = [.nakedSingle, .hiddenSingle, .nakedPair, .hiddenPair]
        #expect(progress.suggestedOrder(order) == order, "nothing met yet, nothing moves")

        progress.recordExplanation(of: .nakedSingle)
        progress.recordExplanation(of: .hiddenSingle)
        #expect(progress.suggestedOrder(order) == [.nakedPair, .nakedSingle, .hiddenSingle, .hiddenPair])
    }

    @Test func aFullyMetCurriculumKeepsItsOrder() {
        var progress = CoachProgress()
        let order: [Technique] = [.nakedSingle, .hiddenSingle]
        for technique in order { progress.recordExplanation(of: technique) }
        #expect(progress.suggestedOrder(order) == order)
    }

    // MARK: - Persistence

    @Test func roundTripsThroughJSON() throws {
        var progress = CoachProgress()
        progress.recordExplanation(of: .simpleColoring)
        progress.recordLessonFinished(.swordfish)
        let back = try JSONDecoder().decode(
            CoachProgress.self, from: JSONEncoder().encode(progress))
        #expect(back == progress)
    }

    /// Nothing here throws. Every shape below used to be a way to lose the
    /// whole blob, and `CouchStored`'s `try?` would have swallowed the throw
    /// and handed the player an empty one.
    @Test(arguments: [
        "null", "[]", "7", "\"words\"",
        "{}",
        "{\"met\": []}",
        "{\"met\": {\"xWing\": 3}}",
        "{\"met\": {\"xWing\": {\"explained\": \"lots\"}}, \"order\": 4}",
        "{\"order\": [\"xWing\"]}",
    ])
    func nothingUnreadableTakesTheBlobDown(_ json: String) throws {
        let progress = try JSONDecoder().decode(CoachProgress.self, from: Data(json.utf8))
        // Whatever it read, it is a usable value rather than a throw.
        #expect(progress.metCount(of: Technique.allCases) >= 0)
    }

    /// A row whose record is unreadable still decodes as a *present* technique
    /// with a zeroed record, rather than throwing the dictionary.
    @Test func anUnreadableRecordReadsAsNothingRememberedForThatTechnique() throws {
        let json = "{\"met\": {\"xWing\": {\"explained\": true}}, \"order\": [\"xWing\"]}"
        let progress = try JSONDecoder().decode(CoachProgress.self, from: Data(json.utf8))
        #expect(progress.record(for: .xWing).explained == 0)
        #expect(!progress.hasMet(.xWing))
    }

    /// Repair: a blob whose `order` and `met` disagree still trims
    /// deterministically instead of leaking rows past the cap forever.
    @Test func aHalfWrittenBlobRepairsItsOwnOrder() throws {
        let json = "{\"met\": {\"xWing\": {\"explained\": 1, \"lessonDone\": false}}, \"order\": [\"gone\"]}"
        let progress = try JSONDecoder().decode(CoachProgress.self, from: Data(json.utf8))
        #expect(progress.hasMet(.xWing))
        let back = try JSONDecoder().decode(
            CoachProgress.self, from: JSONEncoder().encode(progress))
        #expect(back == progress)
    }

    // MARK: - The downgrade drill

    /// **A build that has never heard of a technique must carry its row, not
    /// eat it.** This is the `nine.history` `band` problem in miniature: the
    /// blob is cloud-synced and last-writer-wins, so an old device that
    /// re-encodes a progress blob it only half understood writes that half back
    /// over the good one, on every device.
    ///
    /// String keys are what make it survive. The test stands in a technique id
    /// no build will ever ship, because a real future case would compile.
    @Test func aRowFromAFutureBuildSurvivesAnOlderOnesRewrite() throws {
        let json = """
        {"met": {"xWing": {"explained": 2, "lessonDone": true},
                 "fromTheFuture": {"explained": 9, "lessonDone": true}},
         "order": ["xWing", "fromTheFuture"]}
        """
        let progress = try JSONDecoder().decode(CoachProgress.self, from: Data(json.utf8))
        let rewritten = String(decoding: try JSONEncoder().encode(progress), as: UTF8.self)
        #expect(rewritten.contains("fromTheFuture"), """
            a technique id this build does not know was dropped on re-encode. \
            The blob is cloud-synced and last-writer-wins, so that deletion \
            propagates to the device that *did* understand it.
            """)
    }

    /// Bounded forever. The cap is generous — there are fourteen techniques —
    /// but a blob that can only grow is a blob that eventually cannot sync.
    @Test func theBlobIsBoundedNoMatterWhatItIsFed() throws {
        var rows: [String] = []
        for i in 0..<(CoachProgress.capacity * 2) {
            rows.append("\"t\(i)\": {\"explained\": 1, \"lessonDone\": false}")
        }
        let json = "{\"met\": {\(rows.joined(separator: ","))}}"
        let progress = try JSONDecoder().decode(CoachProgress.self, from: Data(json.utf8))
        #expect(progress.count == CoachProgress.capacity)

        let bytes = try JSONEncoder().encode(progress).count
        #expect(bytes < 2048, "a full blob is \(bytes) bytes; PRD-25 §2.5 budgets under 2 KB")
    }

    /// The worst case PRD-26 introduced: every row carrying every field. A
    /// synthesized encoder would spell all three on all 32 rows and clear
    /// 2 KB; `Met.encode(to:)` omits defaults, which is why the cap did not
    /// have to move.
    @Test func aFullyPopulatedBlobStillFits() throws {
        var progress = CoachProgress()
        for technique in Technique.allCases {
            progress.recordExplanation(of: technique)
            progress.recordLessonFinished(technique)
            progress.recordUse(of: technique)
        }
        let bytes = try JSONEncoder().encode(progress).count
        #expect(bytes < 2048, "every technique met three ways is \(bytes) bytes")
    }

    /// PRD-26 §3.4 — the third route to meeting a technique, and the only one
    /// that does not involve being told.
    @Test func usingATechniqueMeetsIt() {
        var progress = CoachProgress()
        #expect(!progress.hasMet(.xWing))
        progress.recordUse(of: .xWing)
        #expect(progress.hasMet(.xWing))
        #expect(progress.record(for: .xWing).usedInSolve)
        // Not a count. A second use is not a bigger number, because a number
        // here is a score and the covenant bans one.
        #expect(progress.record(for: .xWing).explained == 0)
    }

    @Test func recordingTheSameUseTwiceChangesNothing() {
        var progress = CoachProgress()
        progress.recordUse(of: .swordfish)
        let once = progress
        progress.recordUse(of: .swordfish)
        #expect(progress == once)
    }

    /// A build that has never heard of `usedInSolve` must read the row, not
    /// choke on it — and its rewrite may only cost the bool.
    @Test func anOlderBuildsRowStillDecodes() throws {
        let legacy = Data(#"{"met":{"xWing":{"explained":2}},"order":["xWing"]}"#.utf8)
        let progress = try JSONDecoder().decode(CoachProgress.self, from: legacy)
        #expect(progress.hasMet(.xWing))
        #expect(!progress.record(for: .xWing).usedInSolve)
    }
}
