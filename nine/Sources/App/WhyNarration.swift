// WhyNarration.swift — "why must this be a seven?", on the board (PRD-25).
//
// The shape of this feature is one sentence long: **narrate on the board, one
// step at a time, never a text wall.** Everything below is that sentence
// defended against the four ways it usually breaks.
//
//   • **No scroll, no paragraph.** A beat is a heading, one sentence, and one
//     line saying what it did to the square the player pointed at. The chain is
//     shown six beats at most (`Derivation.narrationLimit`); past that the last
//     six are the ones nearest the answer, and the card says so rather than
//     silently truncating.
//   • **Never auto-advances.** A player reading a proof sets the pace. There is
//     one button and it says Next.
//   • **The coach still does not place a digit** (PRD-7's constitution). The
//     last beat offers *Place it*, which routes through the ordinary
//     `model.place` — the same door PRD-11's card uses, with the same wave, the
//     same error rules and the same persistence.
//   • **It is a presentation, not board state.** Dismissing changes nothing,
//     and nothing about it survives leaving the screen. Same reasoning that put
//     `coachAdvice` in the screen rather than in `AppModel`.
//
// The board payload is `CoachFocus`, unchanged in kind from PRD-11 — the wash,
// the dashes and the ring, driven from an array instead of a single value,
// which is what `CoachCard.swift`'s header said this would be.
import SwiftUI
import CouchKit

/// A narration in progress: the derivation, and which beat is on screen.
///
/// A value, not a reference: it lives in `@State` on the screen that opened it,
/// and every transition below returns a new one rather than mutating shared
/// state that a re-render could catch half-applied.
struct WhyNarration: Equatable {
    let derivation: Derivation
    /// Index into `derivation.narrated` — the tail the card shows.
    var beatIndex: Int

    init(_ derivation: Derivation) {
        self.derivation = derivation
        self.beatIndex = 0
    }

    var beats: [DerivedStep] { Array(derivation.narrated) }
    var beat: DerivedStep? { beats.indices.contains(beatIndex) ? beats[beatIndex] : nil }
    var isLast: Bool { beatIndex >= beats.count - 1 }
    var focus: CoachFocus? { beat.map { CoachFocus($0, asked: derivation.cell) } }

    /// One-based, for the "step 2 of 4" line. Counts the *narrated* beats,
    /// because that is what the player can actually page through — claiming
    /// "step 2 of 40" while offering four cards would be a different lie.
    var position: Int { beatIndex + 1 }
    var total: Int { beats.count }

    mutating func advance() {
        beatIndex = min(beatIndex + 1, max(0, beats.count - 1))
    }

    /// The placement the final beat offers, or nil while the chain is still
    /// ruling candidates out.
    var offeredPlacement: Placement? {
        guard isLast, let beat, beat.places != nil else { return nil }
        return beat.coach.step.placement
    }
}

/// What the board says when it cannot answer.
///
/// Separate from `WhyNarration` rather than a case of it, because a refusal has
/// no beats to page through and folding it in would give every call site an
/// `isEmpty` check it would eventually forget.
struct WhyRefusal: Equatable {
    let refusal: DerivationRefusal

    var title: String {
        switch refusal {
        case .contradiction: return Phrase.slipTitle
        case .beyond, .alreadyFilled: return Phrase.beyondTitle
        }
    }

    var sentence: String {
        switch refusal {
        case .contradiction: return Phrase.slip
        case .beyond, .alreadyFilled: return Phrase.beyond
        }
    }

    /// The contradiction's cells get the same wash a hint's would — pointed at
    /// from the grid alone, never from a solution, so it is identical whether
    /// `showErrors` is on or off (PRD-19's rule, PRD-11's implementation).
    var focus: CoachFocus? {
        guard case .contradiction(let cells) = refusal else { return nil }
        return CoachFocus(pattern: cells, target: nil, victims: [], digit: nil)
    }
}

#if os(iOS) || os(macOS)
/// One beat, in the free band the coach card already lives in.
struct WhyCardContent: View {
    let narration: WhyNarration
    let accent: Color
    let onNext: @MainActor () -> Void
    let onPlace: @MainActor (Placement) -> Void

    private var heading: String { Phrase.heading(narration.derivation.digit) }

    /// The technique's own sentence, then one line about this square. Two
    /// sentences maximum, and the second is the only thing this feature adds to
    /// what PRD-11 already said.
    private var sentence: String {
        guard let beat = narration.beat else { return "" }
        let technique = BoardSpeech.coachSentence(.step(beat.coach))
        let effect = Phrase.effect(of: beat, digit: narration.derivation.digit)
        return technique.isEmpty ? effect : technique + " " + effect
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(heading)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(accent)
                Spacer(minLength: 8)
                Text(Phrase.position(narration.position, of: narration.total))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if let beat = narration.beat {
                Text(BoardSpeech.coachTitle(.step(beat.coach)))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Text(sentence)
                .font(CouchTypography.caption)
                .fixedSize(horizontal: false, vertical: true)

            // The two honesty lines. Both are conditional and both stay off the
            // screen when they would be zero — a permanent "and 0 steps
            // elsewhere" is noise that teaches the eye to skip the line that
            // sometimes matters.
            if narration.derivation.untold > 0 {
                Text(Phrase.untold)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            if narration.derivation.elsewhere > 0 {
                Text(Phrase.elsewhere)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            if let placement = narration.offeredPlacement {
                action(Phrase.placeIt) { onPlace(placement) }
            } else if !narration.isLast {
                action(Phrase.next, then: onNext)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: 360, alignment: .leading)
        .couchGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(CoachCardLabel.spoken(title: heading, sentence: sentence))
    }

    private func action(_ title: String, then perform: @escaping @MainActor () -> Void) -> some View {
        Button(action: perform) {
            Text(title)
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

/// A refusal, in the same frame so the band never changes shape.
struct WhyRefusalContent: View {
    let refusal: WhyRefusal
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(refusal.title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(accent)
            Text(refusal.sentence)
                .font(CouchTypography.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: 360, alignment: .leading)
        .couchGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(CoachCardLabel.spoken(title: refusal.title,
                                                  sentence: refusal.sentence))
    }
}
#endif

/// Every user-facing literal in this file, in one block (PRD-20's seam).
private enum Phrase {
    static func heading(_ digit: Int) -> String {
        Strings.string("why.heading", .int(digit))
    }
    static func position(_ step: Int, of total: Int) -> String {
        Strings.string("why.position", .int(step), .int(total))
    }
    static let next = Strings.string("why.action.next")
    static let placeIt = Strings.string("coach.action.placeIt")
    static let untold = Strings.string("why.untold")
    static let elsewhere = Strings.string("why.elsewhere")
    static let slipTitle = Strings.string("coach.slip.title")
    static let slip = Strings.string("coach.slip.sentence")
    static let beyondTitle = Strings.string("why.beyond.title")
    static let beyond = Strings.string("why.beyond.sentence")

    /// What this beat did to the square the player asked about.
    ///
    /// **One whole entry per rendering, chosen by count in Swift** — the rule
    /// `coachBoxLine` and `coachNakedPair` already follow, and it is why there
    /// is no plural machinery here. A list of digits joined with a comma would
    /// be English's list grammar exported to nine languages that do not share
    /// it; three sentences, each written in the target language, is the version
    /// a translator can actually do.
    ///
    /// Past two, the count stops being the point: the player needs to know the
    /// square got narrower, not to audit which four digits went.
    static func effect(of beat: DerivedStep, digit: Int) -> String {
        if beat.places != nil { return Strings.string("why.effect.leaves", .int(digit)) }
        switch beat.ruledOut.count {
        case 0:  return ""
        case 1:  return Strings.string("why.effect.rulesOutOne", .int(beat.ruledOut[0]))
        case 2:  return Strings.string("why.effect.rulesOutTwo",
                                       .int(beat.ruledOut[0]), .int(beat.ruledOut[1]))
        default: return Strings.string("why.effect.rulesOutMore")
        }
    }
}
