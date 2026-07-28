// WatchHomeView.swift — the wrist's front door (PRD-6 §4 Step 2).
//
// A `List`, not the phone's shelf: on watchOS a vertical list is the idiom the
// crown already scrolls and VoiceOver already knows, and a 198pt-wide card
// shelf is a phone layout shrunk until it breaks — the exact failure PRD-6 §1
// says has killed every watch sudoku so far.
//
// Three rows at most, and often two. There is no difficulty picker: the watch
// may only compose one band (`WatchComposePolicy.ceiling`), so offering the
// others would be offering something it cannot do. There is no timer — PRD-6
// §3 rules it out even as a preference, on the grounds that calm × glance = no
// clock anxiety on a device that is already a clock.
#if os(watchOS)
import SwiftUI
import CouchKit

struct WatchHomeView: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        List {
            todayRow
            if model.game != nil, model.solvedAt == nil {
                Button(action: { model.screen = .board }) {
                    Label {
                        Text(Strings.string("shelf.continue.title"))
                    } icon: {
                        Image(systemName: "square.grid.3x3.topleft.filled")
                    }
                }
            }
            Button(action: { model.composeSelfMade() }) {
                Label {
                    // Named from the policy, not from a literal key. The button
                    // and the generator have to agree about which band the
                    // watch can actually make, and only one of them should get
                    // to decide — `WatchSealTests` caught this reading
                    // "difficulty.gentle.title" while the ceiling was a
                    // constant three files away.
                    Text(Strings.difficulty(WatchComposePolicy.ceiling))
                } icon: {
                    Image(systemName: "plus.circle")
                }
            }
            .disabled(model.composing)
        }
        .navigationTitle(Text(Strings.string("watch.app.name")))
        .overlay { if model.composing { composingChip } }
    }

    /// Today's daily, in whichever of its four honest states it is in.
    ///
    /// The one that matters is `waiting`: the watch cannot compose a steady
    /// board, so when the phone has not been in range since midnight there is
    /// no daily, and the row says exactly that rather than spinning forever or
    /// quietly showing yesterday's.
    @ViewBuilder
    private var todayRow: some View {
        if model.todayIsSolved {
            Label {
                VStack(alignment: .leading) {
                    Text(Strings.string("shelf.today.title"))
                    Text(Strings.string("status.solved"))
                        .font(CouchTypography.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(model.accentChoice.color)
            }
        } else if model.dailyIsAvailable {
            Button(action: { model.openDaily() }) {
                Label {
                    Text(Strings.string("shelf.today.title"))
                } icon: {
                    Image(systemName: "sun.max")
                }
            }
        } else {
            Label {
                VStack(alignment: .leading) {
                    Text(Strings.string("shelf.today.title"))
                    Text(Strings.string("watch.today.waiting"))
                        .font(CouchTypography.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "iphone")
            }
            .accessibilityHint(Text(Strings.string("watch.today.waitingHint")))
        }

        if model.displayedStreak > 0 {
            Label {
                Text(BoardSpeech.streakChip(days: model.displayedStreak, held: model.streakHeld))
            } icon: {
                Image(systemName: model.streakHeld ? "shield" : "flame")
            }
            .font(CouchTypography.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var composingChip: some View {
        Text(Strings.string("status.composing"))
            .font(CouchTypography.caption)
            .padding(.horizontal, 10 * CouchScale.chrome)
            .padding(.vertical, 5 * CouchScale.chrome)
            .couchGlass()
    }
}

extension WatchModel {
    var displayedStreak: Int { streak.displayedStreak(today: todayOrdinal) }
    /// The chip wears a shield rather than a flame while it stands on PRD-13's
    /// one-day bridge. Same rule as every other surface, read from the same
    /// cloud-synced `StreakState`.
    var streakHeld: Bool { displayedStreak > 0 && streak.standsOnGrace }
}
#endif
