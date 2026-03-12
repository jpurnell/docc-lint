import Foundation

/// Parses DocC diagnostics JSON and maps to source files
public struct DiagnosticParser {

    public init() {}

    /// Parse diagnostics JSON and map to source files
    public func parseDiagnostics(
        json: String,
        catalog: URL
    ) throws -> [MappedDiagnostic] {
        guard let data = json.data(using: .utf8) else {
            return []
        }

        let decoder = JSONDecoder()
        let diagnosticsFile: DiagnosticsFile

        do {
            diagnosticsFile = try decoder.decode(DiagnosticsFile.self, from: data)
        } catch {
            // Try to extract diagnostics from partial JSON or different format
            return try parseAlternativeFormat(json: json, catalog: catalog)
        }

        // Get ordered list of markdown files in the catalog for source mapping
        let catalogFiles = try getOrderedFiles(in: catalog)

        // Map each diagnostic to its source file
        return diagnosticsFile.diagnostics.compactMap { rawDiag in
            mapDiagnostic(rawDiag, catalogFiles: catalogFiles, catalog: catalog)
        }
    }

    /// Parse diagnostics from Xcode's DerivedData diagnostics file
    public func parseDiagnosticsFile(at path: String, catalog: URL) throws -> [MappedDiagnostic] {
        let json = try String(contentsOfFile: path, encoding: .utf8)
        return try parseDiagnostics(json: json, catalog: catalog)
    }

    /// Get markdown files in the catalog in processing order
    private func getOrderedFiles(in catalog: URL) throws -> [CatalogFile] {
        var files: [CatalogFile] = []

        let enumerator = FileManager.default.enumerator(
            at: catalog,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "md" {
                let content = try? String(contentsOf: url, encoding: .utf8)
                let lines = content?.components(separatedBy: .newlines) ?? []

                files.append(CatalogFile(
                    url: url,
                    lineCount: lines.count,
                    lines: lines,
                    lineLengths: lines.map { $0.count }
                ))
            }
        }

        // Sort by path to match DocC's processing order
        files.sort { $0.url.path < $1.url.path }

        return files
    }

    /// Map a raw diagnostic to its source file
    private func mapDiagnostic(
        _ raw: RawDiagnostic,
        catalogFiles: [CatalogFile],
        catalog: URL
    ) -> MappedDiagnostic {
        let line = raw.range.start.line
        let column = raw.range.start.column
        let endColumn = raw.range.end.column
        let lineLength = endColumn - column

        var matchedFile: CatalogFile? = nil
        var matchedLine: Int = line
        var content: String? = nil
        var filePath: String? = nil

        // Strategy 0 (BEST): Use the source field from docc JSON if available
        if let sourceURL = raw.source?.url {
            // Extract file path from URL (e.g., "file:///path/to/file.md" -> "/path/to/file.md")
            if sourceURL.hasPrefix("file://") {
                filePath = String(sourceURL.dropFirst(7))
                // URL decode the path
                filePath = filePath?.removingPercentEncoding ?? filePath
            } else {
                filePath = sourceURL
            }

            // Find the matching catalog file if we have a path
            if let path = filePath {
                matchedFile = catalogFiles.first { $0.url.path == path }
                if matchedFile != nil && line > 0 && line <= matchedFile!.lines.count {
                    content = matchedFile!.lines[line - 1]
                }
                matchedLine = line
            }
        }

        // Strategy 1: Use line length to find matching file (fallback)
        // This works because diagnostic line numbers are global across all files processed
        if matchedFile == nil {
            // Try to find the file by matching column width to actual line content
            for file in catalogFiles {
                // Check if any line in this file has the matching length
                for (index, length) in file.lineLengths.enumerated() where length == lineLength {
                    // Additional verification: check if the line number makes sense
                    if index + 1 == line || (matchedFile == nil && length == lineLength) {
                        matchedFile = file
                        matchedLine = index + 1
                        if index < file.lines.count {
                            content = file.lines[index]
                        }
                        break
                    }
                }
            }
        }

        // Strategy 2: If no match by length, try cumulative line counting
        if matchedFile == nil {
            var cumulativeLines = 0
            for file in catalogFiles {
                if cumulativeLines + file.lineCount >= line {
                    matchedFile = file
                    matchedLine = line - cumulativeLines
                    if matchedLine > 0 && matchedLine <= file.lines.count {
                        content = file.lines[matchedLine - 1]
                    }
                    break
                }
                cumulativeLines += file.lineCount
            }
        }

        // Parse severity
        let severity: DiagnosticSeverity
        switch raw.severity.lowercased() {
        case "error":
            severity = .error
        case "note":
            severity = .note
        default:
            severity = .warning
        }

        // Extract suggested fix
        let suggestedFix: SuggestedFix?
        if let solution = raw.solutions.first {
            let replacement = solution.replacements.first?.text ?? ""
            suggestedFix = SuggestedFix(
                description: solution.summary,
                replacement: replacement
            )
        } else {
            suggestedFix = nil
        }

        // Generate rule ID from message
        let ruleId = generateRuleId(from: raw.summary)

        return MappedDiagnostic(
            file: filePath ?? matchedFile?.url.path,
            line: matchedLine,
            column: column,
            endColumn: endColumn,
            severity: severity,
            message: raw.summary,
            content: content,
            ruleId: ruleId,
            suggestedFix: suggestedFix
        )
    }

    /// Try to parse diagnostics from text output format
    /// Format: "warning: message\n   --> file.md:line:col-line:col"
    private func parseAlternativeFormat(json: String, catalog: URL) throws -> [MappedDiagnostic] {
        var diagnostics: [MappedDiagnostic] = []

        // Pattern to match docc text output:
        // warning: 'Symbol' doesn't exist at '/Path'
        //    --> filename.md:303:5-303:11
        let lines = json.components(separatedBy: .newlines)

        var currentSeverity: DiagnosticSeverity?
        var currentMessage: String?
        var suggestion: String?

        for (index, line) in lines.enumerated() {
            // Check for severity line
            if line.hasPrefix("warning:") {
                currentSeverity = .warning
                currentMessage = String(line.dropFirst("warning:".count)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("error:") {
                currentSeverity = .error
                currentMessage = String(line.dropFirst("error:".count)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("note:") {
                currentSeverity = .note
                currentMessage = String(line.dropFirst("note:".count)).trimmingCharacters(in: .whitespaces)
            }
            // Check for location line: "   --> filename.md:line:col-line:col"
            else if line.contains("-->") {
                if let severity = currentSeverity, let message = currentMessage {
                    // Parse the location
                    let locationPart = line.replacingOccurrences(of: "-->", with: "").trimmingCharacters(in: .whitespaces)

                    // Parse "filename.md:line:col-line:col" or "filename.md:line:col"
                    let parsed = parseLocation(locationPart, catalogPath: catalog.path)

                    // Look for suggestion in next lines
                    var suggestedFix: SuggestedFix? = nil
                    for nextIndex in (index + 1)..<min(index + 5, lines.count) {
                        let nextLine = lines[nextIndex]
                        if nextLine.contains("╰─suggestion:") || nextLine.contains("suggestion:") {
                            let suggestionText = nextLine
                                .replacingOccurrences(of: "╰─suggestion:", with: "")
                                .replacingOccurrences(of: "suggestion:", with: "")
                                .trimmingCharacters(in: .whitespaces)
                            suggestedFix = SuggestedFix(description: suggestionText, replacement: "")
                            break
                        }
                    }

                    // Get content from the file if we have a valid location
                    var content: String? = nil
                    if let filePath = parsed.file, parsed.line > 0 {
                        let fullPath = filePath.hasPrefix("/") ? filePath : "\(catalog.path)/\(filePath)"
                        if let fileContent = try? String(contentsOfFile: fullPath, encoding: .utf8) {
                            let fileLines = fileContent.components(separatedBy: .newlines)
                            if parsed.line <= fileLines.count {
                                content = fileLines[parsed.line - 1]
                            }
                        }
                    }

                    diagnostics.append(MappedDiagnostic(
                        file: parsed.file,
                        line: parsed.line,
                        column: parsed.column,
                        endColumn: parsed.endColumn,
                        severity: severity,
                        message: message,
                        content: content,
                        ruleId: generateRuleId(from: message),
                        suggestedFix: suggestedFix
                    ))

                    currentSeverity = nil
                    currentMessage = nil
                }
            }
        }

        return diagnostics
    }

    /// Parse a location string like "filename.md:303:5-303:11"
    private func parseLocation(_ location: String, catalogPath: String) -> (file: String?, line: Int, column: Int, endColumn: Int) {
        // Format: "filename.md:line:col-line:col" or "filename.md:line:col"
        let parts = location.components(separatedBy: ":")

        guard parts.count >= 2 else {
            return (nil, 0, 0, 0)
        }

        let file = parts[0]
        let line = Int(parts[1]) ?? 0

        var column = 0
        var endColumn = 0

        if parts.count >= 3 {
            // Handle "5-303:11" format
            let colPart = parts[2]
            if colPart.contains("-") {
                let colParts = colPart.components(separatedBy: "-")
                column = Int(colParts[0]) ?? 0
                // endColumn might be in parts[3] or after the dash
                if parts.count >= 4 {
                    endColumn = Int(parts[3]) ?? column
                } else if colParts.count >= 2 {
                    endColumn = Int(colParts[1]) ?? column
                }
            } else {
                column = Int(colPart) ?? 0
                endColumn = column
            }
        }

        return (file, line, column, endColumn)
    }

    /// Generate a rule ID from a diagnostic message
    private func generateRuleId(from message: String) -> String {
        // Convert common messages to rule IDs
        let lowercased = message.lowercased()

        if lowercased.contains("only links are allowed") {
            return "task-group-links-only"
        } else if lowercased.contains("extraneous content") {
            return "extraneous-content"
        } else if lowercased.contains("can't resolve") || lowercased.contains("cannot resolve") {
            return "unresolved-reference"
        } else if lowercased.contains("article not found") {
            return "missing-article"
        } else if lowercased.contains("symbol not found") {
            return "missing-symbol"
        }

        // Default: kebab-case first few words
        let words = message.components(separatedBy: .whitespaces)
            .prefix(4)
            .map { $0.lowercased().filter { $0.isLetter || $0.isNumber } }
            .filter { !$0.isEmpty }

        return words.joined(separator: "-")
    }
}

/// Represents a file within a DocC catalog for source mapping
private struct CatalogFile {
    let url: URL
    let lineCount: Int
    let lines: [String]
    let lineLengths: [Int]
}
