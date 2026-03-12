import Foundation

/// Fast markdown-based linter that processes files in parallel
/// This provides instant feedback for syntax-based rules without needing docc convert
public actor MarkdownLinter {
    private let verbose: Bool
    private let rules: [any MarkdownRule]

    public init(verbose: Bool = false) {
        self.verbose = verbose
        self.rules = [
            TaskGroupRule()
        ]
    }

    /// Lint multiple markdown files in parallel
    /// - Parameter files: Array of file URLs to lint
    /// - Returns: Array of scan results, one per file
    public func lintFiles(_ files: [URL]) async -> [ScanResult] {
        await withTaskGroup(of: ScanResult.self) { group in
            for fileURL in files {
                group.addTask {
                    await self.lintFile(fileURL)
                }
            }

            var results: [ScanResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }

    /// Lint a single markdown file
    private func lintFile(_ fileURL: URL) async -> ScanResult {
        let startTime = Date()

        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return ScanResult(
                path: fileURL.path,
                fileType: .markdownInCatalog,
                diagnostics: [],
                success: false,
                scanDuration: Date().timeIntervalSince(startTime)
            )
        }

        var allDiagnostics: [MappedDiagnostic] = []

        for rule in rules {
            let diagnostics = rule.check(content: content, fileURL: fileURL)
            allDiagnostics.append(contentsOf: diagnostics)
        }

        return ScanResult(
            path: fileURL.path,
            fileType: .markdownInCatalog,
            diagnostics: allDiagnostics,
            success: true,
            scanDuration: Date().timeIntervalSince(startTime)
        )
    }
}

/// Protocol for markdown-based rules
public protocol MarkdownRule {
    var ruleId: String { get }
    func check(content: String, fileURL: URL) -> [MappedDiagnostic]
}

extension TaskGroupRule: MarkdownRule {
    public var ruleId: String { Self.ruleId }
}
