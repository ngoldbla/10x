// SharedAppearance.swift — the two appearance facts that cross a device
// boundary (PRD-6).
//
// `NinePrefs` lives in `AppModel.swift` and is deliberately NOT `cloudSynced`:
// controls-at-bottom, board anchor and the rest are properties of a screen, and
// a Mac has no business inheriting an iPhone's thumb reach. Theme and accent
// are different — they are what Nine *looks like*, and a wrist that does not
// match the phone on your other arm reads as a different app.
//
// So this is a sibling top-level key rather than a field on `nine.prefs`
// (EXECUTING-A-PRD §2: an older build's next write erases a field it has no
// property for, and `nine.prefs` ships in every released version). The phone
// publishes; the watch reads; nothing writes it back.
//
// **Raw strings, not the enums.** `ThemeChoice` and `AccentChoice` live in
// `Sources/App/Theme.swift`, which imports SwiftUI — and `Sources/Shared` is
// the `NineShared` SwiftPM target, which builds on Linux. Strings also make the
// decode tolerant for free: a watch meeting a theme it has never heard of falls
// back rather than throwing, and `CouchStored` discards a whole blob when a
// decode throws.
import Foundation

/// Theme and accent, by raw value, mirrored through iCloud KVS.
public struct SharedAppearance: Codable, Equatable, Sendable {
    /// `ThemeChoice.rawValue`; empty means "never published".
    public var theme: String
    /// `AccentChoice.rawValue`; empty means "never published".
    public var accent: String

    public init(theme: String = "", accent: String = "") {
        self.theme = theme
        self.accent = accent
    }

    /// Tolerant by construction: an absent key decodes to the empty string,
    /// which every reader already treats as "use your default".
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `try?` on a `decodeIfPresent` yields `String??` — the outer nil is
        // "the value was the wrong type", the inner is "the key was absent".
        // Both mean the same thing here, so both flatten to "".
        theme = ((try? c.decodeIfPresent(String.self, forKey: .theme)) ?? nil) ?? ""
        accent = ((try? c.decodeIfPresent(String.self, forKey: .accent)) ?? nil) ?? ""
    }

    public static let storeKey = "nine.appearance"
}
