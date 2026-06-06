import Foundation
import os

private let logger = Logger(subsystem: "com.docc-lint", category: "CatalogProcessor")

/// Processes DocC catalogs directly without copying files
/// Optimized for speed by running docc on original catalogs
public actor CatalogProcessor {
    /// Whether verbose logging is enabled
    private let verbose: Bool
    /// Optional directory containing symbol graph files
    private let symbolGraphDir: URL?
    /// Cached path to the docc executable
    private var doccPath: String?

    /// Creates a new catalog processor.
    public init(verbose: Bool, symbolGraphDir: URL?) {
        self.verbose = verbose
        self.symbolGraphDir = symbolGraphDir
    }

    /// Process a catalog and return diagnostics with file information
    public func processCatalog(_ catalogURL: URL) async throws -> [MappedDiagnostic] {
        // Find docc once
        if doccPath == nil {
            doccPath = try await findDocC()
        }

        guard let doccPath = doccPath else {
            throw ProcessorError.doccNotFound
        }

        let safeCatalogURL = catalogURL.standardized

        // Create temp directory for diagnostics file
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("docc-lint-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let diagnosticsFile = tempDir.appendingPathComponent("diagnostics.json")

        defer {
            try? FileManager.default.removeItem(at: tempDir) // silent: error is expected and non-fatal
        }

        if verbose {
            let catalogName = safeCatalogURL.lastPathComponent
            logger.info("    Running docc convert on \(catalogName, privacy: .public)...")
        }

        // Build arguments
        var arguments = [
            "convert",
            safeCatalogURL.path,
            "--diagnostics-file", diagnosticsFile.path
        ]

        if let symbolGraphDir = symbolGraphDir {
            arguments.append(contentsOf: ["--additional-symbol-graph-dir", symbolGraphDir.path])
        }

        // Run docc convert
        let process: Process = .init() // Justification: hardcoded executable path, arguments are validated file paths
        process.executableURL = URL(fileURLWithPath: doccPath)
        process.arguments = arguments
        process.currentDirectoryURL = tempDir

        // Discard stdout and stderr to avoid pipe buffer blocking
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        // Parse diagnostics file
        guard (try? diagnosticsFile.checkResourceIsReachable()) ?? false else {
            if verbose {
                logger.info("    No diagnostics file generated")
            }
            return []
        }

        let json = try String(contentsOf: diagnosticsFile, encoding: .utf8)
        let parser = DiagnosticParser()
        let diagnostics = try parser.parseDiagnostics(json: json, catalog: safeCatalogURL)

        if verbose {
            let catalogName = safeCatalogURL.lastPathComponent
            if diagnostics.isEmpty {
                logger.info("    \(catalogName, privacy: .public): clean")
            } else {
                let diagCount = diagnostics.count
                logger.info("    \(catalogName, privacy: .public): \(diagCount, privacy: .public) diagnostic(s)")
            }
        }

        return diagnostics
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

    /// Errors that can occur during catalog processing.
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
