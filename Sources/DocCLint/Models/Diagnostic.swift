import Foundation

/// Severity level for diagnostics
public enum DiagnosticSeverity: String, Codable, Comparable, Sendable {
    case error
    case warning
    case note

    public static func < (lhs: DiagnosticSeverity, rhs: DiagnosticSeverity) -> Bool {
        let order: [DiagnosticSeverity] = [.note, .warning, .error]
        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs) else {
            return false
        }
        return lhsIndex < rhsIndex
    }
}

/// A diagnostic message from DocC with source location information
public struct MappedDiagnostic: Codable, Sendable {
    /// The source file path (if successfully mapped)
    public let file: String?

    /// Line number in the source file
    public let line: Int

    /// Starting column
    public let column: Int

    /// Ending column
    public let endColumn: Int

    /// Severity level
    public let severity: DiagnosticSeverity

    /// The diagnostic message
    public let message: String

    /// The actual content at the diagnostic location
    public let content: String?

    /// A rule identifier for categorizing the diagnostic
    public let ruleId: String?

    /// Suggested fix information
    public let suggestedFix: SuggestedFix?

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

/// A suggested fix for a diagnostic
public struct SuggestedFix: Codable, Sendable {
    /// Description of the fix
    public let description: String

    /// The replacement text
    public let replacement: String

    public init(description: String, replacement: String) {
        self.description = description
        self.replacement = replacement
    }
}

/// Raw diagnostic as parsed directly from DocC JSON output
public struct RawDiagnostic: Codable {
    public let severity: String
    public let summary: String
    public let range: DiagnosticRange
    public let solutions: [Solution]
    public let notes: [Note]
    /// Source file URL (e.g., "file:///path/to/file.md")
    public let source: SourceLocation?

    public struct SourceLocation: Codable {
        public let url: String?

        public init(from decoder: Decoder) throws {
            // Handle both string and object formats
            if let container = try? decoder.singleValueContainer(),
               let urlString = try? container.decode(String.self) {
                self.url = urlString
            } else {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                self.url = try container.decodeIfPresent(String.self, forKey: .url)
            }
        }

        private enum CodingKeys: String, CodingKey {
            case url
        }
    }

    public struct DiagnosticRange: Codable {
        public let start: Position
        public let end: Position

        public struct Position: Codable {
            public let line: Int
            public let column: Int
        }
    }

    public struct Solution: Codable {
        public let summary: String
        public let replacements: [Replacement]

        public struct Replacement: Codable {
            public let range: DiagnosticRange
            public let text: String
        }
    }

    public struct Note: Codable {
        // Notes structure - may contain additional context
    }
}

/// The root structure of DocC diagnostics JSON
public struct DiagnosticsFile: Codable {
    public let version: Version
    public let diagnostics: [RawDiagnostic]

    public struct Version: Codable {
        public let major: Int
        public let minor: Int
        public let patch: Int
    }
}
