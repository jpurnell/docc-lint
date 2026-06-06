import ArgumentParser
import Foundation
import os

/// Commands for managing the lint cache
struct CacheCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cache",
        abstract: "Manage the docc-lint cache",
        subcommands: [ClearCommand.self, StatusCommand.self]
    )

    /// Subcommand to clear the lint cache
    struct ClearCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "clear",
            abstract: "Clear the lint cache"
        )

        /// Logger for diagnostic messages
        private var logger: Logger { Logger(subsystem: "com.docc-lint", category: "ClearCommand") } // LIVE: logging infrastructure

        @Option(name: .customLong("cache-path"), help: "Custom cache location")
        var cachePath: String?

        @Argument(help: "Project root directory")
        var path: String?

        /// Initialize a new ClearCommand
        public init() {}

        func run() async throws {
            let projectPath = path ?? FileManager.default.currentDirectoryPath
            let cacheLocation = cachePath ?? "\(projectPath)/.docc-lint-cache"

            let cache = HashCache(path: cacheLocation)
            try cache.clear()
            FileHandle.standardOutput.write(Data(("Cache cleared: \(cacheLocation)" + "\n").utf8))
        }
    }

    /// Subcommand to display cache status and statistics
    struct StatusCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Show cache status and statistics"
        )

        /// Logger for diagnostic messages
        private var logger: Logger { Logger(subsystem: "com.docc-lint", category: "StatusCommand") } // LIVE: logging infrastructure

        @Option(name: .customLong("cache-path"), help: "Custom cache location")
        var cachePath: String?

        @Argument(help: "Project root directory")
        var path: String?

        /// Initialize a new StatusCommand
        public init() {}

        func run() async throws {
            let projectPath = path ?? FileManager.default.currentDirectoryPath
            let cacheLocation = cachePath ?? "\(projectPath)/.docc-lint-cache"

            let cache = HashCache(path: cacheLocation)
            try cache.load()

            let stats = cache.statistics()
            FileHandle.standardOutput.write(Data(("Cache Status" + "\n").utf8))
            FileHandle.standardOutput.write(Data(("============" + "\n").utf8))
            FileHandle.standardOutput.write(Data(("Location: \(cacheLocation)" + "\n").utf8))
            FileHandle.standardOutput.write(Data(("Entries: \(stats.entryCount)" + "\n").utf8))
            FileHandle.standardOutput.write(Data(("Last updated: \(stats.lastUpdated?.formatted() ?? "Never")" + "\n").utf8))

            if stats.entryCount > 0 {
                FileHandle.standardOutput.write(Data(("\nCached files with issues:" + "\n").utf8))
                for entry in stats.entriesWithIssues {
                    guard let summary = entry.lastScanSummary else { continue }
                    FileHandle.standardOutput.write(Data(("  \(entry.path): \(summary.errors) errors, \(summary.warnings) warnings" + "\n").utf8))
                }
            }
        }
    }
}
