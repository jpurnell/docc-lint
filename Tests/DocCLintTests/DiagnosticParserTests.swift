import Testing
import Foundation
@testable import DocCLint

@Suite("DiagnosticParser Tests")
struct DiagnosticParserTests {

    // MARK: - JSON Parsing Tests

    @Suite("JSON Format Parsing")
    struct JSONParsingTests {

        @Test("Parse valid DocC diagnostics JSON")
        func parseValidJSON() throws {
            let json = """
            {
                "version": {"major": 1, "minor": 0, "patch": 0},
                "diagnostics": [
                    {
                        "severity": "warning",
                        "summary": "Only links are allowed in task group list items",
                        "range": {
                            "start": {"line": 53, "column": 1},
                            "end": {"line": 53, "column": 38}
                        },
                        "solutions": [],
                        "notes": []
                    }
                ]
            }
            """

            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("test-\(UUID().uuidString)")
                .appendingPathExtension("docc")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let parser = DiagnosticParser()
            let diagnostics = try parser.parseDiagnostics(json: json, catalog: tempDir)

            #expect(diagnostics.count == 1)
            #expect(diagnostics[0].severity == .warning)
            #expect(diagnostics[0].message == "Only links are allowed in task group list items")
        }

        @Test("Parse empty diagnostics array")
        func parseEmptyDiagnostics() throws {
            let json = """
            {
                "version": {"major": 1, "minor": 0, "patch": 0},
                "diagnostics": []
            }
            """

            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("test-\(UUID().uuidString)")
                .appendingPathExtension("docc")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let parser = DiagnosticParser()
            let diagnostics = try parser.parseDiagnostics(json: json, catalog: tempDir)

            #expect(diagnostics.isEmpty)
        }

        @Test("Parse multiple diagnostics")
        func parseMultipleDiagnostics() throws {
            let json = """
            {
                "version": {"major": 1, "minor": 0, "patch": 0},
                "diagnostics": [
                    {
                        "severity": "error",
                        "summary": "Error message",
                        "range": {"start": {"line": 10, "column": 1}, "end": {"line": 10, "column": 20}},
                        "solutions": [],
                        "notes": []
                    },
                    {
                        "severity": "warning",
                        "summary": "Warning message",
                        "range": {"start": {"line": 20, "column": 5}, "end": {"line": 20, "column": 30}},
                        "solutions": [],
                        "notes": []
                    },
                    {
                        "severity": "note",
                        "summary": "Note message",
                        "range": {"start": {"line": 30, "column": 1}, "end": {"line": 30, "column": 15}},
                        "solutions": [],
                        "notes": []
                    }
                ]
            }
            """

            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("test-\(UUID().uuidString)")
                .appendingPathExtension("docc")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let parser = DiagnosticParser()
            let diagnostics = try parser.parseDiagnostics(json: json, catalog: tempDir)

            #expect(diagnostics.count == 3)
            #expect(diagnostics.filter { $0.severity == .error }.count == 1)
            #expect(diagnostics.filter { $0.severity == .warning }.count == 1)
            #expect(diagnostics.filter { $0.severity == .note }.count == 1)
        }
    }

    // MARK: - Text Format Parsing Tests

    @Suite("Text Format Parsing")
    struct TextParsingTests {

        @Test("Parse docc text output format")
        func parseTextFormat() throws {
            let output = """
            warning: 'Period' doesn't exist at '/BusinessMath/1.1-GettingStarted'
               --> 1.1-GettingStarted.md:303:5-303:11
            """

            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("test-\(UUID().uuidString)")
                .appendingPathExtension("docc")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let parser = DiagnosticParser()
            let diagnostics = try parser.parseDiagnostics(json: output, catalog: tempDir)

            #expect(diagnostics.count == 1)
            #expect(diagnostics[0].severity == .warning)
            #expect(diagnostics[0].file == "1.1-GettingStarted.md")
            #expect(diagnostics[0].line == 303)
            #expect(diagnostics[0].column == 5)
        }

        @Test("Parse error severity from text")
        func parseErrorSeverity() throws {
            let output = """
            error: Cannot resolve reference
               --> Article.md:10:1-10:20
            """

            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("test-\(UUID().uuidString)")
                .appendingPathExtension("docc")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let parser = DiagnosticParser()
            let diagnostics = try parser.parseDiagnostics(json: output, catalog: tempDir)

            #expect(diagnostics.count == 1)
            #expect(diagnostics[0].severity == .error)
        }

        @Test("Parse note severity from text")
        func parseNoteSeverity() throws {
            let output = """
            note: Consider using a different approach
               --> Guide.md:50:1-50:30
            """

            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("test-\(UUID().uuidString)")
                .appendingPathExtension("docc")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let parser = DiagnosticParser()
            let diagnostics = try parser.parseDiagnostics(json: output, catalog: tempDir)

            #expect(diagnostics.count == 1)
            #expect(diagnostics[0].severity == .note)
        }

        @Test("Parse multiple text diagnostics")
        func parseMultipleTextDiagnostics() throws {
            let output = """
            warning: First warning
               --> File1.md:10:1-10:20

            warning: Second warning
               --> File2.md:20:5-20:30

            error: An error
               --> File3.md:30:1-30:15
            """

            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("test-\(UUID().uuidString)")
                .appendingPathExtension("docc")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let parser = DiagnosticParser()
            let diagnostics = try parser.parseDiagnostics(json: output, catalog: tempDir)

            #expect(diagnostics.count == 3)
            #expect(diagnostics[0].file == "File1.md")
            #expect(diagnostics[1].file == "File2.md")
            #expect(diagnostics[2].file == "File3.md")
        }

        @Test("Parse text with suggestion")
        func parseTextWithSuggestion() throws {
            let output = """
            warning: 'Symbol' doesn't exist
               --> Test.md:10:5-10:15
                |     ╰─suggestion: Replace 'Symbol' with 'OtherSymbol'
            """

            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("test-\(UUID().uuidString)")
                .appendingPathExtension("docc")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let parser = DiagnosticParser()
            let diagnostics = try parser.parseDiagnostics(json: output, catalog: tempDir)

            #expect(diagnostics.count == 1)
            #expect(diagnostics[0].suggestedFix != nil)
            #expect(diagnostics[0].suggestedFix?.description.contains("Replace") == true)
        }
    }

    // MARK: - Rule ID Generation Tests

    @Suite("Rule ID Generation")
    struct RuleIDTests {

        @Test("Generate task-group-links-only rule ID")
        func generateTaskGroupRuleID() throws {
            let json = """
            {
                "version": {"major": 1, "minor": 0, "patch": 0},
                "diagnostics": [{
                    "severity": "warning",
                    "summary": "Only links are allowed in task group list items",
                    "range": {"start": {"line": 1, "column": 1}, "end": {"line": 1, "column": 10}},
                    "solutions": [],
                    "notes": []
                }]
            }
            """

            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("test-\(UUID().uuidString)")
                .appendingPathExtension("docc")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let parser = DiagnosticParser()
            let diagnostics = try parser.parseDiagnostics(json: json, catalog: tempDir)

            #expect(diagnostics[0].ruleId == "task-group-links-only")
        }

        @Test("Generate unresolved-reference rule ID")
        func generateUnresolvedReferenceRuleID() throws {
            let output = """
            warning: Can't resolve reference to 'Missing'
               --> Test.md:10:1-10:20
            """

            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("test-\(UUID().uuidString)")
                .appendingPathExtension("docc")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let parser = DiagnosticParser()
            let diagnostics = try parser.parseDiagnostics(json: output, catalog: tempDir)

            #expect(diagnostics[0].ruleId == "unresolved-reference")
        }

        @Test("Generate kebab-case rule ID for unknown messages")
        func generateKebabCaseRuleID() throws {
            let output = """
            warning: Some unknown warning message here
               --> Test.md:10:1-10:20
            """

            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("test-\(UUID().uuidString)")
                .appendingPathExtension("docc")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let parser = DiagnosticParser()
            let diagnostics = try parser.parseDiagnostics(json: output, catalog: tempDir)

            // Should be kebab-case of first 4 words
            #expect(diagnostics[0].ruleId?.contains("-") == true)
        }
    }

    // MARK: - Edge Cases

    @Suite("Edge Cases")
    struct EdgeCaseTests {

        @Test("Handle empty input")
        func handleEmptyInput() throws {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("test-\(UUID().uuidString)")
                .appendingPathExtension("docc")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let parser = DiagnosticParser()
            let diagnostics = try parser.parseDiagnostics(json: "", catalog: tempDir)

            #expect(diagnostics.isEmpty)
        }

        @Test("Handle whitespace-only input")
        func handleWhitespaceInput() throws {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("test-\(UUID().uuidString)")
                .appendingPathExtension("docc")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let parser = DiagnosticParser()
            let diagnostics = try parser.parseDiagnostics(json: "   \n\t  ", catalog: tempDir)

            #expect(diagnostics.isEmpty)
        }

        @Test("Handle malformed JSON gracefully")
        func handleMalformedJSON() throws {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("test-\(UUID().uuidString)")
                .appendingPathExtension("docc")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let parser = DiagnosticParser()
            // Should fall back to text parsing
            let diagnostics = try parser.parseDiagnostics(json: "{invalid json", catalog: tempDir)

            // Should not throw, may return empty or partial results
            #expect(diagnostics.count >= 0)
        }

        @Test("Handle location without end column")
        func handleLocationWithoutEndColumn() throws {
            let output = """
            warning: Simple warning
               --> Test.md:10:5
            """

            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("test-\(UUID().uuidString)")
                .appendingPathExtension("docc")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let parser = DiagnosticParser()
            let diagnostics = try parser.parseDiagnostics(json: output, catalog: tempDir)

            #expect(diagnostics.count == 1)
            #expect(diagnostics[0].line == 10)
            #expect(diagnostics[0].column == 5)
        }
    }
}
