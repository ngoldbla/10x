import XCTest
import CouchCore
@testable import RabbitEarsEngine

final class ChannelDirectorTests: XCTestCase {

    // MARK: - Helpers

    private func ids(_ count: Int, prefix: String = "p") -> [String] {
        (0..<count).map { "\(prefix)\($0)" }
    }

    private func makeDirector(
        poolSize: Int = 8,
        seed: UInt64 = 42,
        at now: TimeInterval = 0
    ) -> (director: ChannelDirector, pool: [String], events: [ChannelDirector.Event]) {
        var director = ChannelDirector(seed: seed)
        let pool = ids(poolSize)
        let events = director.setPool(pool, for: .allMemories, at: now)
        return (director, pool, events)
    }

    private func dwellEnd(_ director: ChannelDirector) -> TimeInterval {
        guard case .dwelling(let until) = director.phase else {
            XCTFail("expected dwelling phase, got \(director.phase)")
            return .infinity
        }
        return until
    }

    /// Runs one full dwell → crossfade → landing cycle. Returns the landed
    /// photo id and the time after landing.
    @discardableResult
    private func runTransition(
        _ director: inout ChannelDirector,
        from now: TimeInterval
    ) -> (landedID: String, now: TimeInterval) {
        let until = dwellEnd(director)
        XCTAssertTrue(director.advance(to: until - 0.001).isEmpty, "no events before dwell expiry")
        let startEvents = director.advance(to: until)
        guard case .crossfadeStarted(_, let toID, let duration, _)? = startEvents.first else {
            XCTFail("expected crossfadeStarted, got \(startEvents)")
            return ("", now)
        }
        let doneEvents = director.advance(to: until + duration)
        guard case .photoChanged(let landedID)? = doneEvents.first else {
            XCTFail("expected photoChanged, got \(doneEvents)")
            return ("", now)
        }
        XCTAssertEqual(landedID, toID, "crossfade must land on the announced photo")
        return (landedID, until + duration)
    }

    // MARK: - Activation & dwell scheduling

    func testInitialActivationEmitsPhotoAndSchedulesDwellInEnvelope() {
        let (director, pool, events) = makeDirector()
        guard case .photoChanged(let id)? = events.first else {
            return XCTFail("setPool must emit photoChanged, got \(events)")
        }
        XCTAssertTrue(pool.contains(id))
        XCTAssertEqual(events.count, 1)
        let until = dwellEnd(director)
        XCTAssertGreaterThanOrEqual(until, 20, "dwell must be ≥ 20 s")
        XCTAssertLessThanOrEqual(until, 40, "dwell must be ≤ 40 s")
        XCTAssertNotNil(director.upNextPhotoID, "up-next chosen at dwell start for pre-render")
        XCTAssertNotEqual(director.upNextPhotoID, director.currentPhotoID)
    }

    func testDwellExpiryStartsCrossfadeWithAtLeastThreeSecondFade() {
        var (director, _, _) = makeDirector()
        let expectedNext = director.upNextPhotoID
        let current = director.currentPhotoID
        let until = dwellEnd(director)
        XCTAssertTrue(director.advance(to: until - 1).isEmpty)
        let events = director.advance(to: until)
        guard case .crossfadeStarted(let fromID, let toID, let duration, let isMorph)? = events.first else {
            return XCTFail("expected crossfadeStarted, got \(events)")
        }
        XCTAssertEqual(fromID, current)
        XCTAssertEqual(toID, expectedNext)
        XCTAssertFalse(isMorph)
        XCTAssertGreaterThanOrEqual(duration, 3, "PRD: crossfades are ≥ 3 s")
        XCTAssertEqual(duration, CrossfadeSpeed.standard.fadeDuration)
        // Progress is clamped and monotonic.
        XCTAssertEqual(director.crossfadeProgress(at: until) ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(director.crossfadeProgress(at: until + duration / 2) ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(director.crossfadeProgress(at: until + duration * 2) ?? -1, 1, accuracy: 1e-9)
    }

    func testCrossfadeCompletionLandsAndReschedules() {
        var (director, _, _) = makeDirector()
        let (landedID, now) = runTransition(&director, from: 0)
        XCTAssertEqual(director.currentPhotoID, landedID)
        let nextUntil = dwellEnd(director)
        XCTAssertGreaterThanOrEqual(nextUntil - now, 20)
        XCTAssertLessThanOrEqual(nextUntil - now, 40)
        XCTAssertNil(director.crossfadeProgress(at: now))
    }

    func testEveryDwellStaysInsideEnvelopeAcrossStylesAndSpeeds() {
        for speed in CrossfadeSpeed.allCases {
            XCTAssertGreaterThanOrEqual(speed.dwellRange.lowerBound, 20)
            XCTAssertLessThanOrEqual(speed.dwellRange.upperBound, 40)
            XCTAssertGreaterThanOrEqual(speed.fadeDuration, 3)
        }
        var (director, _, _) = makeDirector(poolSize: 12)
        var now: TimeInterval = 0
        for (i, style) in AsciiStyle.allCases.enumerated() {
            while director.style != style { _ = director.cycleStyle(forward: true) }
            director.setSpeed(CrossfadeSpeed.allCases[i % CrossfadeSpeed.allCases.count])
            let until = dwellEnd(director)
            let landed = runTransition(&director, from: now)
            now = landed.now
            let dwell = dwellEnd(director) - now
            XCTAssertGreaterThanOrEqual(dwell, 20, "style \(style) dwell too short")
            XCTAssertLessThanOrEqual(dwell, 40, "style \(style) dwell too long")
            _ = until
        }
    }

    // MARK: - No-repeat sequencing

    func testNoRepeatWithinSlidingWindow() {
        let poolSize = 10
        var (director, _, _) = makeDirector(poolSize: poolSize, seed: 7)
        var shown: [String] = [director.currentPhotoID!]
        var now: TimeInterval = 0
        for _ in 0..<40 {
            let landed = runTransition(&director, from: now)
            shown.append(landed.landedID)
            now = landed.now
        }
        // Window is clamped to poolSize − 1 = 9, so any 10 consecutive
        // photos must be pairwise distinct.
        for start in 0...(shown.count - poolSize) {
            let window = Array(shown[start..<(start + poolSize)])
            XCTAssertEqual(
                Set(window).count, poolSize,
                "repeat inside no-repeat window at \(start): \(window)"
            )
        }
        for i in 1..<shown.count {
            XCTAssertNotEqual(shown[i], shown[i - 1], "consecutive repeat at \(i)")
        }
    }

    func testUpNextAlwaysMatchesNextCrossfadeTarget() {
        var (director, _, _) = makeDirector(poolSize: 6, seed: 99)
        var now: TimeInterval = 0
        for _ in 0..<10 {
            let promised = director.upNextPhotoID
            XCTAssertNotNil(promised)
            let landed = runTransition(&director, from: now)
            XCTAssertEqual(landed.landedID, promised, "pre-render target must be the actual next photo")
            now = landed.now
        }
    }

    // MARK: - Determinism

    func testSameSeedSameCallsProduceIdenticalEventStreams() {
        func run(seed: UInt64) -> [ChannelDirector.Event] {
            var director = ChannelDirector(seed: seed)
            var events = director.setPool(ids(9), for: .allMemories, at: 0)
            var now: TimeInterval = 0
            for step in 0..<12 {
                if step == 4 { events += director.cycleStyle(forward: true) }
                if step == 7 { events += director.switchLane(forward: true, at: now) }
                if step == 7 { events += director.setPool(ids(5, prefix: "q"), for: .onThisDay, at: now) }
                guard case .dwelling(let until) = director.phase else { continue }
                events += director.advance(to: until)
                events += director.advance(to: until + 10)
                now = until + 10
            }
            return events
        }
        XCTAssertEqual(run(seed: 1234), run(seed: 1234), "same seed ⇒ identical channel")
        XCTAssertNotEqual(run(seed: 1234), run(seed: 5678), "different seed ⇒ different channel")
    }

    // MARK: - Lane switching

    func testLaneSwitchingCyclesAndUsesLanePools() {
        var director = ChannelDirector(seed: 3)
        _ = director.setPool(ids(4, prefix: "all"), for: .allMemories, at: 0)
        _ = director.setPool(ids(4, prefix: "otd"), for: .onThisDay, at: 0)
        _ = director.setPool(ids(4, prefix: "fav"), for: .favorites, at: 0)
        XCTAssertEqual(director.lane, .allMemories)

        let up = director.switchLane(forward: true, at: 10)
        XCTAssertEqual(director.lane, .onThisDay)
        XCTAssertTrue(up.contains(.laneChanged(.onThisDay)))
        guard case .photoChanged(let id)? = up.last else {
            return XCTFail("lane switch must land a photo, got \(up)")
        }
        XCTAssertTrue(id.hasPrefix("otd"), "photo must come from the new lane's pool")

        _ = director.switchLane(forward: true, at: 20)
        XCTAssertEqual(director.lane, .favorites)
        _ = director.switchLane(forward: true, at: 30)
        XCTAssertEqual(director.lane, .allMemories, "lanes wrap around")
        _ = director.switchLane(forward: false, at: 40)
        XCTAssertEqual(director.lane, .favorites, "backward wraps too")
    }

    func testSwitchingIntoEmptyLaneIdlesThenRecoversWhenPoolArrives() {
        var director = ChannelDirector(seed: 3)
        _ = director.setPool(ids(4), for: .allMemories, at: 0)
        _ = director.switchLane(forward: true, at: 5) // onThisDay: no pool yet
        XCTAssertEqual(director.phase, .idle)
        XCTAssertNil(director.currentPhotoID)
        XCTAssertTrue(director.advance(to: 100).isEmpty)
        let events = director.setPool(ids(3, prefix: "otd"), for: .onThisDay, at: 100)
        guard case .photoChanged? = events.first else {
            return XCTFail("pool arrival must land a photo, got \(events)")
        }
    }

    // MARK: - Style cycling

    func testStyleCycleWrapsAroundInBothDirections() {
        var (director, _, _) = makeDirector()
        XCTAssertEqual(director.style, .terminal)
        var seen: [AsciiStyle] = []
        for _ in 0..<5 {
            let events = director.cycleStyle(forward: true)
            XCTAssertEqual(events, [.styleChanged(director.style)])
            seen.append(director.style)
        }
        XCTAssertEqual(seen, [.phosphor, .pixel, .inkline, .mosaic, .terminal],
                       "five forward steps visit all styles and wrap home")
        _ = director.cycleStyle(forward: false)
        XCTAssertEqual(director.style, .mosaic, "backward from terminal wraps to mosaic")
    }

    // MARK: - Freeze

    func testFreezeBlocksAutoAdvanceAndUnfreezeResumes() {
        var (director, _, _) = makeDirector()
        let frozenID = director.currentPhotoID
        let events = director.toggleFreeze(at: 5)
        XCTAssertEqual(events, [.froze(id: frozenID!)])
        XCTAssertTrue(director.isFrozen)
        XCTAssertTrue(director.advance(to: 10_000).isEmpty, "frozen frames never advance")
        XCTAssertEqual(director.currentPhotoID, frozenID)

        let unfreeze = director.toggleFreeze(at: 10_000)
        XCTAssertEqual(unfreeze, [.unfroze])
        XCTAssertFalse(director.isFrozen)
        let until = dwellEnd(director)
        XCTAssertGreaterThanOrEqual(until - 10_000, 20, "unfreeze schedules a fresh dwell from now")
        XCTAssertLessThanOrEqual(until - 10_000, 40)
        let resumed = director.advance(to: until)
        guard case .crossfadeStarted? = resumed.first else {
            return XCTFail("channel must flow again after unfreeze, got \(resumed)")
        }
    }

    func testFreezeMidCrossfadeSnapsToIncomingPhoto() {
        var (director, _, _) = makeDirector()
        let until = dwellEnd(director)
        let start = director.advance(to: until)
        guard case .crossfadeStarted(_, let toID, _, _)? = start.first else {
            return XCTFail("expected crossfadeStarted")
        }
        let events = director.toggleFreeze(at: until + 1)
        XCTAssertEqual(events, [.photoChanged(id: toID), .froze(id: toID)],
                       "freezing mid-fade lands the incoming photo, then freezes it")
        XCTAssertTrue(director.isFrozen)
        XCTAssertEqual(director.currentPhotoID, toID)
    }

    // MARK: - Pause

    func testPausePreservesRemainingDwellExactly() {
        var (director, _, _) = makeDirector()
        let until = dwellEnd(director)
        let pauseAt = until - 12
        XCTAssertEqual(director.togglePause(at: pauseAt), [.paused])
        XCTAssertTrue(director.advance(to: until + 500).isEmpty, "paused channel never advances")
        let resumeAt: TimeInterval = 2_000
        XCTAssertEqual(director.togglePause(at: resumeAt), [.resumed])
        XCTAssertEqual(dwellEnd(director), resumeAt + 12, accuracy: 1e-9,
                       "resume restores the exact remaining dwell")
    }

    // MARK: - Morph

    func testMorphIsShortImmediateCrossfadeAndRespectsFreeze() {
        var (director, _, _) = makeDirector()
        let target = director.upNextPhotoID
        let events = director.morph(at: 2)
        guard case .crossfadeStarted(_, let toID, let duration, let isMorph)? = events.first else {
            return XCTFail("hold must start a morph crossfade, got \(events)")
        }
        XCTAssertTrue(isMorph)
        XCTAssertEqual(duration, 1.5, accuracy: 1e-9)
        XCTAssertEqual(toID, target)
        // Mid-crossfade hold is ignored.
        XCTAssertTrue(director.morph(at: 2.5).isEmpty)
        _ = director.advance(to: 2 + duration)
        // Frozen hold is ignored: freeze wins.
        _ = director.toggleFreeze(at: 10)
        XCTAssertTrue(director.morph(at: 11).isEmpty)
        // Coarse morph grid really is coarser.
        XCTAssertLessThan(MorphGrid.coarseCols(fineCols: 160), 160)
        XCTAssertGreaterThanOrEqual(MorphGrid.coarseCols(fineCols: 10), 24, "floor keeps art legible")
    }

    // MARK: - Persistence

    func testSavedStateRoundTripsThroughCouchJSONAndRestoresFreeze() throws {
        var (director, pool, _) = makeDirector(poolSize: 6, seed: 11)
        _ = director.setPool(ids(6, prefix: "fav"), for: .favorites, at: 0)
        _ = director.switchLane(forward: false, at: 1) // allMemories → favorites
        XCTAssertEqual(director.lane, .favorites)
        _ = director.cycleStyle(forward: true)
        _ = director.cycleStyle(forward: true) // terminal → pixel
        _ = director.toggleFreeze(at: 2)
        let frozenID = director.currentPhotoID!

        let saved = director.savedState
        XCTAssertEqual(saved.lane, .favorites)
        XCTAssertEqual(saved.style, .pixel)
        XCTAssertEqual(saved.frozenPhotoID, frozenID)

        let data = try CouchJSON.encode(saved)
        let decoded = try CouchJSON.decode(ChannelDirector.SavedState.self, from: data)
        XCTAssertEqual(decoded, saved, "byte round-trip preserves the snapshot")

        // A fresh director restored from the snapshot resumes frozen on the
        // same photo once its lane's pool arrives.
        var relaunched = ChannelDirector(seed: 11)
        relaunched.restore(decoded)
        XCTAssertEqual(relaunched.lane, .favorites)
        XCTAssertEqual(relaunched.style, .pixel)
        let events = relaunched.setPool(ids(6, prefix: "fav"), for: .favorites, at: 100)
        XCTAssertTrue(events.contains(.froze(id: frozenID)), "relaunch re-freezes the saved frame")
        XCTAssertTrue(relaunched.isFrozen)
        XCTAssertEqual(relaunched.currentPhotoID, frozenID)
        XCTAssertTrue(relaunched.advance(to: 10_000).isEmpty, "still a picture frame after relaunch")
        _ = pool
    }

    func testUnfrozenSavedStateCarriesNoFrozenPhoto() {
        let (director, _, _) = makeDirector()
        XCTAssertNil(director.savedState.frozenPhotoID)
    }

    func testFrozenPhotoMissingFromNewPoolEmitsUnfroze() {
        var (director, _, _) = makeDirector(poolSize: 4)
        _ = director.toggleFreeze(at: 1)
        XCTAssertTrue(director.isFrozen)
        let events = director.setPool(ids(4, prefix: "new"), for: .allMemories, at: 2)
        XCTAssertTrue(events.contains(.unfroze), "vanished frozen photo must unfreeze")
        XCTAssertFalse(director.isFrozen)
    }

    // MARK: - Edge pools

    func testEmptyPoolIdlesWithoutEvents() {
        var director = ChannelDirector(seed: 1)
        XCTAssertEqual(director.setPool([], for: .allMemories, at: 0), [])
        XCTAssertEqual(director.phase, .idle)
        XCTAssertTrue(director.advance(to: 500).isEmpty)
        XCTAssertNil(director.currentPhotoID)
    }

    func testSinglePhotoPoolDwellsForeverWithoutCrossfades() {
        var director = ChannelDirector(seed: 1)
        let events = director.setPool(["only"], for: .allMemories, at: 0)
        guard case .photoChanged("only")? = events.first else {
            return XCTFail("single photo still lands, got \(events)")
        }
        XCTAssertNil(director.upNextPhotoID)
        for t in stride(from: 0.0, through: 500.0, by: 50.0) {
            XCTAssertTrue(director.advance(to: t).isEmpty)
        }
        XCTAssertEqual(director.currentPhotoID, "only")
    }
}

// MARK: - Types & helpers

final class ChannelTypesTests: XCTestCase {

    func testCaptionFormatting() {
        var components = DateComponents()
        components.year = 2019
        components.month = 6
        components.day = 15
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: components)!
        let locale = Locale(identifier: "en_US")
        let utc = TimeZone(identifier: "UTC")!
        XCTAssertEqual(
            CaptionFormatter.caption(date: date, location: "Lake Tahoe", locale: locale, timeZone: utc),
            "June 2019 · Lake Tahoe"
        )
        XCTAssertEqual(
            CaptionFormatter.caption(date: date, location: nil, locale: locale, timeZone: utc),
            "June 2019"
        )
        XCTAssertEqual(
            CaptionFormatter.caption(date: date, location: "", locale: locale, timeZone: utc),
            "June 2019",
            "empty location collapses to date only"
        )
    }

    func testLaneCyclingIsAClosedLoop() {
        for lane in Lane.allCases {
            XCTAssertEqual(lane.next.previous, lane)
            XCTAssertEqual(lane.previous.next, lane)
        }
        XCTAssertEqual(Lane.allMemories.next, .onThisDay)
        XCTAssertEqual(Lane.favorites.next, .allMemories)
    }

    func testStyleDwellBiasKeepsClampedEnvelopeReachable() {
        for style in AsciiStyle.allCases {
            XCTAssertGreaterThan(style.dwellBias, 0.8)
            XCTAssertLessThan(style.dwellBias, 1.3)
            XCTAssertFalse(style.displayName.isEmpty)
        }
    }

    func testSeedDerivationIsStableAndDiscriminating() {
        XCTAssertEqual(SeedDerivation.seed(for: "demo-dunes"), SeedDerivation.seed(for: "demo-dunes"))
        XCTAssertNotEqual(SeedDerivation.seed(for: "demo-dunes"), SeedDerivation.seed(for: "demo-aurora"))
    }

    func testPrefsRoundTrip() throws {
        let prefs = ChannelPrefs(speed: .leisurely, startOnWake: false)
        let data = try CouchJSON.encode(prefs)
        XCTAssertEqual(try CouchJSON.decode(ChannelPrefs.self, from: data), prefs)
    }
}
