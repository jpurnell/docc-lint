import Testing
import Foundation
@testable import DocCLint

@Suite("Reporter Tests")
struct ReporterTests {

    // Helper to create a test report
    private func createTestReport(
        diagnostics: [MappedDiagnostic] = [],
        filesScanned: Int = 10,
        filesWithIssues: Int = 2
    ) -> LintReport {
        let totalErrors = diagnostics.filter { $0.severity == .error }.count
        let totalWarnings = diagnostics.filter { $0.severity == .warning }.count
        let totalNotes = diagnostics.filter { $0.severity == .note }.count

        return LintReport(
            version: "1.0.0",
            timestamp: Date(timeIntervalSince1970: 1000000),
            summary: LintReport.Summary(
                filesScanned: filesScanned,
                filesWithIssues: filesWithIssues,
                totalErrors: totalErrors,
                totalWarnings: totalWarnings,
                totalNotes: totalNotes,
                scanDuration: 2.5
            ),
            diagnostics: diagnostics
        )
    }

    private func createTestDiagnostic(
        file: String = "test.md",
        line: Int = 10,
        severity: DiagnosticSeverity = .warning,
        message: String = "Test warning"
    ) -> MappedDiagnostic {
        MappedDiagnostic(
            file: file,
            line: line,
            column: 1,
            endColumn: 50,
            severity: severity,
            message: message,
            content: "- ``Symbol`` with description",
            ruleId: "task-group-links-only",
            suggestedFix: SuggestedFix(description: "Remove description", replacement: "- ``Symbol``")
        )
    }

    // MARK: - JSON Reporter Tests

    @Suite("JSONReporter")
    struct JSONReporterTests {

        @Test("Produces valid JSON output")
        func producesValidJSON() throws {
            let diagnostic = MappedDiagnostic(
                file: "test.md",
                line: 10,
                column: 1,
                endColumn: 50,
                severity: .warning,
                message: "Test",
                content: nil,
                ruleId: "test",
                suggestedFix: nil
            )

            let report = LintReport(
                version: "1.0.0",
                timestamp: Date(timeIntervalSince1970: 1000000),
                summary: LintReport.Summary(
                    filesScanned: 5,
                    filesWithIssues: 1,
                    totalErrors: 0,
                    totalWarnings: 1,
                    totalNotes: 0,
                    scanDuration: 1.0
                ),
                diagnostics: [diagnostic]
            )

            let reporter = JSONReporter()
            let output = try reporter.format(report)

            // Should be parseable as JSON
            let data = output.data(using: .utf8)!
            let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]

            #expect(parsed != nil)
            #expect(parsed?["version"] as? String == "1.0.0")
        }

        @Test("Includes all diagnostics in JSON output")
        func includesAllDiagnostics() throws {
            let diagnostics = [
                MappedDiagnostic(file: "a.md", line: 1, column: 1, endColumn: 10, severity: .error, message: "E1", content: nil, ruleId: nil, suggestedFix: nil),
                MappedDiagnostic(file: "b.md", line: 2, column: 1, endColumn: 10, severity: .warning, message: "W1", content: nil, ruleId: nil, suggestedFix: nil),
                MappedDiagnostic(file: "c.md", line: 3, column: 1, endColumn: 10, severity: .note, message: "N1", content: nil, ruleId: nil, suggestedFix: nil),
            ]

            let report = LintReport(
                version: "1.0.0",
                timestamp: Date(),
                summary: LintReport.Summary(filesScanned: 3, filesWithIssues: 3, totalErrors: 1, totalWarnings: 1, totalNotes: 1, scanDuration: 1.0),
                diagnostics: diagnostics
            )

            let reporter = JSONReporter()
            let output = try reporter.format(report)

            // Check for file values (allow for JSON formatting variations)
            #expect(output.contains("\"a.md\""))
            #expect(output.contains("\"b.md\""))
            #expect(output.contains("\"c.md\""))
        }

        @Test("Empty diagnostics produces valid JSON")
        func emptyDiagnosticsValidJSON() throws {
            let report = LintReport(
                version: "1.0.0",
                timestamp: Date(),
                summary: LintReport.Summary(filesScanned: 0, filesWithIssues: 0, totalErrors: 0, totalWarnings: 0, totalNotes: 0, scanDuration: 0),
                diagnostics: []
            )

            let reporter = JSONReporter()
            let output = try reporter.format(report)

            // Check that diagnostics array is empty (accounting for JSON formatting)
            #expect(output.contains("\"diagnostics\""))
            // Parse and verify
            let data = output.data(using: .utf8)!
            let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let diagnostics = parsed?["diagnostics"] as? [Any]
            #expect(diagnostics?.isEmpty == true)
        }
    }

    // MARK: - CSV Reporter Tests

    @Suite("CSVReporter")
    struct CSVReporterTests {

        @Test("Produces CSV with header row")
        func producesCSVWithHeader() throws {
            let report = LintReport(
                version: "1.0.0",
                timestamp: Date(),
                summary: LintReport.Summary(filesScanned: 0, filesWithIssues: 0, totalErrors: 0, totalWarnings: 0, totalNotes: 0, scanDuration: 0),
                diagnostics: []
            )

            let reporter = CSVReporter()
            let output = try reporter.format(report)

            let lines = output.components(separatedBy: "\n")
            #expect(lines[0].contains("file,line,column"))
        }

        @Test("Escapes commas in fields")
        func escapesCommas() throws {
            let diagnostic = MappedDiagnostic(
                file: "test.md",
                line: 10,
                column: 1,
                endColumn: 50,
                severity: .warning,
                message: "Message with, comma",
                content: nil,
                ruleId: nil,
                suggestedFix: nil
            )

            let report = LintReport(
                version: "1.0.0",
                timestamp: Date(),
                summary: LintReport.Summary(filesScanned: 1, filesWithIssues: 1, totalErrors: 0, totalWarnings: 1, totalNotes: 0, scanDuration: 1.0),
                diagnostics: [diagnostic]
            )

            let reporter = CSVReporter()
            let output = try reporter.format(report)

            // Comma should be escaped with quotes
            #expect(output.contains("\"Message with, comma\""))
        }

        @Test("Escapes quotes in fields")
        func escapesQuotes() throws {
            let diagnostic = MappedDiagnostic(
                file: "test.md",
                line: 10,
                column: 1,
                endColumn: 50,
                severity: .warning,
                message: "Message with \"quotes\"",
                content: nil,
                ruleId: nil,
                suggestedFix: nil
            )

            let report = LintReport(
                version: "1.0.0",
                timestamp: Date(),
                summary: LintReport.Summary(filesScanned: 1, filesWithIssues: 1, totalErrors: 0, totalWarnings: 1, totalNotes: 0, scanDuration: 1.0),
                diagnostics: [diagnostic]
            )

            let reporter = CSVReporter()
            let output = try reporter.format(report)

            // Quotes should be doubled
            #expect(output.contains("\"\"quotes\"\""))
        }

        @Test("Includes all diagnostic fields")
        func includesAllFields() throws {
            let diagnostic = MappedDiagnostic(
                file: "test.md",
                line: 42,
                column: 5,
                endColumn: 25,
                severity: .error,
                message: "Test message",
                content: "content line",
                ruleId: "test-rule",
                suggestedFix: nil
            )

            let report = LintReport(
                version: "1.0.0",
                timestamp: Date(),
                summary: LintReport.Summary(filesScanned: 1, filesWithIssues: 1, totalErrors: 1, totalWarnings: 0, totalNotes: 0, scanDuration: 1.0),
                diagnostics: [diagnostic]
            )

            let reporter = CSVReporter()
            let output = try reporter.format(report)

            #expect(output.contains("test.md"))
            #expect(output.contains("42"))
            #expect(output.contains("error"))
            #expect(output.contains("test-rule"))
        }
    }

    // MARK: - SARIF Reporter Tests

    @Suite("SARIFReporter")
    struct SARIFReporterTests {

        @Test("Produces valid SARIF JSON")
        func producesValidSARIF() throws {
            let report = LintReport(
                version: "1.0.0",
                timestamp: Date(),
                summary: LintReport.Summary(filesScanned: 1, filesWithIssues: 0, totalErrors: 0, totalWarnings: 0, totalNotes: 0, scanDuration: 1.0),
                diagnostics: []
            )

            let reporter = SARIFReporter()
            let output = try reporter.format(report)

            let data = output.data(using: .utf8)!
            let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]

            #expect(parsed != nil)
            #expect(parsed?["version"] as? String == "2.1.0")
            #expect(parsed?["$schema"] != nil)
        }

        @Test("Includes tool information")
        func includesToolInfo() throws {
            let report = LintReport(
                version: "1.0.0",
                timestamp: Date(),
                summary: LintReport.Summary(filesScanned: 0, filesWithIssues: 0, totalErrors: 0, totalWarnings: 0, totalNotes: 0, scanDuration: 0),
                diagnostics: []
            )

            let reporter = SARIFReporter()
            let output = try reporter.format(report)

            // Parse JSON and verify structure
            let data = output.data(using: .utf8)!
            let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let runs = parsed?["runs"] as? [[String: Any]]
            let tool = runs?.first?["tool"] as? [String: Any]
            let driver = tool?["driver"] as? [String: Any]

            #expect(driver?["name"] as? String == "docc-lint")
            #expect(driver?["version"] as? String == "1.0.0")
        }

        @Test("Maps severity to SARIF levels")
        func mapsSeverityToLevels() throws {
            let diagnostics = [
                MappedDiagnostic(file: "a.md", line: 1, column: 1, endColumn: 10, severity: .error, message: "E", content: nil, ruleId: "r1", suggestedFix: nil),
                MappedDiagnostic(file: "b.md", line: 2, column: 1, endColumn: 10, severity: .warning, message: "W", content: nil, ruleId: "r2", suggestedFix: nil),
            ]

            let report = LintReport(
                version: "1.0.0",
                timestamp: Date(),
                summary: LintReport.Summary(filesScanned: 2, filesWithIssues: 2, totalErrors: 1, totalWarnings: 1, totalNotes: 0, scanDuration: 1.0),
                diagnostics: diagnostics
            )

            let reporter = SARIFReporter()
            let output = try reporter.format(report)

            // Parse JSON and verify levels
            let data = output.data(using: .utf8)!
            let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let runs = parsed?["runs"] as? [[String: Any]]
            let results = runs?.first?["results"] as? [[String: Any]]

            let levels = results?.compactMap { $0["level"] as? String } ?? []
            #expect(levels.contains("error"))
            #expect(levels.contains("warning"))
        }
    }

    // MARK: - Terminal Reporter Tests

    @Suite("TerminalReporter")
    struct TerminalReporterTests {

        @Test("Produces human-readable output")
        func producesReadableOutput() throws {
            let diagnostic = MappedDiagnostic(
                file: "test.md",
                line: 10,
                column: 1,
                endColumn: 50,
                severity: .warning,
                message: "Test warning",
                content: "- ``Symbol`` with description",
                ruleId: "task-group-links-only",
                suggestedFix: nil
            )

            let report = LintReport(
                version: "1.0.0",
                timestamp: Date(),
                summary: LintReport.Summary(filesScanned: 1, filesWithIssues: 1, totalErrors: 0, totalWarnings: 1, totalNotes: 0, scanDuration: 1.0),
                diagnostics: [diagnostic]
            )

            let reporter = TerminalReporter(useColor: false)
            let output = try reporter.format(report)

            #expect(output.contains("DocC Lint Results"))
            #expect(output.contains("test.md"))
            #expect(output.contains("Test warning"))
            #expect(output.contains("Summary:"))
        }

        @Test("Shows line content when available")
        func showsLineContent() throws {
            let diagnostic = MappedDiagnostic(
                file: "test.md",
                line: 42,
                column: 5,
                endColumn: 25,
                severity: .warning,
                message: "Warning",
                content: "This is the problematic line",
                ruleId: nil,
                suggestedFix: nil
            )

            let report = LintReport(
                version: "1.0.0",
                timestamp: Date(),
                summary: LintReport.Summary(filesScanned: 1, filesWithIssues: 1, totalErrors: 0, totalWarnings: 1, totalNotes: 0, scanDuration: 1.0),
                diagnostics: [diagnostic]
            )

            let reporter = TerminalReporter(useColor: false)
            let output = try reporter.format(report)

            #expect(output.contains("This is the problematic line"))
        }

        @Test("Shows suggested fix when available")
        func showsSuggestedFix() throws {
            let diagnostic = MappedDiagnostic(
                file: "test.md",
                line: 10,
                column: 1,
                endColumn: 50,
                severity: .warning,
                message: "Warning",
                content: "- ``Symbol`` with text",
                ruleId: nil,
                suggestedFix: SuggestedFix(description: "Remove extra text", replacement: "- ``Symbol``")
            )

            let report = LintReport(
                version: "1.0.0",
                timestamp: Date(),
                summary: LintReport.Summary(filesScanned: 1, filesWithIssues: 1, totalErrors: 0, totalWarnings: 1, totalNotes: 0, scanDuration: 1.0),
                diagnostics: [diagnostic]
            )

            let reporter = TerminalReporter(useColor: false)
            let output = try reporter.format(report)

            #expect(output.contains("Suggested fix"))
            #expect(output.contains("Remove extra text"))
        }

        @Test("Groups diagnostics by file")
        func groupsByFile() throws {
            let diagnostics = [
                MappedDiagnostic(file: "a.md", line: 1, column: 1, endColumn: 10, severity: .warning, message: "W1", content: nil, ruleId: nil, suggestedFix: nil),
                MappedDiagnostic(file: "a.md", line: 2, column: 1, endColumn: 10, severity: .warning, message: "W2", content: nil, ruleId: nil, suggestedFix: nil),
                MappedDiagnostic(file: "b.md", line: 1, column: 1, endColumn: 10, severity: .warning, message: "W3", content: nil, ruleId: nil, suggestedFix: nil),
            ]

            let report = LintReport(
                version: "1.0.0",
                timestamp: Date(),
                summary: LintReport.Summary(filesScanned: 2, filesWithIssues: 2, totalErrors: 0, totalWarnings: 3, totalNotes: 0, scanDuration: 1.0),
                diagnostics: diagnostics
            )

            let reporter = TerminalReporter(useColor: false)
            let output = try reporter.format(report)

            // Both files should appear
            #expect(output.contains("a.md"))
            #expect(output.contains("b.md"))
        }

        @Test("Shows correct summary counts")
        func showsCorrectSummaryCounts() throws {
            let report = LintReport(
                version: "1.0.0",
                timestamp: Date(),
                summary: LintReport.Summary(
                    filesScanned: 42,
                    filesWithIssues: 5,
                    totalErrors: 3,
                    totalWarnings: 10,
                    totalNotes: 2,
                    scanDuration: 5.5
                ),
                diagnostics: []
            )

            let reporter = TerminalReporter(useColor: false)
            let output = try reporter.format(report)

            #expect(output.contains("42 files"))
            #expect(output.contains("3 errors"))
            #expect(output.contains("10 warnings"))
        }

        @Test("No issues shows success message")
        func noIssuesShowsSuccess() throws {
            let report = LintReport(
                version: "1.0.0",
                timestamp: Date(),
                summary: LintReport.Summary(
                    filesScanned: 10,
                    filesWithIssues: 0,
                    totalErrors: 0,
                    totalWarnings: 0,
                    totalNotes: 0,
                    scanDuration: 1.0
                ),
                diagnostics: []
            )

            let reporter = TerminalReporter(useColor: false)
            let output = try reporter.format(report)

            #expect(output.contains("no issues found"))
        }
    }
}
