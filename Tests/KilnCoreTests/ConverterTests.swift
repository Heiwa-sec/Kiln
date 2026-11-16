import Testing
import Foundation
import ImageIO
import AVFoundation
import PDFKit
@testable import KilnCore

@Suite struct ImageTests {
    @Test(arguments: [Format.jpg, .tiff, .bmp, .gif, .heic, .pdf])
    func pngTo(_ out: Format) async throws {
        let s = try Scratch(); defer { s.remove() }
        guard Registry.standard().converter(for: ConversionKey(.png, out)) != nil else { print("skipped (not on this macOS):", out); return }
        let r = try await runJob(try s.png(w: 40, h: 30), .png, out)
        if out == .pdf {
            #expect(PDFDocument(url: r[0])?.pageCount == 1)
        } else {
            let src = CGImageSourceCreateWithURL(r[0] as CFURL, nil)!
            let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
            #expect(img.width == 40 && img.height == 30)
        }
    }
    @Test func corruptImage() async throws {
        let s = try Scratch(); defer { s.remove() }
        let e = await kilnError { _ = try await runJob(try s.text("bad.png", "not an image"), .png, .jpg) }
        #expect(e == .corruptInput("bad.png"))
    }
    @Test func reportsWhichImageTargetsExistHere() {
        let r = Registry.standard()
        for f in [Format.webp, .avif, .heic] { print("png ->", f, r.converter(for: ConversionKey(.png, f)) != nil ? "native" : "unsupported") }
    }
}

@Suite struct PdfTests {
    @Test func pagesAtThreeHundredDPI() async throws {
        let s = try Scratch(); defer { s.remove() }
        let r = try await runJob(try s.pdf(), .pdf, .png)
        #expect(r.count == 1 && r[0].lastPathComponent == "doc pages")
        let files = try FileManager.default.contentsOfDirectory(atPath: r[0].path).sorted()
        #expect(files == ["page-001.png", "page-002.png"])
        let img = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(r[0].appendingPathComponent(files[0]) as CFURL, nil)!, 0, nil)!
        #expect(img.width == 833 && img.height == 417) // 200x100 pt at 300 DPI
    }
    @Test func textAndMarkdown() async throws {
        let s = try Scratch(); defer { s.remove() }
        let src = try s.pdf()
        let t = try String(contentsOf: try await runJob(src, .pdf, .txt)[0], encoding: .utf8)
        #expect(t.contains("Hello Kiln page 1") && t.contains("page 2"))
        let m = try String(contentsOf: try await runJob(src, .pdf, .md)[0], encoding: .utf8)
        #expect(m.contains("---"))
    }
    @Test func encryptedPDF() async throws {
        let s = try Scratch(); defer { s.remove() }
        let e = await kilnError { _ = try await runJob(try s.lockedPDF(), .pdf, .txt) }
        #expect(e == .encryptedPDF("locked.pdf"))
    }
    @Test func corruptPDF() async throws {
        let s = try Scratch(); defer { s.remove() }
        let e = await kilnError { _ = try await runJob(try s.text("bad.pdf", "nope"), .pdf, .txt) }
        #expect(e == .corruptInput("bad.pdf"))
    }
}

@Suite struct TextFormatTests {
    @Test func subtitleRoundTrip() async throws {
        let s = try Scratch(); defer { s.remove() }
        let srt = "1\n00:00:01,000 --> 00:00:02,500\nHello\n\n2\n00:00:03,000 --> 00:00:04,000\nWorld\nline two\n"
        let vtt = try await runJob(try s.text("a.srt", srt), .srt, .vtt)[0]
        let v = try String(contentsOf: vtt, encoding: .utf8)
        #expect(v.hasPrefix("WEBVTT") && v.contains("00:00:01.000 --> 00:00:02.500"))
        let back = try await runJob(vtt, .vtt, .srt, policy: .init(location: .folder(s.dir.appendingPathComponent("b", isDirectory: true).createdDir())))[0]
        #expect(try String(contentsOf: back, encoding: .utf8) == srt)
        let txt = try String(contentsOf: try await runJob(s.file("a.srt"), .srt, .txt)[0], encoding: .utf8)
        #expect(txt == "Hello\n\nWorld\nline two\n")
    }
    @Test func csvToTsvKeepsQuotedFields() async throws {
        let s = try Scratch(); defer { s.remove() }
        let r = try await runJob(try s.text("t.csv", "a,b\n\"x,y\",\"say \"\"hi\"\"\"\n"), .csv, .tsv)[0]
        #expect(try String(contentsOf: r, encoding: .utf8) == "a\tb\nx,y\tsay \"hi\"\n")
    }
    @Test func documentChain() async throws {
        let s = try Scratch(); defer { s.remove() }
        var cur = try s.text("note.txt", "Kiln document test")
        var fmt = Format.txt
        for next in [Format.rtf, .docx, .html, .rtfd, .txt] {
            guard Registry.standard().converter(for: ConversionKey(fmt, next)) != nil else { Issue.record("no pair \(fmt)->\(next)"); return }
            cur = try await runJob(cur, fmt, next)[0]; fmt = next
        }
        #expect(try String(contentsOf: cur, encoding: .utf8).contains("Kiln document test"))
    }
    @Test func markdownBecomesText() async throws {
        let s = try Scratch(); defer { s.remove() }
        let r = try await runJob(try s.text("m.md", "Some **bold** text"), .md, .txt)[0]
        #expect(try String(contentsOf: r, encoding: .utf8).contains("Some bold text"))
    }
}

@Suite struct AudioTests {
    @Test(arguments: [Format.m4a, .aiff, .caf, .flac])
    func wavTo(_ out: Format) async throws {
        let s = try Scratch(); defer { s.remove() }
        let r = try await runJob(try s.wav(seconds: 0.5), .wav, out)[0]
        let f = try AVAudioFile(forReading: r)
        #expect(abs(Double(f.length) / f.fileFormat.sampleRate - 0.5) < 0.1)
    }
    @Test func corruptAudio() async throws {
        let s = try Scratch(); defer { s.remove() }
        let e = await kilnError { _ = try await runJob(try s.text("bad.wav", "nope"), .wav, .m4a) }
        #expect(e == .corruptInput("bad.wav"))
    }
}

extension URL {
    func createdDir() -> URL { try? FileManager.default.createDirectory(at: self, withIntermediateDirectories: true); return self }
}

import Network

final class HitCounter: @unchecked Sendable {
    private let lock = NSLock(); private var n = 0
    func hit() { lock.lock(); n += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return n }
}

@Suite struct HTMLPrivacyTests {
    /// A local listener stands in for a remote server named by an untrusted HTML file.
    func listen(_ hits: HitCounter) async throws -> (NWListener, UInt16) {
        let l = try NWListener(using: .tcp, on: .any)
        l.newConnectionHandler = { c in hits.hit(); c.cancel() }
        l.start(queue: .global())
        for _ in 0..<50 { if let p = l.port?.rawValue { return (l, p) }; try await Task.sleep(nanoseconds: 50_000_000) }
        throw KilnError.io("listener did not start")
    }
    func page(_ port: UInt16) -> String {
        let u = "http://127.0.0.1:\(port)"
        return "<html><head><link rel=stylesheet href=\"\(u)/a.css\"><style>p{background:url(\(u)/s.png)}</style></head><body><p>Hi there</p><img src=\"\(u)/x.png\"><iframe src=\"\(u)/f\"></iframe><div style=\"background:url(\(u)/b.png)\">Tail</div></body></html>"
    }

    /// Known sanitizer bypass shapes: slash and newline separators, '>' inside an attribute, uppercase, SVG, CSS, meta refresh, base.
    static func tricks(_ u: String) -> [String] { [
        "<img/src=\"\(u)/1\">", "<IMG\nSRC='\(u)/2'>", "<a title=\"><img src=\(u)/3>\">x</a>", "<im<img src=\(u)/4>g src=\(u)/5>",
        "<svg><image href=\"\(u)/6\"/></svg>", "<style>@import url(\(u)/7);</style>", "<p style=\"background:url(\(u)/8)\">t</p>",
        "<meta http-equiv=refresh content=\"0;url=\(u)/9\">", "<base href=\"\(u)/\"><body background=\(u)/10>", "<video poster=\(u)/11></video>",
        "<table background=\(u)/12><tr><td>c</td></tr></table>", "<scr<script>ipt src=\(u)/13></script>", "<!-- > <img src=\(u)/14> -->",
    ] }

    @Test func sanitizedOutputHasOnlyAttributeFreeTags() {
        let out = String(decoding: DocumentConverter.sanitizedHTML(Data(Self.tricks("http://127.0.0.1:9").joined(separator: "\n").utf8)), as: UTF8.self)
        // URLs may survive as inert text fragments; what must not survive is any tag carrying attributes.
        let tags = out.matches(of: /<[^>]*>/).map { String($0.output) }
        #expect(tags.allSatisfy { $0.wholeMatch(of: /<\/?[a-z0-9]+>/) != nil }, "found a tag with attributes: \(tags)")
    }

    @Test func htmlTricksMakeNoNetworkRequests() async throws {
        let s = try Scratch(); defer { s.remove() }
        let hits = HitCounter(); let (l, port) = try await listen(hits); defer { l.cancel() }
        let html = "<html><body><p>Hi there</p>" + Self.tricks("http://127.0.0.1:\(port)").joined() + "</body></html>"
        let txt = try await runJob(try s.text("t.html", html), .html, .txt)[0]
        try await Task.sleep(nanoseconds: 1_500_000_000)
        #expect(hits.count == 0)
        #expect(try String(contentsOf: txt, encoding: .utf8).contains("Hi there"))
    }

    @Test func htmlInputMakesNoNetworkRequests() async throws {
        let s = try Scratch(); defer { s.remove() }
        let hits = HitCounter(); let (l, port) = try await listen(hits); defer { l.cancel() }
        let txt = try await runJob(try s.text("p.html", page(port)), .html, .txt)[0]
        try await Task.sleep(nanoseconds: 1_500_000_000)
        #expect(hits.count == 0)
        #expect(try String(contentsOf: txt, encoding: .utf8).contains("Hi there"))
    }

    /// Evidence the test has teeth: the same page through the raw importer. Printed, not asserted, since WebKit behavior varies.
    @Test @MainActor func probeUnsanitizedImport() async throws {
        let hits = HitCounter(); let (l, port) = try await listen(hits); defer { l.cancel() }
        _ = try NSAttributedString(data: Data(page(port).utf8), options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil)
        try await Task.sleep(nanoseconds: 1_500_000_000)
        print("unsanitized HTML import connections:", hits.count)
    }
}
