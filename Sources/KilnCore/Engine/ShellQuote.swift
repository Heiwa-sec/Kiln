import Foundation

public enum ShellQuote {
    private static let safe = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_./-")

    /// Safe to paste into a POSIX shell: anything outside a small safe set is single-quoted, with embedded quotes escaped.
    /// Single quotes make every other character literal, newlines included.
    public static func quote(_ s: String) -> String {
        if !s.isEmpty, s.allSatisfy(safe.contains) { return s }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// One line, so pasting never runs a path as its own command.
    public static func line(_ paths: [String]) -> String { paths.map(quote).joined(separator: " ") }
}
