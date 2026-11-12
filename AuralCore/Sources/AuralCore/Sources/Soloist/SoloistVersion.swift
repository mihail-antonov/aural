import Foundation

/// Version and expiry of a Soloist build, read from `soloist --version`, e.g.
/// `soloist 1.3.10.65 build 1794463304 (20261112) (g19412df6ea) (macos/aarch64)`.
public struct SoloistVersion: Sendable, Equatable {
    /// Soloist builds stop working 90 days after their build date (exit code 10).
    public static let lifetimeDays = 90

    public let version: String
    /// Start of the build day, UTC.
    public let buildDate: Date

    public var expiryDate: Date {
        buildDate.addingTimeInterval(TimeInterval(Self.lifetimeDays * 24 * 60 * 60))
    }

    public func isExpired(at date: Date = .now) -> Bool {
        date >= expiryDate
    }

    public init(version: String, buildDate: Date) {
        self.version = version
        self.buildDate = buildDate
    }

    /// Parses the first line of `soloist --version`. Returns nil if the format is unknown.
    public init?(versionOutput: String) {
        // Captures: version ("1.3.10.65") and build date ("20261112").
        let pattern = /soloist (\S+) build \d+ \((\d{4})(\d{2})(\d{2})\)/
        guard let match = versionOutput.firstMatch(of: pattern),
              let year = Int(match.2), let month = Int(match.3), let day = Int(match.4)
        else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        self.init(version: String(match.1), buildDate: date)
    }
}
