import ArgumentParser
import Foundation

@main
struct DocCLint: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "docc-lint",
        abstract: "Validate DocC documentation with source file mapping and actionable diagnostics.",
        version: "1.0.0",
        subcommands: [LintCommand.self, CacheCommand.self],
        defaultSubcommand: LintCommand.self
    )
}
