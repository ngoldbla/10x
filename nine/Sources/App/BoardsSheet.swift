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
                    ProgressRing(fraction: entry.game.fillFraction, accent: accent, scale: s)
                    VStack(alignment: .leading, spacing: 2 * s) {
                        Text(title(for: entry))
                            .font(CouchTypography.body)
                        Text("\(Int((entry.game.fillFraction * 100).rounded()))% · \(Self.format(entry.game.timer.elapsed(at: Date())))")
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
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func title(for entry: LibraryEntry) -> String {
        switch entry.kind {
        case .daily:
            return "Daily · \(entry.createdAt.formatted(date: .abbreviated, time: .omitted))"
        case .free(let difficulty):
            return difficulty.title
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

/// A thin progress ring for a partial's fill fraction.
private struct ProgressRing: View {
    let fraction: Double
    let accent: Color
    let scale: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.25), lineWidth: 3 * scale)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, fraction)))
                .stroke(accent, style: StrokeStyle(lineWidth: 3 * scale, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 26 * scale, height: 26 * scale)
    }
}
#endif
