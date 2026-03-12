import Foundation

/// Generates symbol graphs for a SwiftPM project
/// Symbol graphs are used by DocC to resolve symbol references
public actor SymbolGraphGenerator {
    private var cachedSymbolGraphDir: URL?
    private var cachedFilteredDir: URL?

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
           FileManager.default.fileExists(atPath: cached.path) {
            if verbose {
                print("Using cached filtered symbol graphs from: \(cached.path)")
            }
            return cached
        }

        // Return cached full result if already generated this session
        if let cached = cachedSymbolGraphDir,
           FileManager.default.fileExists(atPath: cached.path) {
            // Apply filtering if module names provided
            if let names = moduleNames, !names.isEmpty {
                let filtered = try filterSymbolGraphs(from: cached, moduleNames: names, verbose: verbose)
                cachedFilteredDir = filtered
                return filtered
            }
            if verbose {
                print("Using cached symbol graphs from: \(cached.path)")
            }
            return cached
        }

        // Check if Package.swift exists
        let packageSwiftPath = projectRoot.appendingPathComponent("Package.swift")
        guard FileManager.default.fileExists(atPath: packageSwiftPath.path) else {
            if verbose {
                print("No Package.swift found at \(projectRoot.path)")
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
                print("Found existing symbol graphs at: \(symbolGraphDir.path)")
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
            print("Generating symbol graphs for project at: \(projectRoot.path)")
            print("This may take a while for large projects...")
        }

        // Run swift build with symbol graph emission for ALL targets
        let process = Process()
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
                // Print progress in verbose mode
                if verbose, let str = String(data: data, encoding: .utf8) {
                    print(str, terminator: "")
                }
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                Task { await errorCollector.append(data) }
                if verbose, let str = String(data: data, encoding: .utf8) {
                    print(str, terminator: "")
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
                print("Swift build failed with exit code \(process.terminationStatus)")
                print("Error output: \(errorString)")
            }
            return nil
        }

        // Check if symbol graphs were generated
        let contents = try? FileManager.default.contentsOfDirectory(at: symbolGraphDir, includingPropertiesForKeys: nil)
        let symbolGraphFiles = contents?.filter { $0.pathExtension == "json" } ?? []

        if symbolGraphFiles.isEmpty {
            if verbose {
                print("Symbol graph generation produced no files")
            }
            return nil
        }

        if verbose {
            print("Generated \(symbolGraphFiles.count) symbol graph file(s)")
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

                if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
                   let size = attrs[.size] as? Int64 {
                    totalSize += size
                }
            }
        }

        if verbose {
            let sizeMB = Double(totalSize) / 1_000_000.0
            print("Filtered symbol graphs: \(copiedCount) files (\(String(format: "%.1f", sizeMB))MB) from \(contents.count) total")
        }

        return filteredDir
    }

    /// Check if symbol graphs already exist and are non-empty
    public nonisolated func hasExistingSymbolGraphs(at directory: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return false
        }

        let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let symbolFiles = contents?.filter { $0.pathExtension == "json" } ?? []

        return !symbolFiles.isEmpty
    }

    /// Clear cached symbol graph directory
    public func clearCache() {
        cachedSymbolGraphDir = nil
    }
}

/// Actor for safely collecting data from async pipe handlers
actor DataCollector {
    private var data = Data()

    func append(_ newData: Data) {
        data.append(newData)
    }

    func getData() -> Data {
        return data
    }
}
