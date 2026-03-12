import Foundation

/// Processes DocC catalogs directly without copying files
/// Optimized for speed by running docc on original catalogs
public actor CatalogProcessor {
    private let verbose: Bool
    private let symbolGraphDir: URL?
    private var doccPath: String?

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

        // Create temp directory for diagnostics file
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("docc-lint-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let diagnosticsFile = tempDir.appendingPathComponent("diagnostics.json")

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        if verbose {
            print("    → Running docc convert on \(catalogURL.lastPathComponent)...")
        }

        // Build arguments
        var arguments = [
            "convert",
            catalogURL.path,
            "--diagnostics-file", diagnosticsFile.path
        ]

        if let symbolGraphDir = symbolGraphDir {
            arguments.append(contentsOf: ["--additional-symbol-graph-dir", symbolGraphDir.path])
        }

        // Run docc convert
        let process = Process()
        process.executableURL = URL(fileURLWithPath: doccPath)
        process.arguments = arguments
        process.currentDirectoryURL = tempDir

        // Discard stdout and stderr to avoid pipe buffer blocking
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        // Parse diagnostics file
        guard FileManager.default.fileExists(atPath: diagnosticsFile.path) else {
            if verbose {
                print("    ⚠ No diagnostics file generated")
            }
            return []
        }

        let json = try String(contentsOf: diagnosticsFile, encoding: .utf8)
        let parser = DiagnosticParser()
        let diagnostics = try parser.parseDiagnostics(json: json, catalog: catalogURL)

        if verbose {
            if diagnostics.isEmpty {
                print("    ✓ \(catalogURL.lastPathComponent): clean")
            } else {
                print("    ⚠ \(catalogURL.lastPathComponent): \(diagnostics.count) diagnostic(s)")
            }
        }

        return diagnostics
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
