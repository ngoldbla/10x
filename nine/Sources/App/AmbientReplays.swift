// AmbientReplays.swift — the first thing Nine has ever drawn on a television
// that nobody is playing (PRD-26 §2.5).
//
// The constraint here is the room, not the screen. This runs unattended, at
// night, in front of people who are talking to each other — so it is
// board-only: no chrome, no text, no title, no progress bar, no counter, no
// sound. It has to pass the roommate test from the doorway, and the only way
// a replay does that is by looking like an object rather than a readout.
//
// It also has to pass the idle-pixel test, which is the harder one for an
// always-on surface: `CometView` draws at 30 fps and the comet is a single
// slow object on a flat ground, so an Apple TV showing this is doing roughly
// what it does showing a screensaver.
import SwiftUI
import CouchKit
#if canImport(NineEngine)
import NineEngine
#endif

#if os(tvOS)

/// Your own solves, one loop each, forever.
struct AmbientReplaysView: View {
    let model: AppModel
    var onExit: () -> Void

    @State private var index = 0
    @State private var loopStart = Date.now
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accent: Color { model.prefs.accent.color(isLight: colorScheme == .light) }

    /// Solved boards that left a replay, newest first — `played` is already in
    /// that order, so this is a filter and not a sort.
    private var replays: [SolveReplay] {
        model.library.played.compactMap { model.replays.replay(for: $0.id) }
    }

    var body: some View {
        ZStack {
            VoidBackground()
            if let replay = current, let puzzle = replay.puzzle {
                CometView(
                    puzzle: puzzle,
                    moves: replay.moves,
                    tones: model.prefs.theme.tones(for: colorScheme),
                    accent: accent,
                    start: loopStart,
                    // Reduce Motion on an ambient surface means *no* motion:
                    // the finished board, held. Freezing beats not offering
                    // the surface at all — the board is still the picture.
                    frozenPhase: reduceMotion ? 1 : nil
                )
                .frame(width: 720, height: 720)
            }
        }
        .ignoresSafeArea()
        // Advance one board per loop. `TimelineView` would redraw the whole
        // stack at 30 fps just to check a clock; a schedule that fires every
        // five seconds is the same behaviour for one wake-up per board.
        .onReceive(
            Timer.publish(every: CometTimeline.loopSeconds, on: .main, in: .common).autoconnect()
        ) { _ in
            guard !replays.isEmpty else { return }
            index = (index + 1) % replays.count
            loopStart = .now
        }
        // **Any button leaves.** A screensaver you have to work out how to
        // dismiss is a screensaver that gets the television turned off. Menu
        // and the directional pad both exit, and so does a click anywhere.
        .onExitCommand(perform: onExit)
        .onMoveCommand { _ in onExit() }
        .onTapGesture(perform: onExit)
        .accessibilityElement()
        .accessibilityLabel(DebriefPhrase.replay)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onExit() }
    }

    private var current: SolveReplay? {
        let all = replays
        guard !all.isEmpty else { return nil }
        return all[index % all.count]
    }
}

/// How long the shelf sits untouched before the replays take over.
///
/// Ninety seconds, and the number is a compromise rather than a preference:
/// short enough that a television left on the shelf becomes something worth
/// looking at, long enough that a player reading the difficulty blurbs — which
/// is a thing this shelf genuinely asks people to do — is never interrupted
/// mid-sentence. Apple TV's own screensaver idles at two minutes, so this
/// stays comfortably inside it and never fights it.
enum AmbientIdle {
    static let seconds: TimeInterval = 90
}

#endif
