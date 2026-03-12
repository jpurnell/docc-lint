import Testing
import Foundation
@testable import DocCLint

@Suite("Diagnostic Model Tests")
struct DiagnosticTests {

    // MARK: - DiagnosticSeverity Tests

    @Suite("Severity Comparison")
    struct SeverityComparisonTests {

        @Test("Severity ordering: note < warning < error")
        func severityOrdering() {
            #expect(DiagnosticSeverity.note < DiagnosticSeverity.warning)
            #expect(DiagnosticSeverity.warning < DiagnosticSeverity.error)
            #expect(DiagnosticSeverity.note < DiagnosticSeverity.error)
        }

        @Test("Same severity is not less than itself")
        func sameSeverityComparison() {
            #expect(!(DiagnosticSeverity.note < DiagnosticSeverity.note))
            #expect(!(DiagnosticSeverity.warning < DiagnosticSeverity.warning))
            #expect(!(DiagnosticSeverity.error < DiagnosticSeverity.error))
        }

        @Test("Severity raw values encode correctly")
        func severityRawValues() {
            #expect(DiagnosticSeverity.error.rawValue == "error")
            #expect(DiagnosticSeverity.warning.rawValue == "warning")
            #expect(DiagnosticSeverity.note.rawValue == "note")
        }
    }

    // MARK: - MappedDiagnostic Tests

    @Suite("MappedDiagnostic")
    struct MappedDiagnosticTests {

        @Test("Create diagnostic with all fields")
        func createFullDiagnostic() {
            let diagnostic = MappedDiagnostic(
                file: "/path/to/file.md",
                line: 42,
                column: 5,
                endColumn: 25,
                severity: .warning,
                message: "Test message",
                content: "- ``Symbol`` description",
                ruleId: "task-group-links-only",
                suggestedFix: SuggestedFix(description: "Remove description", replacement: "- ``Symbol``")
            )

            #expect(diagnostic.file == "/path/to/file.md")
            #expect(diagnostic.line == 42)
            #expect(diagnostic.column == 5)
            #expect(diagnostic.endColumn == 25)
            #expect(diagnostic.severity == .warning)
            #expect(diagnostic.message == "Test message")
            #expect(diagnostic.content == "- ``Symbol`` description")
            #expect(diagnostic.ruleId == "task-group-links-only")
            #expect(diagnostic.suggestedFix?.description == "Remove description")
            #expect(diagnostic.suggestedFix?.replacement == "- ``Symbol``")
        }

        @Test("Create diagnostic with nil optional fields")
        func createMinimalDiagnostic() {
            let diagnostic = MappedDiagnostic(
                file: nil,
                line: 0,
                column: 0,
                endColumn: 0,
                severity: .error,
                message: "Error message",
                content: nil,
                ruleId: nil,
                suggestedFix: nil
            )

            #expect(diagnostic.file == nil)
            #expect(diagnostic.content == nil)
            #expect(diagnostic.ruleId == nil)
            #expect(diagnostic.suggestedFix == nil)
        }

        @Test("Diagnostic encodes to JSON correctly")
        func encodeToJSON() throws {
            let diagnostic = MappedDiagnostic(
                file: "test.md",
                line: 10,
                column: 1,
                endColumn: 50,
                severity: .warning,
                message: "Test",
                content: nil,
                ruleId: "test-rule",
                suggestedFix: nil
            )

            let encoder = JSONEncoder()
            let data = try encoder.encode(diagnostic)
            let json = String(data: data, encoding: .utf8)!

            #expect(json.contains("\"file\":\"test.md\""))
            #expect(json.contains("\"line\":10"))
            #expect(json.contains("\"severity\":\"warning\""))
        }

        @Test("Diagnostic decodes from JSON correctly")
        func decodeFromJSON() throws {
            let json = """
            {
                "file": "test.md",
                "line": 10,
                "column": 1,
                "endColumn": 50,
                "severity": "error",
                "message": "Test message",
                "content": null,
                "ruleId": null,
                "suggestedFix": null
            }
            """

            let decoder = JSONDecoder()
            let diagnostic = try decoder.decode(MappedDiagnostic.self, from: json.data(using: .utf8)!)

            #expect(diagnostic.file == "test.md")
            #expect(diagnostic.line == 10)
            #expect(diagnostic.severity == .error)
        }
    }

    // MARK: - SuggestedFix Tests

    @Suite("SuggestedFix")
    struct SuggestedFixTests {

        @Test("Create suggested fix with replacement")
        func createWithReplacement() {
            let fix = SuggestedFix(
                description: "Replace with correct syntax",
                replacement: "- ``Symbol``"
            )

            #expect(fix.description == "Replace with correct syntax")
            #expect(fix.replacement == "- ``Symbol``")
        }

        @Test("Create suggested fix for removal")
        func createForRemoval() {
            let fix = SuggestedFix(
                description: "Remove this line",
                replacement: ""
            )

            #expect(fix.description == "Remove this line")
            #expect(fix.replacement.isEmpty)
        }

        @Test("SuggestedFix encodes/decodes correctly")
        func encodeDecodeRoundTrip() throws {
            let original = SuggestedFix(
                description: "Test fix",
                replacement: "new content"
            )

            let encoder = JSONEncoder()
            let data = try encoder.encode(original)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(SuggestedFix.self, from: data)

            #expect(decoded.description == original.description)
            #expect(decoded.replacement == original.replacement)
        }
    }

    // MARK: - RawDiagnostic Tests

    @Suite("RawDiagnostic Parsing")
    struct RawDiagnosticParsingTests {

        @Test("Parse DocC diagnostics JSON format")
        func parseDocCJSON() throws {
            let json = """
            {
                "severity": "warning",
                "summary": "Only links are allowed in task group list items",
                "range": {
                    "start": {"line": 53, "column": 1},
                    "end": {"line": 53, "column": 38}
                },
                "solutions": [{
                    "summary": "Remove non-link item",
                    "replacements": [{
                        "range": {
                            "start": {"line": 53, "column": 1},
                            "end": {"line": 53, "column": 38}
                        },
                        "text": ""
                    }]
                }],
                "notes": []
            }
            """

            let decoder = JSONDecoder()
            let diagnostic = try decoder.decode(RawDiagnostic.self, from: json.data(using: .utf8)!)

            #expect(diagnostic.severity == "warning")
            #expect(diagnostic.summary == "Only links are allowed in task group list items")
            #expect(diagnostic.range.start.line == 53)
            #expect(diagnostic.range.start.column == 1)
            #expect(diagnostic.range.end.column == 38)
            #expect(diagnostic.solutions.count == 1)
            #expect(diagnostic.solutions[0].summary == "Remove non-link item")
            #expect(diagnostic.solutions[0].replacements[0].text == "")
        }

        @Test("Parse DiagnosticsFile with version")
        func parseDiagnosticsFile() throws {
            let json = """
            {
                "version": {"major": 1, "minor": 0, "patch": 0},
                "diagnostics": []
            }
            """

            let decoder = JSONDecoder()
            let file = try decoder.decode(DiagnosticsFile.self, from: json.data(using: .utf8)!)

            #expect(file.version.major == 1)
            #expect(file.version.minor == 0)
            #expect(file.version.patch == 0)
            #expect(file.diagnostics.isEmpty)
        }
    }
}
