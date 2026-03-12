import Foundation

/// Protocol for formatting and outputting lint results
public protocol Reporter: Sendable {
    /// Format a lint report as a string
    func format(_ report: LintReport) throws -> String

    /// Output an informational message (for verbose mode)
    func info(_ message: String)

    /// Output a warning message
    func warning(_ message: String)

    /// Output an error message
    func error(_ message: String)
}

/// Default implementations for logging methods
extension Reporter {
    public func info(_ message: String) {
        // Default: no-op for non-terminal reporters
    }

    public func warning(_ message: String) {
        // Default: no-op for non-terminal reporters
    }

    public func error(_ message: String) {
        // Default: no-op for non-terminal reporters
    }
}
