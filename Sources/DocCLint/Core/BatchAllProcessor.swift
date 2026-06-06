import Foundation
import os

private let logger = Logger(subsystem: "com.docc-lint", category: "BatchAllProcessor")

/// Processes ALL markdown files in a single docc convert call
/// Optimized for large symbol graphs where loading cost dominates
public actor BatchAllProcessor {
    /// Whether verbose logging is enabled
    private let verbose: Bool
    /// Optional directory containing symbol graph files
    private let symbolGraphDir: URL?
    /// Optional hash-based file cache for skipping unchanged files
    private let cache: HashCache?
    /// Cached path to the docc executable
    private var doccPath: String?

    /// Creates a new batch processor.
    public init(verbose: Bool, symbolGraphDir: URL?, cache: HashCache?) {
        self.verbose = verbose
        self.symbolGraphDir = symbolGraphDir
        self.cache = cache
    }

    /// Process all files in a single batch, then map diagnostics back
    public func processFiles(_ files: [URL]) async throws -> [FileResult] { // LIVE: public API
        // Find docc once
        doccPath = try await findDocC()

        // Filter out cached files first
        let filesToCheck: [URL]
        if let cache = cache {
            filesToCheck = files.filter { cache.needsScan($0) }
            if verbose && filesToCheck.count < files.count {
                let skippedCount = files.count - filesToCheck.count
                logger.info("  Skipping \(skippedCount, privacy: .public) cached files")
            }
        } else {
            filesToCheck = files
        }

        if filesToCheck.isEmpty {
            if verbose {
                logger.info("  All files cached, nothing to check")
            }
            return []
        }

        if verbose {
            let checkCount = filesToCheck.count
            logger.info("  Checking \(checkCount, privacy: .public) files in single batch (symbol graph loaded once)...")
        }

        // Process ALL files in one batch
        let (diagnosticsByFile, cleanFiles) = try await checkAllFiles(filesToCheck)

        // Cache clean files immediately
        if let cache = cache {
            for file in cleanFiles {
                cache.updateEntry(file, diagnostics: [])
            }
            if verbose && !cleanFiles.isEmpty {
                let cleanCount = cleanFiles.count
                logger.info("  Cached \(cleanCount, privacy: .public) clean files")
            }
        }

        // Build results for files with issues
        var results: [FileResult] = []
        for (file, diagnostics) in diagnosticsByFile {
            // Cache this file's diagnostics
            if let cache = cache {
                cache.updateEntry(file, diagnostics: diagnostics)
            }
            results.append(FileResult(
                file: file,
                diagnostics: diagnostics,
                duration: 0  // Not tracked per-file in batch mode
            ))
        }

        // Persist cache once at the end
        if let cache = cache {
            try? cache.persist() // silent: error is expected and non-fatal
        }

        if verbose {
            let issueCount = results.count
            logger.info("  Found \(issueCount, privacy: .public) files with issues")
        }

        return results
    }

    /// Check all files in a single docc convert call
    private func checkAllFiles(_ files: [URL]) async throws -> (diagnosticsByFile: [URL: [MappedDiagnostic]], cleanFiles: [URL]) {
        guard let doccPath = doccPath else {
            throw ProcessorError.doccNotFound
        }

        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("docc-lint-batch-\(UUID().uuidString)")
        let tempCatalog = tempBase.appendingPathComponent("Batch.docc")

        try FileManager.default.createDirectory(at: tempCatalog, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempBase) // silent: error is expected and non-fatal
        }

        // Copy all files to temp catalog with unique names
        var fileMapping: [String: URL] = [:] // temp filename -> original URL
        for (index, file) in files.enumerated() {
            let safePath = file.standardized
            let destName = "\(index)_\(safePath.lastPathComponent)"
            let destFile = tempCatalog.appendingPathComponent(destName)
            try FileManager.default.copyItem(at: safePath, to: destFile)
            fileMapping[destName] = file
        }

        if verbose {
            let fileCount = files.count
            logger.info("    Running docc convert with \(fileCount, privacy: .public) files and symbol graph...")
        }

        // Run docc convert (no output path = diagnostics only)
        var arguments = ["convert", tempCatalog.path, "--ide-console-output"]

        if let symbolGraphDir = symbolGraphDir {
            arguments.append(contentsOf: ["--additional-symbol-graph-dir", symbolGraphDir.path])
        }

        let output = try await runDocC(path: doccPath, arguments: arguments, workingDirectory: tempBase)

        // Parse diagnostics
        let parser = DiagnosticParser()
        let diagnostics = try parser.parseDiagnostics(json: output, catalog: tempCatalog)

        // Group diagnostics by original file
        var diagnosticsByFile: [URL: [MappedDiagnostic]] = [:]
        var filesWithIssues = Set<URL>()

        for diag in diagnostics {
            guard let file = diag.file else { continue }
            let filename = URL(fileURLWithPath: file).lastPathComponent

            if let originalURL = fileMapping[filename] {
                let mappedDiag = MappedDiagnostic(
                    file: originalURL.path,
                    line: diag.line,
                    column: diag.column,
                    endColumn: diag.endColumn,
                    severity: diag.severity,
                    message: diag.message,
                    content: diag.content,
                    ruleId: diag.ruleId,
                    suggestedFix: diag.suggestedFix
                )
                diagnosticsByFile[originalURL, default: []].append(mappedDiag)
                filesWithIssues.insert(originalURL)
            }
        }

        // Determine clean files (files that were checked but had no issues)
        let cleanFiles = files.filter { !filesWithIssues.contains($0) }

        return (diagnosticsByFile, cleanFiles)
    }

    /// Locate the docc executable on this system.
    private func findDocC() async throws -> String {
        #if os(Linux)
        let process: Process = .init() // Justification: hardcoded executable path, arguments are validated file paths
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["docc"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            return path
        }
        throw ProcessorError.doccNotFound
        #else
        let process: Process = .init() // Justification: hardcoded executable path, arguments are validated file paths
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["--find", "docc"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            return path
        }
        throw ProcessorError.doccNotFound
        #endif
    }

    /// Run the docc tool and capture its stderr output.
    private func runDocC(path: String, arguments: [String], workingDirectory: URL) async throws -> String {
        let process: Process = .init() // Justification: hardcoded executable path, arguments are validated file paths
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let errorCollector = DataCollector()

        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                Task { await errorCollector.append(data) }
            }
        }

        try process.run()

        errorPipe.fileHandleForReading.readabilityHandler = nil

        let remaining = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        var errorData = await errorCollector.getData()
        errorData.append(remaining)

        return String(data: errorData, encoding: .utf8) ?? ""
    }

    /// Errors that can occur during batch processing.
    public enum ProcessorError: Error, LocalizedError {
        /// The docc executable could not be found on this system.
        case doccNotFound

        /// A human-readable description of the error.
        public var errorDescription: String? {
            switch self {
            case .doccNotFound:
                return "Could not find docc executable"
            }
        }
    }
}
