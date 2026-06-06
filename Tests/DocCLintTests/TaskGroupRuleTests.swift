import Testing
import Foundation
@testable import DocCLint

@Suite("TaskGroupRule Tests")
struct TaskGroupRuleTests {

    let rule = TaskGroupRule()
    let testURL = URL(fileURLWithPath: "/test/Test.md")

    // MARK: - Valid Cases (No Diagnostics)

    @Suite("Valid Task Group Items")
    struct ValidCasesTests {
        let rule = TaskGroupRule()
        let testURL = URL(fileURLWithPath: "/test/Test.md")

        @Test("Pure symbol link is valid")
        func pureSymbolLink() {
            let content = """
            ## Topics

            ### Basic Functions

            - ``calculate()``
            """

            let diagnostics = rule.check(content: content, fileURL: testURL)
            #expect(diagnostics.isEmpty)
        }

        @Test("Symbol link with path is valid")
        func symbolLinkWithPath() {
            let content = """
            ## Topics

            ### Methods

            - ``MyClass/myMethod(_:)``
            """

            let diagnostics = rule.check(content: content, fileURL: testURL)
            #expect(diagnostics.isEmpty)
        }

        @Test("Doc link is valid")
        func docLink() {
            let content = """
            ## Topics

            ### Articles

            - <doc:GettingStarted>
            """

            let diagnostics = rule.check(content: content, fileURL: testURL)
            #expect(diagnostics.isEmpty)
        }

        @Test("Multiple valid items")
        func multipleValidItems() {
            let content = """
            ## Topics

            ### Core Types

            - ``Calculator``
            - ``Result``
            - <doc:Overview>
            """

            let diagnostics = rule.check(content: content, fileURL: testURL)
            #expect(diagnostics.isEmpty)
        }

        @Test("List items outside Topics section are ignored")
        func listOutsideTopics() {
            let content = """
            # Overview

            Here are some features:

            - Feature one with text
            - Feature two with more text

            ## Topics

            ### Types

            - ``MyType``
            """

            let diagnostics = rule.check(content: content, fileURL: testURL)
            #expect(diagnostics.isEmpty)
        }

        @Test("List items in other H2 sections are ignored")
        func listInOtherSection() {
            let content = """
            ## Topics

            ### Types

            - ``MyType``

            ## See Also

            - Some other text here is fine
            """

            let diagnostics = rule.check(content: content, fileURL: testURL)
            #expect(diagnostics.isEmpty)
        }
    }

    // MARK: - Invalid Cases (Should Produce Diagnostics)

    @Suite("Invalid Task Group Items")
    struct InvalidCasesTests {
        let rule = TaskGroupRule()
        let testURL = URL(fileURLWithPath: "/test/Test.md")

        @Test("Symbol link with trailing text is invalid")
        func symbolLinkWithTrailingText() {
            let content = """
            ## Topics

            ### Methods

            - ``calculate()`` - Calculates the result
            """

            let diagnostics = rule.check(content: content, fileURL: testURL)
            #expect(diagnostics.count == 1)
            #expect(diagnostics[0].ruleId == "task-group-links-only")
            #expect(diagnostics[0].line == 5)
        }

        @Test("Plain text item is invalid")
        func plainTextItem() {
            let content = """
            ## Topics

            ### Methods

            - Some plain text without a link
            """

            let diagnostics = rule.check(content: content, fileURL: testURL)
            #expect(diagnostics.count == 1)
            #expect(diagnostics[0].message.contains("no symbol link"))
        }

        @Test("Multiple invalid items")
        func multipleInvalidItems() {
            let content = """
            ## Topics

            ### Methods

            - ``validSymbol()``
            - ``symbol()`` with extra text
            - plain text item
            - ``anotherValid``
            """

            let diagnostics = rule.check(content: content, fileURL: testURL)
            #expect(diagnostics.count == 2)
        }

        @Test("Symbol link with description on same line")
        func symbolWithDescription() {
            let content = """
            ## Topics

            ### Statistical Functions

            - ``mean(_:)`` Calculates arithmetic mean
            """

            let diagnostics = rule.check(content: content, fileURL: testURL)
            #expect(diagnostics.count == 1)
            #expect(diagnostics[0].message == "Only links are allowed in task group list items")
        }

        @Test("Diagnostic includes correct line number")
        func correctLineNumber() {
            let content = """
            Line 1
            Line 2
            ## Topics
            Line 4
            ### Group
            - ``valid``
            - invalid text here
            """

            let diagnostics = rule.check(content: content, fileURL: testURL)
            #expect(diagnostics.count == 1)
            #expect(diagnostics[0].line == 7)
        }

        @Test("Diagnostic includes file path")
        func includesFilePath() {
            let content = """
            ## Topics

            ### Test

            - invalid item
            """

            let customURL = URL(fileURLWithPath: "/path/to/MyModule.docc/Article.md")
            let diagnostics = rule.check(content: content, fileURL: customURL)

            #expect(diagnostics.count == 1)
            #expect(diagnostics[0].file == "/path/to/MyModule.docc/Article.md")
        }
    }

    // MARK: - Edge Cases

    @Suite("Edge Cases")
    struct EdgeCaseTests {
        let rule = TaskGroupRule()
        let testURL = URL(fileURLWithPath: "/test/Test.md")

        @Test("Empty file produces no diagnostics")
        func emptyFile() {
            let diagnostics = rule.check(content: "", fileURL: testURL)
            #expect(diagnostics.isEmpty)
        }

        @Test("File without Topics section")
        func noTopicsSection() {
            let content = """
            # My Article

            Some content here.

            ## Details

            More content.
            """

            let diagnostics = rule.check(content: content, fileURL: testURL)
            #expect(diagnostics.isEmpty)
        }

        @Test("Topics section with no task groups")
        func topicsWithNoGroups() {
            let content = """
            ## Topics

            Some text in topics but no H3 headers.
            """

            let diagnostics = rule.check(content: content, fileURL: testURL)
            #expect(diagnostics.isEmpty)
        }

        @Test("Multiple Topics sections")
        func multipleTopicsSections() {
            let content = """
            ## Topics

            ### First

            - ``valid``

            ## Other

            - text is fine here

            ## Topics

            ### Second

            - invalid text
            """

            let diagnostics = rule.check(content: content, fileURL: testURL)
            // Second Topics section should also be checked
            #expect(diagnostics.count == 1)
            #expect(diagnostics[0].line == 15)
        }

        @Test("Nested backticks in symbol")
        func nestedBackticks() {
            let content = """
            ## Topics

            ### Operators

            - ``+(_:_:)``
            """

            let diagnostics = rule.check(content: content, fileURL: testURL)
            #expect(diagnostics.isEmpty)
        }

        @Test("Complex symbol paths")
        func complexSymbolPaths() {
            let content = """
            ## Topics

            ### Methods

            - ``Array/Element``
            - ``Dictionary/Key``
            - ``MyModule/MyClass/myMethod(param1:param2:)``
            """

            let diagnostics = rule.check(content: content, fileURL: testURL)
            #expect(diagnostics.isEmpty)
        }
    }

    // MARK: - Real World Examples

    @Suite("Real World Examples")
    struct RealWorldTests {
        let rule = TaskGroupRule()
        let testURL = URL(fileURLWithPath: "/test/Statistics.md")

        @Test("BusinessMath-style task group violation")
        func businessMathStyleViolation() {
            let content = """
            ## Topics

            ### Descriptive Statistics

            - ``mean(_:)`` Calculates the arithmetic mean of a dataset
            - ``median(_:)`` Finds the middle value
            - ``standardDeviation(_:)``
            """

            let diagnostics = rule.check(content: content, fileURL: testURL)
            #expect(diagnostics.count == 2)  // First two have descriptions
        }

        @Test("Proper task group format")
        func properTaskGroupFormat() {
            let content = """
            ## Topics

            ### Descriptive Statistics

            - ``mean(_:)``
            - ``median(_:)``
            - ``standardDeviation(_:)``

            ### Probability Distributions

            - ``normalPDF(x:mean:stdDev:)``
            - ``normalCDF(x:mean:stdDev:)``
            """

            let diagnostics = rule.check(content: content, fileURL: testURL)
            #expect(diagnostics.isEmpty)
        }
    }
}
