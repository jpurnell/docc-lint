import Foundation

/// Reporter that outputs machine-readable JSON
public struct JSONReporter: Reporter, Sendable {

    /// Creates a new JSON reporter
    public init() {}

    /// Format a lint report as pretty-printed JSON
    public func format(_ report: LintReport) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(report)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
