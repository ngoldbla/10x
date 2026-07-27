// BoardsSheet.swift — the board tracker (playtest fix D4). Lists every board
// the library holds: in-progress partials (resume / archive / delete) and the
// "previously played" log (solved + archived, delete only). Follows the
// HistorySheetContent pattern — a chrome-scaled GlassSheet body shared by iOS,
// macOS and tvOS, with an optional focusable close control for the TV.
#if os(iOS) || os(macOS) || os(tvOS)
import SwiftUI
import CouchKit

struct BoardsSheetContent: View {
    let model: AppModel
    /// tvOS: a focusable dismiss control so the remote/pad can always leave.
    /// On iOS/macOS the scrim tap / window chrome dismisses. Also called after
    /// a resume so the presenting binding resets.
    var onClose: (@MainActor () -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color { model.prefs.accent.color(isLight: colorScheme == .light) }

    /// TV read distance wants everything larger; iOS/macOS stay pixel-identical.
    private var s: CGFloat {
        #if os(tvOS)
        1.7
        #else
        1.0
        #endif
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24 * s) {
                header

                freshBoardSection

                if model.partials.isEmpty && model.playedBoards.isEmpty {
                    Text("Start a board and it lands here — resume it any time, or archive it for later.")
                        .font(CouchTypography.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    if !model.partials.isEmpty { inProgressSection }
                    if !model.playedBoards.isEmpty { playedSection }
                }

                Spacer(minLength: 12)

                #if os(tvOS)
                Text("Press Back to return")
                    .font(CouchTypography.caption)
                    .foregroundStyle(.tertiary)
                #elseif !os(macOS)
                Text("Tap outside to return")
                    .font(CouchTypography.caption)
                    .foregroundStyle(.tertiary)
                #endif
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Boards")
                .couchText(CouchTypography.title)
            #if os(tvOS)
            if let onClose {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 22 * s, weight: .semibold))
                        .padding(18 * s)
                        .couchGlassInteractive(in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close boards")
            }
            #endif
        }
        .padding(.bottom, 4)
    }

    // MARK: - Fresh board (PRD-34)

    /// The second of "New game"'s three new homes. This sheet is the one place
    /// in the app that already means *boards, all of them* — so the row that
    /// makes one belongs at the top of it, above the list it will add to,
    /// rather than at the bottom of Settings where the live audit found it.
    private var freshBoardSection: some View {
        VStack(alignment: .leading, spacing: 12 * s) {
            Text("Fresh board")
                .font(CouchTypography.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 10 * s) {
                ForEach(Difficulty.allCases, id: \.self) { difficulty in
                    Button {
                        model.startFree(difficulty)
                        onClose?()
                    } label: {
                        Text(Strings.difficulty(difficulty))
                            .font(CouchTypography.caption)
                            .foregroundStyle(accent)
                            .frame(maxWidth: .infinity)
                            // 14, not 12: measured at 40pt in the sim, and the
                            // craft charter's floor for a tap target is 44.
                            .padding(.vertical, 14 * s)
                            // Glass on glass is invisible: inside a GlassSheet
                            // `couchGlassInteractive` rendered these three as
                            // bare text with no affordance at all (verified in
                            // the sim). A tinted fill and hairline is the least
                            // ink that still reads as "these are buttons".
                            .background(accent.opacity(0.12), in: Capsule())
                            .overlay { Capsule().strokeBorder(accent.opacity(0.35), lineWidth: 1) }
                            .contentShape(.accessibility, Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New \(Strings.difficulty(difficulty)) board")
                }
            }
            // The board you are on is never destroyed by this: it stays in
            // the library, one row below, exactly where you left it.
            Text("Your current board stays in this list")
                .font(.system(size: 11 * s, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - In progress

    private var inProgressSection: some View {
        VStack(alignment: .leading, spacing: 12 * s) {
            Text("In progress")
                .font(CouchTypography.caption)
                .foregroundStyle(.secondary)
            ForEach(model.partials) { entry in
                partialRow(entry)
            }
        }
    }

    private func partialRow(_ entry: LibraryEntry) -> some View {
        HStack(spacing: 12 * s) {
            Button {
                model.resumeEntry(id: entry.id)
                onClose?()
            } label: {
                HStack(spacing: 12 * s) {
                    // PRD-22: the same board portrait the shelf shows, so a
                    // row here and a row there are recognisably one board.
                    BoardFingerprint(game: entry.game, accent: accent, side: 30 * s)
                    VStack(alignment: .leading, spacing: 2 * s) {
                        Text(title(for: entry))
                            .font(CouchTypography.body)
                        Text("\(BoardProgressCaption.text(for: entry.game)) · \(Self.format(entry.game.timer.elapsed(at: Date())))")
                            .font(.system(size: 11 * s, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Spacer(minLength: 8)
                }
                .padding(14 * s)
                .couchGlassInteractive(in: RoundedRectangle(cornerRadius: 16 * s, style: .continuous))
            }
            .buttonStyle(.plain)

            iconButton("archivebox", label: "Archive board") { model.archiveEntry(id: entry.id) }
            iconButton("xmark.circle.fill", label: "Delete board") { model.deleteEntry(id: entry.id) }
        }
    }

    // MARK: - Previously played

    private var playedSection: some View {
        VStack(alignment: .leading, spacing: 12 * s) {
            Text("Previously played")
                .font(CouchTypography.caption)
                .foregroundStyle(.secondary)
            ForEach(model.playedBoards) { entry in
                playedRow(entry)
            }
        }
    }

    private func playedRow(_ entry: LibraryEntry) -> some View {
        HStack(spacing: 12 * s) {
            Image(systemName: entry.status == .archived ? "archivebox" : "checkmark.circle")
                .font(.system(size: 16 * s, weight: .semibold))
                .foregroundStyle(entry.status == .archived ? AnyShapeStyle(.secondary) : AnyShapeStyle(accent))
                .frame(width: 26 * s)
            VStack(alignment: .leading, spacing: 2 * s) {
                Text(title(for: entry))
                    .font(CouchTypography.body)
                Text(statusLine(for: entry))
                    .font(.system(size: 11 * s, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            iconButton("xmark.circle.fill", label: "Delete board") { model.deleteEntry(id: entry.id) }
        }
        .padding(.vertical, 4 * s)
    }

    // MARK: - Bits

    private func iconButton(_ symbol: String, label: String, action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18 * s, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44 * s, height: 44 * s)
                .couchGlass(in: Circle())
                // Without this the AX frame collapses to the glyph's tight
                // bounds (~18pt) — see GlassIconButton for the same fix.
                .contentShape(.accessibility, Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func title(for entry: LibraryEntry) -> String {
        switch entry.kind {
        case .daily(let day):
            // The daily's own day, not `createdAt` (PRD-14). The two were the
            // same date for every board that could exist before the archive, so
            // reading `createdAt` was invisibly wrong; open 13 July from the
            // archive today and the tracker listed it as "Daily · Jul 26".
            return "Daily · \(ArchiveCalendar.mediumLabel(forDayOrdinal: day))"
        case .free(let difficulty):
            return Strings.difficulty(difficulty)
        }
    }

    private func statusLine(for entry: LibraryEntry) -> String {
        let date = (entry.solvedAt ?? entry.updatedAt).formatted(date: .abbreviated, time: .omitted)
        if entry.status == .solved {
            return "Solved · \(date) · \(Self.format(entry.game.timer.elapsed(at: Date())))"
        }
        return "Archived · \(date)"
    }

    private static func format(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// PRD-22 retired this file's `ProgressRing` in favour of `BoardFingerprint`.
// The ring's 0.02 floor was the right instinct — a board is never *nothing* —
// but an arc that short is indistinguishable from the next board's, and a
// portrait made of the givens tells you which board it is instead of only how
// far along it is. Deleted rather than kept dormant: dead view code drifts.
#endif
