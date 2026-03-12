import Foundation

/// Rule that checks for task group list items containing more than just symbol links
/// DocC requires task group list items to contain ONLY a symbol link like `- ``Symbol```
public struct TaskGroupRule {
    public static let ruleId = "task-group-links-only"

    public init() {}

    /// Check a single markdown file for task group violations
    /// - Parameters:
    ///   - content: The markdown file content
    ///   - fileURL: The URL of the file being checked
    /// - Returns: Array of diagnostics for any violations found
    public func check(content: String, fileURL: URL) -> [MappedDiagnostic] {
        var diagnostics: [MappedDiagnostic] = []
        let lines = content.components(separatedBy: .newlines)

        var inTopicsSection = false
        var inTaskGroup = false

        for (index, line) in lines.enumerated() {
            let lineNumber = index + 1  // 1-indexed
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            // Detect Topics section start
            if trimmedLine.hasPrefix("## Topics") {
                inTopicsSection = true
                inTaskGroup = false
                continue
            }

            // Detect new H2 section (ends Topics)
            if trimmedLine.hasPrefix("## ") && !trimmedLine.hasPrefix("## Topics") {
                inTopicsSection = false
                inTaskGroup = false
                continue
            }

            // Detect task group header (H3 within Topics)
            if inTopicsSection && trimmedLine.hasPrefix("### ") {
                inTaskGroup = true
                continue
            }

            // Check list items within task groups
            if inTaskGroup && trimmedLine.hasPrefix("- ") {
                if let diagnostic = checkListItem(line: line, lineNumber: lineNumber, fileURL: fileURL) {
                    diagnostics.append(diagnostic)
                }
            }
        }

        return diagnostics
    }

    /// Check if a list item contains only a valid symbol link
    private func checkListItem(line: String, lineNumber: Int, fileURL: URL) -> MappedDiagnostic? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Remove the "- " prefix
        guard trimmed.hasPrefix("- ") else { return nil }
        let content = String(trimmed.dropFirst(2))

        // Valid formats:
        // - ``Symbol``
        // - <doc:Article>
        // - ``Symbol/method(_:)``

        // Check for pure symbol link: ``...``
        let symbolLinkPattern = #"^``[^`]+``$"#
        if content.range(of: symbolLinkPattern, options: .regularExpression) != nil {
            return nil  // Valid
        }

        // Check for doc link: <doc:...>
        let docLinkPattern = #"^<doc:[^>]+>$"#
        if content.range(of: docLinkPattern, options: .regularExpression) != nil {
            return nil  // Valid
        }

        // Check for article link: <doc:ArticleName>
        let articlePattern = #"^<doc:[A-Za-z0-9_-]+>$"#
        if content.range(of: articlePattern, options: .regularExpression) != nil {
            return nil  // Valid
        }

        // If we get here, it's an invalid task group item
        let column = line.distance(from: line.startIndex, to: line.firstIndex(of: "-") ?? line.startIndex) + 1
        let endColumn = column + line.trimmingCharacters(in: .whitespaces).count

        // Determine what's wrong
        let message: String
        let suggestedFix: SuggestedFix?

        if content.contains("``") && content.count > content.filter({ $0 != "`" }).count + 4 {
            // Has symbol link but also extra content
            message = "Only links are allowed in task group list items; found additional text after symbol link"
            // Try to extract just the symbol link
            if let match = content.range(of: #"``[^`]+``"#, options: .regularExpression) {
                let symbolLink = String(content[match])
                suggestedFix = SuggestedFix(
                    description: "Remove text after symbol link",
                    replacement: "- \(symbolLink)"
                )
            } else {
                suggestedFix = nil
            }
        } else if !content.contains("``") && !content.contains("<doc:") {
            // No symbol link at all
            message = "Only links are allowed in task group list items; this item has no symbol link"
            suggestedFix = SuggestedFix(
                description: "Remove this line or convert to a symbol link",
                replacement: ""
            )
        } else {
            message = "Only links are allowed in task group list items"
            suggestedFix = nil
        }

        return MappedDiagnostic(
            file: fileURL.path,
            line: lineNumber,
            column: column,
            endColumn: endColumn,
            severity: .warning,
            message: message,
            content: line,
            ruleId: Self.ruleId,
            suggestedFix: suggestedFix
        )
    }
}
