import Foundation

struct SubtitleConverter: Converter {
    let pairs = [ConversionKey(.srt, .vtt), ConversionKey(.vtt, .srt), ConversionKey(.srt, .txt), ConversionKey(.vtt, .txt)]

    struct Cue: Equatable { var start: String; var end: String; var text: String }

    func convert(input: URL, key: ConversionKey, output: Output, progress: @Sendable (Double) -> Void) async throws {
        try Limits.checkText(input)
        guard let raw = try? String(contentsOf: input, encoding: .utf8) else { throw KilnError.corruptInput(input.lastPathComponent) }
        let cues = Self.parse(raw)
        guard !cues.isEmpty else { throw KilnError.corruptInput(input.lastPathComponent) }
        let text: String
        switch key.output {
        case .vtt: text = "WEBVTT\n\n" + cues.map { "\($0.start.replacingOccurrences(of: ",", with: ".")) --> \($0.end.replacingOccurrences(of: ",", with: "."))\n\($0.text)" }.joined(separator: "\n\n") + "\n"
        case .srt: text = cues.enumerated().map { "\($0 + 1)\n\($1.start.replacingOccurrences(of: ".", with: ",")) --> \($1.end.replacingOccurrences(of: ".", with: ","))\n\($1.text)" }.joined(separator: "\n\n") + "\n"
        default: text = cues.map(\.text).joined(separator: "\n\n") + "\n"
        }
        try text.write(to: output.url(ext: key.output.ext), atomically: true, encoding: .utf8)
    }

    /// Reads SRT or VTT: any block holding a "start --> end" line is a cue.
    static func parse(_ raw: String) -> [Cue] {
        let blocks = raw.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
        return blocks.compactMap { block in
            let lines = block.components(separatedBy: "\n")
            guard let i = lines.firstIndex(where: { $0.contains("-->") }) else { return nil }
            let parts = lines[i].components(separatedBy: "-->").map { $0.trimmingCharacters(in: .whitespaces).components(separatedBy: " ")[0] }
            guard parts.count == 2 else { return nil }
            func full(_ t: String) -> String { t.split(separator: ":").count == 2 ? "00:" + t : t } // VTT may omit hours
            return Cue(start: full(parts[0]), end: full(parts[1]), text: lines[(i + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
