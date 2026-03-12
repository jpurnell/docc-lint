import Foundation
import Crypto

/// Manages file content hashing and caching for incremental scanning
public class HashCache {
    /// Path to the cache file
    private let cachePath: String

    /// In-memory cache data
    private var cacheFile: CacheFile

    /// File manager for file operations
    private let fileManager = FileManager.default

    public init(path: String) {
        self.cachePath = path
        self.cacheFile = CacheFile()
    }

    /// Load cache from disk
    public func load() throws {
        let url = URL(fileURLWithPath: cachePath)

        guard fileManager.fileExists(atPath: cachePath) else {
            cacheFile = CacheFile()
            return
        }

        let data = try Data(contentsOf: url)
        cacheFile = try JSONDecoder().decode(CacheFile.self, from: data)
    }

    /// Persist cache to disk
    public func persist() throws {
        let url = URL(fileURLWithPath: cachePath)

        // Ensure parent directory exists
        let parentDir = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
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

        let url = URL(fileURLWithPath: cachePath)
        if fileManager.fileExists(atPath: cachePath) {
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
        guard let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
              let currentModTime = attrs[.modificationDate] as? Date else {
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
    public func updateEntry(_ fileURL: URL, result: ScanResult) {
        guard let hash = computeHash(for: fileURL),
              let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
              let modDate = attrs[.modificationDate] as? Date else {
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
              let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
              let modDate = attrs[.modificationDate] as? Date else {
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
    public func getCachedResult(_ fileURL: URL) -> CacheEntry.ScanSummary? {
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
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}

/// Statistics about the cache
public struct CacheStatistics {
    public let entryCount: Int
    public let lastUpdated: Date?
    public let entriesWithIssues: [CacheEntry]
}
