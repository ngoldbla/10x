// WatchHomeView.swift — the wrist's front door (PRD-6 §4 Step 2).
//
// A `List`, not the phone's shelf: on watchOS a vertical list is the idiom the
// crown already scrolls and VoiceOver already knows, and a 198pt-wide card
// shelf is a phone layout shrunk until it breaks — the exact failure PRD-6 §1
// says has killed every watch sudoku so far.
//
// Two rows at most. There is no difficulty picker: the watch may only compose
// one band (`WatchComposePolicy.ceiling`), so offering the others would be
// offering something it cannot do. There is no timer — PRD-6 §3 rules it out
// even as a preference, on the grounds that calm × glance = no clock anxiety
// on a device that is already a clock. The daily row and the streak row left
// with the daily system (2026-08-02): the watch is free play, standalone.
#if os(watchOS)
import SwiftUI
import CouchKit

struct WatchHomeView: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        List {
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

    private var composingChip: some View {
        Text(Strings.string("status.composing"))
            .font(CouchTypography.caption)
            .padding(.horizontal, 10 * CouchScale.chrome)
            .padding(.vertical, 5 * CouchScale.chrome)
            .couchGlass()
    }
}
#endif
