import Foundation

/// Severity level for diagnostics.
public enum DiagnosticSeverity: String, Codable, Comparable, Sendable {
    /// An error-level diagnostic indicating a documentation problem that must be fixed.
    case error
    /// A warning-level diagnostic indicating a potential documentation issue.
    case warning
    /// A note-level diagnostic providing informational context.
    case note

    /// Compares two severity levels by their natural ordering (note < warning < error).
    public static func < (lhs: DiagnosticSeverity, rhs: DiagnosticSeverity) -> Bool {
        let order: [DiagnosticSeverity] = [.note, .warning, .error]
        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs) else {
            return false
        }
        return lhsIndex < rhsIndex
    }
}

/// A diagnostic message from DocC with source location information.
public struct MappedDiagnostic: Codable, Sendable {
    /// The source file path (if successfully mapped).
    public let file: String?

    /// Line number in the source file.
    public let line: Int

    /// Starting column.
    public let column: Int

    /// Ending column.
    public let endColumn: Int

    /// Severity level.
    public let severity: DiagnosticSeverity

    /// The diagnostic message.
    public let message: String

    /// The actual content at the diagnostic location.
    public let content: String?

    /// A rule identifier for categorizing the diagnostic.
    public let ruleId: String?

    /// Suggested fix information.
    public let suggestedFix: SuggestedFix?

    /// Creates a new mapped diagnostic with the given parameters.
    public init(
        file: String?,
        line: Int,
        column: Int,
        endColumn: Int,
        severity: DiagnosticSeverity,
        message: String,
        content: String?,
        ruleId: String?,
        suggestedFix: SuggestedFix?
    ) {
        self.file = file
        self.line = line
        self.column = column
        self.endColumn = endColumn
        self.severity = severity
        self.message = message
        self.content = content
        self.ruleId = ruleId
        self.suggestedFix = suggestedFix
    }
}

/// A suggested fix for a diagnostic.
public struct SuggestedFix: Codable, Sendable {
    /// Description of the fix.
    public let description: String

    /// The replacement text.
    public let replacement: String

    /// Creates a new suggested fix with the specified description and replacement.
    public init(description: String, replacement: String) {
        self.description = description
        self.replacement = replacement
    }
}

/// Raw diagnostic as parsed directly from DocC JSON output.
public struct RawDiagnostic: Codable {
    /// The severity string from the raw JSON.
    public let severity: String
    /// The summary message of the diagnostic.
    public let summary: String
    /// The source range affected by the diagnostic.
    public let range: DiagnosticRange
    /// Suggested solutions for the diagnostic.
    public let solutions: [Solution]
    /// Additional notes providing context for the diagnostic.
    public let notes: [Note] // LIVE: public API
    /// Source file URL (e.g., "file:///path/to/file.md").
    public let source: SourceLocation?

    /// A source location parsed from DocC diagnostic JSON.
    public struct SourceLocation: Codable {
        /// The URL string identifying the source file.
        public let url: String?

        /// Creates a new instance by decoding from the given decoder, handling both string and object formats.
        public init(from decoder: Decoder) throws {
            // Handle both string and object formats
            if let container = try? decoder.singleValueContainer(), // silent: error is expected and non-fatal
               let urlString = try? container.decode(String.self) { // silent: error is expected and non-fatal
                self.url = urlString
            } else {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                self.url = try container.decodeIfPresent(String.self, forKey: .url)
            }
        }

        /// Coding keys for decoding source location fields.
        private enum CodingKeys: String, CodingKey {
            case url
        }
    }

    /// A range of positions within a source file.
    public struct DiagnosticRange: Codable {
        /// The start position of the range.
        public let start: Position
        /// The end position of the range.
        public let end: Position

        /// A line and column position within a source file.
        public struct Position: Codable {
            /// The line number.
            public let line: Int
            /// The column number.
            public let column: Int
        }
    }

    /// A suggested solution for a raw diagnostic.
    public struct Solution: Codable {
        /// A summary of the suggested solution.
        public let summary: String
        /// The text replacements to apply.
        public let replacements: [Replacement]

        /// A text replacement within a diagnostic range.
        public struct Replacement: Codable {
            /// The range to replace.
            public let range: DiagnosticRange // LIVE: public API
            /// The replacement text.
            public let text: String
        }
    }

    /// A note providing additional context for a diagnostic.
    public struct Note: Codable {
        // Notes structure - may contain additional context
    }
}

/// The root structure of DocC diagnostics JSON.
public struct DiagnosticsFile: Codable {
    /// The version of the diagnostics file format.
    public let version: Version // LIVE: public API
    /// The list of raw diagnostics.
    public let diagnostics: [RawDiagnostic]

    /// The version number of the diagnostics file format.
    public struct Version: Codable {
        /// The major version number.
        public let major: Int // LIVE: public API
        /// The minor version number.
        public let minor: Int // LIVE: public API
        /// The patch version number.
        public let patch: Int // LIVE: public API
    }
}
