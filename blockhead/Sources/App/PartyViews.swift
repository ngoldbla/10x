// Party mode: token setup (claim + hold-to-cycle avatars), the handoff card,
// the 8-bit bottom score meters, and the podium with one-click rematch.
import SwiftUI
import CouchKit

// MARK: - Setup

struct PartySetupView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 64) {
            VStack(spacing: 14) {
                Text("PARTY")
                    .font(CouchTypography.caption)
                    .kerning(8)
                    .foregroundStyle(.secondary)
                Text("Claim your seats")
                    .couchText(CouchTypography.title)
            }
            HStack(spacing: 44) {
                ForEach(model.tokens) { token in
                    TokenTile(token: token, isSelected: model.setupSelection == token.id)
                }
            }
            StartSlab(
                isSelected: model.setupSelection == 6,
                enabled: model.canStartParty
            )
            GlassChip("Click to claim · Hold to change avatar", systemImage: "hand.tap")
                .opacity(0.65)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TokenTile: View {
    let token: AppModel.TokenSlot
    let isSelected: Bool

    var body: some View {
        ZStack {
            if token.claimed {
                Image(systemName: AvatarKit.symbol(token.symbolIndex))
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(AvatarKit.color(token.id))
            } else {
                Image(systemName: "plus")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .opacity(0.5)
            }
        }
        .frame(width: 170, height: 170)
        .couchGlassInteractive(in: RoundedRectangle(cornerRadius: 36, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .strokeBorder(
                    token.claimed ? AvatarKit.color(token.id).opacity(0.7) : Color.white.opacity(0.08),
                    lineWidth: 3
                )
        )
        .selectionHalo(isSelected, cornerRadius: 36)
        .animation(.couchFast, value: token)
    }
}

private struct StartSlab: View {
    let isSelected: Bool
    let enabled: Bool

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "play.fill")
                .font(.system(size: 30, weight: .bold))
            Text(enabled ? "Start the show" : "Claim 2–6 seats")
                .font(CouchTypography.body)
        }
        .foregroundStyle(enabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .padding(.horizontal, 54)
        .padding(.vertical, 24)
        .couchGlassInteractive(in: Capsule())
        .opacity(enabled ? 1 : 0.6)
        .selectionHalo(isSelected, cornerRadius: 44)
    }
}

// MARK: - Handoff card

struct HandoffView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 40) {
            if let match = model.match, let player = match.currentPlayer {
                Text("PASS THE REMOTE")
                    .font(CouchTypography.caption)
                    .kerning(8)
                    .foregroundStyle(.secondary)
                Image(systemName: AvatarKit.symbol(player.symbolIndex))
                    .font(.system(size: 160, weight: .bold))
                    .foregroundStyle(AvatarKit.color(player.colorIndex))
                    .padding(54)
                    .background(Circle().fill(AvatarKit.color(player.colorIndex).opacity(0.12)))
                    .overlay(
                        Circle().strokeBorder(
                            AvatarKit.color(player.colorIndex).opacity(0.6), lineWidth: 4
                        )
                    )
                Text("Round \(match.currentRound) of \(match.rounds)")
                    .font(CouchTypography.body)
                    .foregroundStyle(.secondary)
                GlassChip("Click when ready", systemImage: "hand.tap")
            }
        }
        .padding(.horizontal, 120)
        .padding(.vertical, 80)
        .couchGlass(in: RoundedRectangle(cornerRadius: 60, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Bottom score meters (8-bit health bars — sanctioned scoreboard retro)

struct PartyScoreMeters: View {
    let match: PartyMatch

    var body: some View {
        HStack(spacing: 36) {
            ForEach(Array(match.players.enumerated()), id: \.element.id) { index, player in
                meter(
                    player: player,
                    score: match.scores[index],
                    isCurrent: index == match.currentPlayerIndex
                )
            }
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 18)
        .couchGlass(in: Capsule())
    }

    private func meter(player: PartyPlayer, score: Int, isCurrent: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: AvatarKit.symbol(player.symbolIndex))
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(AvatarKit.color(player.colorIndex))
            HStack(spacing: 4) {
                ForEach(0..<match.maxScorePerPlayer, id: \.self) { cell in
                    Rectangle()
                        .fill(
                            cell < score
                                ? AvatarKit.color(player.colorIndex)
                                : Color.white.opacity(0.10)
                        )
                        .frame(width: 16, height: 18)
                }
            }
        }
        .opacity(isCurrent ? 1 : 0.55)
        .animation(.couchFast, value: score)
    }
}

// MARK: - Podium

struct PodiumView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 56) {
            Text("FINAL TALLY")
                .font(CouchTypography.caption)
                .kerning(8)
                .foregroundStyle(.secondary)
            if let match = model.match {
                HStack(alignment: .bottom, spacing: 40) {
                    ForEach(displayOrder(match), id: \.playerIndex) { place in
                        PodiumColumn(place: place, player: match.players[place.playerIndex])
                    }
                }
            }
            GlassChip("Click — rematch · Back — the stage", systemImage: "arrow.counterclockwise")
                .opacity(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Classic podium arrangement: runner-up left, winner center, rest right.
    private func displayOrder(_ match: PartyMatch) -> [PodiumPlace] {
        let places = match.podium()
        guard places.count >= 2 else { return places }
        var order = [places[1], places[0]]
        if places.count > 2 { order.append(contentsOf: places[2...]) }
        return order
    }
}

private struct PodiumColumn: View {
    let place: PodiumPlace
    let player: PartyPlayer

    private var height: CGFloat {
        switch place.rank {
        case 1: 300
        case 2: 230
        default: 180
        }
    }

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: AvatarKit.symbol(player.symbolIndex))
                .font(.system(size: place.rank == 1 ? 96 : 64, weight: .bold))
                .foregroundStyle(AvatarKit.color(player.colorIndex))
            VStack(spacing: 8) {
                Text("\(place.score)")
                    .couchText(CouchTypography.title)
                Text(rankLabel)
                    .font(CouchTypography.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 200, height: height)
            .couchGlass(in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        }
    }

    private var rankLabel: String {
        switch place.rank {
        case 1: "1st"
        case 2: "2nd"
        case 3: "3rd"
        default: "\(place.rank)th"
        }
    }
}
