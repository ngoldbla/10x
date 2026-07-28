// SchoolView.swift — Technique School (PRD-25 §2.3).
//
// One lesson per technique, each a **real position from a real board**. The
// list ships as ten `(seed, difficulty, stepIndex)` triples; the device
// regenerates the puzzle, replays its trace, proves the step is the technique
// the lesson claims, and hands the position to the same `BoardView` everything
// else in Nine is drawn on. `TechniqueSchool` is where all of that lives — this
// file is only the screen.
//
// Three rules the design is holding, all of them PRD-7's:
//
//   • **Nothing locks.** Every lesson is open from the first launch. The list
//     is ordered, not gated, and `CoachProgress` moves exactly one row — the
//     first technique you have not met — to the top. A curriculum that
//     re-sorts itself under someone reading it is worse than one that never
//     moves.
//   • **No score.** A met technique gets a filled dot and an accessibility
//     label. No count on this screen, no percentage, no badge. The one place a
//     number appears is the stats drawer, once, in a sentence.
//   • **The coach still does not place a digit.** A lesson ends by handing the
//     board back: you make the move.
//
// Resolution composes a puzzle — Tempest is ~0.02 s and Sharp ~0.7 s in
// Release — so it happens off the main actor and the row shows a placeholder
// until it lands, exactly as the difficulty cards do while composing.
#if os(iOS) || os(macOS)
import SwiftUI
import CouchKit

struct SchoolView: View {
    let model: AppModel
    let accent: Color
    let onDismiss: @MainActor () -> Void

    @State private var open: TechniqueLesson?
    @State private var loading: Technique?
    @Environment(\.nineTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    /// Rank order, with the first unmet lesson floated to the top.
    private var order: [Technique] {
        model.coachProgress.suggestedOrder(TechniqueSchool.lessons.map(\.technique))
    }

    var body: some View {
        ZStack {
            theme.tones(for: colorScheme).plane.ignoresSafeArea()
            if let open {
                SchoolLessonView(lesson: open, accent: accent) { finished in
                    if finished { model.noteLessonFinished(open.exemplar.technique) }
                    withAnimation(.couchFast) { self.open = nil }
                }
                .transition(.opacity)
            } else {
                list.transition(.opacity)
            }
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Phrase.title)
                        .font(CouchTypography.title)
                    Text(Phrase.subtitle)
                        .font(CouchTypography.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Button(action: onDismiss) { Text(Phrase.close) }
                    .buttonStyle(.plain)
                    .foregroundStyle(accent)
                    .font(CouchTypography.caption)
                    .contentShape(.accessibility, Capsule())
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(order, id: \.self) { technique in
                        row(technique)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: 560)
    }

    private func row(_ technique: Technique) -> some View {
        let met = model.coachProgress.hasMet(technique)
        return Button {
            openLesson(technique)
        } label: {
            HStack(spacing: 14) {
                // A dot, not a checkmark and not a count. It says "you have met
                // this" and stops there; a tick reads as a task completed and
                // this is not a task list.
                Circle()
                    .fill(met ? accent : Color.secondary.opacity(0.25))
                    .frame(width: 8, height: 8)
                Text(Strings.technique(technique))
                    .font(CouchTypography.caption)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                if loading == technique {
                    Text(Strings.string("status.composing"))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .couchGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(loading != nil)
        .accessibilityLabel(Phrase.rowLabel(Strings.technique(technique), met: met))
    }

    /// Compose off the main actor. A lesson that fails to resolve simply does
    /// not open — CI is where a rotted exemplar should be loud, not a player's
    /// phone (`TechniqueSchoolTests`).
    private func openLesson(_ technique: Technique) {
        guard loading == nil,
              let exemplar = TechniqueSchool.lessons.first(where: { $0.technique == technique })
        else { return }
        loading = technique
        Task {
            let lesson = await Task.detached { TechniqueSchool.resolve(exemplar) }.value
            loading = nil
            guard let lesson else { return }
            withAnimation(.couchFast) { open = lesson }
        }
    }
}

/// One lesson: the position, then the pattern, then the board handed back.
private struct SchoolLessonView: View {
    let lesson: TechniqueLesson
    let accent: Color
    /// `true` when the player reached the end rather than backing out.
    let onDismiss: @MainActor (Bool) -> Void

    /// Three beats, and the middle one is the whole lesson: **look before you
    /// are shown.** Revealing the pattern immediately would make this a
    /// diagram; making the player look first is what makes it practice.
    private enum Beat { case look, shown, done }
    @State private var beat: Beat = .look
    @State private var game: NineGame?

    private var technique: Technique { lesson.exemplar.technique }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Strings.technique(technique))
                        .font(CouchTypography.title)
                    Text(detail)
                        .font(CouchTypography.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button { onDismiss(beat == .done) } label: { Text(Phrase.close) }
                    .buttonStyle(.plain)
                    .foregroundStyle(accent)
                    .font(CouchTypography.caption)
                    .contentShape(.accessibility, Capsule())
            }

            if let game {
                GeometryReader { proxy in
                    let side = min(proxy.size.width, proxy.size.height) - 24
                    BoardView(
                        game: game,
                        cursor: lesson.coach.step.cells.first ?? 40,
                        accent: accent,
                        showErrors: false,
                        solvedAt: nil,
                        roseOpen: false,
                        previewDigit: nil,
                        previewPencil: false,
                        // Lit only once the player has asked to be shown.
                        coachFocus: beat == .look ? nil : CoachFocus(.step(lesson.coach)),
                        side: max(120, side),
                        inset: 12
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .aspectRatio(1, contentMode: .fit)
            } else {
                ProgressView().controlSize(.small)
            }

            Button(action: advance) {
                Text(actionTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .couchGlass(in: Capsule())
                    .contentShape(.accessibility, Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(22)
        .frame(maxWidth: 560)
        .task { game = buildGame() }
    }

    private var detail: String {
        switch beat {
        case .look:  return Phrase.lessonLook
        case .shown: return BoardSpeech.coachSentence(.step(lesson.coach))
        case .done:  return Phrase.lessonDone(Strings.technique(technique))
        }
    }

    private var actionTitle: String {
        switch beat {
        case .look:  return Phrase.showMe
        case .shown: return Phrase.gotIt
        case .done:  return Phrase.close
        }
    }

    private func advance() {
        switch beat {
        case .look:  withAnimation(.couchFast) { beat = .shown }
        case .shown: withAnimation(.couchFast) { beat = .done }
        case .done:  onDismiss(true)
        }
    }

    /// The lesson's position as a real `NineGame`: the replayed placements go
    /// in as moves, and the candidate masks go in as pencil marks. The player
    /// is handed the notes because **a technique you cannot see the notes for
    /// is a technique you cannot learn** — every pattern here is a claim about
    /// where a digit can still go.
    private func buildGame() -> NineGame {
        var game = NineGame(puzzle: lesson.puzzle)
        for cell in 0..<81 where lesson.values[cell] != 0 && !lesson.givens[cell] {
            _ = game.place(lesson.values[cell], at: cell)
        }
        for cell in 0..<81 where lesson.values[cell] == 0 {
            for digit in 1...9 where lesson.candidates[cell] & Sudoku.bit(digit) != 0 {
                _ = game.togglePencil(digit, at: cell)
            }
        }
        return game
    }
}

/// Every user-facing literal in this file, in one block (PRD-20's seam).
private enum Phrase {
    static let title = Strings.string("school.title")
    static let subtitle = Strings.string("school.subtitle")
    static let close = Strings.string("school.close")
    static let showMe = Strings.string("school.action.showMe")
    static let gotIt = Strings.string("school.action.gotIt")
    static let lessonLook = Strings.string("school.lesson.look")
    static func lessonDone(_ technique: String) -> String {
        Strings.string("school.lesson.done", .text(technique))
    }
    static func rowLabel(_ technique: String, met: Bool) -> String {
        Strings.string(met ? "school.row.met" : "school.row.new", .text(technique))
    }
}
#endif
