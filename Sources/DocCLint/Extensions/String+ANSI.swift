import Foundation

/// ANSI color codes for terminal output
public enum ANSIColor: String {
    case black = "\u{001B}[30m"
    case red = "\u{001B}[31m"
    case green = "\u{001B}[32m"
    case yellow = "\u{001B}[33m"
    case blue = "\u{001B}[34m"
    case magenta = "\u{001B}[35m"
    case cyan = "\u{001B}[36m"
    case white = "\u{001B}[37m"

    case brightBlack = "\u{001B}[90m"
    case brightRed = "\u{001B}[91m"
    case brightGreen = "\u{001B}[92m"
    case brightYellow = "\u{001B}[93m"
    case brightBlue = "\u{001B}[94m"
    case brightMagenta = "\u{001B}[95m"
    case brightCyan = "\u{001B}[96m"
    case brightWhite = "\u{001B}[97m"

    public static let reset = "\u{001B}[0m"
    public static let bold = "\u{001B}[1m"
    public static let dim = "\u{001B}[2m"
    public static let italic = "\u{001B}[3m"
    public static let underline = "\u{001B}[4m"
}

extension String {
    /// Apply ANSI color to the string
    public func colored(_ color: ANSIColor) -> String {
        "\(color.rawValue)\(self)\(ANSIColor.reset)"
    }

    /// Make the string bold
    public var bold: String {
        "\(ANSIColor.bold)\(self)\(ANSIColor.reset)"
    }

    /// Make the string dim
    public var dim: String {
        "\(ANSIColor.dim)\(self)\(ANSIColor.reset)"
    }

    /// Make the string italic
    public var italic: String {
        "\(ANSIColor.italic)\(self)\(ANSIColor.reset)"
    }

    /// Make the string underlined
    public var underlined: String {
        "\(ANSIColor.underline)\(self)\(ANSIColor.reset)"
    }
}
