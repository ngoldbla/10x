// VariantChannel.swift — the door between the variant engine and the app.
//
// **It is open now.** PRD-23 shipped this file with the door bolted: `isOpen` was
// `false` outright in Release so the compiler removed the composition entry point
// from the shipping binary, Debug additionally needed `NINE_VARIANTS=1`, and
// `VariantChannelSealTests` greppéd the whole app layer and failed if anything
// named this type. All three were correct for a PRD whose product surface was two
// waves away, and all three are wrong for the PRD that builds it.
//
// What replaced them is not nothing, and the difference is worth reading before
// assuming the seal was simply dropped:
//
//   • `VariantInputSealTests` now seals the **input and wrist** layers instead of
//     the whole app. The old seal asserted a temporary fact ("no variant surface
//     exists yet"); the new one asserts PRD-24's actual claim, which is permanent
//     — the rose is variant-agnostic and the watch is classic-only.
//   • `VariantCorpusTests` freezes variant generation the way the golden corpus
//     freezes classic. PRD-23 needed no corpus because nothing was persisted and
//     no daily depended on it. A channel daily is `(day → seed) → board`, so that
//     is no longer true and the tripwire is now mandatory.
//
// The reason this type still exists at all, rather than callers reaching straight
// for `VariantGenerator`, is `compose`'s contract below: **nil is a first-class
// answer**, and having one door means there is one place that guarantees a caller
// can never be handed a partially-proven board.
import Foundation
import CouchCore

public enum VariantChannel {

    /// Compose a variant board, or nil — because the variant has no supply, or
    /// because the tier could not reach a proven board inside its attempt budget.
    ///
    /// Both of those are nil on purpose and callers must handle it. There is no
    /// partially-proven board to hand a player and no spinner that never ends:
    /// PRD-23's never-spin rule is enforced by `VariantGenerator.attemptBudget`
    /// being calibrated against *attempts* rather than wall-clock, which is the
    /// lesson PRD-17 paid for (a seconds-calibrated budget fired on nearly every
    /// seed and handed out boards a band below their label, while the measured
    /// compose time *improved* — so a timing test would have called it a win).
    ///
    /// A tier whose nil rate is not near zero is a tier that does not ship. Both
    /// shipped rulesets compose 200/200 per tier in Release
    /// (`scripts/thermo-scan.sh`, `scripts/killer-scan.sh`).
    public static func compose(
        seed: UInt64, variant: Variant, tier: VariantTier
    ) -> VariantPuzzle? {
        VariantGenerator.generate(seed: seed, variant: variant, tier: tier)
    }

    /// Compose a channel's daily for a day ordinal.
    ///
    /// This is the whole `(day, channel) → board` primitive, and it is three lines
    /// because the two halves already existed: `DailySeed.seed(forDayOrdinal:)` is
    /// the frozen day→seed function every classic daily has used since 1.0, and
    /// `VariantGenerator.attemptSeed` folds in `Variant.seedSalt` so two channels
    /// never hand out the same board on the same day.
    ///
    /// `seedSalt` is an explicit constant rather than a `hashValue` for the reason
    /// stated where it lives: `String.hashValue` is seeded per process in Swift, so
    /// a hash in the seed path would return a different board on every launch —
    /// the one property the whole corpus discipline exists to protect.
    ///
    /// Every channel daily is `.steady`, matching classic (`AppModel.openToday`).
    /// A daily is the board everyone plays today, so it is not the place to make
    /// the player choose a tier.
    public static func daily(day: Int, channel: Channel.Ledgered) -> VariantPuzzle? {
        compose(
            seed: DailySeed.seed(forDayOrdinal: day),
            variant: channel.variant,
            tier: dailyTier)
    }

    /// The tier every channel daily composes at.
    public static let dailyTier: VariantTier = .steady
}
