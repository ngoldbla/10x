// FeedView — the vertical channel pager plus every piece of glass chrome:
// cartridge label, score chip, verdict card, pause curtain, prefs sheet.
// Paging is our own state (driven by .couchRemote moves), not a ScrollView.
import SwiftUI
import CouchKit

struct FeedView: View {
    let model: FeedModel
    let locker: SpriteLocker
    let chrome: ChromeVisibility

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Array(model.order.enumerated()), id: \.element) { i, game in
                    let rel = model.relativePosition(of: i)
                    if abs(rel) <= 1 {
                        channelPage(game)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .offset(y: CGFloat(rel) * geo.size.height)
                    }
                }
            }
            .animation(model.reduceMotion ? nil : .couchFast, value: model.index)
        }
        .ignoresSafeArea()
        .overlay(alignment: .bottomLeading) { cartridgeLabel }
        .overlay(alignment: .topTrailing) { scoreChip }
        .overlay { verdictCard }
        .overlay { pauseCurtain }
    }

    // MARK: Pages

    @ViewBuilder
    private func channelPage(_ game: GameID) -> some View {
        let session = model.displaySession(for: game)
        GameCanvasView(
            game: game,
            entities: session?.entities ?? [],
            palette: GamePalette(paletteID: model.mutator(for: game).paletteID),
            paletteID: model.mutator(for: game).paletteID,
            locker: locker
        )
    }

    // MARK: Cartridge label (feed chrome, recedes on idle)

    @ViewBuilder
    private var cartridgeLabel: some View {
        if model.mode == .feed {
            let game = model.currentGame
            let best = model.best(for: game)
            let daily = model.mutator(for: game).label
            VStack(alignment: .leading, spacing: 14) {
                GlassChip(labelText(game: game, best: best, daily: daily),
                          systemImage: "gamecontroller.fill")
                GlassChip(game.hint, systemImage: schemeSymbol(game.scheme))
            }
            .padding(.leading, 64)
            .padding(.bottom, 56)
            .opacity(chrome.isVisible ? 1 : 0)
            .blur(radius: chrome.isVisible ? 0 : 10)
            .offset(y: chrome.isVisible ? 0 : 18)
            .animation(chrome.isVisible ? .couchFast : .couchAmbient, value: chrome.isVisible)
        }
    }

    private func labelText(game: GameID, best: Int, daily: String) -> String {
        var text = game.title
        if game == model.order.first { text += " · Daily" }
        text += best > 0 ? " · Best \(best)" : " · New"
        text += " · \(daily)"
        return text
    }

    private func schemeSymbol(_ scheme: Scheme) -> String {
        switch scheme {
        case .clickOnly: return "circle.circle"
        case .swipeSteer: return "arrow.up.and.down.and.arrow.left.and.right"
        case .fourWaySnap: return "square.grid.2x2"
        case .holdRelease: return "dot.circle.and.hand.point.up.left.fill"
        }
    }

    // MARK: In-game score chip

    @ViewBuilder
    private var scoreChip: some View {
        if model.mode == .playing || model.mode == .paused, let live = model.live {
            GlassChip("\(live.score)", systemImage: "bolt.fill")
                .padding(.top, 48)
                .padding(.trailing, 64)
        }
    }

    // MARK: Verdict card — already listening (click retry, swipe ↑ next)

    @ViewBuilder
    private var verdictCard: some View {
        if model.mode == .verdict {
            let game = model.currentGame
            VStack(spacing: 30) {
                Text("\(model.verdictScore)")
                    .couchText(CouchTypography.display)
                Text(model.verdictIsBest
                     ? "New best on \(game.title)"
                     : "Best \(model.best(for: game)) · \(game.title)")
                    .font(CouchTypography.body)
                    .foregroundStyle(.secondary)
                HStack(spacing: 26) {
                    GlassChip("Click · Retry", systemImage: "arrow.counterclockwise")
                    GlassChip("Swipe ↑ · Next channel", systemImage: "arrow.up")
                }
            }
            .padding(.horizontal, 90)
            .padding(.vertical, 64)
            .couchGlass(in: RoundedRectangle(cornerRadius: 52, style: .continuous))
            .transition(.opacity.combined(with: .scale(scale: 1.04)))
            .animation(.couchFast, value: model.mode)
        }
    }

    // MARK: Pause curtain

    @ViewBuilder
    private var pauseCurtain: some View {
        if model.mode == .paused {
            ZStack {
                CouchPalette.void.opacity(0.45).ignoresSafeArea()
                VStack(spacing: 24) {
                    Text("Paused")
                        .couchText(CouchTypography.title)
                    HStack(spacing: 26) {
                        GlassChip("Click · Resume", systemImage: "play.fill")
                        GlassChip("Back · Channel feed", systemImage: "chevron.backward")
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 56)
                .couchGlass(in: RoundedRectangle(cornerRadius: 52, style: .continuous))
            }
            .transition(.opacity)
            .animation(.couchFast, value: model.mode)
        }
    }
}

// MARK: - Prefs sheet (the app's single GlassSheet)

struct PrefsSheetView: View {
    @Bindable var model: FeedModel

    var body: some View {
        GlassSheet(isPresented: $model.showPrefs) {
            VStack(alignment: .leading, spacing: 34) {
                Text("Cartridge")
                    .couchText(CouchTypography.title)

                Text("SPRITES")
                    .font(CouchTypography.caption)
                    .foregroundStyle(.secondary)
                ForEach(SpriteLane.allCases, id: \.rawValue) { lane in
                    Button {
                        model.spriteLane = lane
                    } label: {
                        HStack {
                            Text(lane.title).font(CouchTypography.body)
                            Spacer()
                            if model.spriteLane == lane {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }

                Text("MOTION")
                    .font(CouchTypography.caption)
                    .foregroundStyle(.secondary)
                Button {
                    model.reduceMotion.toggle()
                } label: {
                    HStack {
                        Text("Reduce motion").font(CouchTypography.body)
                        Spacer()
                        Image(systemName: model.reduceMotion ? "checkmark.square" : "square")
                    }
                }

                Spacer()
                Text("Photos become sprites on this Apple TV only.")
                    .font(CouchTypography.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
