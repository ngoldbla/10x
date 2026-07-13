// Darkroom — the app model: daily roll curation, session persistence,
// streaks, prefs. All engine calls are pure; compiling runs off-main.
import SwiftUI
import CouchKit
import Observation

/// Preferences behind the single glass sheet (PRD §4.3).
struct Prefs: Codable, Sendable, Equatable {
    /// Max cells per repeated swipe (momentum cursor as simple repeat-move).
    var cursorMomentum: Int = 2
    /// Colorblind-safe clue palette (violation flashes in sky blue).
    var colorblindClues: Bool = false
}

/// One developed memory hanging on the wall.
struct WallEntry: Codable, Sendable, Equatable {
    let puzzleID: String
    let photoID: String
    let slot: Int
    let day: Int
    let caption: String
}

@MainActor @Observable
final class AppModel {

    enum Route: Equatable {
        case wall
        case board(GridSize)
        case memory(GridSize)
    }

    /// One of the three undeveloped plates on the wall.
    struct Plate: Identifiable {
        let slot: GridSize
        var photo: CuratedPhoto?
        var puzzle: Puzzle?
        var session: PuzzleSession?
        var image: CGImage?
        var aura: Color = CouchPalette.fallbackAccent
        var developed = false
        var id: Int { slot.rawValue }
    }

    var route: Route = .wall
    var plates: [Plate] = GridSize.allCases.map { Plate(slot: $0) }
    var selectedPlate = 0
    var streak = 0
    var isLoading = true
    var showPrefs = false
    var showPermission = false
    /// First-run help (design §6). Defaults true so a returning player never
    /// sees a flash of the overlay; the stored truth loads with the roll.
    var helpSeen = true {
        didSet { helpSeenStore.wrappedValue = helpSeen }
    }
    /// The "Hold ▶︎ for settings" chip — flashed once per session on the wall.
    var settingsHintVisible = false
    private var settingsHintFlashed = false
    var prefs = Prefs() {
        didSet { prefsStore.wrappedValue = prefs }
    }

    // MARK: - Persistence

    private let streakStore = CouchStored(
        wrappedValue: StreakState(), "streak", cloudSynced: true
    )
    private let sessionStore = CouchStored(
        wrappedValue: [String: SessionSnapshot](), "sessions"
    )
    private let wallStore = CouchStored(
        wrappedValue: [WallEntry](), "wall"
    )
    private let prefsStore = CouchStored(
        wrappedValue: Prefs(), "prefs"
    )
    private let helpSeenStore = CouchStored(
        wrappedValue: false, "help.seen"
    )

    private var loaded = false

    // MARK: - Daily roll

    func loadDailyIfNeeded() async {
        guard !loaded else { return }
        loaded = true
        prefs = prefsStore.wrappedValue
        helpSeen = helpSeenStore.wrappedValue

        let now = Date()
        let today = Streaks.dayNumber(for: now)
        streak = Streaks.effectiveStreak(streakStore.wrappedValue, today: today)
        if PhotoAccess.canPrompt { showPermission = true }

        let dateSeed = DailyRoll.dateSeed(for: now)
        // Yesterday's in-progress boards are gone with yesterday's roll.
        let snapshots = sessionStore.wrappedValue.filter { $0.key.hasSuffix("|\(dateSeed)") }
        sessionStore.wrappedValue = snapshots

        let photos = await CouchPhotos.onThisDay(limit: 12)
        let developedIDs = Set(wallStore.wrappedValue.map(\.puzzleID))

        for (index, slot) in GridSize.allCases.enumerated() {
            let order = DailyRoll.photoOrder(count: photos.count, slot: slot, dateSeed: dateSeed)
            var candidates: [(puzzle: Puzzle, photo: CuratedPhoto, image: CGImage, buffer: PixelBuffer)] = []

            for photoIndex in order.prefix(6) {
                let photo = photos[photoIndex]
                guard let image = try? await photo.load(maxDimension: 1280),
                      let buffer = AsciiEngine.pixelBuffer(from: image, maxDimension: 512)
                else { continue }
                let size = slot.rawValue
                let photoID = photo.id
                let puzzle = await Task.detached(priority: .userInitiated) {
                    PuzzleCompiler.compile(
                        photoID: photoID, buffer: buffer, size: size, dateSeed: dateSeed
                    )
                }.value
                guard let puzzle else { continue }
                candidates.append((puzzle, photo, image, buffer))
                if puzzle.band == slot.targetBand { break }
            }

            guard let pick = DailyRoll.select(from: candidates.map { $0.puzzle }, target: slot.targetBand),
                  let chosen = candidates.first(where: { $0.puzzle.id == pick.id })
            else { continue }

            var plate = plates[index]
            plate.photo = chosen.photo
            plate.puzzle = pick
            plate.image = chosen.image
            plate.aura = AccentDerivation.accent(from: chosen.buffer)
            plate.session = PuzzleSession(puzzle: pick, restoring: snapshots[pick.id])
            plate.developed = developedIDs.contains(pick.id)
            plates[index] = plate
        }
        isLoading = false
        flashSettingsHintIfNeeded()
    }

    // MARK: - Help + the settings hint

    /// The overlay was clicked away — remember forever, then surface the one
    /// discoverability chip the design allows (design §5, §6).
    func dismissHelp() {
        helpSeen = true
        flashSettingsHintIfNeeded()
    }

    /// Flash "Hold ▶︎ for settings" on the wall: once per session, briefly.
    func flashSettingsHintIfNeeded() {
        guard helpSeen, !settingsHintFlashed else { return }
        settingsHintFlashed = true
        settingsHintVisible = true
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            settingsHintVisible = false
        }
    }

    func resolvePermission(granted: Bool) {
        showPermission = false
        if granted { reloadDaily() }
    }

    private func reloadDaily() {
        loaded = false
        isLoading = true
        plates = GridSize.allCases.map { Plate(slot: $0) }
        Task { await loadDailyIfNeeded() }
    }

    // MARK: - Plate access

    func plateIndex(_ slot: GridSize) -> Int? {
        plates.firstIndex { $0.slot == slot }
    }

    func plate(for slot: GridSize) -> Plate? {
        plateIndex(slot).map { plates[$0] }
    }

    func session(for slot: GridSize) -> PuzzleSession? {
        plate(for: slot)?.session
    }

    /// Mutate a board session and auto-save the snapshot instantly (PRD §4.3).
    @discardableResult
    func updateSession(
        for slot: GridSize,
        _ mutate: (inout PuzzleSession) -> MoveResult
    ) -> MoveResult? {
        guard let index = plateIndex(slot), var session = plates[index].session else {
            return nil
        }
        let result = mutate(&session)
        plates[index].session = session
        var all = sessionStore.wrappedValue
        all[session.puzzle.id] = session.snapshot
        sessionStore.wrappedValue = all
        return result
    }

    // MARK: - Navigation

    func openSelectedPlate() {
        guard plates.indices.contains(selectedPlate) else { return }
        let plate = plates[selectedPlate]
        guard plate.puzzle != nil else { return }
        route = plate.developed ? .memory(plate.slot) : .board(plate.slot)
    }

    func returnToWall() {
        route = .wall
    }

    // MARK: - The develop

    /// Called the moment the final fill lands — before the animation, so a
    /// power cut can't eat a streak.
    func recordDevelop(for slot: GridSize) {
        guard let index = plateIndex(slot), let puzzle = plates[index].puzzle else { return }
        let day = Streaks.dayNumber(for: Date())
        let newState = Streaks.recordingDevelop(streakStore.wrappedValue, day: day)
        streakStore.wrappedValue = newState
        try? streakStore.flushNow() // streaks are precious
        streak = Streaks.effectiveStreak(newState, today: day)

        plates[index].developed = true
        var wall = wallStore.wrappedValue
        if !wall.contains(where: { $0.puzzleID == puzzle.id }) {
            wall.append(WallEntry(
                puzzleID: puzzle.id,
                photoID: puzzle.photoID,
                slot: slot.rawValue,
                day: day,
                caption: caption(for: plates[index])
            ))
            if wall.count > 24 { wall.removeFirst(wall.count - 24) }
            wallStore.wrappedValue = wall
        }
    }

    // MARK: - Copy

    /// "June 2019 · Lake Tahoe" — the chip under a developed memory.
    func caption(for plate: Plate) -> String {
        guard let photo = plate.photo else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        let date = formatter.string(from: photo.displayDate)
        if let location = photo.locationLabel, !location.isEmpty {
            return "\(date) · \(location)"
        }
        return date
    }

    /// The date whispered on an undeveloped plate (PRD §4.1).
    func whisper(for plate: Plate) -> String {
        guard let date = plate.photo?.displayDate else { return "" }
        let years = Calendar.current.dateComponents([.year], from: date, to: Date()).year ?? 0
        switch years {
        case ..<1: return "From this year"
        case 1: return "From a year ago"
        default: return "From \(spelledOut(years)) years ago"
        }
    }

    private func spelledOut(_ n: Int) -> String {
        let words = [
            2: "two", 3: "three", 4: "four", 5: "five",
            6: "six", 7: "seven", 8: "eight", 9: "nine",
        ]
        return words[n] ?? "\(n)"
    }
}

// MARK: - The legend

extension AppModel {
    /// The remote grammar in legend form (design §6). The first-run overlay
    /// shows all six rows; the prefs sheet keeps the first four as a compact
    /// reminder, so the sheet doubles as the manual thereafter.
    static let legendRows: [LegendRow] = [
        LegendRow(symbol: "arrow.up.and.down.and.arrow.left.and.right",
                  gesture: "Swipe", action: "Choose a plate / move on the board"),
        LegendRow(symbol: "hand.tap", gesture: "Click",
                  action: "Develop / fill a square"),
        LegendRow(symbol: "playpause.fill", gesture: "▶︎", action: "Mark ✕"),
        LegendRow(symbol: "rays", gesture: "Hold, release",
                  action: "Hint (the coach ray)"),
        LegendRow(symbol: "gearshape.fill", gesture: "Hold ▶︎",
                  action: "Settings"),
        LegendRow(symbol: "chevron.backward", gesture: "Back",
                  action: "Back to the wall"),
    ]
}
