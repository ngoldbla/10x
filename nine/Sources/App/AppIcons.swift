// AppIcons.swift — the alternate Home Screen icons (PRD-16 §2).
//
// iOS only: a tvOS icon is a layered image stack with no alternate-icon API, and
// macOS has no `setAlternateIconName` outside Mac Catalyst. The asset names here
// must match `ASSETCATALOG_COMPILER_ALTERNATE_APP_ICON_NAMES` in `project.yml`
// and the sets `scripts/generate_brand_assets.swift` emits. Nothing in the
// toolchain checks that agreement for us — a wrong name compiles, ships, and
// fails only when a player taps the swatch — which is why all three live within
// one commit of each other.
//
// State ownership: `UIApplication.alternateIconName` IS the state. It persists
// across launches and app updates on its own and it is what Springboard draws,
// so mirroring it into `NinePrefs` would only create a second copy that can
// disagree with the first — a prefs downgrade would reset the stored value while
// the Home Screen kept the icon, with no honest way to reconcile the two. Prefs
// are not cloudSynced (`AppModel.swift`), so the mirror would buy nothing in
// exchange either. One owner, and it is the system.
import SwiftUI
import CouchKit
#if canImport(UIKit)
import UIKit
#endif

/// The icons a player can choose. `original` is the shipped mark; the other
/// three are the PRD-16 theme grounds. No locks, no unlock order, no counter —
/// all four are available on first launch (PRD-7 §1).
enum AppIconChoice: String, CaseIterable, Sendable {
    case original, ember, tide, mono

    var title: String {
        switch self {
        case .original: return Strings.string("appIcon.original")
        case .ember: return Strings.string("appIcon.ember")
        case .tide: return Strings.string("appIcon.tide")
        case .mono: return Strings.string("appIcon.mono")
        }
    }

    /// The asset-catalog set name, or nil for the primary icon —
    /// `setAlternateIconName(nil)` is how UIKit spells "back to default".
    var assetName: String? {
        switch self {
        case .original: return nil
        case .ember: return "AppIcon-Ember"
        case .tide: return "AppIcon-Tide"
        case .mono: return "AppIcon-Mono"
        }
    }

    /// The ground and mark colors, so the picker can draw a swatch without
    /// loading a 1024×1024 PNG per row. Kept parallel to the `IconVariant`
    /// table in `scripts/generate_brand_assets.swift` by hand — the same
    /// arrangement `AccentChoice.lightBarRGB` uses, for the same reason.
    var swatch: (ground: Color, mark: Color) {
        switch self {
        case .original:
            return (Color(red: 0.06, green: 0.05, blue: 0.14),
                    Color(red: 0.76, green: 0.70, blue: 0.94))
        case .ember:
            return (Color(red: 0.24, green: 0.09, blue: 0.05),
                    Color(red: 0.98, green: 0.86, blue: 0.78))
        case .tide:
            return (Color(red: 0.04, green: 0.20, blue: 0.23),
                    Color(red: 0.76, green: 0.93, blue: 0.94))
        case .mono:
            return (Color(red: 0.19, green: 0.19, blue: 0.20),
                    Color(red: 0.88, green: 0.88, blue: 0.89))
        }
    }
}

#if os(iOS)
@MainActor
enum AppIcons {
    /// Whether this build can swap icons at all. False in some managed and
    /// embedded contexts; the row hides itself rather than offering a control
    /// that silently does nothing.
    static var supported: Bool { UIApplication.shared.supportsAlternateIcons }

    /// The system's answer, not a cached one.
    static var current: AppIconChoice {
        let name = UIApplication.shared.alternateIconName
        return AppIconChoice.allCases.first { $0.assetName == name } ?? .original
    }

    /// Swap the icon. UIKit posts its own "You have changed the icon" alert, so
    /// there is nothing here to confirm. Failures are swallowed deliberately:
    /// every one of them is "the player dismissed the system alert" or "this
    /// device does not allow it", and neither is news. The caller re-reads
    /// `current` afterwards, so a refused change simply leaves the previous
    /// swatch ringed — which is the truth.
    static func select(_ choice: AppIconChoice) async {
        guard supported, UIApplication.shared.alternateIconName != choice.assetName else { return }
        try? await UIApplication.shared.setAlternateIconName(choice.assetName)
    }
}

/// The "App icon" row: four icon-shaped swatches, the current one ringed.
struct AppIconRow: View {
    /// The live accent, resolved for the current ground by the sheet that owns
    /// this row. Passed in rather than read here: this view has no model, and
    /// the one thing it must not do is invent a second answer to "what colour
    /// is this app right now".
    let accent: Color

    @State private var selection: AppIconChoice = .original

    var body: some View {
        if AppIcons.supported {
            // The row's header line and its gutter come from `PrefsSheet`'s own
            // metrics rather than from a second set of numbers here: this row
            // is drawn *inside* that sheet's Appearance card, and it was the
            // third of the four left edges the W4A audit found in one 387pt
            // panel. One vertical for the symbol, one for the label, one row
            // height, in both files.
            VStack(alignment: .leading, spacing: 0) {
                PrefsSheetContent.SwatchHeader(
                    title: Strings.string("prefs.appIcon.title"),
                    symbol: "app.badge.fill",
                    value: selection.title,
                    accent: accent)

                PrefsSheetContent.SwatchFlow(spacing: PrefsSheetContent.Swatch.gap) {
                    ForEach(AppIconChoice.allCases, id: \.self) { choice in
                        Button {
                            Task {
                                await AppIcons.select(choice)
                                selection = AppIcons.current
                            }
                        } label: {
                            iconSwatch(choice)
                        }
                        .buttonStyle(.plain)
                        // Now a statement of fact rather than a correction: the
                        // swatch really is `Hit.min` square. It used to be
                        // `44 * CouchScale.chrome` — 24.2pt drawn on iOS — with
                        // this line quietly telling the accessibility tree 44.
                        .contentShape(
                            .accessibility,
                            RoundedRectangle(
                                cornerRadius: PrefsSheetContent.Swatch.ringRadius,
                                style: .continuous)
                                .size(width: Hit.min, height: Hit.min))
                        .accessibilityLabel(choice.title)
                        .accessibilityAddTraits(choice == selection ? [.isSelected] : [])
                    }
                }
                .padding(.horizontal, PrefsSheetContent.Metrics.gutter)
                .padding(.bottom, PrefsSheetContent.Metrics.cardPadding)
            }
            // Read on appear rather than in the initializer: the system owns
            // this value and can change it behind our back (another scene, a
            // shortcut), so the row asks every time it comes back.
            .onAppear { selection = AppIcons.current }
        }
    }

    /// The icon at swatch size: its ground with the rose's nine marks. A
    /// miniature rather than a photograph of the icon — decoding four
    /// 1024×1024 PNGs to fill four 44 pt squares is the kind of thing that
    /// shows up as a hitch when the sheet opens.
    private func iconSwatch(_ choice: AppIconChoice) -> some View {
        let colors = choice.swatch
        // **Not `44 * CouchScale.chrome`.** That is 24.2pt on iOS — the only
        // platform this file compiles for — so the four icon swatches were a
        // little over half the size the accessibility tree was told they were,
        // with no interactive `contentShape` to make up the difference. A floor
        // that scales is not a floor (`Hit.min`).
        let side = PrefsSheetContent.Swatch.art
        let unit = side / 9
        let isSelected = choice == selection
        // The Home Screen's continuous corner, so the swatch reads as an icon
        // and not as another theme tile.
        let art = RoundedRectangle(cornerRadius: side * Radius.iconSquircle, style: .continuous)
        return ZStack {
            ZStack {
                Rectangle().fill(colors.ground)
                VStack(spacing: unit) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: unit) {
                            ForEach(0..<3, id: \.self) { column in
                                Rectangle()
                                    .fill(colors.mark)
                                    .frame(width: unit * 1.6, height: unit * 1.6)
                                    // The centre pixel carries the icon's secondary,
                                    // exactly as the rendered icon does.
                                    .opacity(row == 1 && column == 1 ? 0.55 : 1)
                            }
                        }
                    }
                }
            }
            .frame(width: side, height: side)
            .clipShape(art)
            .overlay {
                art.strokeBorder(
                    Color.primary.opacity(PrefsSheetContent.Swatch.hairlineTone),
                    lineWidth: PrefsSheetContent.Swatch.hairline)
            }
            // The selection ring is drawn *outside* the art, on the 44pt hit
            // shape, so it never crops the icon it is pointing at — and it is
            // five times the unselected hairline rather than the shipped
            // 1.65-against-1, which was not a difference anybody could see.
            if isSelected {
                RoundedRectangle(
                    cornerRadius: PrefsSheetContent.Swatch.ringRadius, style: .continuous)
                    .strokeBorder(Color.primary, lineWidth: PrefsSheetContent.Swatch.selected)
                    .frame(width: Hit.min, height: Hit.min)
            }
        }
        .frame(width: Hit.min, height: Hit.min)
    }
}
#endif
