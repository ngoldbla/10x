// PrefsSheet.swift — the one allowed secondary surface (suite rule): timer
// on/off (off is the default and the statement), error-highlight on/off, and
// the accent tint. Lives inside CouchKit's GlassSheet; Back dismisses.
import SwiftUI
import CouchKit

struct PrefsSheetContent: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 36) {
            Text("Nine")
                .couchText(CouchTypography.title)
                .padding(.bottom, 8)

            prefRow(
                title: "Timer",
                detail: model.prefs.showTimer ? "Shown" : "Hidden",
                symbol: model.prefs.showTimer ? "clock.fill" : "clock"
            ) {
                model.prefs.showTimer.toggle()
            }

            prefRow(
                title: "Error highlight",
                detail: model.prefs.errorHighlight ? "On" : "Off",
                symbol: model.prefs.errorHighlight ? "checkmark.circle.fill" : "circle"
            ) {
                model.prefs.errorHighlight.toggle()
            }

            accentRow

            Spacer()

            Text("Press Back to return")
                .font(CouchTypography.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var accentRow: some View {
        Button {
            let all = AccentChoice.allCases
            let index = all.firstIndex(of: model.prefs.accent) ?? 0
            model.prefs.accent = all[(index + 1) % all.count]
        } label: {
            HStack(spacing: 24) {
                Circle()
                    .fill(model.prefs.accent.color)
                    .frame(width: 36, height: 36)
                Text("Accent")
                    .font(CouchTypography.body)
                Spacer()
                Text(model.prefs.accent.title)
                    .font(CouchTypography.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
        }
        .buttonStyle(.plain)
    }

    private func prefRow(
        title: String, detail: String, symbol: String, action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 24) {
                Image(systemName: symbol)
                    .font(.system(size: 34, weight: .semibold))
                Text(title)
                    .font(CouchTypography.body)
                Spacer()
                Text(detail)
                    .font(CouchTypography.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
        }
        .buttonStyle(.plain)
    }
}
