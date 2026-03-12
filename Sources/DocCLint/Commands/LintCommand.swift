import ArgumentParser
import Foundation

/// Main lint command for validating DocC documentation
struct LintCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lint",
        abstract: "Validate DocC documentation and report issues with source locations."
    )

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
            reporter.info("Scanning: \(projectPath)")
            reporter.info("Mode: \(full ? "full (file-by-file)" : "syntax-only")")
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
        if verbose { print("  [timing] Loading cache..."); timingStart = Date() }
        try cache?.load()
        if verbose { print("  [timing] Cache loaded in \(Date().timeIntervalSince(timingStart))s") }

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
        if verbose { print("  [timing] Discovering files..."); timingStart = Date() }
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
            print("  [timing] File discovery took \(Date().timeIntervalSince(timingStart))s")
            reporter.info("Found \(markdownFiles.count) documentation files to scan")
        }

        // Quick check: are ALL files already cached?
        if verbose { print("  [timing] Checking cache..."); timingStart = Date() }
        let uncachedCount = cache != nil ? markdownFiles.filter { cache!.needsScan($0) }.count : markdownFiles.count
        if verbose { print("  [timing] Cache check took \(Date().timeIntervalSince(timingStart))s") }

        if uncachedCount == 0 {
            if verbose {
                reporter.info("All \(markdownFiles.count) files cached, skipping symbol graphs and processing")
            }
            // Return empty results - everything is cached
            let fileResults: [FileResult] = []
            let allDiagnostics: [MappedDiagnostic] = []
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
                diagnostics: allDiagnostics,
                fileResults: nil
            )

            let output = try reporter.format(report)
            if let outputFile = outputFile {
                try output.write(toFile: outputFile, atomically: true, encoding: .utf8)
            } else {
                print(output)
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
            reporter.info("Processing \(catalogURLs.count) catalog(s) using full catalog mode...")
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
        var allDiagnostics = allDiagnosticsFromCatalogs.filter { $0.severity >= minimumSeverity }

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
                print("Results written to: \(outputFile)")
            }
        } else {
            print(output)
        }

        // GitHub Actions annotations
        if githubActions {
            for diagnostic in allDiagnostics {
                let level = diagnostic.severity == .error ? "error" : "warning"
                if let file = diagnostic.file {
                    print("::\(level) file=\(file),line=\(diagnostic.line),col=\(diagnostic.column)::\(diagnostic.message)")
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
        let fileURL = URL(fileURLWithPath: filePath)

        // Verify file exists and is a documentation file
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw ValidationError("File not found: \(filePath)")
        }

        let ext = fileURL.pathExtension.lowercased()
        guard ext == "md" || ext == "tutorial" else {
            throw ValidationError("File must be .md or .tutorial: \(filePath)")
        }

        if verbose {
            reporter.info("Processing single file: \(filePath)")
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
            print(output)
            return
        }

        // Generate symbol graphs with module filtering
        if verbose {
            reporter.info("Generating symbol graphs (or using cached)...")
        }

        // Extract module name from file path
        let moduleNames = extractModuleNames(from: [fileURL])
        if verbose && !moduleNames.isEmpty {
            reporter.info("Filtering symbol graphs to modules: \(moduleNames.joined(separator: ", "))")
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
                print("Results written to: \(outputFile)")
            }
        } else {
            print(output)
        }

        // GitHub Actions annotations
        if githubActions {
            for diagnostic in allDiagnostics {
                let level = diagnostic.severity == .error ? "error" : "warning"
                if let file = diagnostic.file {
                    print("::\(level) file=\(file),line=\(diagnostic.line),col=\(diagnostic.column)::\(diagnostic.message)")
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

enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
    case terminal
    case json
    case csv
    case sarif
}

extension DiagnosticSeverity: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument.lowercased())
    }
}
