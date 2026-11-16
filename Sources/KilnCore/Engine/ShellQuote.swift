import Foundation

public enum ShellQuote {
    private static let safe = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_./-")

    /// Safe to paste into a POSIX shell: anything outside a small safe set is single-quoted, with embedded quotes escaped.
    /// Control characters (ESC, CR, ^U, newline...) can act on the terminal itself when pasted, for example by ending a
    /// bracketed paste early. So a name containing any is written with them spelled out, as $'...' with \xHH escapes.
    public static func quote(_ s: String) -> String {
        if !s.isEmpty, s.allSatisfy(safe.contains) { return s }
        guard s.unicodeScalars.contains(where: isControl) else { return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        var out = "$'"
        for u in s.unicodeScalars {
            switch u {
            case "'": out += "\\'"
            case "\\": out += "\\\\"
            default: out += isControl(u) ? String(format: "\\x%02x", u.value) : String(u)
            }
        }
        return out + "'"
    }

    private static func isControl(_ u: Unicode.Scalar) -> Bool { u.value < 0x20 || u.value == 0x7F }

    /// One line, so pasting never runs a path as its own command.
    public static func line(_ paths: [String]) -> String { paths.map(quote).joined(separator: " ") }
}
