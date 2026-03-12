import Testing
import Foundation
@testable import DocCLint

@Suite("ScanResult Model Tests")
struct ScanResultTests {

    // MARK: - ScanResult Tests

    @Suite("ScanResult Creation")
    struct ScanResultCreationTests {

        @Test("Create successful scan result with no issues")
        func createCleanResult() {
            let result = ScanResult(
                path: "/path/to/catalog.docc",
                fileType: .doccCatalog,
                diagnostics: [],
                success: true,
                scanDuration: 1.5
            )

            #expect(result.path == "/path/to/catalog.docc")
            #expect(result.success == true)
            #expect(result.diagnostics.isEmpty)
            #expect(result.errorMessage == nil)
            #expect(abs(result.scanDuration - 1.5) < 0.001)
        }

        @Test("Create failed scan result")
        func createFailedResult() {
            let result = ScanResult(
                path: "/path/to/catalog.docc",
                fileType: .doccCatalog,
                diagnostics: [],
                success: false,
                errorMessage: "DocC not found",
                scanDuration: 0.1
            )

            #expect(result.success == false)
            #expect(result.errorMessage == "DocC not found")
        }

        @Test("Create result with diagnostics")
        func createWithDiagnostics() {
            let diagnostics = [
                MappedDiagnostic(
                    file: "test.md",
                    line: 10,
                    column: 1,
                    endColumn: 50,
                    severity: .error,
                    message: "Error 1",
                    content: nil,
                    ruleId: nil,
                    suggestedFix: nil
                ),
                MappedDiagnostic(
                    file: "test.md",
                    line: 20,
                    column: 1,
                    endColumn: 30,
                    severity: .warning,
                    message: "Warning 1",
                    content: nil,
                    ruleId: nil,
                    suggestedFix: nil
                ),
                MappedDiagnostic(
                    file: "test.md",
                    line: 30,
                    column: 1,
                    endColumn: 20,
                    severity: .note,
                    message: "Note 1",
                    content: nil,
                    ruleId: nil,
                    suggestedFix: nil
                )
            ]

            let result = ScanResult(
                path: "/catalog.docc",
                fileType: .doccCatalog,
                diagnostics: diagnostics,
                success: true,
                scanDuration: 2.0
            )

            #expect(result.diagnostics.count == 3)
        }
    }

    @Suite("ScanResult Summary")
    struct ScanResultSummaryTests {

        @Test("Summary counts errors correctly")
        func summaryCountsErrors() {
            let diagnostics = [
                MappedDiagnostic(file: nil, line: 1, column: 0, endColumn: 0, severity: .error, message: "E1", content: nil, ruleId: nil, suggestedFix: nil),
                MappedDiagnostic(file: nil, line: 2, column: 0, endColumn: 0, severity: .error, message: "E2", content: nil, ruleId: nil, suggestedFix: nil),
                MappedDiagnostic(file: nil, line: 3, column: 0, endColumn: 0, severity: .warning, message: "W1", content: nil, ruleId: nil, suggestedFix: nil),
            ]

            let result = ScanResult(
                path: "/test.docc",
                fileType: .doccCatalog,
                diagnostics: diagnostics,
                success: true,
                scanDuration: 1.0
            )

            let summary = result.summary
            #expect(summary.errors == 2)
            #expect(summary.warnings == 1)
            #expect(summary.notes == 0)
        }

        @Test("Summary counts all severity levels")
        func summaryCountsAllLevels() {
            let diagnostics = [
                MappedDiagnostic(file: nil, line: 1, column: 0, endColumn: 0, severity: .error, message: "", content: nil, ruleId: nil, suggestedFix: nil),
                MappedDiagnostic(file: nil, line: 2, column: 0, endColumn: 0, severity: .warning, message: "", content: nil, ruleId: nil, suggestedFix: nil),
                MappedDiagnostic(file: nil, line: 3, column: 0, endColumn: 0, severity: .warning, message: "", content: nil, ruleId: nil, suggestedFix: nil),
                MappedDiagnostic(file: nil, line: 4, column: 0, endColumn: 0, severity: .note, message: "", content: nil, ruleId: nil, suggestedFix: nil),
                MappedDiagnostic(file: nil, line: 5, column: 0, endColumn: 0, severity: .note, message: "", content: nil, ruleId: nil, suggestedFix: nil),
                MappedDiagnostic(file: nil, line: 6, column: 0, endColumn: 0, severity: .note, message: "", content: nil, ruleId: nil, suggestedFix: nil),
            ]

            let result = ScanResult(
                path: "/test.docc",
                fileType: .doccCatalog,
                diagnostics: diagnostics,
                success: true,
                scanDuration: 1.0
            )

            let summary = result.summary
            #expect(summary.errors == 1)
            #expect(summary.warnings == 2)
            #expect(summary.notes == 3)
        }

        @Test("Empty diagnostics gives zero counts")
        func emptyDiagnosticsZeroCounts() {
            let result = ScanResult(
                path: "/test.docc",
                fileType: .doccCatalog,
                diagnostics: [],
                success: true,
                scanDuration: 1.0
            )

            let summary = result.summary
            #expect(summary.errors == 0)
            #expect(summary.warnings == 0)
            #expect(summary.notes == 0)
        }
    }

    // MARK: - ScannedFileType Tests

    @Suite("ScannedFileType")
    struct ScannedFileTypeTests {

        @Test("File types have correct raw values")
        func fileTypeRawValues() {
            #expect(ScannedFileType.doccCatalog.rawValue == "doccCatalog")
            #expect(ScannedFileType.markdownInCatalog.rawValue == "markdownInCatalog")
            #expect(ScannedFileType.standaloneMarkdown.rawValue == "standaloneMarkdown")
            #expect(ScannedFileType.swiftSource.rawValue == "swiftSource")
        }

        @Test("File types encode/decode correctly")
        func encodeDecodeFileType() throws {
            let types: [ScannedFileType] = [.doccCatalog, .markdownInCatalog, .standaloneMarkdown, .swiftSource]

            for type in types {
                let encoder = JSONEncoder()
                let data = try encoder.encode(type)

                let decoder = JSONDecoder()
                let decoded = try decoder.decode(ScannedFileType.self, from: data)

                #expect(decoded == type)
            }
        }
    }

    // MARK: - LintReport Tests

    @Suite("LintReport")
    struct LintReportTests {

        @Test("Create lint report with summary")
        func createLintReport() {
            let summary = LintReport.Summary(
                filesScanned: 10,
                filesWithIssues: 2,
                totalErrors: 1,
                totalWarnings: 5,
                totalNotes: 3,
                scanDuration: 2.5
            )

            let report = LintReport(
                version: "1.0.0",
                timestamp: Date(),
                summary: summary,
                diagnostics: []
            )

            #expect(report.version == "1.0.0")
            #expect(report.summary.filesScanned == 10)
            #expect(report.summary.filesWithIssues == 2)
            #expect(report.summary.totalErrors == 1)
            #expect(report.summary.totalWarnings == 5)
            #expect(report.summary.totalNotes == 3)
            #expect(abs(report.summary.scanDuration - 2.5) < 0.001)
        }

        @Test("LintReport encodes to JSON")
        func encodeToJSON() throws {
            let report = LintReport(
                version: "1.0.0",
                timestamp: Date(timeIntervalSince1970: 1000000),
                summary: LintReport.Summary(
                    filesScanned: 5,
                    filesWithIssues: 1,
                    totalErrors: 0,
                    totalWarnings: 2,
                    totalNotes: 0,
                    scanDuration: 1.0
                ),
                diagnostics: []
            )

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(report)
            let json = String(data: data, encoding: .utf8)!

            #expect(json.contains("\"version\":\"1.0.0\""))
            #expect(json.contains("\"filesScanned\":5"))
            #expect(json.contains("\"totalWarnings\":2"))
        }
    }
}
