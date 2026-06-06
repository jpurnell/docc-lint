import Foundation

/// Protocol for formatting and outputting lint results
public protocol Reporter: Sendable {
    /// Format a lint report as a string
    func format(_ report: LintReport) throws -> String

    /// Output an informational message (for verbose mode)
    func info(_ message: String)

    /// Output a warning message
    func warning(_ message: String) // LIVE: public API

    /// Output an error message
    func error(_ message: String) // LIVE: public API
}

/// Default implementations for logging methods
extension Reporter {
    /// Output an informational message (default: no-op for non-terminal reporters)
    public func info(_ message: String) {
        // Default: no-op for non-terminal reporters
    }

    /// Output a warning message (default: no-op for non-terminal reporters)
    public func warning(_ message: String) { // LIVE: public API
        // Default: no-op for non-terminal reporters
    }

    /// Output an error message (default: no-op for non-terminal reporters)
    public func error(_ message: String) { // LIVE: public API
        // Default: no-op for non-terminal reporters
    }
}
