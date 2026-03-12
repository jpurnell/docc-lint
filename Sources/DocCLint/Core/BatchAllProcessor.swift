import Foundation

/// Processes ALL markdown files in a single docc convert call
/// Optimized for large symbol graphs where loading cost dominates
public actor BatchAllProcessor {
    private let verbose: Bool
    private let symbolGraphDir: URL?
    private let cache: HashCache?
    private var doccPath: String?

    public init(verbose: Bool, symbolGraphDir: URL?, cache: HashCache?) {
        self.verbose = verbose
        self.symbolGraphDir = symbolGraphDir
        self.cache = cache
    }

    /// Process all files in a single batch, then map diagnostics back
    public func processFiles(_ files: [URL]) async throws -> [FileResult] {
        // Find docc once
        doccPath = try await findDocC()

        // Filter out cached files first
        let filesToCheck: [URL]
        if let cache = cache {
            filesToCheck = files.filter { cache.needsScan($0) }
            if verbose && filesToCheck.count < files.count {
                print("  Skipping \(files.count - filesToCheck.count) cached files")
            }
        } else {
            filesToCheck = files
        }

        if filesToCheck.isEmpty {
            if verbose {
                print("  All files cached, nothing to check")
            }
            return []
        }

        if verbose {
            print("  Checking \(filesToCheck.count) files in single batch (symbol graph loaded once)...")
        }

        // Process ALL files in one batch
        let (diagnosticsByFile, cleanFiles) = try await checkAllFiles(filesToCheck)

        // Cache clean files immediately
        if let cache = cache {
            for file in cleanFiles {
                cache.updateEntry(file, diagnostics: [])
            }
            if verbose && !cleanFiles.isEmpty {
                print("  ✓ Cached \(cleanFiles.count) clean files")
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
            try? cache.persist()
        }

        if verbose {
            print("  ⚠ Found \(results.count) files with issues")
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
            try? FileManager.default.removeItem(at: tempBase)
        }

        // Copy all files to temp catalog with unique names
        var fileMapping: [String: URL] = [:] // temp filename -> original URL
        for (index, file) in files.enumerated() {
            let destName = "\(index)_\(file.lastPathComponent)"
            let destFile = tempCatalog.appendingPathComponent(destName)
            try FileManager.default.copyItem(at: file, to: destFile)
            fileMapping[destName] = file
        }

        if verbose {
            print("    → Running docc convert with \(files.count) files and symbol graph...")
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

    private func findDocC() async throws -> String {
        #if os(Linux)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["docc"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            return path
        }
        throw ProcessorError.doccNotFound
        #else
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["--find", "docc"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            return path
        }
        throw ProcessorError.doccNotFound
        #endif
    }

    private func runDocC(path: String, arguments: [String], workingDirectory: URL) async throws -> String {
        let process = Process()
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
        process.waitUntilExit()

        errorPipe.fileHandleForReading.readabilityHandler = nil

        let remaining = errorPipe.fileHandleForReading.readDataToEndOfFile()
        var errorData = await errorCollector.getData()
        errorData.append(remaining)

        return String(data: errorData, encoding: .utf8) ?? ""
    }

    public enum ProcessorError: Error, LocalizedError {
        case doccNotFound

        public var errorDescription: String? {
            switch self {
            case .doccNotFound:
                return "Could not find docc executable"
            }
        }
    }
}
