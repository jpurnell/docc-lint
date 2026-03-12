import Foundation

/// Processes markdown files using a binary search approach
/// Batches files into catalogs and only splits when warnings are found
public actor BinarySearchProcessor {
    private let verbose: Bool
    private let symbolGraphDir: URL?
    private let cache: HashCache?
    private var doccPath: String?

    public init(verbose: Bool, symbolGraphDir: URL?, cache: HashCache?) {
        self.verbose = verbose
        self.symbolGraphDir = symbolGraphDir
        self.cache = cache
    }

    /// Process files using binary search to efficiently find problematic ones
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
            print("  Checking \(filesToCheck.count) files using binary search...")
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
                try? cache.persist()
            }
            if !result.diagnostics.isEmpty {
                return [result]
            }
            return []
        }

        // If batch is too large, split first without checking (more parallel)
        if files.count > maxBatchSize {
            if verbose {
                print("    Splitting \(files.count) files into smaller batches...")
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
            print("    → Checking batch of \(files.count) files...")
        }
        let batchResult = try await checkBatch(files)

        if batchResult.isEmpty {
            // No issues in this batch - cache ALL files as clean IMMEDIATELY
            if let cache = cache {
                for file in files {
                    cache.updateEntry(file, diagnostics: [])
                }
                try? cache.persist()  // Persist once for the whole batch
            }
            if verbose {
                print("    ✓ \(files.count) files: clean (cached)")
            }
            return []
        }

        if verbose {
            print("    ⚠ \(files.count) files: \(batchResult.count) issue(s) found, narrowing down...")
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
            try? FileManager.default.removeItem(at: tempBase)
        }

        // Copy all files to temp catalog, preserving relative structure
        var fileMapping: [String: URL] = [:] // temp filename -> original URL
        for (index, file) in files.enumerated() {
            let destName = "\(index)_\(file.lastPathComponent)"
            let destFile = tempCatalog.appendingPathComponent(destName)
            try FileManager.default.copyItem(at: file, to: destFile)
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
        if FileManager.default.fileExists(atPath: diagnosticsFile.path),
           let json = try? String(contentsOf: diagnosticsFile, encoding: .utf8) {
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

    /// Check a single file
    private func checkSingleFile(_ file: URL) async throws -> FileResult {
        guard let doccPath = doccPath else {
            throw ProcessorError.doccNotFound
        }

        let startTime = Date()

        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("docc-lint-\(UUID().uuidString)")
        let tempCatalog = tempBase.appendingPathComponent("Single.docc")

        try FileManager.default.createDirectory(at: tempCatalog, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempBase)
        }

        let destFile = tempCatalog.appendingPathComponent(file.lastPathComponent)
        try FileManager.default.copyItem(at: file, to: destFile)

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
        if FileManager.default.fileExists(atPath: diagnosticsFile.path),
           let json = try? String(contentsOf: diagnosticsFile, encoding: .utf8) {
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
            if diagnostics.isEmpty {
                print("    ✓ \(file.lastPathComponent)")
            } else {
                print("    ⚠ \(file.lastPathComponent): \(diagnostics.count) issue(s)")
                for diag in diagnostics {
                    print("      Line \(diag.line):\(diag.column)-\(diag.endColumn): \(diag.message)")
                }
            }
        }

        return FileResult(
            file: file,
            diagnostics: diagnostics,
            duration: Date().timeIntervalSince(startTime)
        )
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

        // Discard stdout and stderr to avoid pipe buffer blocking
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        return ""  // We use diagnostics file, not output
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
