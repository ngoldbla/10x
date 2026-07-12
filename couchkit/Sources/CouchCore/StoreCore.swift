import Foundation

/// Canonical JSON coding for everything CouchKit persists. Sorted keys and
/// ISO-8601 dates give stable bytes, so identical values produce identical
/// files (nice for change detection and tests).
public enum CouchJSON {
    public static func encode<T: Encodable>(_ value: T, pretty: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.sortedKeys, .prettyPrinted] : [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
}

/// Pure debounce bookkeeping for `CouchStored`'s write coalescing. Tracks the
/// classic debounce (flush after `interval` of quiet) plus a `maxLatency`
/// backstop so a value that changes continuously still reaches disk.
/// Time is injected — no clocks in here, so it is fully testable.
public struct WriteDebouncer: Sendable, Equatable {
    public let interval: TimeInterval
    /// Upper bound on how long a dirty value may stay unflushed.
    public let maxLatency: TimeInterval
    public private(set) var firstChange: Date?
    public private(set) var lastChange: Date?

    public var isDirty: Bool { firstChange != nil }

    public init(interval: TimeInterval = 0.6, maxLatency: TimeInterval = 3.0) {
        self.interval = interval
        self.maxLatency = max(interval, maxLatency)
    }

    public mutating func recordChange(at now: Date) {
        if firstChange == nil { firstChange = now }
        lastChange = now
    }

    /// True when a flush is due at `now`. Marks the debouncer clean when it
    /// fires, so callers just write on `true`.
    public mutating func shouldFlush(at now: Date) -> Bool {
        guard let first = firstChange, let last = lastChange else { return false }
        let quietElapsed = now.timeIntervalSince(last) >= interval
        let latencyExceeded = now.timeIntervalSince(first) >= maxLatency
        guard quietElapsed || latencyExceeded else { return false }
        firstChange = nil
        lastChange = nil
        return true
    }
}

/// Profile-scoped key namespacing for CouchStore. tvOS shares one box across
/// household members, so anything personal (streaks, progress) is keyed by
/// the active profile.
public enum CouchKeyspace {
    /// `couch.<profile>.<key>`, with both parts sanitized.
    public static func namespacedKey(_ key: String, profile: String = "default") -> String {
        "couch.\(sanitize(profile)).\(sanitize(key))"
    }

    /// Filename (without directory) for a key's JSON document.
    public static func filename(forKey key: String, profile: String = "default") -> String {
        "\(sanitize(profile)).\(sanitize(key)).json"
    }

    /// Keep only `[A-Za-z0-9._-]`; everything else becomes `-`. Empty input
    /// becomes `unnamed` so keys never collapse to nothing.
    public static func sanitize(_ component: String) -> String {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        let cleaned = String(component.map { allowed.contains($0) ? $0 : "-" })
        return cleaned.isEmpty ? "unnamed" : cleaned
    }
}
