import Foundation

/// Represents a location in a source file
public struct SourceLocation: Codable, Sendable {
    /// Path to the source file
    public let filePath: String

    /// Line number (1-indexed)
    public let line: Int

    /// Column number (1-indexed)
    public let column: Int

    /// The content of the line at this location
    public let lineContent: String?

    public init(filePath: String, line: Int, column: Int, lineContent: String? = nil) {
        self.filePath = filePath
        self.line = line
        self.column = column
        self.lineContent = lineContent
    }

    /// Returns a formatted string representation like "file.swift:42:10"
    public var formatted: String {
        "\(filePath):\(line):\(column)"
    }
}
