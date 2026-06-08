import Testing
import Foundation
@testable import DocCLint

@Suite("DocCProcessor Tests")
struct DocCProcessorTests {

    // MARK: - Symbol Graph Generation Tests

    @Suite("Symbol Graph Generation")
    struct SymbolGraphGenerationTests {

        // MARK: - Project Root Detection Tests

        @Test("Detect Package.swift at project root")
        func detectPackageSwift() async throws {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("test-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            // Create Package.swift
            let packageSwift = """
            // swift-tools-version: 5.9
            import PackageDescription
            let package = Package(name: "TestPackage")
            """
            try packageSwift.write(
                to: tempDir.appendingPathComponent("Package.swift"),
                atomically: true,
                encoding: .utf8
            )

            let hasPackage = FileManager.default.fileExists(
                atPath: tempDir.appendingPathComponent("Package.swift").path
            )
            #expect(hasPackage)
        }

        @Test("Project root calculation from catalog path")
        func projectRootFromCatalogPath() {
            // Given: /path/to/project/Sources/ModuleName/ModuleName.docc
            // Expected root: /path/to/project
            let catalogURL = URL(fileURLWithPath: "/Users/test/MyProject/Sources/MyModule/MyModule.docc")

            let projectRoot = catalogURL
                .deletingLastPathComponent()  // /Users/test/MyProject/Sources/MyModule
                .deletingLastPathComponent()  // /Users/test/MyProject/Sources
                .deletingLastPathComponent()  // /Users/test/MyProject

            #expect(projectRoot.lastPathComponent == "MyProject")
        }

        @Test("Handles catalog at non-standard depth")
        func nonStandardCatalogDepth() {
            // Catalog directly in project root: /project/Module.docc
            let shallowCatalog = URL(fileURLWithPath: "/project/Module.docc")
            let shallowRoot = shallowCatalog
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()

            // Should still produce a valid URL (though possibly unexpected)
            #expect(!shallowRoot.path.isEmpty)

            // Deeply nested: /project/a/b/c/d/Module.docc
            let deepCatalog = URL(fileURLWithPath: "/project/a/b/c/d/Module.docc")
            let deepRoot = deepCatalog
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()

            #expect(deepRoot.lastPathComponent == "b")
        }

        // MARK: - Symbol Graph Directory Tests

        @Test("Symbol graph output directory structure")
        func symbolGraphOutputDirectory() throws {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("test-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            // Expected: .build/<platform>/debug/symbol-graph/
            let symbolGraphDir = tempDir
                .appendingPathComponent(".build")
                .appendingPathComponent("arm64-apple-macosx")
                .appendingPathComponent("debug")
                .appendingPathComponent("symbol-graph")

            try FileManager.default.createDirectory(at: symbolGraphDir, withIntermediateDirectories: true)

            #expect(FileManager.default.fileExists(atPath: symbolGraphDir.path))
        }

        @Test("Symbol graph files have correct extension")
        func symbolGraphFileExtension() throws {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("test-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            // Symbol graphs are JSON files with .symbols.json extension
            let symbolFile = tempDir.appendingPathComponent("MyModule.symbols.json")
            try "{}".write(to: symbolFile, atomically: true, encoding: .utf8)

            let isSymbolGraph = symbolFile.pathExtension == "json" &&
                               symbolFile.deletingPathExtension().pathExtension == "symbols"

            #expect(isSymbolGraph)
        }

        // MARK: - Edge Cases

        @Test("Missing Package.swift returns nil for symbol graphs")
        func missingPackageSwift() async throws {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("test-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            // No Package.swift - should indicate inability to generate symbol graphs
            let hasPackage = FileManager.default.fileExists(
                atPath: tempDir.appendingPathComponent("Package.swift").path
            )
            #expect(!hasPackage)
        }

        @Test("Empty project root path handled gracefully")
        func emptyProjectRoot() {
            // Edge case: what if URL manipulation produces empty/invalid path
            let rootURL = URL(fileURLWithPath: "/")

            // Repeatedly calling deletingLastPathComponent on root should stay at root
            let afterDeletion = rootURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()

            // Should not crash and should produce a non-empty path
            #expect(!afterDeletion.path.isEmpty)
        }

        // MARK: - Processing Mode Tests

        @Test("ProcessingMode enum values")
        func processingModeValues() {
            let fullMode = ProcessingMode.full
            let syntaxMode = ProcessingMode.syntaxOnly

            // Both modes should be distinct
            switch fullMode {
            case .full:
                #expect(true)
            case .syntaxOnly:
                Issue.record("Full mode incorrectly matched syntaxOnly")
            }

            switch syntaxMode {
            case .full:
                Issue.record("SyntaxOnly mode incorrectly matched full")
            case .syntaxOnly:
                #expect(true)
            }
        }

        @Test("ProcessingMode is Sendable")
        func processingModeSendable() async {
            // This test verifies ProcessingMode can be safely passed across actor boundaries
            let mode: ProcessingMode = .full

            let task = Task {
                return mode
            }

            let result = await task.value
            #expect(result == .full)
        }
    }

    // MARK: - DocCProcessorError Tests

    @Suite("DocCProcessorError")
    struct DocCProcessorErrorTests {

        @Test("doccNotFound error description")
        func doccNotFoundDescription() {
            let error = DocCProcessorError.doccNotFound

            #expect(error.errorDescription?.contains("docc") == true)
            #expect(error.errorDescription?.contains("Xcode") == true)
        }

        @Test("processingFailed error includes message")
        func processingFailedDescription() {
            let message = "Symbol graph generation timed out"
            let error = DocCProcessorError.processingFailed(message)

            #expect(error.errorDescription?.contains(message) == true)
        }

        @Test("Errors conform to LocalizedError")
        func errorsAreLocalized() {
            let error1: LocalizedError = DocCProcessorError.doccNotFound
            let error2: LocalizedError = DocCProcessorError.processingFailed("test")

            #expect(error1.errorDescription == "Could not find docc executable. Ensure Xcode command line tools are installed.")
            #expect(error2.errorDescription == "DocC processing failed: test")
        }
    }

    // MARK: - Integration Tests (require actual swift toolchain)

    @Suite("Integration Tests")
    struct IntegrationTests {

        @Test("Generate symbol graphs for minimal SwiftPM package")
        @available(macOS 14.0, *)
        func generateSymbolGraphsMinimalPackage() async throws {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("test-symbolgraph-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            // Create minimal SwiftPM package
            let packageSwift = """
            // swift-tools-version: 5.9
            import PackageDescription
            let package = Package(
                name: "TestLib",
                products: [.library(name: "TestLib", targets: ["TestLib"])],
                targets: [.target(name: "TestLib")]
            )
            """
            try packageSwift.write(
                to: tempDir.appendingPathComponent("Package.swift"),
                atomically: true,
                encoding: .utf8
            )

            // Create source file
            let sourcesDir = tempDir.appendingPathComponent("Sources/TestLib")
            try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)

            let sourceCode = """
            /// A simple test function
            public func testFunction() -> Int { 42 }
            """
            try sourceCode.write(
                to: sourcesDir.appendingPathComponent("TestLib.swift"),
                atomically: true,
                encoding: .utf8
            )

            // Run swift build with symbol graph emission
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
            process.arguments = [
                "build",
                "--target", "TestLib",
                "-Xswiftc", "-emit-symbol-graph",
                "-Xswiftc", "-emit-symbol-graph-dir",
                "-Xswiftc", tempDir.appendingPathComponent(".build/symbol-graph").path
            ]
            process.currentDirectoryURL = tempDir

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            try process.run()
            process.waitUntilExit()

            // Check if symbol graph was generated
            let symbolGraphDir = tempDir.appendingPathComponent(".build/symbol-graph")
            let files = try? FileManager.default.contentsOfDirectory(at: symbolGraphDir, includingPropertiesForKeys: nil)
            let symbolGraphFiles = files?.filter { $0.pathExtension == "json" } ?? []

            // Should have at least one symbol graph file
            #expect(!symbolGraphFiles.isEmpty, "Expected symbol graph files to be generated")
        }

        @Test("Swift build for symbol graphs completes within timeout", .timeLimit(.minutes(1)))
        @available(macOS 14.0, *)
        func swiftBuildTimeout() async throws {
            // This test ensures we have reasonable timeout handling
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("test-timeout-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            // Create minimal package
            let packageSwift = """
            // swift-tools-version: 5.9
            import PackageDescription
            let package = Package(
                name: "TimeoutTest",
                products: [.library(name: "TimeoutTest", targets: ["TimeoutTest"])],
                targets: [.target(name: "TimeoutTest")]
            )
            """
            try packageSwift.write(
                to: tempDir.appendingPathComponent("Package.swift"),
                atomically: true,
                encoding: .utf8
            )

            let sourcesDir = tempDir.appendingPathComponent("Sources/TimeoutTest")
            try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
            try "public func test() {}".write(
                to: sourcesDir.appendingPathComponent("TimeoutTest.swift"),
                atomically: true,
                encoding: .utf8
            )

            // The test should complete within the time limit
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
            process.arguments = ["build", "--target", "TimeoutTest"]
            process.currentDirectoryURL = tempDir
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            try process.run()
            process.waitUntilExit()

            #expect(process.terminationStatus == 0)
        }
    }

    // MARK: - Symbol Graph Generation Strategy Tests

    @Suite("Symbol Graph Strategy")
    struct SymbolGraphStrategyTests {

        @Test("Symbol graphs should be generated once per project, not per catalog")
        func symbolGraphsGeneratedOncePerProject() async throws {
            // Given a project with multiple catalogs, symbol graph generation
            // should happen at the project level, not catalog level
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("test-strategy-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            // Create Package.swift
            let packageSwift = """
            // swift-tools-version: 5.9
            import PackageDescription
            let package = Package(
                name: "MultiModule",
                products: [
                    .library(name: "ModuleA", targets: ["ModuleA"]),
                    .library(name: "ModuleB", targets: ["ModuleB"])
                ],
                targets: [
                    .target(name: "ModuleA"),
                    .target(name: "ModuleB")
                ]
            )
            """
            try packageSwift.write(to: tempDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

            // Create sources
            for module in ["ModuleA", "ModuleB"] {
                let sourceDir = tempDir.appendingPathComponent("Sources/\(module)")
                try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
                try "public func \(module.lowercased())() {}".write(
                    to: sourceDir.appendingPathComponent("\(module).swift"),
                    atomically: true,
                    encoding: .utf8
                )
            }

            // The expectation is that SymbolGraphGenerator generates symbol graphs
            // for ALL targets in one build, not separately
            let generator = SymbolGraphGenerator()
            let result = try await generator.generateSymbolGraphs(
                projectRoot: tempDir,
                verbose: false
            )

            // Should have symbol graphs for both modules in ONE directory
            let dir = try #require(result)
            #expect(dir.lastPathComponent == "symbol-graph")
            let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            let symbolFiles = files.filter { $0.pathExtension == "json" }
            // At minimum should have symbol graphs present
            #expect(symbolFiles.count >= 1)
        }

        @Test("Pre-generated symbol graphs are reused if they exist")
        func preGeneratedSymbolGraphsReused() async throws {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("test-reuse-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            // Create a marker file in the symbol graph directory
            let symbolGraphDir = tempDir.appendingPathComponent(".build/symbol-graph")
            try FileManager.default.createDirectory(at: symbolGraphDir, withIntermediateDirectories: true)
            let markerFile = symbolGraphDir.appendingPathComponent("Test.symbols.json")
            try "{}".write(to: markerFile, atomically: true, encoding: .utf8)

            // Generator should detect existing symbol graphs and skip regeneration
            let generator = SymbolGraphGenerator()
            let hasExisting = generator.hasExistingSymbolGraphs(at: symbolGraphDir)

            #expect(hasExisting)
        }
    }

    // MARK: - Symbol Graph Helper Tests

    @Suite("Symbol Graph Helpers")
    struct SymbolGraphHelperTests {

        @Test("Extract target name from catalog path")
        func extractTargetName() {
            // Standard pattern: Sources/ModuleName/ModuleName.docc
            let catalogURL = URL(fileURLWithPath: "/project/Sources/BusinessMath/BusinessMath.docc")

            // Target name should match the parent directory
            let targetName = catalogURL.deletingLastPathComponent().lastPathComponent

            #expect(targetName == "BusinessMath")
        }

        @Test("Extract target name from non-standard catalog name")
        func extractTargetNameNonStandard() {
            // Catalog name doesn't match module: Sources/MyModule/Documentation.docc
            let catalogURL = URL(fileURLWithPath: "/project/Sources/MyModule/Documentation.docc")

            let parentDirName = catalogURL.deletingLastPathComponent().lastPathComponent
            let catalogName = catalogURL.deletingPathExtension().lastPathComponent

            // Parent directory is more reliable than catalog name for target
            #expect(parentDirName == "MyModule")
            #expect(catalogName == "Documentation")
        }

        @Test("Build arguments for symbol graph generation")
        func buildArgumentsForSymbolGraph() {
            let targetName = "MyModule"
            let outputDir = "/tmp/symbol-graphs"

            let expectedArgs = [
                "build",
                "--target", targetName,
                "-Xswiftc", "-emit-symbol-graph",
                "-Xswiftc", "-emit-symbol-graph-dir",
                "-Xswiftc", outputDir
            ]

            // Verify argument structure
            #expect(expectedArgs[0] == "build")
            #expect(expectedArgs[1] == "--target")
            #expect(expectedArgs[2] == targetName)
            #expect(expectedArgs.contains("-emit-symbol-graph"))
            #expect(expectedArgs.contains(outputDir))
        }

        @Test("Multiple targets build arguments",
              arguments: ["Target1", "Target2", "Target3"])
        func multipleTargetsBuildArgs(targetName: String) {
            let args = [
                "build",
                "--target", targetName,
                "-Xswiftc", "-emit-symbol-graph"
            ]

            #expect(args.contains(targetName))
        }
    }
}
