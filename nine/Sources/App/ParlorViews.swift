// ParlorViews.swift — a dot each, and then the comets (PRD-28 §5, §6).
//
// Every decision about *what* these draw already happened in `ParlorRoom`, which
// is pure and tests on Linux — including the one that matters most: a
// `Member.finish` is nil until the room completes, so **this file cannot draw a
// time early even if somebody later wanted it to.** That is deliberate. PRD-30's
// finding was that a view can render a clock the payload never carried, and the
// answer both times is to make the surface unable to reach the number rather
// than to remember not to.
//
// What is left here is geometry and words.
import SwiftUI
import CouchKit
#if canImport(NineEngine)
import NineEngine
#endif

// MARK: - The dots

/// One soft glow-dot per participant, ordered you-first-then-by-id.
///
/// **Nothing in this row moves on its own.** A dot changes when a message
/// arrives and at no other time — no pulse, no breathing, no shimmer — so a
/// board that reaches 0fps while you think keeps reaching it in a parlor. That
/// is the craft charter's idle-pixel rule, and an ambient presence indicator is
/// exactly the kind of surface it was written for.
struct ParlorPresenceRow: View {
    let room: ParlorRoom
    let accent: Color

    var body: some View {
        HStack(spacing: 9) {
            ForEach(room.members) { member in
                ParlorDot(member: member, fillable: room.fillable, accent: accent)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .couchGlass(in: Capsule())
        // One container so Switch Control's group scan treats the row as a
        // place rather than as N loose circles floating over the board
        // (PRD-19's grouping rule).
        //
        // **Deliberately unlabelled.** PRD-24 lost the channel pager's leading
        // chevron to exactly this: a label on a `.contain` container merges the
        // first child away, and the dot that would vanish here is *yours*.
        .accessibilityElement(children: .contain)
    }
}

/// Somebody's board, as a fill.
private struct ParlorDot: View {
    let member: ParlorRoom.Member
    /// The denominator, which never crossed the wire — everyone composed the
    /// same puzzle, so this is known locally on every device (PRD-28 §4).
    let fillable: Int
    let accent: Color

    /// 18pt of drawn dot. Not 44: the charter's floor is about *interactive*
    /// elements and this row answers no touch at all — there is nothing to tap,
    /// which is most of the point of calling it ambient.
    private static let side: CGFloat = 18

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)

            // The empty dot is always drawn, so a participant at zero is a
            // person who has not started rather than a person who is not there.
            // The zero-state rule ("honest absence over fake data") cuts the
            // other way here: absence would be the dishonest reading.
            context.stroke(
                Path(ellipseIn: rect.insetBy(dx: 1, dy: 1)),
                with: .color(accent.opacity(0.25)), lineWidth: 1
            )

            // The fill is a disc that grows, not an arc that sweeps. An arc is a
            // progress ring, a progress ring is a percentage, and a percentage
            // beside somebody else's percentage is a race.
            let radius = (size.width / 2 - 1.5) * sqrt(member.fraction)
            guard radius > 0 else { return }
            context.fill(
                Path(ellipseIn: CGRect(
                    x: centre.x - radius, y: centre.y - radius,
                    width: radius * 2, height: radius * 2
                )),
                with: .color(accent.opacity(member.isMe ? 0.95 : 0.55))
            )
            // A finished dot gets a hairline ring rather than a checkmark, a
            // colour change or a flourish: the strongest signal this row is
            // allowed to send is "full".
            if member.presence.done {
                context.stroke(
                    Path(ellipseIn: rect.insetBy(dx: 0.5, dy: 0.5)),
                    with: .color(accent.opacity(0.9)), lineWidth: 1.5
                )
            }
        }
        .frame(width: Self.side, height: Self.side)
        .accessibilityElement()
        .accessibilityLabel(ParlorPhrase.dotLabel(isMe: member.isMe))
        .accessibilityValue(ParlorPhrase.dotValue(member, fillable: fillable))
    }
}

// MARK: - Side by side (PRD-28 §6)

/// The payoff: every comet, on small boards, all running the same 5 s loop.
///
/// Shown only when the room has completed, which this view does not check —
/// `ParlorRoom` already did, by handing over a `finish` of nil until then. The
/// order is the dots' order, so **the fastest solve is wherever it happened to
/// be all along.** Sorting this by time is how the feature becomes a
/// leaderboard in one line, and it is the line PRD-27 §7 already refused.
struct ParlorCometsSection: View {
    let members: [ParlorRoom.Member]
    let tones: ThemeTones
    let accent: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Only the members who actually sent one. A participant who left before
    /// the room completed has no comet, and an empty slot for them would be a
    /// hole where a person used to be.
    private var comets: [ParlorRoom.Member] { members.filter { $0.finish != nil } }

    var body: some View {
        if comets.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                Text(ParlorPhrase.sideBySide)
                    // The section head is a rung above its captions rather than
                    // a hand-set 14pt that happened to land near one — and on
                    // the TV the ramp is couch-sized, which a literal never was.
                    .font(CouchTypography.label)
                    .foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 10) {
                    ForEach(comets) { member in
                        cometColumn(member)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cometColumn(_ member: ParlorRoom.Member) -> some View {
        let unpacked = member.finish.flatMap { SolveReplay.unpack($0.packed) }
        VStack(spacing: 5) {
            Group {
                if let unpacked, !unpacked.moves.isEmpty {
                    CometView(
                        puzzle: unpacked.puzzle,
                        moves: unpacked.moves,
                        tones: tones,
                        accent: member.isMe ? accent : accent.opacity(0.65),
                        frozenPhase: reduceMotion ? 1 : nil
                    )
                } else {
                    // An untimed or stripped log has no comet and says so with a
                    // quiet plane rather than with an apology — PRD-26's rule
                    // that a missing timing line is simply absent.
                    //
                    // It used to be a bare `RoundedRectangle.fill(gridTone…)`,
                    // and beside a live comet at the same size that is not "no
                    // moves yet", it is *a picture that failed to load*. The
                    // fix is the material ladder rather than a darker grey: an
                    // inset is a named region **of** the surface it sits on
                    // (`.identity` glass plus a wash), so it reads as a slot
                    // that was left empty on purpose. The dotted ring is the
                    // one mark that says "nothing here" without saying "error"
                    // — the theme's own tone, one step up in opacity from the
                    // plane it sits on, and a single `heading` rung so it is
                    // legible in a 150pt column without ever competing with the
                    // comet drawn beside it.
                    ZStack {
                        Color.clear
                            .couchInset(
                                in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous),
                                tint: tones.gridTone.opacity(tones.isLight ? 0.07 : 0.10))
                        Image(systemName: "circle.dotted")
                            .font(CouchTypography.heading)
                            .foregroundStyle(tones.gridTone.opacity(tones.isLight ? 0.28 : 0.34))
                            // The column speaks as one element with the caption
                            // as its words; a symbol description in front of it
                            // would be VoiceOver reading out the absence.
                            .accessibilityHidden(true)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)

            Text(ParlorPhrase.cometCaption(member))
                // The caption is a clock, and a row of clocks that do not share
                // a column of digits is a row that jitters as the times differ.
                .font(CouchTypography.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 150)
        // The comet is `accessibilityHidden` by its own rule (one picture, one
        // sentence), so the column speaks as one element with the caption as
        // its words.
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Sending

#if os(iOS)
/// A started activity's party URL, wrapped so `.sheet(item:)` can key on it.
struct SentBoard: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// The system share sheet, which SwiftUI has no presenter for when the item
/// only exists after the tap. Fifteen lines rather than a second tap.
struct SystemShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif

// MARK: - Words

/// PRD-28's strings, in one block — the seam PRD-20 established.
enum ParlorPhrase {
    static var activityTitle: String { Strings.string("parlor.activity.title") }
    static var activitySubtitle: String { Strings.string("parlor.activity.subtitle") }
    static var start: String { Strings.string("parlor.start.title") }
    static var startCaption: String { Strings.string("parlor.start.caption") }
    static var sideBySide: String { Strings.string("parlor.sideBySide") }
    static var challenge: String { Strings.string("parlor.challenge") }
    static var inviteAccepted: String { Strings.string("parlor.invite.accepted") }

    static func dotLabel(isMe: Bool) -> String {
        Strings.string(isMe ? "parlor.dot.you" : "parlor.dot.other")
    }

    /// **The value, never the label** — PRD-27's rule, for PRD-27's reason: a
    /// fill changes whenever the board does, and value is the part VoiceOver
    /// re-speaks on every focus move.
    ///
    /// A finished dot says *finished* and nothing else. The local device does
    /// not know anybody's time yet, so there is nothing here to leak.
    static func dotValue(_ member: ParlorRoom.Member, fillable: Int) -> String {
        member.presence.done
            ? Strings.string("parlor.dot.finished")
            : Strings.string("parlor.dot.progress",
                             .int(member.presence.fill), .int(fillable))
    }

    static func cometCaption(_ member: ParlorRoom.Member) -> String {
        let clock = SolveCardFacts.elapsedText(TimeInterval(member.finish?.seconds ?? 0))
        return Strings.string(
            member.isMe ? "parlor.comet.you" : "parlor.comet.other", .text(clock))
    }
}
