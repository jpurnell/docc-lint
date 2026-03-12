import Foundation

/// A cache entry for a scanned file
public struct CacheEntry: Codable, Sendable {
    /// Path to the file
    public let path: String

    /// SHA256 hash of file contents
    public let contentHash: String

    /// File modification time when cached
    public let modificationTime: Date

    /// Summary of last scan result
    public let lastScanSummary: ScanSummary?

    public init(
        path: String,
        contentHash: String,
        modificationTime: Date,
        lastScanSummary: ScanSummary?
    ) {
        self.path = path
        self.contentHash = contentHash
        self.modificationTime = modificationTime
        self.lastScanSummary = lastScanSummary
    }

    /// Brief summary of scan results for caching
    public struct ScanSummary: Codable, Sendable {
        public let errors: Int
        public let warnings: Int
        public let notes: Int

        public init(errors: Int, warnings: Int, notes: Int) {
            self.errors = errors
            self.warnings = warnings
            self.notes = notes
        }

        public var hasIssues: Bool {
            errors > 0 || warnings > 0
        }
    }
}

/// The complete cache file structure
public struct CacheFile: Codable, Sendable {
    /// Cache format version
    public let version: Int

    /// When the cache was last updated
    public var lastUpdated: Date

    /// Cached entries by file path
    public var entries: [String: CacheEntry]

    public init(version: Int = 1, lastUpdated: Date = Date(), entries: [String: CacheEntry] = [:]) {
        self.version = version
        self.lastUpdated = lastUpdated
        self.entries = entries
    }
}
