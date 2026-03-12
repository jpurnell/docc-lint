import Testing
import Foundation
@testable import DocCLint

@Suite("CacheEntry Model Tests")
struct CacheEntryTests {

    // MARK: - ScanSummary Tests

    @Suite("ScanSummary")
    struct ScanSummaryTests {

        @Test("hasIssues returns true for errors")
        func hasIssuesWithErrors() {
            let summary = CacheEntry.ScanSummary(errors: 1, warnings: 0, notes: 0)
            #expect(summary.hasIssues == true)
        }

        @Test("hasIssues returns true for warnings")
        func hasIssuesWithWarnings() {
            let summary = CacheEntry.ScanSummary(errors: 0, warnings: 1, notes: 0)
            #expect(summary.hasIssues == true)
        }

        @Test("hasIssues returns false for notes only")
        func hasIssuesWithNotesOnly() {
            let summary = CacheEntry.ScanSummary(errors: 0, warnings: 0, notes: 5)
            #expect(summary.hasIssues == false)
        }

        @Test("hasIssues returns false when clean")
        func hasIssuesWhenClean() {
            let summary = CacheEntry.ScanSummary(errors: 0, warnings: 0, notes: 0)
            #expect(summary.hasIssues == false)
        }

        @Test("hasIssues returns true for mixed issues")
        func hasIssuesWithMixed() {
            let summary = CacheEntry.ScanSummary(errors: 2, warnings: 5, notes: 10)
            #expect(summary.hasIssues == true)
        }

        @Test("ScanSummary encodes/decodes correctly")
        func encodeDecodeRoundTrip() throws {
            let original = CacheEntry.ScanSummary(errors: 3, warnings: 7, notes: 2)

            let encoder = JSONEncoder()
            let data = try encoder.encode(original)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(CacheEntry.ScanSummary.self, from: data)

            #expect(decoded.errors == original.errors)
            #expect(decoded.warnings == original.warnings)
            #expect(decoded.notes == original.notes)
        }
    }

    // MARK: - CacheEntry Tests

    @Suite("CacheEntry Creation")
    struct CacheEntryCreationTests {

        @Test("Create cache entry with all fields")
        func createFullEntry() {
            let now = Date()
            let summary = CacheEntry.ScanSummary(errors: 1, warnings: 2, notes: 3)

            let entry = CacheEntry(
                path: "/path/to/file.md",
                contentHash: "abc123def456",
                modificationTime: now,
                lastScanSummary: summary
            )

            #expect(entry.path == "/path/to/file.md")
            #expect(entry.contentHash == "abc123def456")
            #expect(entry.modificationTime == now)
            #expect(entry.lastScanSummary?.errors == 1)
            #expect(entry.lastScanSummary?.warnings == 2)
            #expect(entry.lastScanSummary?.notes == 3)
        }

        @Test("Create cache entry without scan summary")
        func createEntryWithoutSummary() {
            let entry = CacheEntry(
                path: "/path/to/file.md",
                contentHash: "abc123",
                modificationTime: Date(),
                lastScanSummary: nil
            )

            #expect(entry.lastScanSummary == nil)
        }

        @Test("CacheEntry encodes/decodes correctly")
        func encodeDecodeRoundTrip() throws {
            let original = CacheEntry(
                path: "/test/path.md",
                contentHash: "hash123",
                modificationTime: Date(timeIntervalSince1970: 1000000),
                lastScanSummary: CacheEntry.ScanSummary(errors: 1, warnings: 2, notes: 0)
            )

            let encoder = JSONEncoder()
            let data = try encoder.encode(original)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(CacheEntry.self, from: data)

            #expect(decoded.path == original.path)
            #expect(decoded.contentHash == original.contentHash)
            #expect(decoded.lastScanSummary?.errors == original.lastScanSummary?.errors)
        }
    }

    // MARK: - CacheFile Tests

    @Suite("CacheFile")
    struct CacheFileTests {

        @Test("Create empty cache file")
        func createEmptyCache() {
            let cache = CacheFile()

            #expect(cache.version == 1)
            #expect(cache.entries.isEmpty)
        }

        @Test("Create cache file with custom values")
        func createCustomCache() {
            let entries: [String: CacheEntry] = [
                "/path/a.md": CacheEntry(
                    path: "/path/a.md",
                    contentHash: "hash1",
                    modificationTime: Date(),
                    lastScanSummary: nil
                )
            ]

            let cache = CacheFile(
                version: 2,
                lastUpdated: Date(),
                entries: entries
            )

            #expect(cache.version == 2)
            #expect(cache.entries.count == 1)
        }

        @Test("CacheFile is mutable for lastUpdated")
        func mutateLastUpdated() {
            var cache = CacheFile()
            let newDate = Date()
            cache.lastUpdated = newDate

            #expect(cache.lastUpdated == newDate)
        }

        @Test("CacheFile entries can be added")
        func addEntries() {
            var cache = CacheFile()

            let entry = CacheEntry(
                path: "/test.md",
                contentHash: "hash",
                modificationTime: Date(),
                lastScanSummary: nil
            )

            cache.entries["/test.md"] = entry

            #expect(cache.entries.count == 1)
            #expect(cache.entries["/test.md"]?.contentHash == "hash")
        }

        @Test("CacheFile encodes/decodes correctly")
        func encodeDecodeRoundTrip() throws {
            var original = CacheFile()
            original.entries["/test.md"] = CacheEntry(
                path: "/test.md",
                contentHash: "hash123",
                modificationTime: Date(timeIntervalSince1970: 1000000),
                lastScanSummary: CacheEntry.ScanSummary(errors: 0, warnings: 1, notes: 0)
            )

            let encoder = JSONEncoder()
            let data = try encoder.encode(original)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(CacheFile.self, from: data)

            #expect(decoded.version == original.version)
            #expect(decoded.entries.count == original.entries.count)
            #expect(decoded.entries["/test.md"]?.contentHash == "hash123")
        }
    }
}
