import Foundation

public enum ShellQuote {
    private static let safe = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_./-")

    /// Safe to paste into a POSIX shell: anything outside a small safe set is single-quoted, with embedded quotes escaped.
    /// Control characters (ESC, CR, ^U, newline...) can act on the terminal itself when pasted, for example by ending a
    /// bracketed paste early. So a name containing any is written with them spelled out, as $'...' with \xHH escapes.
    public static func quote(_ s: String) -> String {
        if !s.isEmpty, s.allSatisfy(safe.contains) { return s }
        guard s.unicodeScalars.contains(where: isControl) else { return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        // Quote and backslash are spelled as hex too, so the only single quotes in the result are the two delimiters:
        // a shell that does not understand $'...' still sees one inert single-quoted string, never a broken-out command.
        var out = "$'"
        for u in s.unicodeScalars {
            switch u.value {
            case 0x27, 0x5C, 0..<0x20, 0x7F: out += String(format: "\\x%02x", u.value)
            case 0x80...0x9F: out += String(format: "\\xc2\\x%02x", u.value)   // C1 controls, as their UTF-8 bytes
            default: out += String(u)
            }
        }
        return out + "'"
    }

    /// C0, DEL and C1 controls: a terminal may act on any of them.
    private static func isControl(_ u: Unicode.Scalar) -> Bool { u.value < 0x20 || (0x7F...0x9F).contains(u.value) }

    /// One line, so pasting never runs a path as its own command.
    public static func line(_ paths: [String]) -> String { paths.map(quote).joined(separator: " ") }
}
