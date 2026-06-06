import Foundation
import CryptoKit
import os

/// Logger for hash cache operations
private let logger = Logger(subsystem: "com.docc-lint", category: "HashCache") // LIVE: logging infrastructure

/// Manages file content hashing and caching for incremental scanning
public class HashCache {
    /// Path to the cache file
    private let cachePath: String

    /// In-memory cache data
    private var cacheFile: CacheFile

    /// File manager for file operations
    private let fileManager = FileManager.default

    /// Creates a new hash cache backed by the file at the given path.
    public init(path: String) {
        self.cachePath = path
        self.cacheFile = CacheFile()
    }

    /// Load cache from disk
    public func load() throws {
        let safePath = URL(fileURLWithPath: cachePath).standardized
        let url = safePath

        guard (try? url.checkResourceIsReachable()) ?? false else { // silent: existence check
            cacheFile = CacheFile()
            return
        }

        let data = try Data(contentsOf: url)
        cacheFile = try JSONDecoder().decode(CacheFile.self, from: data)
    }

    /// Persist cache to disk
    public func persist() throws {
        let safePath = URL(fileURLWithPath: cachePath).standardized
        let url = safePath

        // Ensure parent directory exists
        let parentDir = url.deletingLastPathComponent()
        if !((try? parentDir.checkResourceIsReachable()) ?? false) { // silent: existence check
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        cacheFile.lastUpdated = Date()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(cacheFile)
        try data.write(to: url)
    }

    /// Clear all cached entries
    public func clear() throws {
        cacheFile = CacheFile()

        let safePath = URL(fileURLWithPath: cachePath).standardized
        let url = safePath
        if (try? url.checkResourceIsReachable()) ?? false { // silent: existence check
            try fileManager.removeItem(at: url)
        }
    }

    /// Check if a file needs to be scanned (content changed since last scan)
    /// Uses fast modification time check first, only computes hash if needed
    public func needsScan(_ fileURL: URL) -> Bool {
        guard let entry = cacheFile.entries[fileURL.path] else {
            return true // Not cached, needs scan
        }

        // Check if file still exists and get modification time
        guard let vals = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]), // silent: error is expected and non-fatal
              let currentModTime = vals.contentModificationDate else {
            return true
        }

        // FAST PATH: If modification time hasn't changed, file is unchanged
        if currentModTime == entry.modificationTime {
            return false  // No need to scan
        }

        // Modification time changed - verify with hash (handles clock drift, etc.)
        guard let currentHash = computeHash(for: fileURL) else {
            return true // Can't compute hash, scan to be safe
        }

        return entry.contentHash != currentHash
    }

    /// Update cache entry after scanning a file
    public func updateEntry(_ fileURL: URL, result: ScanResult) { // LIVE: public API
        guard let hash = computeHash(for: fileURL),
              let vals = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]), // silent: error is expected and non-fatal
              let modDate = vals.contentModificationDate else {
            return
        }

        let summary = CacheEntry.ScanSummary(
            errors: result.summary.errors,
            warnings: result.summary.warnings,
            notes: result.summary.notes
        )

        let entry = CacheEntry(
            path: fileURL.path,
            contentHash: hash,
            modificationTime: modDate,
            lastScanSummary: summary
        )

        cacheFile.entries[fileURL.path] = entry
    }

    /// Update cache entry with diagnostics array (for file-by-file processing)
    public func updateEntry(_ fileURL: URL, diagnostics: [MappedDiagnostic]) {
        guard let hash = computeHash(for: fileURL),
              let vals = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]), // silent: error is expected and non-fatal
              let modDate = vals.contentModificationDate else {
            return
        }

        let summary = CacheEntry.ScanSummary(
            errors: diagnostics.filter { $0.severity == .error }.count,
            warnings: diagnostics.filter { $0.severity == .warning }.count,
            notes: diagnostics.filter { $0.severity == .note }.count
        )

        let entry = CacheEntry(
            path: fileURL.path,
            contentHash: hash,
            modificationTime: modDate,
            lastScanSummary: summary
        )

        cacheFile.entries[fileURL.path] = entry
    }

    /// Get cached result for a file if available and still valid
    public func getCachedResult(_ fileURL: URL) -> CacheEntry.ScanSummary? { // LIVE: public API
        guard !needsScan(fileURL),
              let entry = cacheFile.entries[fileURL.path] else {
            return nil
        }
        return entry.lastScanSummary
    }

    /// Get statistics about the cache
    public func statistics() -> CacheStatistics {
        let entriesWithIssues = cacheFile.entries.values.filter {
            $0.lastScanSummary?.hasIssues ?? false
        }

        return CacheStatistics(
            entryCount: cacheFile.entries.count,
            lastUpdated: cacheFile.entries.isEmpty ? nil : cacheFile.lastUpdated,
            entriesWithIssues: Array(entriesWithIssues)
        )
    }

    /// Compute SHA256 hash of file contents
    private func computeHash(for url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { // silent: error is expected and non-fatal
            return nil
        }

        let digest = SHA256.hash(data: data)
        return digest.compactMap { byte in
            let hex = String(byte, radix: 16)
            return byte < 16 ? "0\(hex)" : hex
        }.joined()
    }
}

/// Statistics about the cache
public struct CacheStatistics {
    /// Total number of entries in the cache.
    public let entryCount: Int

    /// Date the cache was last updated, if available.
    public let lastUpdated: Date?

    /// Cache entries that recorded at least one issue.
    public let entriesWithIssues: [CacheEntry]
}
