// Darkroom — the board (PRD §4.2, §4.3, §4.4). A glass plane over black;
// clue rails on two glass strips; one focusable view, cursor drawn
// in-canvas. Fills paint the hidden photo's actual cell colors.
import SwiftUI
import CouchKit

/// Stages of the develop reveal (PRD §4.5).
enum DevelopPhase: Int, Comparable {
    case solving, held, pixel, mosaic, photo, done
    static func < (lhs: DevelopPhase, rhs: DevelopPhase) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct BoardView: View {
    @Bindable var model: AppModel
    let slot: GridSize

    @State private var chrome = ChromeVisibility()
    @State private var cursorX = 0
    @State private var cursorY = 0
    @State private var cursorCentered = false

    // Momentum cursor: repeated same-direction swipes accelerate.
    @State private var lastMoveDirection: Direction4?
    @State private var lastMoveTime = Date.distantPast
    @State private var momentum = 1

    // Hold + swipe drag-fill; a still hold is the coach ray.
    @State private var holdActive = false
    @State private var draggedDuringHold = false
    @State private var dragRejected = false

    // Contradiction feedback.
    @State private var violatedLine: Violation.Line?
    @State private var shakePulse = 0

    // Coach ray.
    @State private var coachTarget: CoachHint.Target?
    @State private var coachGeneration = 0

    // Undo buffer for the playPause/playPauseLongPress double-fire.
    @State private var lastXToggle: (x: Int, y: Int, at: Date)?

    // The develop.
    @State private var developPhase: DevelopPhase = .solving
    @State private var revealPixel: CGImage?
    @State private var revealMosaic: CGImage?

    private var session: PuzzleSession? { model.session(for: slot) }

    private var violationColor: Color {
        model.prefs.colorblindClues
            ? Color(RGB(72, 150, 226))   // sky — safe for red-green vision
            : Color(RGB(214, 56, 71))    // signal red
    }

    var body: some View {
        // While the prefs sheet is up, the remote surface detaches so the
        // tvOS focus engine can walk the sheet's Buttons (Nine's sheet
        // pattern); Back — GlassSheet's onExitCommand — brings it home.
        if model.showPrefs {
            board
        } else {
            board.couchRemote(chrome: chrome, eightWay: true, interceptsBack: true) { gesture in
                handle(gesture)
            }
        }
    }

    private var board: some View {
        ZStack {
            CouchPalette.void.ignoresSafeArea()

            if let session, let plate = model.plate(for: slot) {
                boardContent(session: session, plate: plate)
            }

            DevelopOverlay(
                phase: developPhase,
                pixel: revealPixel,
                mosaic: revealMosaic,
                photo: model.plate(for: slot)?.image,
                caption: model.plate(for: slot).map(model.caption(for:)) ?? ""
            )
        }
        .overlay { PrefsSheet(model: model) }
        // Both fire again when the prefs branch swaps: render the reveal
        // once, and never recenter the cursor under the player.
        .task {
            guard revealPixel == nil else { return }
            await prepareReveal()
        }
        .onAppear {
            guard !cursorCentered else { return }
            cursorCentered = true
            centerCursor()
        }
    }

    // MARK: - Layout

    @ViewBuilder
    private func boardContent(session: PuzzleSession, plate: AppModel.Plate) -> some View {
        GeometryReader { geo in
            let n = session.size
            let puzzle = session.puzzle
            let clueFont: CGFloat = n >= 20 ? 29 : (n >= 15 ? 32 : 36)
            let clueSlot = clueFont * 1.18
            let maxRowRuns = max(1, puzzle.rowClues.map(\.count).max() ?? 1)
            let maxColRuns = max(1, puzzle.colClues.map(\.count).max() ?? 1)
            let leftRailWidth = CGFloat(maxRowRuns) * clueSlot * 1.15 + 36
            let topRailHeight = CGFloat(maxColRuns) * clueSlot + 32
            let railGap: CGFloat = 14
            let cell = min(
                (geo.size.height - topRailHeight - railGap - 120) / CGFloat(n),
                (geo.size.width - leftRailWidth - railGap - 200) / CGFloat(n)
            )
            let boardSide = cell * CGFloat(n)

            VStack(alignment: .leading, spacing: railGap) {
                HStack(spacing: railGap) {
                    Color.clear.frame(width: leftRailWidth, height: topRailHeight)
                    ColumnClueRail(
                        session: session,
                        cellSize: cell,
                        font: clueFont,
                        railHeight: topRailHeight,
                        violatedLine: violatedLine,
                        violationColor: violationColor,
                        coachTarget: coachTarget,
                        shakePulse: shakePulse
                    )
                    .frame(width: boardSide, height: topRailHeight)
                }
                HStack(spacing: railGap) {
                    RowClueRail(
                        session: session,
                        cellSize: cell,
                        font: clueFont,
                        railWidth: leftRailWidth,
                        violatedLine: violatedLine,
                        violationColor: violationColor,
                        coachTarget: coachTarget,
                        shakePulse: shakePulse
                    )
                    .frame(width: leftRailWidth, height: boardSide)

                    BoardCanvas(
                        session: session,
                        cursorX: cursorX,
                        cursorY: cursorY,
                        showCursor: developPhase == .solving,
                        accent: plate.aura
                    )
                    .frame(width: boardSide, height: boardSide)
                    .padding(10)
                    .couchGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay { coachBeam(cell: cell, boardSide: boardSide) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(developPhase == .solving || developPhase == .held ? 1 : 0)
            .animation(.couchAmbient, value: developPhase)
            .position(x: geo.size.width / 2, y: geo.size.height / 2 + 12)
        }
        .overlay(alignment: .bottomTrailing) {
            coachCooldownRing(session: session)
                .padding(56)
        }
        .overlay(alignment: .bottom) {
            statusWhisper(session: session)
                .padding(.bottom, 40)
        }
    }

    /// The soft light beam that settles on the hinted line (PRD §4.4).
    @ViewBuilder
    private func coachBeam(cell: CGFloat, boardSide: CGFloat) -> some View {
        if let target = coachTarget {
            let gradient = LinearGradient(
                colors: [.clear, .white.opacity(0.16), .clear],
                startPoint: target.isRow ? .top : .leading,
                endPoint: target.isRow ? .bottom : .trailing
            )
            Rectangle()
                .fill(gradient)
                .frame(
                    width: target.isRow ? boardSide : cell,
                    height: target.isRow ? cell : boardSide
                )
                .offset(
                    x: target.isRow ? 0 : cell * CGFloat(target.index) - boardSide / 2 + cell / 2,
                    y: target.isRow ? cell * CGFloat(target.index) - boardSide / 2 + cell / 2 : 0
                )
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }

    /// The glass ring that refills toward the next ray (PRD §4.4).
    @ViewBuilder
    private func coachCooldownRing(session: PuzzleSession) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
            let readiness = session.coach.readiness(at: timeline.date)
            if readiness < 1, developPhase == .solving {
                GlassRing(progress: readiness, lineWidth: 7)
                    .frame(width: 64, height: 64)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private func statusWhisper(session: PuzzleSession) -> some View {
        let plural: String = session.mistakes == 1 ? "" : "s"
        let missteps: String = session.mistakes > 0 ? " · \(session.mistakes) misstep\(plural)" : ""
        Text("Click fill · Play/Pause mark · Hold for hint\(missteps)")
            .font(CouchTypography.caption)
            .foregroundStyle(.secondary)
            .opacity(chrome.isVisible && developPhase == .solving ? 1 : 0)
            .animation(.couchAmbient, value: chrome.isVisible)
    }

    // MARK: - Remote grammar (PRD §4.3)

    private func handle(_ gesture: CouchGesture) {
        if gesture == .back {
            model.returnToWall()
            return
        }
        if developPhase == .done, gesture == .click {
            model.returnToWall()
            return
        }

        guard developPhase == .solving, session != nil else { return }

        switch gesture {
        case .swipe(let direction):
            move(direction)
        case .click:
            guard !holdActive else { return }
            applyMove { $0.toggleFill(x: cursorX, y: cursorY) }
        case .playPause:
            let result = applyMove { $0.toggleX(x: cursorX, y: cursorY) }
            if result == .marked || result == .unmarked {
                lastXToggle = (cursorX, cursorY, Date())
            }
        case .holdBegan:
            holdActive = true
            draggedDuringHold = false
            dragRejected = false
        case .holdEnded:
            let wasDrag = draggedDuringHold
            holdActive = false
            draggedDuringHold = false
            dragRejected = false
            if !wasDrag { fireCoachRay() }
        case .playPauseLongPress:
            // The system already delivered .playPause on press; undo that
            // accidental ✕ toggle before opening prefs.
            if let last = lastXToggle, Date().timeIntervalSince(last.at) < 1.2 {
                applyMove { $0.toggleX(x: last.x, y: last.y) }
                lastXToggle = nil
            }
            model.showPrefs = true
        default:
            break
        }
    }

    private func centerCursor() {
        cursorX = slot.rawValue / 2
        cursorY = slot.rawValue / 2
    }

    private func move(_ direction: Direction4) {
        let now = Date()
        if direction == lastMoveDirection, now.timeIntervalSince(lastMoveTime) < 0.35 {
            momentum = min(momentum + 1, max(1, model.prefs.cursorMomentum))
        } else {
            momentum = 1
        }
        lastMoveDirection = direction
        lastMoveTime = now

        // Drag-fill anchors the cell where the hold began.
        if holdActive && !draggedDuringHold {
            draggedDuringHold = true
            dragFillCursor()
        }
        let steps = holdActive ? 1 : momentum
        for _ in 0..<steps {
            step(direction)
            if holdActive { dragFillCursor() }
        }
    }

    private func step(_ direction: Direction4) {
        let n = slot.rawValue
        switch direction {
        case .up: cursorY = max(0, cursorY - 1)
        case .down: cursorY = min(n - 1, cursorY + 1)
        case .left: cursorX = max(0, cursorX - 1)
        case .right: cursorX = min(n - 1, cursorX + 1)
        }
    }

    private func dragFillCursor() {
        guard !dragRejected else { return }
        let result = applyMove { $0.dragFill(x: cursorX, y: cursorY) }
        if case .some(.rejected) = result {
            // One refusal ends the paint stroke; the cursor keeps moving.
            dragRejected = true
        }
    }

    @discardableResult
    private func applyMove(_ mutate: (inout PuzzleSession) -> MoveResult) -> MoveResult? {
        guard let result = model.updateSession(for: slot, mutate) else { return nil }
        switch result {
        case .rejected(let violation):
            flash(violation)
        case .placed(solvedPuzzle: true):
            startDevelop()
        default:
            break
        }
        return result
    }

    // MARK: - Contradiction feedback (PRD §4.2)

    private func flash(_ violation: Violation) {
        violatedLine = violation.line
        withAnimation(.linear(duration: 0.45)) { shakePulse += 1 }
        let pulse = shakePulse
        Task {
            try? await Task.sleep(nanoseconds: 950_000_000)
            if shakePulse == pulse {
                withAnimation(.couchAmbient) { violatedLine = nil }
            }
        }
    }

    // MARK: - Coach ray (PRD §4.4)

    private func fireCoachRay() {
        guard let session else { return }
        let now = Date()
        guard session.coach.isReady(at: now) else {
            chrome.touch() // wake the ring so the player sees the refill
            return
        }
        guard let hint = CoachRay.hint(for: session) else { return }
        model.updateSession(for: slot) { s in
            s.coach.fire(at: now)
            return .ignored
        }
        coachGeneration += 1
        let generation = coachGeneration
        withAnimation(.couchAmbient) { coachTarget = hint.target }
        Task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if coachGeneration == generation {
                withAnimation(.couchAmbient) { coachTarget = nil }
            }
        }
    }

    // MARK: - The develop (PRD §4.5)

    private func prepareReveal() async {
        guard let plate = model.plate(for: slot),
              let image = plate.image,
              let puzzle = plate.puzzle else { return }
        let n = puzzle.size
        revealPixel = try? await AsciiEngine.shared.render(
            image: image, style: .pixel, grid: .fit(cols: n * 2), seed: puzzle.dateSeed
        )
        revealMosaic = try? await AsciiEngine.shared.render(
            image: image, style: .mosaic, grid: .fit(cols: n * 6), seed: puzzle.dateSeed
        )
    }

    private func startDevelop() {
        guard developPhase == .solving else { return }
        developPhase = .held
        chrome.hide()
        coachTarget = nil
        model.recordDevelop(for: slot) // before the animation: uninterruptible
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            withAnimation(.easeInOut(duration: 1.0)) { developPhase = .pixel }
            try? await Task.sleep(nanoseconds: 1_150_000_000)
            withAnimation(.easeInOut(duration: 1.0)) { developPhase = .mosaic }
            try? await Task.sleep(nanoseconds: 1_150_000_000)
            withAnimation(.easeInOut(duration: 1.2)) { developPhase = .photo }
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            withAnimation(.couchAmbient) { developPhase = .done }
        }
    }
}

// MARK: - Target helpers

extension CoachHint.Target {
    var isRow: Bool {
        if case .row = self { return true }
        return false
    }

    var index: Int {
        switch self {
        case .row(let y): return y
        case .column(let x): return x
        }
    }
}
