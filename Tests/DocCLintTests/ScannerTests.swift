import Testing
import Foundation
@testable import DocCLint

@Suite("Scanner Tests")
struct ScannerTests {

    // Helper to create temporary directory structure
    private func createTempDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("docc-lint-scanner-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - File Discovery Tests

    @Suite("DocC Catalog Discovery")
    struct CatalogDiscoveryTests {

        @Test("Discover single .docc catalog")
        func discoverSingleCatalog() async throws {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("test-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            // Create a .docc catalog
            let catalogDir = tempDir.appendingPathComponent("Test.docc")
            try FileManager.default.createDirectory(at: catalogDir, withIntermediateDirectories: true)
            try "# Test".write(to: catalogDir.appendingPathComponent("Test.md"), atomically: true, encoding: .utf8)

            let scanner = Scanner()
            let files = try await scanner.discoverFiles(at: tempDir, options: ScanOptions())

            let catalogs = files.filter {
                if case .doccCatalog = $0.type { return true }
                return false
            }

            #expect(catalogs.count == 1)
        }

        @Test("Discover multiple .docc catalogs")
        func discoverMultipleCatalogs() async throws {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("test-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            // Create multiple catalogs
            for name in ["First", "Second", "Third"] {
                let catalogDir = tempDir.appendingPathComponent("\(name).docc")
                try FileManager.default.createDirectory(at: catalogDir, withIntermediateDirectories: true)
                try "# \(name)".write(to: catalogDir.appendingPathComponent("\(name).md"), atomically: true, encoding: .utf8)
            }

            let scanner = Scanner()
            let files = try await scanner.discoverFiles(at: tempDir, options: ScanOptions())

            let catalogs = files.filter {
                if case .doccCatalog = $0.type { return true }
                return false
            }

            #expect(catalogs.count == 3)
        }

        @Test("Discover nested .docc catalogs")
        func discoverNestedCatalogs() async throws {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("test-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            // Create nested structure
            let sourcesDir = tempDir.appendingPathComponent("Sources/MyLib")
            try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)

            let catalogDir = sourcesDir.appendingPathComponent("MyLib.docc")
            try FileManager.default.createDirectory(at: catalogDir, withIntermediateDirectories: true)
            try "# MyLib".write(to: catalogDir.appendingPathComponent("MyLib.md"), atomically: true, encoding: .utf8)

            let scanner = Scanner()
            let files = try await scanner.discoverFiles(at: tempDir, options: ScanOptions())

            let catalogs = files.filter {
                if case .doccCatalog = $0.type { return true }
                return false
            }

            #expect(catalogs.count == 1)
        }

        @Test("Direct .docc path is recognized")
        func discoverDirectCatalogPath() async throws {
            let catalogDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("test-\(UUID().uuidString).docc")
            try FileManager.default.createDirectory(at: catalogDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: catalogDir) }

            try "# Test".write(to: catalogDir.appendingPathComponent("Test.md"), atomically: true, encoding: .utf8)

            let scanner = Scanner()
            let files = try await scanner.discoverFiles(at: catalogDir, options: ScanOptions())

            let catalogs = files.filter {
                if case .doccCatalog = $0.type { return true }
                return false
            }

            #expect(catalogs.count == 1)
        }
    }

    // MARK: - Markdown Discovery Tests

    @Suite("Markdown File Discovery")
    struct MarkdownDiscoveryTests {

        @Test("Discover markdown files within catalog")
        func discoverMarkdownInCatalog() async throws {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("test-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let catalogDir = tempDir.appendingPathComponent("Test.docc")
            try FileManager.default.createDirectory(at: catalogDir, withIntermediateDirectories: true)

            // Create multiple markdown files
            for name in ["Overview", "Guide", "Reference", "Tutorial"] {
                try "# \(name)".write(
                    to: catalogDir.appendingPathComponent("\(name).md"),
                    atomically: true,
                    encoding: .utf8
                )
            }

            let scanner = Scanner()
            let files = try await scanner.discoverFiles(at: tempDir, options: ScanOptions())

            let markdownFiles = files.filter {
                if case .markdownInCatalog = $0.type { return true }
                return false
            }

            #expect(markdownFiles.count == 4)
        }

        @Test("Discover nested markdown files in catalog subdirectories")
        func discoverNestedMarkdown() async throws {
            let catalogDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("test-\(UUID().uuidString).docc")
            try FileManager.default.createDirectory(at: catalogDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: catalogDir) }

            // Create nested structure
            let articlesDir = catalogDir.appendingPathComponent("Articles")
            let tutorialsDir = catalogDir.appendingPathComponent("Tutorials")
            try FileManager.default.createDirectory(at: articlesDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: tutorialsDir, withIntermediateDirectories: true)

            try "# Main".write(to: catalogDir.appendingPathComponent("Main.md"), atomically: true, encoding: .utf8)
            try "# Article".write(to: articlesDir.appendingPathComponent("Article.md"), atomically: true, encoding: .utf8)
            try "# Tutorial".write(to: tutorialsDir.appendingPathComponent("Tutorial.md"), atomically: true, encoding: .utf8)

            let scanner = Scanner()
            let files = try await scanner.discoverFiles(at: catalogDir, options: ScanOptions())

            let markdownFiles = files.filter {
                if case .markdownInCatalog = $0.type { return true }
                return false
            }

            #expect(markdownFiles.count == 3)
        }
    }

    // MARK: - Ignore Pattern Tests

    @Suite("Ignore Pattern Handling")
    struct IgnorePatternTests {

        @Test("Default ignore patterns exclude .build directory")
        func ignoreDefaultBuildDirectory() async throws {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("test-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            // Create catalog in .build (should be ignored)
            let buildDir = tempDir.appendingPathComponent(".build/Test.docc")
            try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
            try "# Build".write(to: buildDir.appendingPathComponent("Test.md"), atomically: true, encoding: .utf8)

            // Create catalog outside .build (should be found)
            let sourceDir = tempDir.appendingPathComponent("Sources/Test.docc")
            try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
            try "# Source".write(to: sourceDir.appendingPathComponent("Test.md"), atomically: true, encoding: .utf8)

            let scanner = Scanner()
            let files = try await scanner.discoverFiles(at: tempDir, options: ScanOptions())

            let catalogs = files.filter {
                if case .doccCatalog = $0.type { return true }
                return false
            }

            #expect(catalogs.count == 1)
            #expect(catalogs[0].url.path.contains("Sources"))
        }

        @Test("Custom ignore patterns work")
        func customIgnorePatterns() async throws {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("test-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            // Create catalogs
            let ignoreDir = tempDir.appendingPathComponent("ignore-me/Test.docc")
            let keepDir = tempDir.appendingPathComponent("keep-me/Test.docc")
            try FileManager.default.createDirectory(at: ignoreDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: keepDir, withIntermediateDirectories: true)
            try "# Ignore".write(to: ignoreDir.appendingPathComponent("Test.md"), atomically: true, encoding: .utf8)
            try "# Keep".write(to: keepDir.appendingPathComponent("Test.md"), atomically: true, encoding: .utf8)

            let options = ScanOptions(ignorePatterns: ["**/ignore-me/**"])
            let scanner = Scanner()
            let files = try await scanner.discoverFiles(at: tempDir, options: options)

            let catalogs = files.filter {
                if case .doccCatalog = $0.type { return true }
                return false
            }

            #expect(catalogs.count == 1)
            #expect(catalogs[0].url.path.contains("keep-me"))
        }
    }

    // MARK: - Edge Cases

    @Suite("Edge Cases")
    struct EdgeCaseTests {

        @Test("Empty directory returns empty results")
        func emptyDirectory() async throws {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("test-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let scanner = Scanner()
            let files = try await scanner.discoverFiles(at: tempDir, options: ScanOptions())

            #expect(files.isEmpty)
        }

        @Test("Directory with only non-docc files returns empty")
        func nonDoccFilesOnly() async throws {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("test-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            // Create non-docc files
            try "test".write(to: tempDir.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
            try "let x = 1".write(to: tempDir.appendingPathComponent("code.swift"), atomically: true, encoding: .utf8)

            let scanner = Scanner()
            let files = try await scanner.discoverFiles(at: tempDir, options: ScanOptions())

            #expect(files.isEmpty)
        }

        @Test("File with .docc extension but not directory is ignored")
        func doccFileNotDirectory() async throws {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("test-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            // Create a FILE with .docc extension (not a directory)
            try "not a catalog".write(
                to: tempDir.appendingPathComponent("test.docc"),
                atomically: true,
                encoding: .utf8
            )

            let scanner = Scanner()
            let files = try await scanner.discoverFiles(at: tempDir, options: ScanOptions())

            #expect(files.isEmpty)
        }
    }
}
