import ArgumentParser
import Foundation
import os

/// Main lint command for validating DocC documentation
struct LintCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lint",
        abstract: "Validate DocC documentation and report issues with source locations."
    )

    /// Logger for diagnostic and progress messages
    private var logger: Logger { Logger(subsystem: "com.docc-lint", category: "LintCommand") }

    // MARK: - Arguments

    @Argument(help: "Project root directory to scan (default: current directory)")
    var path: String?

    @Option(name: .customLong("file"), help: "Lint a single documentation file (requires --full mode)")
    var singleFile: String?

    // MARK: - Validation Mode

    @Flag(name: .long, help: "Full validation with symbol graph generation (slower, more comprehensive)")
    var full: Bool = false

    @Flag(name: .long, help: "Syntax-only validation without compilation (faster, default)")
    var syntaxOnly: Bool = false

    // MARK: - Output Options

    @Option(name: [.short, .customLong("format")], help: "Output format: terminal, json, csv, sarif")
    var format: OutputFormat = .terminal

    @Option(name: [.short, .customLong("output")], help: "Write output to file instead of stdout")
    var outputFile: String?

    @Flag(name: .customLong("no-color"), help: "Disable ANSI colors in terminal output")
    var noColor: Bool = false

    // MARK: - Filtering

    @Flag(name: .customLong("include-swift-docs"), help: "Also lint /// doc comments in Swift files")
    var includeSwiftDocs: Bool = false

    @Option(name: .customLong("ignore"), parsing: .upToNextOption, help: "Glob patterns to ignore (can be repeated)")
    var ignorePatterns: [String] = []

    @Option(name: .customLong("severity"), help: "Minimum severity to report: error, warning, note")
    var minimumSeverity: DiagnosticSeverity = .warning

    // MARK: - Caching

    @Flag(name: .customLong("no-cache"), help: "Disable incremental caching")
    var noCache: Bool = false

    @Flag(name: .customLong("clear-cache"), help: "Clear cache before running")
    var clearCache: Bool = false

    @Option(name: .customLong("cache-path"), help: "Custom cache location")
    var cachePath: String?

    // MARK: - Fix Options

    @Flag(name: .long, help: "Apply suggested fixes automatically")
    var fix: Bool = false

    @Flag(name: .customLong("dry-run"), help: "Preview fixes without applying (requires --fix)")
    var dryRun: Bool = false

    // MARK: - CI/CD

    @Flag(name: .long, help: "Treat warnings as errors (exit code 2)")
    var strict: Bool = false

    @Flag(name: .customLong("github-actions"), help: "Output GitHub Actions workflow commands")
    var githubActions: Bool = false

    // MARK: - Verbosity

    @Flag(name: [.short, .long], help: "Verbose output")
    var verbose: Bool = false

    @Flag(name: [.short, .long], help: "Only output errors")
    var quiet: Bool = false

    /// Initialize a new LintCommand
    public init() {}

    // MARK: - Validation

    mutating func validate() throws {
        if full && syntaxOnly {
            throw ValidationError("Cannot specify both --full and --syntax-only")
        }
        if dryRun && !fix {
            throw ValidationError("--dry-run requires --fix")
        }
        if verbose && quiet {
            throw ValidationError("Cannot specify both --verbose and --quiet")
        }
        if singleFile != nil && !full {
            throw ValidationError("--file requires --full mode")
        }
    }

    // MARK: - Execution

    func run() async throws {
        let startTime = Date()
        var timingStart = Date()
        let projectPath = path ?? FileManager.default.currentDirectoryPath

        // Configure reporter
        let useColor = !noColor && format == .terminal && outputFile == nil
        let reporter = createReporter(useColor: useColor)

        if verbose {
            let scanMsg = "Scanning: \(projectPath)"
            reporter.info(scanMsg)
            let modeDesc = full ? "full (file-by-file)" : "syntax-only"
            let modeMsg = "Mode: " + modeDesc
            reporter.info(modeMsg)
        }

        // Initialize components
        let scanner = Scanner()
        let cache = noCache ? nil : HashCache(path: cachePath ?? "\(projectPath)/.docc-lint-cache")

        // Clear cache if requested
        if clearCache, let cache = cache {
            try cache.clear()
            if verbose {
                reporter.info("Cache cleared")
            }
        }

        // Load cache
        if verbose { logger.info("  [timing] Loading cache..."); timingStart = Date() }
        try cache?.load()
        if verbose { logger.info("  [timing] Cache loaded in \(Date().timeIntervalSince(timingStart), privacy: .public)s") }

        // SINGLE FILE MODE: Process just one file
        if let singleFilePath = singleFile {
            try await processSingleFile(
                singleFilePath,
                projectPath: projectPath,
                cache: cache,
                reporter: reporter,
                startTime: startTime
            )
            return
        }

        // Discover files
        if verbose { logger.info("  [timing] Discovering files..."); timingStart = Date() }
        let discoveredFiles = try await scanner.discoverFiles(
            at: URL(fileURLWithPath: projectPath),
            options: ScanOptions(
                includeSwiftDocs: includeSwiftDocs,
                ignorePatterns: ignorePatterns
            )
        )

        // Extract documentation files from Scanner results (already enumerated)
        let markdownFiles = discoveredFiles.compactMap { file -> URL? in
            switch file.type {
            case .markdownInCatalog:
                return file.url
            default:
                return nil
            }
        }

        if verbose {
            logger.info("  [timing] File discovery took \(Date().timeIntervalSince(timingStart), privacy: .public)s")
            let foundMsg = "Found " + String(markdownFiles.count) + " documentation files to scan"
            reporter.info(foundMsg)
        }

        // Quick check: are ALL files already cached?
        if verbose { logger.info("  [timing] Checking cache..."); timingStart = Date() }
        let uncachedCount: Int
        if let cache = cache {
            uncachedCount = markdownFiles.filter { cache.needsScan($0) }.count
        } else {
            uncachedCount = markdownFiles.count
        }
        if verbose { logger.info("  [timing] Cache check took \(Date().timeIntervalSince(timingStart), privacy: .public)s") }

        if uncachedCount == 0 {
            if verbose {
                let cacheMsg = "All " + String(markdownFiles.count) + " files cached, skipping symbol graphs and processing"
                reporter.info(cacheMsg)
            }
            // Return empty results - everything is cached
            let scanDuration = Date().timeIntervalSince(startTime)

            let report = LintReport(
                version: "1.0.0",
                timestamp: Date(),
                summary: LintReport.Summary(
                    filesScanned: markdownFiles.count,
                    filesWithIssues: 0,
                    totalErrors: 0,
                    totalWarnings: 0,
                    totalNotes: 0,
                    scanDuration: scanDuration
                ),
                diagnostics: [],
                fileResults: nil
            )

            let output = try reporter.format(report)
            if let outputFile = outputFile {
                try output.write(toFile: outputFile, atomically: true, encoding: .utf8)
            } else {
                FileHandle.standardOutput.write(Data((output + "\n").utf8))
            }
            return  // Early exit - nothing to do
        }

        // For full mode, generate symbol graphs ONCE for the entire project
        // NOTE: We use FULL symbol graphs (not filtered) to ensure accurate parsing.
        // Filtered graphs caused false positives because DocC couldn't resolve all symbols.
        var symbolGraphDir: URL?
        if full {
            if verbose {
                reporter.info("Generating symbol graphs for project (this is done once)...")
            }

            let generator = SymbolGraphGenerator()
            symbolGraphDir = try await generator.generateSymbolGraphs(
                projectRoot: URL(fileURLWithPath: projectPath),
                verbose: verbose,
                moduleNames: nil  // Use full symbol graphs for accuracy
            )

            if symbolGraphDir != nil && verbose {
                reporter.info("Symbol graph generation complete")
            }
        }

        // Find unique catalogs from the markdown files
        var catalogURLs = Set<URL>()
        for file in markdownFiles {
            var current = file.deletingLastPathComponent()
            while !current.path.isEmpty && current.path != "/" {
                if current.pathExtension == "docc" {
                    catalogURLs.insert(current)
                    break
                }
                current = current.deletingLastPathComponent()
            }
        }

        if verbose {
            let catMsg = "Processing " + String(catalogURLs.count) + " catalog(s) using full catalog mode..."
            reporter.info(catMsg)
        }

        // Process each catalog using CatalogProcessor (full catalog mode = accurate warnings)
        let catalogProcessor = CatalogProcessor(
            verbose: verbose,
            symbolGraphDir: symbolGraphDir
        )

        var allDiagnosticsFromCatalogs: [MappedDiagnostic] = []
        for catalogURL in catalogURLs {
            let diagnostics = try await catalogProcessor.processCatalog(catalogURL)
            // Filter to only include diagnostics from files within our project (not dependencies)
            let filteredDiags = diagnostics.filter { diag in
                guard let filePath = diag.file else { return false }
                // Exclude .build/checkouts (dependencies)
                return !filePath.contains(".build/checkouts") && !filePath.contains(".build/index-build/checkouts")
            }
            allDiagnosticsFromCatalogs.append(contentsOf: filteredDiags)
        }

        // Create file results for compatibility (group by file)
        var fileResultsDict: [URL: [MappedDiagnostic]] = [:]
        for diag in allDiagnosticsFromCatalogs {
            if let filePath = diag.file {
                let fileURL = URL(fileURLWithPath: filePath)
                fileResultsDict[fileURL, default: []].append(diag)
            }
        }

        let fileResults = fileResultsDict.map { (url, diags) in
            FileResult(file: url, diagnostics: diags, duration: 0)
        }

        // Filter by severity
        let allDiagnostics = allDiagnosticsFromCatalogs.filter { $0.severity >= minimumSeverity }

        let scanDuration = Date().timeIntervalSince(startTime)

        // Count files with issues from results
        let filesWithIssues = fileResults.filter { !$0.diagnostics.isEmpty }.count

        let report = LintReport(
            version: "1.0.0",
            timestamp: Date(),
            summary: LintReport.Summary(
                filesScanned: markdownFiles.count,
                filesWithIssues: filesWithIssues,
                totalErrors: allDiagnostics.filter { $0.severity == .error }.count,
                totalWarnings: allDiagnostics.filter { $0.severity == .warning }.count,
                totalNotes: allDiagnostics.filter { $0.severity == .note }.count,
                scanDuration: scanDuration
            ),
            diagnostics: allDiagnostics,
            fileResults: nil
        )

        // Output results
        let output = try reporter.format(report)

        if let outputFile = outputFile {
            try output.write(toFile: outputFile, atomically: true, encoding: .utf8)
            if !quiet {
                FileHandle.standardOutput.write(Data(("Results written to: \(outputFile)" + "\n").utf8))
            }
        } else {
            FileHandle.standardOutput.write(Data((output + "\n").utf8))
        }

        // GitHub Actions annotations
        if githubActions {
            for diagnostic in allDiagnostics {
                let level = diagnostic.severity == .error ? "error" : "warning"
                if let file = diagnostic.file {
                    FileHandle.standardOutput.write(Data(("::\(level) file=\(file),line=\(diagnostic.line),col=\(diagnostic.column)::\(diagnostic.message)" + "\n").utf8))
                }
            }
        }

        // Exit code
        let hasErrors = report.summary.totalErrors > 0
        let hasWarnings = report.summary.totalWarnings > 0

        if hasErrors {
            throw ExitCode(2)
        } else if hasWarnings && strict {
            throw ExitCode(2)
        } else if hasWarnings {
            throw ExitCode(1)
        }
    }

    /// Extract module names from .docc catalog paths
    /// For example: "/path/to/BusinessMath.docc/Article.md" -> "BusinessMath"
    private func extractModuleNames(from files: [URL]) -> [String] {
        var moduleNames = Set<String>()

        for file in files {
            // Walk up the path to find the .docc catalog
            var current = file.deletingLastPathComponent()
            while !current.path.isEmpty && current.path != "/" {
                if current.pathExtension == "docc" {
                    // Extract module name from catalog name (e.g., "BusinessMath.docc" -> "BusinessMath")
                    let catalogName = current.deletingPathExtension().lastPathComponent
                    moduleNames.insert(catalogName)
                    break
                }
                current = current.deletingLastPathComponent()
            }
        }

        return Array(moduleNames).sorted()
    }

    /// Create the appropriate reporter based on the selected output format
    private func createReporter(useColor: Bool) -> any Reporter {
        switch format {
        case .terminal:
            return TerminalReporter(useColor: useColor, verbose: verbose, quiet: quiet)
        case .json:
            return JSONReporter()
        case .csv:
            return CSVReporter()
        case .sarif:
            return SARIFReporter()
        }
    }

    /// Process a single documentation file with full symbol graph support
    private func processSingleFile(
        _ filePath: String,
        projectPath: String,
        cache: HashCache?,
        reporter: any Reporter,
        startTime: Date
    ) async throws {
        let fileURL = URL(fileURLWithPath: filePath).standardized

        // Verify file exists and is a documentation file
        guard (try? fileURL.checkResourceIsReachable()) ?? false else { // silent: existence check
            throw ValidationError("File not found: \(filePath)")
        }

        let ext = fileURL.pathExtension.lowercased()
        guard ext == "md" || ext == "tutorial" else {
            throw ValidationError("File must be .md or .tutorial: \(filePath)")
        }

        if verbose {
            let fileMsg = "Processing single file: \(filePath)"
            reporter.info(fileMsg)
        }

        // Check cache first
        if let cache = cache, !cache.needsScan(fileURL) {
            if verbose {
                reporter.info("File is cached and unchanged, skipping")
            }

            let report = LintReport(
                version: "1.0.0",
                timestamp: Date(),
                summary: LintReport.Summary(
                    filesScanned: 1,
                    filesWithIssues: 0,
                    totalErrors: 0,
                    totalWarnings: 0,
                    totalNotes: 0,
                    scanDuration: Date().timeIntervalSince(startTime)
                ),
                diagnostics: [],
                fileResults: nil
            )

            let output = try reporter.format(report)
            FileHandle.standardOutput.write(Data((output + "\n").utf8))
            return
        }

        // Generate symbol graphs with module filtering
        if verbose {
            reporter.info("Generating symbol graphs (or using cached)...")
        }

        // Extract module name from file path
        let moduleNames = extractModuleNames(from: [fileURL])
        if verbose && !moduleNames.isEmpty {
            let modMsg = "Filtering symbol graphs to modules: " + moduleNames.joined(separator: ", ")
            reporter.info(modMsg)
        }

        let generator = SymbolGraphGenerator()
        let symbolGraphDir = try await generator.generateSymbolGraphs(
            projectRoot: URL(fileURLWithPath: projectPath),
            verbose: verbose,
            moduleNames: moduleNames.isEmpty ? nil : moduleNames
        )

        // Process the single file using BatchAllProcessor
        let processor = BatchAllProcessor(
            verbose: verbose,
            symbolGraphDir: symbolGraphDir,
            cache: cache
        )

        let fileResults = try await processor.processFiles([fileURL])

        // Aggregate results
        let allDiagnostics = fileResults.flatMap { $0.diagnostics }
            .filter { $0.severity >= minimumSeverity }

        let scanDuration = Date().timeIntervalSince(startTime)

        let report = LintReport(
            version: "1.0.0",
            timestamp: Date(),
            summary: LintReport.Summary(
                filesScanned: 1,
                filesWithIssues: fileResults.filter { !$0.diagnostics.isEmpty }.count,
                totalErrors: allDiagnostics.filter { $0.severity == .error }.count,
                totalWarnings: allDiagnostics.filter { $0.severity == .warning }.count,
                totalNotes: allDiagnostics.filter { $0.severity == .note }.count,
                scanDuration: scanDuration
            ),
            diagnostics: allDiagnostics,
            fileResults: nil
        )

        // Output results
        let output = try reporter.format(report)

        if let outputFile = outputFile {
            try output.write(toFile: outputFile, atomically: true, encoding: .utf8)
            if !quiet {
                FileHandle.standardOutput.write(Data(("Results written to: \(outputFile)" + "\n").utf8))
            }
        } else {
            FileHandle.standardOutput.write(Data((output + "\n").utf8))
        }

        // GitHub Actions annotations
        if githubActions {
            for diagnostic in allDiagnostics {
                let level = diagnostic.severity == .error ? "error" : "warning"
                if let file = diagnostic.file {
                    FileHandle.standardOutput.write(Data(("::\(level) file=\(file),line=\(diagnostic.line),col=\(diagnostic.column)::\(diagnostic.message)" + "\n").utf8))
                }
            }
        }

        // Exit code
        let hasErrors = report.summary.totalErrors > 0
        let hasWarnings = report.summary.totalWarnings > 0

        if hasErrors {
            throw ExitCode(2)
        } else if hasWarnings && strict {
            throw ExitCode(2)
        } else if hasWarnings {
            throw ExitCode(1)
        }
    }
}

// MARK: - Supporting Types

/// Output format options for lint results
enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
    /// Terminal-friendly formatted output with optional ANSI colors
    case terminal
    /// Machine-readable JSON output
    case json
    /// Comma-separated values output
    case csv
    /// Static Analysis Results Interchange Format
    case sarif
}

extension DiagnosticSeverity: ExpressibleByArgument {
    /// Initialize a DiagnosticSeverity from a command-line argument string
    public init?(argument: String) {
        self.init(rawValue: argument.lowercased())
    }
}
