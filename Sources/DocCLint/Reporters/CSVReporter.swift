import Foundation

/// Reporter that outputs CSV format for spreadsheet compatibility
public struct CSVReporter: Reporter, Sendable {

    public init() {}

    public func format(_ report: LintReport) throws -> String {
        var output = "file,line,column,end_column,severity,message,content,rule_id\n"

        for diagnostic in report.diagnostics {
            let fields = [
                escapeCSV(diagnostic.file ?? ""),
                String(diagnostic.line),
                String(diagnostic.column),
                String(diagnostic.endColumn),
                diagnostic.severity.rawValue,
                escapeCSV(diagnostic.message),
                escapeCSV(diagnostic.content ?? ""),
                escapeCSV(diagnostic.ruleId ?? "")
            ]

            output += fields.joined(separator: ",")
            output += "\n"
        }

        return output
    }

    private func escapeCSV(_ value: String) -> String {
        // If the value contains comma, quote, or newline, wrap in quotes
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }
}
