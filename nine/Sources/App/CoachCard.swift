// CoachCard.swift — how a hint looks and reads (PRD-11 11a).
//
// Built to be reused. PRD-25 ("why must this be a seven?") narrates a *chain*
// of steps on the board — "involved cells breathe in sequence, one step at a
// time, no text walls" — which is this same card and this same wash driven from
// an array instead of a single value. So the payload the board takes is one
// `CoachFocus` rather than four loose `BoardView` parameters, and its role
// names are the base/cover/pivot/victim vocabulary PROGRAM-2.0 fixes for trace
// schema v2: a `pivot` appends later without moving the other three.
//
// Every string on screen comes from `BoardSpeech`, which is also exactly what
// VoiceOver speaks. One sentence, one source, one thing for PRD-20 to localize.
import SwiftUI
import CouchKit

/// The cells a hint lights, by the part each plays in it.
///
/// Arrays rather than a `[Int: Role]` dictionary: where two roles land on one
/// cell the draw order decides what the player sees, and dictionary iteration
/// order is not defined.
struct CoachFocus: Equatable, Sendable {
    /// The cells forming the pattern — an accent wash.
    let pattern: [Int]
    /// The cell the step resolves, if any — a stronger ring.
    let target: Int?
    /// Cells losing a candidate — a dashed, dimmer border.
    let victims: [Int]
    /// The digit under discussion, when the step is about exactly one.
    let digit: Int?

    /// Nil for a solved board: the Afterglow owns that moment and nothing
    /// should wash over it.
    init?(_ advice: CoachAdvice) {
        switch advice {
        case .solved:
            return nil
        case .exhausted:
            pattern = []
            target = nil
            victims = []
            digit = nil
        case .contradiction(let cells):
            pattern = cells
            target = nil
            victims = []
            digit = nil
        case .step(let coach):
            pattern = coach.step.cells
            target = coach.step.placement?.cell
            victims = Set(coach.step.eliminations.map(\.cell)).sorted()
            digit = coach.step.digits.count == 1 ? coach.step.digits.first : nil
        }
    }
}

extension CoachAdvice {
    /// The card's one action, or nil when the coach has nothing to offer but
    /// the sentence.
    ///
    /// `autoNotes` suppresses `Mark it`: in that mode the marks are the
    /// machine's and the next placement re-derives them, so a button whose
    /// effect is erased one move later would be a button that lies.
    func actionTitle(autoNotes: Bool) -> String? {
        guard case .step(let coach) = self else { return nil }
        if coach.step.placement != nil { return Phrase.placeIt }
        guard !autoNotes, !coach.step.eliminations.isEmpty else { return nil }
        return Phrase.markIt
    }
}

#if os(iOS)
/// The card: a heading, one sentence, and at most one button. It sits in the
/// free band opposite the controls, which PRD-2 sized precisely so a panel
/// could appear there without the board moving a pixel.
struct CoachCardContent: View {
    let advice: CoachAdvice
    let accent: Color
    let actionTitle: String?
    let onAction: @MainActor () -> Void

    private var title: String { BoardSpeech.coachTitle(advice) }
    private var sentence: String { BoardSpeech.coachSentence(advice) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(accent)
            Text(sentence)
                .font(CouchTypography.caption)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle {
                Button(action: onAction) {
                    Text(actionTitle)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .couchGlass(in: Capsule())
                        .contentShape(.accessibility, Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: 360, alignment: .leading)
        .couchGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        // `.contain`, not `.combine`: the button has to stay its own element or
        // there is no way to activate it, but the heading and the sentence read
        // as the one thing they are.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(CoachCardLabel.spoken(title: title, sentence: sentence))
    }
}
#endif

/// Every user-facing literal in this file, in one block (PRD-20's seam).
///
/// Named `Phrase` like every other block in `Sources/App` — it was `CoachPhrase`
/// until PRD-20, which is exactly the kind of file a `grep "enum Phrase"` misses.
private enum Phrase {
    static let placeIt = Strings.string("coach.action.placeIt")
    static let markIt = Strings.string("coach.action.markIt")
}

/// How the coach's heading and sentence become one utterance.
///
/// Not `private`, and not inside `CoachCardContent`: the iOS game screen posts
/// the identical join as a VoiceOver announcement when the card opens
/// (`TouchUI.toggleCoach`), and the card is fenced to iOS while the announcement
/// is not. One key, so a screen reader hears the same sentence twice rather than
/// two spellings of it.
enum CoachCardLabel {
    static func spoken(title: String, sentence: String) -> String {
        Strings.string("coach.card.label", .text(title), .text(sentence))
    }
}
