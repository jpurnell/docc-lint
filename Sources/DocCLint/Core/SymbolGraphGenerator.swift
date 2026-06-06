import Foundation
import os

/// Logger for symbol graph generation operations
private let logger = Logger(subsystem: "com.docc-lint", category: "SymbolGraphGenerator")

/// Generates symbol graphs for a SwiftPM project
/// Symbol graphs are used by DocC to resolve symbol references
public actor SymbolGraphGenerator {
    /// Cached directory containing full symbol graph output.
    private var cachedSymbolGraphDir: URL?

    /// Cached directory containing filtered symbol graph output.
    private var cachedFilteredDir: URL?

    /// Creates a new symbol graph generator.
    public init() {}

    /// Generate symbol graphs for a SwiftPM project
    /// - Parameters:
    ///   - projectRoot: The root directory containing Package.swift
    ///   - verbose: Whether to print progress information
    ///   - moduleNames: Optional list of module names to filter to (for faster docc processing)
    /// - Returns: The directory containing symbol graph files, or nil if generation failed
    public func generateSymbolGraphs(
        projectRoot: URL,
        verbose: Bool,
        moduleNames: [String]? = nil
    ) async throws -> URL? {
        // Return cached filtered result if available
        if let cached = cachedFilteredDir,
           (try? cached.checkResourceIsReachable()) ?? false { // silent: existence check
            if verbose {
                logger.info("Using cached filtered symbol graphs from: \(cached.path, privacy: .public)")
            }
            return cached
        }

        // Return cached full result if already generated this session
        if let cached = cachedSymbolGraphDir,
           (try? cached.checkResourceIsReachable()) ?? false { // silent: existence check
            // Apply filtering if module names provided
            if let names = moduleNames, !names.isEmpty {
                let filtered = try filterSymbolGraphs(from: cached, moduleNames: names, verbose: verbose)
                cachedFilteredDir = filtered
                return filtered
            }
            if verbose {
                logger.info("Using cached symbol graphs from: \(cached.path, privacy: .public)")
            }
            return cached
        }

        // Check if Package.swift exists
        let packageSwiftPath = projectRoot.appendingPathComponent("Package.swift")
        guard (try? packageSwiftPath.checkResourceIsReachable()) ?? false else { // silent: existence check
            if verbose {
                logger.info("No Package.swift found at \(projectRoot.path, privacy: .public)")
            }
            return nil
        }

        // Create output directory for symbol graphs
        let symbolGraphDir = projectRoot
            .appendingPathComponent(".build")
            .appendingPathComponent("symbol-graph")

        // Check if we already have symbol graphs (from previous runs)
        if hasExistingSymbolGraphs(at: symbolGraphDir) {
            if verbose {
                logger.info("Found existing symbol graphs at: \(symbolGraphDir.path, privacy: .public)")
            }
            cachedSymbolGraphDir = symbolGraphDir

            // Apply filtering if module names provided
            if let names = moduleNames, !names.isEmpty {
                let filtered = try filterSymbolGraphs(from: symbolGraphDir, moduleNames: names, verbose: verbose)
                cachedFilteredDir = filtered
                return filtered
            }
            return symbolGraphDir
        }

        try FileManager.default.createDirectory(at: symbolGraphDir, withIntermediateDirectories: true)

        if verbose {
            logger.info("Generating symbol graphs for project at: \(projectRoot.path, privacy: .public)")
            logger.info("This may take a while for large projects...")
        }

        // Run swift build with symbol graph emission for ALL targets
        let process: Process = .init() // Justification: hardcoded executable path, arguments are validated file paths
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = [
            "build",
            "-Xswiftc", "-emit-symbol-graph",
            "-Xswiftc", "-emit-symbol-graph-dir",
            "-Xswiftc", symbolGraphDir.path
        ]
        process.currentDirectoryURL = projectRoot

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Use actor-safe data collection
        let outputCollector = DataCollector()
        let errorCollector = DataCollector()

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                Task { await outputCollector.append(data) }
                // Log progress in verbose mode
                if verbose, let str = String(data: data, encoding: .utf8) {
                    logger.debug("\(str, privacy: .public)")
                }
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                Task { await errorCollector.append(data) }
                if verbose, let str = String(data: data, encoding: .utf8) {
                    logger.debug("\(str, privacy: .public)")
                }
            }
        }

        try process.run()
        process.waitUntilExit()

        // Clean up handlers
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil

        // Check exit status
        if process.terminationStatus != 0 {
            if verbose {
                let errorOutput = await errorCollector.getData()
                let errorString = String(data: errorOutput, encoding: .utf8) ?? ""
                logger.info("Swift build failed with exit code \(process.terminationStatus, privacy: .public)")
                logger.info("Error output: \(errorString, privacy: .public)")
            }
            return nil
        }

        // Check if symbol graphs were generated
        let contents = try? FileManager.default.contentsOfDirectory(at: symbolGraphDir, includingPropertiesForKeys: nil) // silent: error is expected and non-fatal
        let symbolGraphFiles = contents?.filter { $0.pathExtension == "json" } ?? []

        if symbolGraphFiles.isEmpty {
            if verbose {
                logger.info("Symbol graph generation produced no files")
            }
            return nil
        }

        if verbose {
            let count = symbolGraphFiles.count
            logger.info("Generated \(count, privacy: .public) symbol graph file(s)")
        }

        // Cache the full result
        cachedSymbolGraphDir = symbolGraphDir

        // Apply filtering if module names provided
        if let names = moduleNames, !names.isEmpty {
            let filtered = try filterSymbolGraphs(from: symbolGraphDir, moduleNames: names, verbose: verbose)
            cachedFilteredDir = filtered
            return filtered
        }

        return symbolGraphDir
    }

    /// Filter symbol graphs to only include specified modules
    /// This dramatically speeds up docc convert by excluding dependency symbol graphs
    private func filterSymbolGraphs(
        from sourceDir: URL,
        moduleNames: [String],
        verbose: Bool
    ) throws -> URL {
        let filteredDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("docc-lint-filtered-symbols-\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: filteredDir, withIntermediateDirectories: true)

        let contents = try FileManager.default.contentsOfDirectory(at: sourceDir, includingPropertiesForKeys: nil)
        var copiedCount = 0
        var totalSize: Int64 = 0

        for file in contents where file.pathExtension == "json" {
            let filename = file.lastPathComponent

            // Check if this file belongs to one of our modules
            let shouldInclude = moduleNames.contains { moduleName in
                filename.hasPrefix(moduleName + ".symbols.json") ||
                filename.hasPrefix(moduleName + "@")  // Extension symbols like Module@Swift.symbols.json
            }

            if shouldInclude {
                let destFile = filteredDir.appendingPathComponent(filename)
                try FileManager.default.copyItem(at: file, to: destFile)
                copiedCount += 1

                if let vals = try? file.resourceValues(forKeys: [.fileSizeKey]), // silent: error is expected and non-fatal
                   let size = vals.fileSize {
                    totalSize += Int64(size)
                }
            }
        }

        if verbose {
            let sizeMB = Double(totalSize) / 1_000_000.0
            let formattedSize = sizeMB.formatted(.number.precision(.fractionLength(1)))
            let totalCount = contents.count
            logger.info("Filtered symbol graphs: \(copiedCount, privacy: .public) files (\(formattedSize, privacy: .public)MB) from \(totalCount, privacy: .public) total")
        }

        return filteredDir
    }

    /// Check if symbol graphs already exist and are non-empty
    public nonisolated func hasExistingSymbolGraphs(at directory: URL) -> Bool {
        guard (try? directory.checkResourceIsReachable()) ?? false else { // silent: existence check
            return false
        }

        let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) // silent: error is expected and non-fatal
        let symbolFiles = contents?.filter { $0.pathExtension == "json" } ?? []

        return !symbolFiles.isEmpty
    }

    /// Clear cached symbol graph directory
    public func clearCache() { // LIVE: public API
        cachedSymbolGraphDir = nil
    }
}

/// Actor for safely collecting data from async pipe handlers
actor DataCollector {
    /// Collected data buffer.
    private var data = Data()

    /// Append new data to the buffer.
    func append(_ newData: Data) {
        data.append(newData)
    }

    /// Return the accumulated data.
    func getData() -> Data {
        return data
    }
}
