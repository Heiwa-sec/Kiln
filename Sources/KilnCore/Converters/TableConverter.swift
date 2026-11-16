import Foundation

struct TableConverter: Converter {
    let pairs = [ConversionKey(.csv, .tsv), ConversionKey(.tsv, .csv)]

    func convert(input: URL, key: ConversionKey, output: Output, progress: @Sendable (Double) -> Void) async throws {
        try Limits.checkText(input)
        guard let raw = try? String(contentsOf: input, encoding: .utf8) else { throw KilnError.corruptInput(input.lastPathComponent) }
        let rows = Self.parse(raw, delimiter: key.input == .csv ? "," : "\t")
        let out = Self.write(rows, delimiter: key.output == .csv ? "," : "\t")
        try out.write(to: output.url(ext: key.output.ext), atomically: true, encoding: .utf8)
    }

    /// RFC 4180 style: quotes, doubled quotes, newlines inside quotes.
    static func parse(_ s: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
        let chars = Array(s), n = chars.count
        var i = 0
        while i < n {
            let c = chars[i]
            if quoted {
                if c == "\"" { if i + 1 < n, chars[i + 1] == "\"" { field.append("\""); i += 1 } else { quoted = false } }
                else { field.append(c) }
            } else if c == "\"" { quoted = true }
            else if c == delimiter { row.append(field); field = "" }
            else if c == "\n" || c == "\r\n" { row.append(field); rows.append(row); row = []; field = "" } // "\r\n" is one Character in Swift
            else { field.append(c) }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    static func write(_ rows: [[String]], delimiter: Character) -> String {
        func esc(_ f: String) -> String {
            f.contains(delimiter) || f.contains("\n") || (f.contains("\"") && (delimiter == "," || f.hasPrefix("\""))) ? "\"" + f.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : f
        }
        return rows.map { $0.map(esc).joined(separator: String(delimiter)) }.joined(separator: "\n") + "\n"
    }
}
