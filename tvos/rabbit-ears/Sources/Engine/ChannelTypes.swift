// Rabbit Ears engine vocabulary — pure Swift, no UI.
// Imports: Foundation + CouchCore only (Linux-testable).
import Foundation
import CouchCore

// MARK: - Lanes

/// The channel's content lanes (PRD §4.2, swipe ↑/↓). Cycles in declaration
/// order with wrap-around.
public enum Lane: String, CaseIterable, Codable, Sendable, Hashable {
    case allMemories
    case onThisDay
    case favorites

    public var displayName: String {
        switch self {
        case .allMemories: return "All Memories"
        case .onThisDay: return "On This Day"
        case .favorites: return "Favorites"
        }
    }

    public var next: Lane {
        let all = Lane.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }

    public var previous: Lane {
        let all = Lane.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + all.count - 1) % all.count]
    }
}

// MARK: - Crossfade speed (the prefs sheet's 3 choices)

/// One of three pacing choices. All dwell ranges stay inside the PRD's
/// 20–40 s envelope and every fade is ≥ 3 s.
public enum CrossfadeSpeed: String, CaseIterable, Codable, Sendable, Hashable {
    case brisk
    case standard
    case leisurely

    public var displayName: String {
        switch self {
        case .brisk: return "Brisk"
        case .standard: return "Standard"
        case .leisurely: return "Leisurely"
        }
    }

    /// How long a photo dwells before the next crossfade begins.
    public var dwellRange: ClosedRange<TimeInterval> {
        switch self {
        case .brisk: return 20...26
        case .standard: return 25...33
        case .leisurely: return 32...40
        }
    }

    /// Crossfade duration (PRD: ≥ 3 s).
    public var fadeDuration: TimeInterval {
        switch self {
        case .brisk: return 3.0
        case .standard: return 4.5
        case .leisurely: return 6.0
        }
    }
}

// MARK: - Style pacing + labels

extension AsciiStyle {
    /// Style-dependent dwell multiplier (PRD §4.1: "20–40s, style-dependent").
    /// Gentler, more photographic styles linger; busy ones move on sooner.
    /// The director clamps the biased dwell back into its 20–40 s envelope.
    public var dwellBias: Double {
        switch self {
        case .terminal: return 1.0
        case .phosphor: return 1.06
        case .pixel: return 0.94
        case .inkline: return 1.1
        case .mosaic: return 1.16
        }
    }

    public var displayName: String {
        switch self {
        case .terminal: return "Terminal"
        case .phosphor: return "Phosphor"
        case .pixel: return "Pixel"
        case .inkline: return "Ink Line"
        case .mosaic: return "Mosaic"
        }
    }
}

// MARK: - Preferences

/// Everything behind the one GlassSheet. Codable for @CouchStored.
public struct ChannelPrefs: Codable, Sendable, Equatable {
    public var speed: CrossfadeSpeed
    public var startOnWake: Bool

    public init(speed: CrossfadeSpeed = .standard, startOnWake: Bool = true) {
        self.speed = speed
        self.startOnWake = startOnWake
    }

    public static let `default` = ChannelPrefs()
}

// MARK: - Caption formatting

/// "June 2019 · Lake Tahoe" — the caption chip's text.
public enum CaptionFormatter {
    public static func caption(
        date: Date,
        location: String?,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMMM yyyy"
        let dateText = formatter.string(from: date)
        if let location, !location.isEmpty {
            return "\(dateText) · \(location)"
        }
        return dateText
    }
}

// MARK: - Morph grid

/// The hold-to-morph gesture crossfades through a coarser cell grid so the
/// glyphs visibly re-sort themselves (sanctioned simplification of the
/// character-space morph).
public enum MorphGrid {
    public static func coarseCols(fineCols: Int) -> Int {
        max(24, fineCols / 2)
    }
}

// MARK: - Seed derivation

/// Stable per-photo seed (FNV-1a over the photo id) so drift and render
/// noise are deterministic for a given photo across sessions.
public enum SeedDerivation {
    public static func seed(for id: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}
