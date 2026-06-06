import Foundation
import os

private let logger = Logger(subsystem: "com.docc-lint", category: "BinarySearchProcessor")

/// Processes markdown files using a binary search approach
/// Batches files into catalogs and only splits when warnings are found
public actor BinarySearchProcessor {
    /// Whether verbose logging is enabled
    private let verbose: Bool
    /// Optional directory containing symbol graph files
    private let symbolGraphDir: URL?
    /// Optional hash-based file cache for skipping unchanged files
    private let cache: HashCache?
    /// Cached path to the docc executable
    private var doccPath: String?

    /// Creates a new binary search processor.
    public init(verbose: Bool, symbolGraphDir: URL?, cache: HashCache?) {
        self.verbose = verbose
        self.symbolGraphDir = symbolGraphDir
        self.cache = cache
    }

    /// Process files using binary search to efficiently find problematic ones
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
            logger.info("  Checking \(checkCount, privacy: .public) files using binary search...")
        }

        // Run binary search (caching happens immediately during search)
        let results = try await binarySearchForIssues(files: filesToCheck)

        return results
    }

    /// Maximum files per batch to keep docc convert fast
    private let maxBatchSize = 10

    /// Binary search to find files with issues
    private func binarySearchForIssues(files: [URL]) async throws -> [FileResult] {
        guard !files.isEmpty else { return [] }

        // Base case: single file
        if files.count == 1 {
            let result = try await checkSingleFile(files[0])
            // Cache immediately (whether clean or with issues)
            if let cache = cache {
                cache.updateEntry(files[0], diagnostics: result.diagnostics)
                try? cache.persist() // silent: error is expected and non-fatal
            }
            if !result.diagnostics.isEmpty {
                return [result]
            }
            return []
        }

        // If batch is too large, split first without checking (more parallel)
        if files.count > maxBatchSize {
            if verbose {
                let fileCount = files.count
                logger.info("    Splitting \(fileCount, privacy: .public) files into smaller batches...")
            }
            let mid = files.count / 2
            let leftHalf = Array(files[..<mid])
            let rightHalf = Array(files[mid...])

            async let leftResults = binarySearchForIssues(files: leftHalf)
            async let rightResults = binarySearchForIssues(files: rightHalf)

            return try await leftResults + rightResults
        }

        // Check the batch
        if verbose {
            let batchCount = files.count
            logger.info("    Checking batch of \(batchCount, privacy: .public) files...")
        }
        let batchResult = try await checkBatch(files)

        if batchResult.isEmpty {
            // No issues in this batch - cache ALL files as clean IMMEDIATELY
            if let cache = cache {
                for file in files {
                    cache.updateEntry(file, diagnostics: [])
                }
                try? cache.persist() // silent: error is expected and non-fatal
            }
            if verbose {
                let cleanCount = files.count
                logger.info("    \(cleanCount, privacy: .public) files: clean (cached)")
            }
            return []
        }

        if verbose {
            let batchCount = files.count
            let issueCount = batchResult.count
            logger.info("    \(batchCount, privacy: .public) files: \(issueCount, privacy: .public) issue(s) found, narrowing down...")
        }

        // Split and recurse
        let mid = files.count / 2
        let leftHalf = Array(files[..<mid])
        let rightHalf = Array(files[mid...])

        // Process both halves in parallel
        async let leftResults = binarySearchForIssues(files: leftHalf)
        async let rightResults = binarySearchForIssues(files: rightHalf)

        return try await leftResults + rightResults
    }

    /// Check a batch of files by creating a temp catalog with all of them
    private func checkBatch(_ files: [URL]) async throws -> [MappedDiagnostic] {
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

        // Copy all files to temp catalog, preserving relative structure
        var fileMapping: [String: URL] = [:] // temp filename -> original URL
        for (index, file) in files.enumerated() {
            let safePath = file.standardized
            let destName = "\(index)_\(safePath.lastPathComponent)"
            let destFile = tempCatalog.appendingPathComponent(destName)
            try FileManager.default.copyItem(at: safePath, to: destFile)
            fileMapping[destName] = file
        }

        // Run docc convert with diagnostics file for proper JSON output
        let diagnosticsFile = tempBase.appendingPathComponent("diagnostics.json")
        var arguments = ["convert", tempCatalog.path, "--diagnostics-file", diagnosticsFile.path]

        if let symbolGraphDir = symbolGraphDir {
            arguments.append(contentsOf: ["--additional-symbol-graph-dir", symbolGraphDir.path])
        }

        _ = try await runDocC(path: doccPath, arguments: arguments, workingDirectory: tempBase)

        // Read and parse diagnostics file
        let parser = DiagnosticParser()
        let diagnostics: [MappedDiagnostic]
        if (try? diagnosticsFile.checkResourceIsReachable()) ?? false,
           let json = try? String(contentsOf: diagnosticsFile, encoding: .utf8) { // silent: error is expected and non-fatal
            diagnostics = try parser.parseDiagnostics(json: json, catalog: tempCatalog)
        } else {
            diagnostics = []
        }

        // Map diagnostics back to original files
        return diagnostics.compactMap { diag -> MappedDiagnostic? in
            guard let file = diag.file else { return nil }
            let filename = URL(fileURLWithPath: file).lastPathComponent

            if let originalURL = fileMapping[filename] {
                return MappedDiagnostic(
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
            }
            return nil
        }
    }

    /// Check a single file by creating a mini-catalog
    private func checkSingleFile(_ file: URL) async throws -> FileResult {
        guard let doccPath = doccPath else {
            throw ProcessorError.doccNotFound
        }

        let startTime = Date()
        let safePath = file.standardized

        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("docc-lint-\(UUID().uuidString)")
        let tempCatalog = tempBase.appendingPathComponent("Single.docc")

        try FileManager.default.createDirectory(at: tempCatalog, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempBase) // silent: error is expected and non-fatal
        }

        let destFile = tempCatalog.appendingPathComponent(safePath.lastPathComponent)
        try FileManager.default.copyItem(at: safePath, to: destFile)

        // Run docc convert with diagnostics file
        let diagnosticsFile = tempBase.appendingPathComponent("diagnostics.json")
        var arguments = ["convert", tempCatalog.path, "--diagnostics-file", diagnosticsFile.path]

        if let symbolGraphDir = symbolGraphDir {
            arguments.append(contentsOf: ["--additional-symbol-graph-dir", symbolGraphDir.path])
        }

        _ = try await runDocC(path: doccPath, arguments: arguments, workingDirectory: tempBase)

        // Read and parse diagnostics file
        let parser = DiagnosticParser()
        var diagnostics: [MappedDiagnostic]
        if (try? diagnosticsFile.checkResourceIsReachable()) ?? false,
           let json = try? String(contentsOf: diagnosticsFile, encoding: .utf8) { // silent: error is expected and non-fatal
            diagnostics = try parser.parseDiagnostics(json: json, catalog: tempCatalog)
        } else {
            diagnostics = []
        }

        // Remap to original file path
        diagnostics = diagnostics.map { diag in
            MappedDiagnostic(
                file: file.path,
                line: diag.line,
                column: diag.column,
                endColumn: diag.endColumn,
                severity: diag.severity,
                message: diag.message,
                content: diag.content,
                ruleId: diag.ruleId,
                suggestedFix: diag.suggestedFix
            )
        }

        if verbose {
            let fileName = file.lastPathComponent
            if diagnostics.isEmpty {
                logger.info("    \(fileName, privacy: .public)")
            } else {
                let issueCount = diagnostics.count
                logger.info("    \(fileName, privacy: .public): \(issueCount, privacy: .public) issue(s)")
                for diag in diagnostics {
                    let line = diag.line
                    let col = diag.column
                    let endCol = diag.endColumn
                    let msg = diag.message
                    logger.debug("      Line \(line, privacy: .public):\(col, privacy: .public)-\(endCol, privacy: .public): \(msg, privacy: .public)")
                }
            }
        }

        return FileResult(
            file: file,
            diagnostics: diagnostics,
            duration: Date().timeIntervalSince(startTime)
        )
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

    /// Run the docc tool with the given arguments.
    private func runDocC(path: String, arguments: [String], workingDirectory: URL) async throws -> String {
        let process: Process = .init() // Justification: hardcoded executable path, arguments are validated file paths
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory

        // Discard stdout and stderr to avoid pipe buffer blocking
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        return ""  // We use diagnostics file, not output
    }

    /// Errors that can occur during binary search processing.
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
