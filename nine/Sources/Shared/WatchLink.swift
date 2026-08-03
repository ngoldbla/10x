// WatchLink.swift — what remains of the iPhone↔wrist link (PRD-6) after the
// daily's removal (product decision, 2026-08-02).
//
// The link existed to courier today's `.steady` daily to a watch that may not
// compose above `.gentle`, and to carry the solve back for streak/history
// bookkeeping. The daily, the streak and the day-keyed bookkeeping are gone,
// so the wire types (`WatchDailyHandoff`, `WatchSolveReport`, `WatchLinkWire`)
// went with them. What stays is the compose ceiling: the watch still builds
// its own boards, and "never above catalog-easy" is still the rule
// (PROGRAM-2.0 "watch never generates above catalog-easy").
import Foundation
#if canImport(NineEngine)
import NineEngine
#endif

// MARK: - What the watch may compose for itself

/// The one place the "never above catalog-easy" rule lives.
///
/// There is no fast-seed catalog in the repo yet (PRD-23 shipped its engine
/// with "catalogs/pantry" explicitly not done), so "catalog-easy" can only mean
/// the easiest band. `WatchSealTests` enforces that nothing under
/// `Sources/Watch` names a `Difficulty` case except through this policy, and
/// that the watch reaches the generator in exactly one place.
public enum WatchComposePolicy {
    /// The hardest band the watch composes on its own.
    public static let ceiling: Difficulty = .gentle

    public static func mayComposeLocally(_ difficulty: Difficulty) -> Bool {
        difficulty == ceiling
    }
}
