// VariantChannel.swift — the only door between the variant engine and the app,
// and it is bolted shut.
//
// PRD-23 is long-lead engine work landing during Wave 1 ("Worthy"), and the
// product surface it eventually feeds — Channels, the shelf page-turn, per-
// variant dailies and streaks — is PRD-24, in Wave 3. The covenant's one-new-
// input-concept-per-release rule and the taste ritual both apply to *that* PRD,
// not this one. So this ships with **no user-facing UI at all**, and the way
// that is guaranteed is mechanical rather than aspirational:
//
//   1. `isOpen` is `false` outright in Release — the compiler removes the
//      composition entry point from the shipping binary.
//   2. Even in Debug it needs `NINE_VARIANTS=1` in the environment, so a
//      developer running the app in Xcode still sees nothing by default.
//   3. `VariantChannelSealTests` greps `Sources/App`, `Sources/Widgets` and
//      `Sources/Shared` and fails if any of them so much as names this type.
//      That is the assertion that survives someone deciding to "just wire up a
//      debug menu" — the seal is a test, not a comment.
//
// The engine below the channel is compiled in every configuration on purpose:
// the Release compose measurements PRD-23 has to report are only meaningful in
// Release, and `scripts/killer-scan.sh` needs `VariantGenerator` to exist there.
// What Release does not get is a way to *reach* it from the app.
import Foundation
import CouchCore

public enum VariantChannel {

    /// Whether the variant channel is reachable in this build. Always false
    /// outside DEBUG.
    public static var isOpen: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["NINE_VARIANTS"] == "1"
        #else
        return false
        #endif
    }

    /// Compose a variant board, or nil — because the channel is shut, because
    /// the variant is not implemented, or because the tier could not reach a
    /// proven board inside its attempt budget.
    ///
    /// Every one of those is nil on purpose. A caller that cannot distinguish
    /// them also cannot accidentally ship one: there is no partially-proven
    /// board to hand a player, and no spinner that never ends.
    public static func compose(
        seed: UInt64, variant: Variant, tier: VariantTier
    ) -> VariantPuzzle? {
        guard isOpen else { return nil }
        return VariantGenerator.generate(seed: seed, variant: variant, tier: tier)
    }
}
