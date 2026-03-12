import Foundation

/// Result of scanning a single file or catalog
public struct ScanResult: Codable, Sendable {
    /// The path that was scanned
    public let path: String

    /// Type of the scanned item
    public let fileType: ScannedFileType

    /// Diagnostics found during scanning
    public let diagnostics: [MappedDiagnostic]

    /// Whether the scan was successful
    public let success: Bool

    /// Error message if scan failed
    public let errorMessage: String?

    /// Time taken to scan in seconds
    public let scanDuration: Double

    public init(
        path: String,
        fileType: ScannedFileType,
        diagnostics: [MappedDiagnostic],
        success: Bool,
        errorMessage: String? = nil,
        scanDuration: Double
    ) {
        self.path = path
        self.fileType = fileType
        self.diagnostics = diagnostics
        self.success = success
        self.errorMessage = errorMessage
        self.scanDuration = scanDuration
    }

    /// Summary of diagnostics by severity
    public var summary: (errors: Int, warnings: Int, notes: Int) {
        var errors = 0, warnings = 0, notes = 0
        for diagnostic in diagnostics {
            switch diagnostic.severity {
            case .error: errors += 1
            case .warning: warnings += 1
            case .note: notes += 1
            }
        }
        return (errors, warnings, notes)
    }
}

/// Classification of files that can be scanned
public enum ScannedFileType: String, Codable, Sendable {
    /// A .docc catalog bundle
    case doccCatalog

    /// A markdown file inside a .docc catalog
    case markdownInCatalog

    /// A standalone markdown file outside any catalog
    case standaloneMarkdown

    /// A Swift source file with documentation comments
    case swiftSource
}

/// Aggregated results from scanning multiple files
public struct LintReport: Codable, Sendable {
    /// Tool version
    public let version: String

    /// When the scan was performed
    public let timestamp: Date

    /// Summary statistics
    public let summary: Summary

    /// All diagnostics found
    public let diagnostics: [MappedDiagnostic]

    /// Individual file results (optional, for detailed reports)
    public let fileResults: [ScanResult]?

    public struct Summary: Codable, Sendable {
        public let filesScanned: Int
        public let filesWithIssues: Int
        public let totalErrors: Int
        public let totalWarnings: Int
        public let totalNotes: Int
        public let scanDuration: Double

        public init(
            filesScanned: Int,
            filesWithIssues: Int,
            totalErrors: Int,
            totalWarnings: Int,
            totalNotes: Int,
            scanDuration: Double
        ) {
            self.filesScanned = filesScanned
            self.filesWithIssues = filesWithIssues
            self.totalErrors = totalErrors
            self.totalWarnings = totalWarnings
            self.totalNotes = totalNotes
            self.scanDuration = scanDuration
        }
    }

    public init(
        version: String,
        timestamp: Date,
        summary: Summary,
        diagnostics: [MappedDiagnostic],
        fileResults: [ScanResult]? = nil
    ) {
        self.version = version
        self.timestamp = timestamp
        self.summary = summary
        self.diagnostics = diagnostics
        self.fileResults = fileResults
    }
}
