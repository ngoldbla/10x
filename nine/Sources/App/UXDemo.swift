// UXDemo.swift — iPhone UX/UI audit prototypes (screenshot-only).
//
// A decision menu, not a shipped feature: each launch-argument flag turns on
// ONE static-state prototype so the before/after pairs can be screenshotted
// from the running app without ~12 rebuilds. All of it is fenced to iOS and
// to the audit flags — with every flag off (the default, and every other
// platform) this file adds nothing to the app's behavior. No StoreKit, no
// engine calls, no persistence writes; the boards below are hand-authored
// static data so a prototype can never depend on live game state.
//
// Relaunch per flag:  xcrun simctl launch booted com.couchsuite.nine -uxdemo.pro
#if os(iOS)
import SwiftUI
import CouchKit

// MARK: - Flag reader

/// Which audit prototype (if any) this launch is showing. Read once from the
/// process arguments; `-uxdemo.<case>` selects a case.
enum UXDemo: String, CaseIterable {
    case coach          // 1  explainable hint
    case pro            // 2  "Nine Pro" paywall
    case archive        // 3  daily archive month grid
    case autonotes      // 4  auto-fill pencil marks
    case erase          // 5  erase petal on the rose (free — table stakes)
    case shield         // 6  streak shield
    case themes         // 8  theme / accent / icon packs
    case variants       // 9  variants teaser (Killer · Thermo)
    case nocturne       // 10 expert difficulty
    case share          // 11 share-your-solve card (free — funnel)
    case rosecounts     // 12 "N left" petal badges (free polish)
    case feedback       // 13 haptics + sound settings group (free polish)

    /// The active prototype for this launch, or nil for a normal run.
    static let active: UXDemo? = {
        let args = ProcessInfo.processInfo.arguments
        return UXDemo.allCases.first { args.contains("-uxdemo.\($0.rawValue)") }
    }()

    /// Prototypes that decorate the real home in place (handled inside
    /// TouchHomeView) rather than as a full-screen overlay scene.
    var isHomeInline: Bool {
        switch self {
        case .variants, .nocturne: return true
        default: return false
        }
    }
}

// MARK: - Overlay host

/// Renders the active full-screen prototype scene over the home. Home-inline
/// prototypes (variants, nocturne) render nothing here — the home draws them.
struct UXDemoLayer: View {
    let model: AppModel

    var body: some View {
        if let demo = UXDemo.active, !demo.isHomeInline {
            switch demo {
            case .coach:      CoachDemo(model: model)
            case .pro:        ProSheetDemo(model: model)
            case .archive:    ArchiveDemo(model: model)
            case .autonotes:  AutoNotesDemo(model: model)
            case .erase:      RoseDemo(model: model, mode: .erase)
            case .shield:     ShieldDemo(model: model)
            case .themes:     ThemePacksDemo(model: model)
            case .share:      ShareCardDemo(model: model)
            case .rosecounts: RoseDemo(model: model, mode: .counts)
            case .feedback:   FeedbackDemo(model: model)
            case .variants, .nocturne: EmptyView()
            }
        }
    }
}

// MARK: - Shared vocabulary

extension AccentChoice {
    /// The accent as it reads on the dark Void surface these demos run on.
    var demoColor: Color { color(isLight: false) }
}

/// The soft sparkles capsule that markets Pro without shouting — used in the
/// home header (rec 2 funnel) and as a section marker inside gated surfaces.
struct ProChip: View {
    var text = "Pro"
    var accent: Color = .white
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
            Text(text)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(accent)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            Capsule().fill(accent.opacity(0.16))
        }
        .overlay { Capsule().strokeBorder(accent.opacity(0.35), lineWidth: 1) }
    }
}

/// A small lock glyph badge — the calm "this is Pro" marker on locked swatches
/// and rows. Never a nag; just a quiet closed padlock.
struct LockBadge: View {
    var size: CGFloat = 22
    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: size, height: size)
            .background { Circle().fill(.black.opacity(0.55)) }
            .overlay { Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1) }
    }
}

/// A left-aligned section label in the sheet grammar the app already uses.
struct DemoSectionHeader: View {
    let text: String
    var trailing: String? = nil
    var body: some View {
        HStack {
            Text(text)
                .font(CouchTypography.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(CouchTypography.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The scrim + trailing glass panel that CouchKit's GlassSheet draws, rebuilt
/// here so a prototype can present its own always-open sheet for a screenshot
/// (the real GlassSheet needs a binding + a host). Same metrics as the kit.
struct DemoSheet<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.45).ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                content
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(22)
            .frame(maxWidth: 380, maxHeight: .infinity)
            .couchGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.trailing, 16)
            .padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }
}

// MARK: - Demo board

/// A hand-authored 9×9 board for the prototype scenes, drawn in Nine's grid
/// language (box washes, given vs. entered tone, optional accent-washed coach
/// cells and pencil candidates). Static data only — never the live game.
struct DemoBoard: View {
    /// 81 givens (0 = empty), the calm face of the board.
    var givens: [Int]
    /// 81 entered digits layered over the givens (0 = none).
    var entered: [Int] = Array(repeating: 0, count: 81)
    /// Cells lit by the coach (accent wash).
    var litCells: Set<Int> = []
    /// The single cell the coach is pointing at (stronger ring).
    var focusCell: Int? = nil
    /// Per-cell pencil candidates, for the auto-notes prototype.
    var notes: [Int: [Int]] = [:]
    var accent: Color = .white
    @Environment(\.nineTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let cell = side / 9
            let tones = theme.tones(for: colorScheme)
            ZStack(alignment: .topLeading) {
                // Box washes: the alternating 3×3 tint the real board uses.
                ForEach(0..<9, id: \.self) { box in
                    let bx = box % 3, by = box / 3
                    if (bx + by) % 2 == 0 {
                        Rectangle()
                            .fill(tones.gridTone.opacity(colorScheme == .light ? 0.05 : 0.04))
                            .frame(width: cell * 3, height: cell * 3)
                            .offset(x: CGFloat(bx) * cell * 3, y: CGFloat(by) * cell * 3)
                    }
                }
                // Coach wash.
                ForEach(Array(litCells), id: \.self) { idx in
                    Rectangle()
                        .fill(accent.opacity(0.22))
                        .frame(width: cell, height: cell)
                        .offset(x: CGFloat(idx % 9) * cell, y: CGFloat(idx / 9) * cell)
                }
                // Digits + notes.
                ForEach(0..<81, id: \.self) { idx in
                    cellContent(idx, cell: cell, tones: tones)
                        .frame(width: cell, height: cell)
                        .offset(x: CGFloat(idx % 9) * cell, y: CGFloat(idx / 9) * cell)
                }
                // Focus ring.
                if let focusCell {
                    RoundedRectangle(cornerRadius: cell * 0.16, style: .continuous)
                        .strokeBorder(accent, lineWidth: 2.5)
                        .frame(width: cell * 0.92, height: cell * 0.92)
                        .offset(x: CGFloat(focusCell % 9) * cell + cell * 0.04,
                                y: CGFloat(focusCell / 9) * cell + cell * 0.04)
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .couchGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func cellContent(_ idx: Int, cell: CGFloat, tones: ThemeTones) -> some View {
        let given = givens[idx]
        let entry = entered[idx]
        if given != 0 {
            Text("\(given)")
                .font(.system(size: cell * 0.5, weight: .semibold, design: .rounded))
                .foregroundStyle(tones.digitTone)
        } else if entry != 0 {
            Text("\(entry)")
                .font(.system(size: cell * 0.5, weight: .semibold, design: .rounded))
                .foregroundStyle(accent)
        } else if let marks = notes[idx], !marks.isEmpty {
            NoteGrid(marks: Set(marks), cell: cell, tone: tones.gridTone)
        }
    }
}

/// The 3×3 corner-note cluster the real board renders inside an empty cell.
private struct NoteGrid: View {
    let marks: Set<Int>
    let cell: CGFloat
    let tone: Color
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { c in
                        let d = r * 3 + c + 1
                        Text(marks.contains(d) ? "\(d)" : " ")
                            .font(.system(size: cell * 0.19, weight: .semibold, design: .rounded))
                            .foregroundStyle(tone.opacity(0.55))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .padding(cell * 0.08)
    }
}

// MARK: - Fixed demo data

enum DemoData {
    /// A solved grid (valid sudoku) — the source of truth for the demo boards.
    static let solved = [
        5,3,4, 6,7,8, 9,1,2,
        6,7,2, 1,9,5, 3,4,8,
        1,9,8, 3,4,2, 5,6,7,
        8,5,9, 7,6,1, 4,2,3,
        4,2,6, 8,5,3, 7,9,1,
        7,1,3, 9,2,4, 8,5,6,
        9,6,1, 5,3,7, 2,8,4,
        2,8,7, 4,1,9, 6,3,5,
        3,4,5, 2,8,6, 1,7,9,
    ]

    /// A denser dot field than MiniBoard's Sharp — the Nocturne preview.
    static let nocturneDensity = 0.82

    /// A mid-game face: keep ~half the givens, blank the rest.
    static func puzzle(keepEvery n: Int = 0) -> [Int] {
        // Deterministic "givens" mask — roughly a real Steady clue count.
        let keep: Set<Int> = [0,2,4,6,8, 10,13,16, 20,22,24, 27,31,35,
                              38,40,42, 45,49,53, 56,58,60, 64,67,70,
                              72,74,76,78,80, 12,29,51]
        return (0..<81).map { keep.contains($0) ? solved[$0] : 0 }
    }
}

/// The Nocturne difficulty preview: MiniBoard's dot field, turned up.
struct DemoNocturneBoard: View {
    let accent: Color
    var body: some View {
        Canvas { context, size in
            let cell = size.width / 9
            for y in 0..<9 {
                for x in 0..<9 {
                    guard CouchHash.noise(x, y, seed: 0x9E) < DemoData.nocturneDensity else { continue }
                    let rect = CGRect(x: CGFloat(x) * cell + cell * 0.3,
                                      y: CGFloat(y) * cell + cell * 0.3,
                                      width: cell * 0.4, height: cell * 0.4)
                    context.fill(Path(ellipseIn: rect), with: .color(accent.opacity(0.85)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
#endif
