import AppKit

struct DocumentConverter: Converter {
    static let inputs: [Format] = [.txt, .md, .rtf, .rtfd, .html, .docx]
    static let outputs: [Format] = [.txt, .rtf, .rtfd, .html, .docx]
    let pairs = inputs.flatMap { i in outputs.filter { $0 != i }.map { ConversionKey(i, $0) } }

    func convert(input: URL, key: ConversionKey, output: Output, progress: @Sendable (Double) -> Void) async throws {
        // NSAttributedString isn't Sendable and its HTML import runs WebKit, so read and write on the main actor.
        let name = input.lastPathComponent
        if key.input == .rtfd { if Self.hasSymlink(input) { throw KilnError.unsafeInput(name) } } else { try Limits.checkText(input) }
        let out = try output.url(ext: key.output.ext)
        try await MainActor.run {
            let text: NSAttributedString
            do { text = try Self.read(input, as: key.input) } catch { throw KilnError.corruptInput(name) }
            try Self.write(text, to: out, as: key.output)
        }
    }

    /// An RTFD package is a folder. A link inside it could pull a file from elsewhere on the disk into the result.
    static func hasSymlink(_ folder: URL) -> Bool {
        guard let e = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey]) else { return false }
        return e.contains { ((try? ($0 as? URL)?.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? false) == true }
    }

    @MainActor static func read(_ url: URL, as f: Format) throws -> NSAttributedString {
        switch f {
        case .txt: return NSAttributedString(string: try String(contentsOf: url, encoding: .utf8))
        case .md:
            let md = try String(contentsOf: url, encoding: .utf8)
            return NSAttributedString(try AttributedString(markdown: md, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
        case .html:
            let clean = sanitizedHTML(try Data(contentsOf: url))
            return try NSAttributedString(data: clean, options: [.documentType: NSAttributedString.DocumentType.html,
                                          .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil)
        default:
            return try NSAttributedString(url: url, options: [.documentType: f.documentType], documentAttributes: nil)
        }
    }

    @MainActor static func write(_ s: NSAttributedString, to url: URL, as f: Format) throws {
        let range = NSRange(location: 0, length: s.length)
        switch f {
        case .txt: try s.string.write(to: url, atomically: true, encoding: .utf8)
        case .rtfd: try s.fileWrapper(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
            .write(to: url, options: .atomic, originalContentsURL: nil)
        default:
            try s.data(from: range, documentAttributes: [.documentType: f.documentType]).write(to: url, options: .atomic)
        }
    }

    private static let allowedTags: Set<String> = ["html", "body", "p", "br", "div", "span", "b", "i", "u", "s", "strong", "em", "small",
        "sub", "sup", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "dl", "dt", "dd", "table", "thead", "tbody", "tfoot", "tr",
        "td", "th", "caption", "blockquote", "pre", "code", "hr", "center"]

    /// The HTML importer runs WebKit and could fetch remote images, stylesheets or frames named in an untrusted file.
    /// So rebuild the document from an allowlist: elements that carry no text are dropped with their content, every other
    /// tag is either dropped or rewritten with no attributes at all, and stray angle brackets in text are escaped.
    /// With no attribute and no style left, nothing can name a URL. Cost: images, styling and link targets are lost.
    nonisolated static func sanitizedHTML(_ data: Data) -> Data {
        var s = String(decoding: data, as: UTF8.self)
        // Fail closed: if a pattern ever failed to compile, return nothing rather than unsanitized HTML.
        guard let dropWhole = try? NSRegularExpression(pattern: #"<(script|style|iframe|object|embed|applet|svg|math|template|noscript|head)\b.*?</\1\s*>"#,
                                                       options: [.dotMatchesLineSeparators, .caseInsensitive]),
              let token = try? NSRegularExpression(pattern: #"<[^>]*>"#) else { return Data() }
        s = dropWhole.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        func text(_ t: Substring) -> String { t.replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") }
        var out = "", last = s.startIndex
        for m in token.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            guard let r = Range(m.range, in: s) else { continue }
            out += text(s[last..<r.lowerBound])
            var body = s[r].dropFirst()
            let closing = body.first == "/"; if closing { body = body.dropFirst() }
            let name = String(body.prefix { $0.isASCII && ($0.isLetter || $0.isNumber) }).lowercased()
            if allowedTags.contains(name) { out += closing ? "</\(name)>" : "<\(name)>" }
            last = r.upperBound
        }
        out += text(s[last...])
        return Data(out.utf8)
    }
}

private extension Format {
    var documentType: NSAttributedString.DocumentType {
        switch self { case .rtf: .rtf; case .rtfd: .rtfd; case .html: .html; case .docx: .officeOpenXML; default: .plain }
    }
}
