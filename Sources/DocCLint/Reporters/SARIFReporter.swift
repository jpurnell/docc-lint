import Foundation

/// Reporter that outputs SARIF format for GitHub Code Scanning integration
public struct SARIFReporter: Reporter, Sendable {

    public init() {}

    public func format(_ report: LintReport) throws -> String {
        let sarif = SARIFOutput(
            version: "2.1.0",
            schema: "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json",
            runs: [
                SARIFRun(
                    tool: SARIFTool(
                        driver: SARIFDriver(
                            name: "docc-lint",
                            version: report.version,
                            informationUri: "https://github.com/your-repo/docc-lint",
                            rules: extractRules(from: report.diagnostics)
                        )
                    ),
                    results: report.diagnostics.map { toSARIFResult($0) }
                )
            ]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(sarif)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func extractRules(from diagnostics: [MappedDiagnostic]) -> [SARIFRule] {
        var rules: [String: SARIFRule] = [:]

        for diagnostic in diagnostics {
            guard let ruleId = diagnostic.ruleId, rules[ruleId] == nil else { continue }

            rules[ruleId] = SARIFRule(
                id: ruleId,
                name: ruleId.replacingOccurrences(of: "-", with: " ").capitalized,
                shortDescription: SARIFMessage(text: diagnostic.message),
                defaultConfiguration: SARIFRuleConfiguration(
                    level: diagnostic.severity == .error ? "error" : "warning"
                )
            )
        }

        return Array(rules.values)
    }

    private func toSARIFResult(_ diagnostic: MappedDiagnostic) -> SARIFResult {
        SARIFResult(
            ruleId: diagnostic.ruleId ?? "unknown",
            level: diagnostic.severity == .error ? "error" : "warning",
            message: SARIFMessage(text: diagnostic.message),
            locations: [
                SARIFLocation(
                    physicalLocation: SARIFPhysicalLocation(
                        artifactLocation: SARIFArtifactLocation(uri: diagnostic.file ?? "unknown"),
                        region: SARIFRegion(
                            startLine: diagnostic.line,
                            startColumn: diagnostic.column,
                            endColumn: diagnostic.endColumn,
                            snippet: diagnostic.content.map { SARIFSnippet(text: $0) }
                        )
                    )
                )
            ],
            fixes: diagnostic.suggestedFix.map { fix in
                [SARIFFix(
                    description: SARIFMessage(text: fix.description),
                    artifactChanges: [
                        SARIFArtifactChange(
                            artifactLocation: SARIFArtifactLocation(uri: diagnostic.file ?? "unknown"),
                            replacements: [
                                SARIFReplacement(
                                    deletedRegion: SARIFRegion(
                                        startLine: diagnostic.line,
                                        startColumn: diagnostic.column,
                                        endColumn: diagnostic.endColumn,
                                        snippet: nil
                                    ),
                                    insertedContent: SARIFInsertedContent(text: fix.replacement)
                                )
                            ]
                        )
                    ]
                )]
            }
        )
    }
}

// MARK: - SARIF Data Structures

private struct SARIFOutput: Codable {
    let version: String
    let schema: String
    let runs: [SARIFRun]

    enum CodingKeys: String, CodingKey {
        case version
        case schema = "$schema"
        case runs
    }
}

private struct SARIFRun: Codable {
    let tool: SARIFTool
    let results: [SARIFResult]
}

private struct SARIFTool: Codable {
    let driver: SARIFDriver
}

private struct SARIFDriver: Codable {
    let name: String
    let version: String
    let informationUri: String
    let rules: [SARIFRule]
}

private struct SARIFRule: Codable {
    let id: String
    let name: String
    let shortDescription: SARIFMessage
    let defaultConfiguration: SARIFRuleConfiguration
}

private struct SARIFRuleConfiguration: Codable {
    let level: String
}

private struct SARIFResult: Codable {
    let ruleId: String
    let level: String
    let message: SARIFMessage
    let locations: [SARIFLocation]
    let fixes: [SARIFFix]?
}

private struct SARIFMessage: Codable {
    let text: String
}

private struct SARIFLocation: Codable {
    let physicalLocation: SARIFPhysicalLocation
}

private struct SARIFPhysicalLocation: Codable {
    let artifactLocation: SARIFArtifactLocation
    let region: SARIFRegion
}

private struct SARIFArtifactLocation: Codable {
    let uri: String
}

private struct SARIFRegion: Codable {
    let startLine: Int
    let startColumn: Int
    let endColumn: Int
    let snippet: SARIFSnippet?
}

private struct SARIFSnippet: Codable {
    let text: String
}

private struct SARIFFix: Codable {
    let description: SARIFMessage
    let artifactChanges: [SARIFArtifactChange]
}

private struct SARIFArtifactChange: Codable {
    let artifactLocation: SARIFArtifactLocation
    let replacements: [SARIFReplacement]
}

private struct SARIFReplacement: Codable {
    let deletedRegion: SARIFRegion
    let insertedContent: SARIFInsertedContent
}

private struct SARIFInsertedContent: Codable {
    let text: String
}
