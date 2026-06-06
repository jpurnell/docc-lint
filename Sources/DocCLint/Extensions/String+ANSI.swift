import Foundation

/// ANSI color codes for terminal output.
public enum ANSIColor: String {
    /// The black ANSI color code.
    case black = "\u{001B}[30m" // LIVE: public API
    /// The red ANSI color code.
    case red = "\u{001B}[31m" // LIVE: public API
    /// The green ANSI color code.
    case green = "\u{001B}[32m" // LIVE: public API
    /// The yellow ANSI color code.
    case yellow = "\u{001B}[33m" // LIVE: public API
    /// The blue ANSI color code.
    case blue = "\u{001B}[34m" // LIVE: public API
    /// The magenta ANSI color code.
    case magenta = "\u{001B}[35m" // LIVE: public API
    /// The cyan ANSI color code.
    case cyan = "\u{001B}[36m" // LIVE: public API
    /// The white ANSI color code.
    case white = "\u{001B}[37m" // LIVE: public API

    /// The bright black ANSI color code.
    case brightBlack = "\u{001B}[90m" // LIVE: public API
    /// The bright red ANSI color code.
    case brightRed = "\u{001B}[91m" // LIVE: public API
    /// The bright green ANSI color code.
    case brightGreen = "\u{001B}[92m" // LIVE: public API
    /// The bright yellow ANSI color code.
    case brightYellow = "\u{001B}[93m" // LIVE: public API
    /// The bright blue ANSI color code.
    case brightBlue = "\u{001B}[94m" // LIVE: public API
    /// The bright magenta ANSI color code.
    case brightMagenta = "\u{001B}[95m" // LIVE: public API
    /// The bright cyan ANSI color code.
    case brightCyan = "\u{001B}[96m" // LIVE: public API
    /// The bright white ANSI color code.
    case brightWhite = "\u{001B}[97m" // LIVE: public API

    /// The ANSI reset escape sequence.
    public static let reset = "\u{001B}[0m" // LIVE: public API
    /// The ANSI bold escape sequence.
    public static let bold = "\u{001B}[1m" // LIVE: public API
    /// The ANSI dim escape sequence.
    public static let dim = "\u{001B}[2m" // LIVE: public API
    /// The ANSI italic escape sequence.
    public static let italic = "\u{001B}[3m" // LIVE: public API
    /// The ANSI underline escape sequence.
    public static let underline = "\u{001B}[4m" // LIVE: public API
}

extension String {
    /// Applies the given ANSI color to this string.
    public func colored(_ color: ANSIColor) -> String { // LIVE: public API
        "\(color.rawValue)\(self)\(ANSIColor.reset)"
    }

    /// Returns a bold-styled version of this string.
    public var bold: String { // LIVE: public API
        "\(ANSIColor.bold)\(self)\(ANSIColor.reset)"
    }

    /// Returns a dim-styled version of this string.
    public var dim: String { // LIVE: public API
        "\(ANSIColor.dim)\(self)\(ANSIColor.reset)"
    }

    /// Returns an italic-styled version of this string.
    public var italic: String { // LIVE: public API
        "\(ANSIColor.italic)\(self)\(ANSIColor.reset)"
    }

    /// Returns an underlined version of this string.
    public var underlined: String { // LIVE: public API
        "\(ANSIColor.underline)\(self)\(ANSIColor.reset)"
    }
}
