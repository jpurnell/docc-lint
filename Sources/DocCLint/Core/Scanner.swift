import Foundation
import os

/// Logger for file scanning operations
private let logger = Logger(subsystem: "com.docc-lint", category: "Scanner") // LIVE: logging infrastructure

/// Options for file discovery
public struct ScanOptions: Sendable {
    /// Include Swift files with documentation comments
    public let includeSwiftDocs: Bool

    /// Glob patterns to ignore
    public let ignorePatterns: [String]

    /// Creates scan options with the given settings.
    public init(includeSwiftDocs: Bool = false, ignorePatterns: [String] = []) {
        self.includeSwiftDocs = includeSwiftDocs
        self.ignorePatterns = ignorePatterns
    }

    /// Default ignore patterns for common build artifacts
    public static let defaultIgnorePatterns = [
        "**/.build/**",
        "**/build/**",
        "**/DerivedData/**",
        "**/Pods/**",
        "**/.git/**",
        "**/node_modules/**"
    ]
}

/// A discovered file ready for processing
public struct DiscoveredFile: Sendable {
    /// URL to the file or catalog
    public let url: URL

    /// Type classification
    public let type: FileType

    /// File size in bytes
    public let size: Int64

    /// Modification date
    public let modificationDate: Date

    /// Creates a discovered file with the given metadata.
    public init(url: URL, type: FileType, size: Int64, modificationDate: Date) {
        self.url = url
        self.type = type
        self.size = size
        self.modificationDate = modificationDate
    }

    /// File type classification
    public enum FileType: Sendable {
        /// A .docc catalog bundle
        case doccCatalog(URL)

        /// A markdown file inside a .docc catalog
        case markdownInCatalog(catalogURL: URL)

        /// A standalone markdown file outside any catalog
        case standaloneMarkdown // LIVE: public API

        /// A Swift source file with doc comments
        case swiftSource
    }
}

/// Discovers files for DocC validation
public actor Scanner {
    /// File manager used for file system queries.
    private let fileManager = FileManager.default

    /// Creates a new scanner.
    public init() {}

    /// Discover all files to scan at the given root
    public func discoverFiles(
        at root: URL,
        options: ScanOptions
    ) async throws -> [DiscoveredFile] {
        var results: [DiscoveredFile] = []
        let ignorePatterns = options.ignorePatterns + ScanOptions.defaultIgnorePatterns

        // Find all .docc catalogs
        let catalogs = try findDocCCatalogs(at: root, ignoring: ignorePatterns)

        for catalogURL in catalogs {
            // Add the catalog itself
            if let vals = try? catalogURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) { // silent: error is expected and non-fatal
                results.append(DiscoveredFile(
                    url: catalogURL,
                    type: .doccCatalog(catalogURL),
                    size: Int64(vals.fileSize ?? 0),
                    modificationDate: vals.contentModificationDate ?? Date()
                ))
            }

            // Find markdown files within the catalog
            let markdownFiles = try findMarkdownFiles(in: catalogURL)
            for mdURL in markdownFiles {
                if let vals = try? mdURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) { // silent: error is expected and non-fatal
                    results.append(DiscoveredFile(
                        url: mdURL,
                        type: .markdownInCatalog(catalogURL: catalogURL),
                        size: Int64(vals.fileSize ?? 0),
                        modificationDate: vals.contentModificationDate ?? Date()
                    ))
                }
            }
        }

        // Optionally find Swift files with doc comments
        if options.includeSwiftDocs {
            let swiftFiles = try findSwiftFiles(at: root, ignoring: ignorePatterns)
            for swiftURL in swiftFiles {
                if let vals = try? swiftURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]), // silent: error is expected and non-fatal
                   await hasDocComments(swiftURL) {
                    results.append(DiscoveredFile(
                        url: swiftURL,
                        type: .swiftSource,
                        size: Int64(vals.fileSize ?? 0),
                        modificationDate: vals.contentModificationDate ?? Date()
                    ))
                }
            }
        }

        return results
    }

    /// Find all .docc catalog directories using fast shell command
    private func findDocCCatalogs(at root: URL, ignoring patterns: [String]) throws -> [URL] {
        // First, check if root itself is a .docc catalog
        if root.pathExtension == "docc" {
            let resourceValues = try? root.resourceValues(forKeys: [.isDirectoryKey]) // silent: error is expected and non-fatal
            if resourceValues?.isDirectory == true {
                return [root]
            }
        }

        // Use find command for speed - exclude common build directories
        let process: Process = .init() // Justification: hardcoded executable path, arguments are validated file paths
        process.executableURL = URL(fileURLWithPath: "/usr/bin/find")
        process.arguments = [
            root.path,
            "-type", "d",
            "-name", "*.docc",
            "-not", "-path", "*/.build/*",
            "-not", "-path", "*/build/*",
            "-not", "-path", "*/.git/*",
            "-not", "-path", "*/DerivedData/*"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(data: data, encoding: .utf8) ?? ""

        return output
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0) }
    }

    /// Find documentation files within a .docc catalog (.md and .tutorial) using fast shell command
    private func findMarkdownFiles(in catalog: URL) throws -> [URL] {
        let process: Process = .init() // Justification: hardcoded executable path, arguments are validated file paths
        process.executableURL = URL(fileURLWithPath: "/usr/bin/find")
        process.arguments = [
            catalog.path,
            "-type", "f",
            "(", "-name", "*.md", "-o", "-name", "*.tutorial", ")"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(data: data, encoding: .utf8) ?? ""

        return output
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0) }
            .sorted { $0.path < $1.path }
    }

    /// Find Swift source files
    private func findSwiftFiles(at root: URL, ignoring patterns: [String]) throws -> [URL] {
        var swiftFiles: [URL] = []

        let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        while let url = enumerator?.nextObject() as? URL {
            if shouldIgnore(url, patterns: patterns) {
                enumerator?.skipDescendants()
                continue
            }

            if url.pathExtension == "swift" {
                swiftFiles.append(url)
            }
        }

        return swiftFiles
    }

    /// Check if a Swift file contains documentation comments
    private func hasDocComments(_ url: URL) async -> Bool {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { // silent: error is expected and non-fatal
            return false
        }

        // Quick check for doc comment patterns
        return content.contains("///") || content.contains("/**")
    }

    /// Check if a URL matches any ignore pattern
    private func shouldIgnore(_ url: URL, patterns: [String]) -> Bool {
        let path = url.path

        for pattern in patterns {
            if matchesGlobPattern(path: path, pattern: pattern) {
                return true
            }
        }

        return false
    }

    /// Simple glob pattern matching
    private func matchesGlobPattern(path: String, pattern: String) -> Bool {
        // Handle ** patterns
        if pattern.contains("**") {
            let components = pattern.components(separatedBy: "**")
            if components.count == 2 {
                let prefix = components[0].replacingOccurrences(of: "*", with: "")
                let suffix = components[1].replacingOccurrences(of: "*", with: "")

                if !prefix.isEmpty && !path.contains(prefix) {
                    return false
                }
                if !suffix.isEmpty && !path.contains(suffix) {
                    return false
                }
                return true
            }
        }

        // Handle simple * patterns
        let regexPattern = pattern
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "*", with: ".*")

        return path.range(of: regexPattern, options: .regularExpression) != nil
    }
}
