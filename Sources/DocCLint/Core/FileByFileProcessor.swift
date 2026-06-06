import Foundation
import os

private let logger = Logger(subsystem: "com.docc-lint", category: "FileByFileProcessor")

/// Processes individual markdown files using docc convert with mini-catalogs
/// Each file is processed in parallel and cached immediately after completion
public actor FileByFileProcessor {
    /// Whether verbose logging is enabled
    private let verbose: Bool
    /// Optional directory containing symbol graph files
    private let symbolGraphDir: URL?
    /// Optional hash-based file cache for skipping unchanged files
    private let cache: HashCache?

    /// Creates a new file-by-file processor.
    public init(verbose: Bool, symbolGraphDir: URL?, cache: HashCache?) {
        self.verbose = verbose
        self.symbolGraphDir = symbolGraphDir
        self.cache = cache
    }

    /// Process multiple markdown files in parallel
    /// Each file is checked via docc convert and cached immediately
    public func processFiles(_ files: [URL]) async throws -> [FileResult] { // LIVE: public API
        // Find docc once
        let doccPath = try await findDocC()

        return try await withThrowingTaskGroup(of: FileResult?.self) { group in
            for fileURL in files {
                group.addTask {
                    // Check cache first
                    if let cache = self.cache, !cache.needsScan(fileURL) {
                        if self.verbose {
                            let fileName = fileURL.lastPathComponent
                            logger.info("  [cached] \(fileName, privacy: .public)")
                        }
                        return nil  // Skip, already cached with no changes
                    }

                    let result = try await self.processSingleFile(fileURL, doccPath: doccPath)

                    // Immediately cache and persist
                    if let cache = self.cache {
                        cache.updateEntry(fileURL, diagnostics: result.diagnostics)
                        try? cache.persist() // silent: error is expected and non-fatal
                    }

                    if self.verbose {
                        let fileName = fileURL.lastPathComponent
                        if result.diagnostics.isEmpty {
                            logger.info("  [ok] \(fileName, privacy: .public)")
                        } else {
                            let diagCount = result.diagnostics.count
                            logger.info("  [\(diagCount, privacy: .public) issues] \(fileName, privacy: .public)")
                        }
                    }

                    return result
                }
            }

            var results: [FileResult] = []
            for try await result in group {
                if let result = result {
                    results.append(result)
                }
            }
            return results
        }
    }

    /// Process a single markdown file by creating a temp mini-catalog
    private func processSingleFile(_ fileURL: URL, doccPath: String) async throws -> FileResult {
        let startTime = Date()
        let safePath = fileURL.standardized

        // Create temp directory for mini-catalog (no output dir needed - diagnostics only)
        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("docc-lint-\(UUID().uuidString)")
        let tempCatalog = tempBase.appendingPathComponent("Temp.docc")

        try FileManager.default.createDirectory(at: tempCatalog, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempBase) // silent: error is expected and non-fatal
        }

        // Copy the markdown file to the temp catalog
        let destFile = tempCatalog.appendingPathComponent(safePath.lastPathComponent)
        try FileManager.default.copyItem(at: safePath, to: destFile)

        // Build docc convert arguments - NO output path = diagnostics only (much faster!)
        var arguments = [
            "convert",
            tempCatalog.path,
            "--ide-console-output"  // Structured diagnostic output
        ]

        // Add symbol graphs if available
        if let symbolGraphDir = symbolGraphDir {
            arguments.append(contentsOf: [
                "--additional-symbol-graph-dir", symbolGraphDir.path
            ])
        }

        // Run docc convert - diagnostics come from stderr
        let diagnosticsOutput = try await runDocC(path: doccPath, arguments: arguments, workingDirectory: tempBase)

        // Parse diagnostics
        let parser = DiagnosticParser()
        var diagnostics = try parser.parseDiagnostics(json: diagnosticsOutput, catalog: tempCatalog)

        // Remap file paths from temp back to original
        diagnostics = diagnostics.map { diag in
            MappedDiagnostic(
                file: fileURL.path,  // Use original path
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

        return FileResult(
            file: fileURL,
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

    /// Run docc and capture stderr (diagnostics)
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

    /// Errors that can occur during file-by-file processing.
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

/// Result for a single file
public struct FileResult: Sendable {
    /// The URL of the file that was processed
    public let file: URL // LIVE: public API
    /// Diagnostics found in this file
    public let diagnostics: [MappedDiagnostic] // LIVE: public API
    /// Time taken to process this file
    public let duration: TimeInterval // LIVE: public API
}
