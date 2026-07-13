// HelpKit — the suite's guidance vocabulary. Every app shows the same shape
// of help: a control legend (gesture → action rows) inside a glass card,
// auto-shown once on first launch and embedded in the prefs sheet thereafter,
// so no screen ever asks the player to guess what the remote does.
// On iOS the same shapes carry a touch legend and dismiss on tap.
#if os(tvOS) || os(iOS)
import SwiftUI

/// One row of the control legend: an SF Symbol for the gesture, the gesture's
/// couch name ("Swipe", "Click", "Hold ▶︎"), and what it does in this app.
public struct LegendRow: Identifiable, Sendable {
    public let id: String
    public let symbol: String
    public let gesture: String
    public let action: String

    public init(symbol: String, gesture: String, action: String) {
        self.id = gesture + action
        self.symbol = symbol
        self.gesture = gesture
        self.action = action
    }
}

/// The legend list itself — embeddable in a prefs sheet or the HelpOverlay.
public struct ControlLegend: View {
    private let rows: [LegendRow]

    public init(rows: [LegendRow]) {
        self.rows = rows
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 22 * CouchScale.chrome) {
            ForEach(rows) { row in
                HStack(spacing: 24 * CouchScale.chrome) {
                    Image(systemName: row.symbol)
                        .font(.system(size: 30 * CouchScale.chrome, weight: .semibold))
                        .frame(width: 56 * CouchScale.chrome)
                        .foregroundStyle(.secondary)
                    Text(row.gesture)
                        .font(CouchTypography.caption)
                        .frame(width: 210 * CouchScale.chrome, alignment: .leading)
                    Text(row.action)
                        .font(CouchTypography.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

/// First-launch guidance: a centered glass card with the app's one-liner and
/// its control legend. Any click or Back dismisses. This view owns the remote
/// while shown — present it INSTEAD of the screen's `.couchRemote` surface
/// (the Nine sheet pattern: `if showHelp { core.overlay { HelpOverlay(…) } }
/// else { core.couchRemote(…) }`), never stacked on top of a live surface,
/// so focus returns cleanly on dismiss. Gate with
/// `@CouchStored("help.seen") var seen = false`.
public struct HelpOverlay: View {
    private let title: String
    private let tagline: String
    private let rows: [LegendRow]
    private let onDismiss: @MainActor () -> Void

    public init(
        title: String,
        tagline: String,
        rows: [LegendRow],
        onDismiss: @escaping @MainActor () -> Void
    ) {
        self.title = title
        self.tagline = tagline
        self.rows = rows
        self.onDismiss = onDismiss
    }

    public var body: some View {
        let card = ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 44 * CouchScale.chrome) {
                VStack(spacing: 14 * CouchScale.chrome) {
                    Text(title)
                        .couchText(CouchTypography.title)
                    Text(tagline)
                        .font(CouchTypography.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                ControlLegend(rows: rows)
                GlassChip(Self.dismissHint, systemImage: "hand.tap")
                    .opacity(0.7)
            }
            .padding(72 * CouchScale.chrome)
            .frame(maxWidth: 1100 * CouchScale.chrome)
            .couchGlass(in: RoundedRectangle(cornerRadius: 56 * CouchScale.chrome, style: .continuous))
        }
        #if os(tvOS)
        card.couchRemote(interceptsBack: true) { gesture in
            switch gesture {
            case .click, .back, .playPause: onDismiss()
            default: break
            }
        }
        #else
        card
            .contentShape(Rectangle())
            .onTapGesture { onDismiss() }
        #endif
    }

    private static var dismissHint: String {
        #if os(tvOS)
        "Click to start"
        #else
        "Tap to start"
        #endif
    }
}

/// Shared status-line copy for the prefs sheets' Photos section, so all
/// apps explain an empty library the same way.
public enum PhotoStatusLine {
    public static func text(photos: Int, favorites: Int) -> String {
        if photos == 0 {
            return "No photos found — sign into iCloud Photos in Settings"
        }
        if favorites == 0 {
            return "\(photos) photos"
        }
        return "\(photos) photos · \(favorites) favorites"
    }
}
#endif
