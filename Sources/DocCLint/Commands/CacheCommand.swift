import ArgumentParser
import Foundation

/// Commands for managing the lint cache
struct CacheCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cache",
        abstract: "Manage the docc-lint cache",
        subcommands: [ClearCommand.self, StatusCommand.self]
    )

    struct ClearCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "clear",
            abstract: "Clear the lint cache"
        )

        @Option(name: .customLong("cache-path"), help: "Custom cache location")
        var cachePath: String?

        @Argument(help: "Project root directory")
        var path: String?

        func run() async throws {
            let projectPath = path ?? FileManager.default.currentDirectoryPath
            let cacheLocation = cachePath ?? "\(projectPath)/.docc-lint-cache"

            let cache = HashCache(path: cacheLocation)
            try cache.clear()
            print("Cache cleared: \(cacheLocation)")
        }
    }

    struct StatusCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Show cache status and statistics"
        )

        @Option(name: .customLong("cache-path"), help: "Custom cache location")
        var cachePath: String?

        @Argument(help: "Project root directory")
        var path: String?

        func run() async throws {
            let projectPath = path ?? FileManager.default.currentDirectoryPath
            let cacheLocation = cachePath ?? "\(projectPath)/.docc-lint-cache"

            let cache = HashCache(path: cacheLocation)
            try cache.load()

            let stats = cache.statistics()
            print("Cache Status")
            print("============")
            print("Location: \(cacheLocation)")
            print("Entries: \(stats.entryCount)")
            print("Last updated: \(stats.lastUpdated?.formatted() ?? "Never")")

            if stats.entryCount > 0 {
                print("\nCached files with issues:")
                for entry in stats.entriesWithIssues {
                    let summary = entry.lastScanSummary!
                    print("  \(entry.path): \(summary.errors) errors, \(summary.warnings) warnings")
                }
            }
        }
    }
}
