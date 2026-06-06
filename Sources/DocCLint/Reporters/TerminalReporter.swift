import Foundation
import os

/// Logger for terminal reporter diagnostics
private let reporterLogger = Logger(subsystem: "com.docc-lint", category: "TerminalReporter") // LIVE: logging infrastructure

/// Reporter that outputs human-readable terminal output with optional ANSI colors
public struct TerminalReporter: Reporter, Sendable {
    private let useColor: Bool
    private let verbose: Bool
    private let quiet: Bool

    /// Creates a new terminal reporter with the given display options
    /// - Parameters:
    ///   - useColor: Whether to use ANSI color codes in output
    ///   - verbose: Whether to show verbose informational messages
    ///   - quiet: Whether to suppress non-error output
    public init(useColor: Bool = true, verbose: Bool = false, quiet: Bool = false) {
        self.useColor = useColor
        self.verbose = verbose
        self.quiet = quiet
    }

    /// Format a lint report as human-readable terminal output
    public func format(_ report: LintReport) throws -> String {
        var output = ""

        // Header
        if !quiet {
            output += styled("DocC Lint Results", style: .bold)
            output += "\n"
            output += String(repeating: "=", count: 17)
            output += "\n\n"
        }

        // Group diagnostics by file
        let grouped = Dictionary(grouping: report.diagnostics) { $0.file ?? "Unknown" }

        for (file, diagnostics) in grouped.sorted(by: { $0.key < $1.key }) {
            // File header
            let icon = diagnostics.contains { $0.severity == .error } ? "❌" : "⚠️"
            output += "\(icon) \(styled(file, style: .bold))\n"

            for diagnostic in diagnostics.sorted(by: { $0.line < $1.line }) {
                output += formatDiagnostic(diagnostic)
            }

            output += "\n"
        }

        // Summary
        output += styled(String(repeating: "─", count: 50), style: .dim)
        output += "\n\n"

        let summary = report.summary
        output += "Summary: "
        output += "\(summary.filesScanned) files scanned, "

        if summary.totalErrors > 0 {
            output += styled("\(summary.totalErrors) errors", style: .red)
            output += ", "
        }

        if summary.totalWarnings > 0 {
            output += styled("\(summary.totalWarnings) warnings", style: .yellow)
        } else if summary.totalErrors == 0 {
            output += styled("no issues found", style: .green)
        }

        output += "\n"

        if verbose {
            output += "Scan duration: \(summary.scanDuration.formatted(.number.precision(.fractionLength(2))))s\n"
        }

        return output
    }

    private func formatDiagnostic(_ diagnostic: MappedDiagnostic) -> String {
        var output = ""

        // Location
        let locationStr = "   Line \(diagnostic.line), Column \(diagnostic.column)-\(diagnostic.endColumn)"
        output += styled(locationStr, style: .dim)
        output += "\n"

        // Content snippet with highlighting
        if let content = diagnostic.content {
            output += "   │\n"
            output += "\(String(diagnostic.line).padding(toLength: 3, withPad: " ", startingAt: 0)) │ "
            output += content
            output += "\n"

            // Underline the problematic portion
            let padding = String(repeating: " ", count: 4 + String(diagnostic.line).count)
            let underlineStart = max(0, diagnostic.column - 1)
            let underlineLength = max(1, diagnostic.endColumn - diagnostic.column)
            let leadingSpaces = String(repeating: " ", count: underlineStart)
            let underline = String(repeating: "^", count: underlineLength)

            output += padding + "│ " + leadingSpaces
            output += styled(underline, style: diagnostic.severity == .error ? .red : .yellow)
            output += "\n"
            output += padding + "│\n"
        }

        // Message
        let severityIcon: String
        let severityStyle: ANSIStyle

        switch diagnostic.severity {
        case .error:
            severityIcon = "✖"
            severityStyle = .red
        case .warning:
            severityIcon = "⚠"
            severityStyle = .yellow
        case .note:
            severityIcon = "ℹ"
            severityStyle = .blue
        }

        output += "   \(styled(severityIcon, style: severityStyle)) \(diagnostic.message)\n"

        // Suggested fix
        if let fix = diagnostic.suggestedFix {
            output += "\n"
            output += "   💡 \(styled("Suggested fix:", style: .cyan)) \(fix.description)\n"

            if !fix.replacement.isEmpty {
                output += "      \(styled("-", style: .red)) \(diagnostic.content ?? "")\n"
                output += "      \(styled("+", style: .green)) \(fix.replacement)\n"
            } else if let content = diagnostic.content {
                output += "      \(styled("-", style: .red)) \(content)\n"
                output += "      \(styled("(remove this line)", style: .dim))\n"
            }
        }

        output += "\n"
        return output
    }

    /// Output an informational message to stdout when verbose mode is enabled
    public func info(_ message: String) {
        guard verbose else { return }
        FileHandle.standardOutput.write(Data((styled("ℹ ", style: .blue) + message + "\n").utf8))
    }

    /// Output a warning message to stdout unless quiet mode is enabled
    public func warning(_ message: String) {
        guard !quiet else { return }
        FileHandle.standardOutput.write(Data((styled("⚠ ", style: .yellow) + message + "\n").utf8))
    }

    /// Output an error message to stdout
    public func error(_ message: String) {
        FileHandle.standardOutput.write(Data((styled("✖ ", style: .red) + message + "\n").utf8))
    }

    // MARK: - ANSI Styling

    private enum ANSIStyle {
        case bold
        case dim
        case red
        case green
        case yellow
        case blue
        case cyan

        var code: String {
            switch self {
            case .bold: return "\u{001B}[1m"
            case .dim: return "\u{001B}[2m"
            case .red: return "\u{001B}[31m"
            case .green: return "\u{001B}[32m"
            case .yellow: return "\u{001B}[33m"
            case .blue: return "\u{001B}[34m"
            case .cyan: return "\u{001B}[36m"
            }
        }

        static let reset = "\u{001B}[0m"
    }

    private func styled(_ text: String, style: ANSIStyle) -> String {
        guard useColor else { return text }
        return style.code + text + ANSIStyle.reset
    }
}
