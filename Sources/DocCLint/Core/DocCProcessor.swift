import Foundation

/// Processing mode for DocC validation
public enum ProcessingMode: Sendable {
    /// Full validation with symbol graph generation
    case full

    /// Syntax-only validation (faster, no compilation)
    case syntaxOnly
}

/// Wraps xcrun docc convert for processing DocC catalogs
public actor DocCProcessor {
    private let verbose: Bool
    private let reporter: any Reporter

    public init(verbose: Bool, reporter: any Reporter) {
        self.verbose = verbose
        self.reporter = reporter
    }

    /// Process a single DocC catalog and return diagnostics
    /// - Parameters:
    ///   - catalogURL: The URL to the .docc catalog
    ///   - mode: Processing mode (full or syntaxOnly)
    ///   - symbolGraphDir: Optional pre-generated symbol graph directory for full mode
    /// - Returns: ScanResult containing diagnostics
    public func processDocCCatalog(
        at catalogURL: URL,
        mode: ProcessingMode,
        symbolGraphDir: URL? = nil
    ) async throws -> ScanResult {
        let startTime = Date()

        // Find docc executable
        let doccPath = try await findDocC()

        // Create temporary directory for output
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("docc-lint-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Build docc convert command
        var arguments = [
            "convert",
            catalogURL.path,
            "--output-path", tempDir.appendingPathComponent("output").path,
            "--emit-digest",
            "--experimental-enable-custom-templates"
        ]

        // Add symbol graph directory if provided for full mode
        if mode == .full, let symbolGraphDir = symbolGraphDir {
            arguments.append(contentsOf: [
                "--additional-symbol-graph-dir", symbolGraphDir.path
            ])
            if verbose {
                reporter.info("Using symbol graphs from: \(symbolGraphDir.path)")
            }
        } else if mode == .full && symbolGraphDir == nil {
            if verbose {
                reporter.info("Full mode requested but no symbol graphs provided, running syntax-only")
            }
        }

        // Run docc convert
        let (_, diagnosticsOutput) = try await runDocC(
            path: doccPath,
            arguments: arguments,
            workingDirectory: catalogURL.deletingLastPathComponent()
        )

        // Parse diagnostics (handles both JSON and text formats)
        let parser = DiagnosticParser()
        let diagnostics = try parser.parseDiagnostics(
            json: diagnosticsOutput ?? "",
            catalog: catalogURL
        )

        let scanDuration = Date().timeIntervalSince(startTime)

        return ScanResult(
            path: catalogURL.path,
            fileType: .doccCatalog,
            diagnostics: diagnostics,
            success: true,
            scanDuration: scanDuration
        )
    }

    /// Find the docc executable path
    private func findDocC() async throws -> String {
        #if os(Linux)
        // On Linux, look for docc in PATH
        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = ["docc"]

        let pipe = Pipe()
        whichProcess.standardOutput = pipe

        try whichProcess.run()
        whichProcess.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            return path
        }

        throw DocCProcessorError.doccNotFound
        #else
        // On macOS, use xcrun to find docc
        let xcrunProcess = Process()
        xcrunProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        xcrunProcess.arguments = ["--find", "docc"]

        let pipe = Pipe()
        xcrunProcess.standardOutput = pipe
        xcrunProcess.standardError = FileHandle.nullDevice

        try xcrunProcess.run()
        xcrunProcess.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            return path
        }

        throw DocCProcessorError.doccNotFound
        #endif
    }

    /// Run docc and capture output and diagnostics
    private func runDocC(
        path: String,
        arguments: [String],
        workingDirectory: URL
    ) async throws -> (output: String, diagnosticsOutput: String?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Use actor-safe data collection to avoid Swift 6 sendable warnings
        let outputCollector = DataCollector()
        let errorCollector = DataCollector()

        // Read stdout asynchronously
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                Task { await outputCollector.append(data) }
            }
        }

        // Read stderr asynchronously
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                Task { await errorCollector.append(data) }
            }
        }

        try process.run()
        process.waitUntilExit()

        // Clean up handlers
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil

        // Read any remaining data directly (handlers are disabled)
        let remainingOutput = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let remainingError = errorPipe.fileHandleForReading.readDataToEndOfFile()

        // Combine collected data with remaining data
        var outputData = await outputCollector.getData()
        var errorData = await errorCollector.getData()
        outputData.append(remainingOutput)
        errorData.append(remainingError)

        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

        // Return combined output and stderr separately for parsing
        // DocC outputs diagnostics to stderr (either JSON or text format)
        return (output, errorOutput.isEmpty ? nil : errorOutput)
    }
}

/// Errors from DocC processing
public enum DocCProcessorError: Error, LocalizedError {
    case doccNotFound
    case processingFailed(String)
    case symbolGraphGenerationFailed(String)
    case noPackageFound

    public var errorDescription: String? {
        switch self {
        case .doccNotFound:
            return "Could not find docc executable. Ensure Xcode command line tools are installed."
        case .processingFailed(let message):
            return "DocC processing failed: \(message)"
        case .symbolGraphGenerationFailed(let message):
            return "Symbol graph generation failed: \(message)"
        case .noPackageFound:
            return "No Package.swift found at project root. Symbol graphs require a SwiftPM project."
        }
    }
}
