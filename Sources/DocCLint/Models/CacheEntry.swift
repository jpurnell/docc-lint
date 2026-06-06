import Foundation

/// A cache entry for a scanned file.
public struct CacheEntry: Codable, Sendable {
    /// Path to the file.
    public let path: String

    /// SHA256 hash of file contents.
    public let contentHash: String

    /// File modification time when cached.
    public let modificationTime: Date

    /// Summary of last scan result.
    public let lastScanSummary: ScanSummary?

    /// Creates a new cache entry with the specified values.
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

    /// Brief summary of scan results for caching.
    public struct ScanSummary: Codable, Sendable {
        /// The number of errors found.
        public let errors: Int
        /// The number of warnings found.
        public let warnings: Int
        /// The number of notes found.
        public let notes: Int

        /// Creates a new scan summary with the specified counts.
        public init(errors: Int, warnings: Int, notes: Int) {
            self.errors = errors
            self.warnings = warnings
            self.notes = notes
        }

        /// Whether the scan found any errors or warnings.
        public var hasIssues: Bool {
            errors > 0 || warnings > 0
        }
    }
}

/// The complete cache file structure.
public struct CacheFile: Codable, Sendable {
    /// Cache format version.
    public let version: Int

    /// When the cache was last updated.
    public var lastUpdated: Date

    /// Cached entries by file path.
    public var entries: [String: CacheEntry]

    /// Creates a new cache file with the specified values.
    public init(version: Int = 1, lastUpdated: Date = Date(), entries: [String: CacheEntry] = [:]) {
        self.version = version
        self.lastUpdated = lastUpdated
        self.entries = entries
    }
}
