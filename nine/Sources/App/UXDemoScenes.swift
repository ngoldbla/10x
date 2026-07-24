// UXDemoScenes.swift — the individual audit prototype scenes (screenshot-only).
// See UXDemo.swift for the flag reader and shared vocabulary. Every view here
// is static-state: it reads model.prefs.accent for tint fidelity but never
// mutates the model, the engine, or persistence.
#if os(iOS)
import SwiftUI
import CouchKit

// MARK: - Shared scene chrome

/// The void backdrop a game-context scene sits on, so it fully replaces the
/// home behind the audit overlay and matches the real app's calm plane.
private struct SceneBackdrop<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            VoidBackground()
            BreathingVoid()
            content
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }
}

/// A faithful copy of the game control bar (reuses the real GlassIconButton),
/// with an optional extra tool inserted for the coach / auto-notes prototypes.
private struct DemoControlBar: View {
    var accent: Color
    /// An extra, "active" tool at the head of the right cluster.
    var tool: (symbol: String, label: String)? = nil
    var body: some View {
        HStack(spacing: 10) {
            GlassIconButton(symbol: "chevron.left", label: "Home") {}
            Spacer()
            if let tool {
                GlassIconButton(symbol: tool.symbol, label: tool.label, active: true, accent: accent) {}
            }
            GlassIconButton(symbol: "pencil", label: "Pencil marks") {}
            GlassIconButton(symbol: "arrow.uturn.backward", label: "Undo") {}
            GlassIconButton(symbol: "gearshape", label: "Settings") {}
        }
        .padding(.bottom, 8)
        .padding(.horizontal, 6)
    }
}

/// The primary glass card the sheets share — a rounded slab.
private struct DemoCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(18)
            .couchGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

// MARK: - 1 · Coach hints

struct CoachDemo: View {
    let model: AppModel
    private var accent: Color { model.prefs.accent.demoColor }

    var body: some View {
        SceneBackdrop {
            VStack(spacing: 12) {
                Spacer(minLength: 8)
                DemoBoard(
                    givens: DemoData.puzzle(),
                    litCells: [1, 9, 11, 19],
                    focusCell: 11,
                    accent: accent
                )
                .frame(width: 360, height: 360)
                .padding(.horizontal, 12)
                Spacer(minLength: 8)
                coachCard
                    .padding(.horizontal, 14)
                DemoControlBar(accent: accent, tool: ("lightbulb.fill", "Show me why"))
            }
        }
    }

    private var coachCard: some View {
        DemoCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(accent)
                    Text("Hidden Single")
                        .font(CouchTypography.body)
                    Spacer()
                    Text("Place it")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(accent)
                }
                Text("Only one square in this box can still take a 7 — the other cells in the box already see one.")
                    .font(CouchTypography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 2 · Nine Pro paywall

struct ProSheetDemo: View {
    let model: AppModel
    private var accent: Color { model.prefs.accent.demoColor }

    private let features: [(String, String)] = [
        ("lightbulb.fill", "Unlimited coach hints"),
        ("wand.and.stars", "Auto-fill pencil notes"),
        ("calendar", "The full daily archive"),
        ("shield.lefthalf.filled", "Streak Shield"),
        ("chart.bar.xaxis", "Rich stats & trends"),
        ("paintpalette.fill", "Every theme, accent & icon"),
        ("moon.stars.fill", "Nocturne — expert puzzles"),
        ("square.on.square", "New variants as they land"),
    ]

    var body: some View {
        DemoSheet {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Nine Pro")
                        .couchText(CouchTypography.title)
                    Spacer()
                    ProChip(accent: accent)
                }
                Text("One purchase. Everything, forever — no subscription.")
                    .font(CouchTypography.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(features, id: \.1) { icon, label in
                        HStack(spacing: 14) {
                            Image(systemName: icon)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(accent)
                                .frame(width: 26)
                            Text(label)
                                .font(CouchTypography.body)
                            Spacer()
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)

                priceButton(title: "Unlock everything", price: "$14.99", note: "One purchase · yours forever", primary: true)

                HStack {
                    Spacer()
                    Text("Restore purchase")
                        .font(CouchTypography.caption)
                        .foregroundStyle(accent)
                    Spacer()
                }
                .padding(.top, 2)

                Text("The daily puzzle and your streak are always free. No subscription, no ads, ever.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func priceButton(title: String, price: String, note: String, primary: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(CouchTypography.body)
                Text(note)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(primary ? .white.opacity(0.8) : .secondary)
            }
            Spacer()
            Text(price)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(primary ? .white : .primary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(primary ? AnyShapeStyle(accent) : AnyShapeStyle(.clear))
        }
        .overlay {
            if !primary {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            }
        }
    }
}

// MARK: - 3 · Daily archive

struct ArchiveDemo: View {
    let model: AppModel
    private var accent: Color { model.prefs.accent.demoColor }
    // A plausible month: solved days scattered, today = 24, past days Pro-locked.
    private let solvedDays: Set<Int> = [18, 19, 20, 22, 23, 24]
    private let today = 24

    var body: some View {
        DemoSheet {
            VStack(alignment: .leading, spacing: 18) {
                Text("Archive")
                    .couchText(CouchTypography.title)
                Text("July 2026")
                    .font(CouchTypography.body)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                    ForEach(1...31, id: \.self) { day in
                        dayCell(day)
                    }
                }

                HStack(spacing: 14) {
                    legend(symbol: "checkmark.circle.fill", tint: accent, text: "Solved")
                    legend(symbol: "circle", tint: .secondary, text: "Unplayed")
                }
                .padding(.top, 4)

                Text("Every past daily, on tap. Deterministic seeds mean the whole year is already here — nothing to download.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Int) -> some View {
        let isToday = day == today
        let solved = solvedDays.contains(day)
        let future = day > today
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isToday ? accent.opacity(0.9) : Color.white.opacity(future ? 0.03 : 0.06))
            if solved {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(accent)
            } else {
                Text("\(day)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(isToday ? Color.white : (future ? Color.white.opacity(0.25) : Color.white.opacity(0.85)))
            }
        }
        .frame(height: 40)
    }

    private func legend(symbol: String, tint: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
            Text(text).font(CouchTypography.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - 4 · Auto notes

struct AutoNotesDemo: View {
    let model: AppModel
    private var accent: Color { model.prefs.accent.demoColor }

    private var notes: [Int: [Int]] {
        // Fill candidates into the empty cells of the demo puzzle.
        let givens = DemoData.puzzle()
        var out: [Int: [Int]] = [:]
        for idx in 0..<81 where givens[idx] == 0 {
            // A believable 2–3 candidate spread seeded off the cell index.
            let base = (idx * 7) % 9 + 1
            let marks = [base, (base % 9) + 1, ((base + 3) % 9) + 1].sorted()
            out[idx] = Array(Set(marks)).sorted()
        }
        return out
    }

    var body: some View {
        SceneBackdrop {
            VStack(spacing: 12) {
                Spacer(minLength: 8)
                DemoBoard(givens: DemoData.puzzle(), notes: notes, accent: accent)
                    .frame(width: 360, height: 360)
                    .padding(.horizontal, 12)
                GlassChip("Auto notes · filled 47 candidates", systemImage: "wand.and.stars")
                Spacer(minLength: 8)
                DemoControlBar(accent: accent, tool: ("wand.and.stars", "Auto notes"))
            }
        }
    }
}

// MARK: - 5 & 12 · Rose petal prototypes (erase / counts)

struct RoseDemo: View {
    let model: AppModel
    enum Mode { case erase, counts }
    let mode: Mode
    private var accent: Color { model.prefs.accent.demoColor }

    var body: some View {
        SceneBackdrop {
            VStack(spacing: 28) {
                Spacer()
                ZStack {
                    FlickRoseView(
                        state: RoseState(pencil: false, focusedIndex: 4),
                        accent: accent,
                        completedDigits: [3, 8],
                        showsFocusRing: true,
                        scale: 0.95
                    )
                    if mode == .counts { countBadges }
                }
                .frame(width: 320, height: 320)
                if mode == .erase { eraseAffordance }
                Spacer()
                captionCard
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
        }
    }

    /// "N left" badge under each petal (rec 12).
    private var countBadges: some View {
        let remaining = [2, 0, 3, 1, 0, 4, 3, 2, 1] // per digit 1…9
        return ForEach(1...9, id: \.self) { digit in
            let off = RoseGeometry.offset(forDigit: digit)
            let spacing: CGFloat = 126 * 0.95
            Text(remaining[digit - 1] == 0 ? "done" : "\(remaining[digit - 1]) left")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(remaining[digit - 1] == 0 ? accent : .secondary)
                .offset(x: off.x * spacing, y: off.y * spacing + 42)
        }
    }

    /// A dedicated erase petal for filled cells (rec 5).
    private var eraseAffordance: some View {
        HStack(spacing: 10) {
            Image(systemName: "eraser.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accent)
            Text("Flick down to erase")
                .font(CouchTypography.body)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .couchGlass(in: Capsule())
    }

    private var captionCard: some View {
        DemoCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(mode == .erase ? "Erase on touch" : "Rose completion counts")
                    .font(CouchTypography.body)
                Text(mode == .erase
                     ? "A wrong digit today can only be walked back with Undo. An erase petal lets any filled cell be cleared in place."
                     : "Each petal shows how many of that digit are still unplaced — chase the number that's almost done.")
                    .font(CouchTypography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 6 · Streak Shield

struct ShieldDemo: View {
    let model: AppModel
    private var accent: Color { model.prefs.accent.demoColor }

    var body: some View {
        SceneBackdrop {
            VStack(alignment: .leading, spacing: 20) {
                Text("Nine").couchText(CouchTypography.title)
                // Header chips — streak now carries a quiet shield glyph.
                HStack(spacing: 10) {
                    chip("625 pts", symbol: "star.fill")
                    shieldChip
                }
                DemoCard {
                    HStack(spacing: 14) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Your streak held")
                                .font(CouchTypography.body)
                            Text("You took yesterday off — Nine kept your 12-day streak safe. Life happens; one rest day won't cost you.")
                                .font(CouchTypography.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var shieldChip: some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill").font(.system(size: 14, weight: .semibold))
            Text("12 day streak").font(CouchTypography.caption)
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .couchGlass(in: Capsule())
    }

    private func chip(_ text: String, symbol: String) -> some View {
        GlassChip(text, systemImage: symbol)
    }
}


// MARK: - 8 · Theme / accent / icon packs

struct ThemePacksDemo: View {
    let model: AppModel
    private var accent: Color { model.prefs.accent.demoColor }

    var body: some View {
        DemoSheet {
            VStack(alignment: .leading, spacing: 24) {
                Text("Appearance").couchText(CouchTypography.title)

                // A wider palette of themes — all just available.
                VStack(alignment: .leading, spacing: 14) {
                    DemoSectionHeader(text: "Theme", trailing: "Auto")
                    swatchRow(extraNames: ["Ember", "Tide", "Mono"],
                              extraColors: [Color(red: 0.5, green: 0.12, blue: 0.05),
                                            Color(red: 0.03, green: 0.28, blue: 0.36),
                                            Color(red: 0.14, green: 0.14, blue: 0.15)])
                }

                VStack(alignment: .leading, spacing: 14) {
                    DemoSectionHeader(text: "Accent", trailing: "Glacier")
                    accentRow
                }

                VStack(alignment: .leading, spacing: 14) {
                    DemoSectionHeader(text: "App icon")
                    iconRow
                }
            }
        }
    }

    private func swatchRow(extraNames: [String], extraColors: [Color]) -> some View {
        let free: [ThemeChoice] = [.dark, .light, .camel, .blueprint, .forest]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(free, id: \.self) { theme in
                    swatch(theme.tones(for: .dark).background, digitTone: theme.tones(for: .dark).digitTone)
                }
                ForEach(Array(extraColors.enumerated()), id: \.offset) { _, c in
                    swatch(c, digitTone: .white)
                }
            }
        }
    }

    private func swatch(_ bg: Color, digitTone: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(bg)
            Text("9").font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(digitTone)
        }
        .frame(width: 34, height: 34)
        .overlay { RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1) }
    }

    private var accentRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AccentChoice.allCases, id: \.self) { a in
                    Circle().fill(a.color).frame(width: 26, height: 26)
                        .overlay { if a == .glacier { Circle().strokeBorder(.primary, lineWidth: 3) } }
                }
                ForEach(0..<2, id: \.self) { i in
                    Circle().fill(LinearGradient(colors: i == 0 ? [.pink, .orange] : [.mint, .cyan],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 26, height: 26)
                }
            }
        }
    }

    private var iconRow: some View {
        HStack(spacing: 12) {
            ForEach(0..<4, id: \.self) { i in
                let bg: [Color] = [CouchPalette.void, Color(red: 0.5, green: 0.12, blue: 0.05),
                                   Color(red: 0.03, green: 0.28, blue: 0.36), Color(red: 0.14, green: 0.14, blue: 0.15)]
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous).fill(bg[i])
                    Text("9").font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(.white)
                }
                .frame(width: 52, height: 52)
                .overlay { RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1) }
            }
        }
    }
}

// MARK: - 11 · Share your solve

struct ShareCardDemo: View {
    let model: AppModel
    private var accent: Color { model.prefs.accent.demoColor }

    var body: some View {
        SceneBackdrop {
            VStack(spacing: 26) {
                Spacer()
                shareCard
                    .frame(width: 300)
                shareRow
                Spacer()
            }
            .padding(.horizontal, 20)
        }
    }

    private var shareCard: some View {
        VStack(spacing: 16) {
            DemoBoard(givens: DemoData.solved, accent: accent)
                .frame(width: 220, height: 220)
            VStack(spacing: 4) {
                Text("Solved in 3:40")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("Steady · 12-day streak")
                    .font(CouchTypography.caption)
                    .foregroundStyle(.secondary)
            }
            Text("NINE")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .tracking(6)
                .foregroundStyle(accent)
        }
        .padding(24)
        .couchGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var shareRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 17, weight: .semibold))
            Text("Share your solve")
                .font(CouchTypography.body)
        }
        .foregroundStyle(accent)
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .couchGlass(in: Capsule())
    }
}

// MARK: - 13 · Feedback settings group

struct FeedbackDemo: View {
    let model: AppModel
    private var accent: Color { model.prefs.accent.demoColor }

    var body: some View {
        DemoSheet {
            VStack(alignment: .leading, spacing: 20) {
                Text("Nine").couchText(CouchTypography.title)
                DemoSectionHeader(text: "Feedback")
                row("Placement haptics", detail: "On", symbol: "hand.tap.fill", on: true)
                row("Solve chime", detail: "On", symbol: "speaker.wave.2.fill", on: true)
                row("Error buzz", detail: "Off", symbol: "exclamationmark.triangle", on: false)
                Text("Haptics and sound aren't screenshottable — this is the new group they'd live in.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(_ title: String, detail: String, symbol: String, on: Bool) -> some View {
        HStack(spacing: 20) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(on ? AnyShapeStyle(accent) : AnyShapeStyle(.secondary))
                .frame(width: 40)
            Text(title).font(CouchTypography.body)
            Spacer()
            Text(detail).font(CouchTypography.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}
#endif
