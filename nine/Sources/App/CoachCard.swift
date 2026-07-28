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
