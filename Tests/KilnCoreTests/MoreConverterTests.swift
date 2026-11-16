import Testing
import Foundation
import AVFoundation
import ImageIO
import PDFKit
@testable import KilnCore

@Suite struct VideoTests {
    @Test(arguments: [Format.mp4, .m4a, .gif])
    func movTo(_ out: Format) async throws {
        let s = try Scratch(); defer { s.remove() }
        let r = try await runJob(try await s.movie(), .mov, out)[0]
        if out == .gif {
            #expect(CGImageSourceGetCount(CGImageSourceCreateWithURL(r as CFURL, nil)!) == 10)
        } else {
            let a = AVURLAsset(url: r)
            #expect(abs(try await a.load(.duration).seconds - 1) < 0.3)
            #expect(try await a.loadTracks(withMediaType: out == .m4a ? .audio : .video).count == 1)
        }
    }
    @Test func mp4BackToMov() async throws {
        let s = try Scratch(); defer { s.remove() }
        let mp4 = try await runJob(try await s.movie(), .mov, .mp4)[0]
        let mov = try await runJob(mp4, .mp4, .mov)[0]
        #expect(try await AVURLAsset(url: mov).loadTracks(withMediaType: .video).count == 1)
    }
    @Test func extractingAudioFromSilentVideoSaysSo() async throws {
        let s = try Scratch(); defer { s.remove() }
        let e = await kilnError { _ = try await runJob(try await s.movie("mute.mov", audio: false), .mov, .m4a) }
        if case .io(let m)? = e { #expect(m.contains("no audio")) } else { Issue.record("got \(String(describing: e))") }
    }
    @Test func corruptVideo() async throws {
        let s = try Scratch(); defer { s.remove() }
        let e = await kilnError { _ = try await runJob(try s.text("bad.mp4", "nope"), .mp4, .mov) }
        #expect(e == .corruptInput("bad.mp4"))
    }
}

@Suite struct ArchiveTests {
    func folder(_ s: Scratch) throws -> URL {
        let f = s.file("stuff"); try FileManager.default.createDirectory(at: f.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try "one".write(to: f.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "two".write(to: f.appendingPathComponent("sub/b.txt"), atomically: true, encoding: .utf8)
        return f
    }
    @Test(arguments: [Format.zip, .tar]) func folderRoundTrip(_ fmt: Format) async throws {
        let s = try Scratch(); defer { s.remove() }
        let archive = try await runJob(try folder(s), .folder, fmt)[0]
        #expect(archive.lastPathComponent == "stuff.\(fmt.ext)")
        let out = try await runJob(archive, fmt, .folder)[0]
        #expect(out.lastPathComponent == "stuff 2")   // "stuff" already exists, so the suffix rule applies
        #expect(try String(contentsOf: out.appendingPathComponent("stuff/sub/b.txt"), encoding: .utf8) == "two")
    }
    @Test func gzipSingleFile() async throws {
        let s = try Scratch(); defer { s.remove() }
        let gz = try await runJob(try s.text("note.txt", "hello gzip"), .txt, .gz)[0]
        let out = try await runJob(gz, .gz, .folder)[0]
        #expect(try String(contentsOf: out.appendingPathComponent("note.txt"), encoding: .utf8) == "hello gzip")
    }
    /// Names that tar or zip would read as options or "@archive" members must just be file names.
    @Test(arguments: ["-x.txt", "@list.txt", "-r"]) func oddFileNamesAreJustNames(_ name: String) async throws {
        let s = try Scratch(); defer { s.remove() }
        let f = try s.text(name, "payload")
        for fmt in [Format.zip, .tar] {
            let a = try await runJob(f, Format(url: f) ?? .txt, fmt)[0]
            let listing = try String(decoding: await Run.exec("/usr/bin/tar", ["-tf", a.path]).utf8, as: UTF8.self)
            #expect(listing.contains(name), "\(fmt): \(listing)")
        }
    }
    @Test func gzipOfAFolderIsUnsupported() async throws {
        let s = try Scratch(); defer { s.remove() }
        let e = await kilnError { _ = try await runJob(try folder(s), .folder, .gz) }
        #expect(e == .unsupportedPair(ConversionKey(.folder, .gz)))
    }
    @Test func zipSlipIsRefusedAndNothingEscapes() async throws {
        let s = try Scratch(); defer { s.remove() }
        let evil = try s.rawZip("evil.zip", entries: [("fine.txt", "ok"), ("../escaped.txt", "bad")])
        let e = await kilnError { _ = try await runJob(evil, .zip, .folder) }
        #expect(e == .unsafeInput("evil.zip"))
        #expect(!FileManager.default.fileExists(atPath: s.dir.deletingLastPathComponent().appendingPathComponent("escaped.txt").path))
        #expect(!FileManager.default.fileExists(atPath: s.file("escaped.txt").path))
        #expect(!FileManager.default.fileExists(atPath: s.file("evil").path))   // no half-extracted folder left
    }
    @Test func absolutePathEntriesAreRefused() {
        #expect(ArchiveExtractor.escapes("/etc/passwd")); #expect(ArchiveExtractor.escapes("a/../../b")); #expect(!ArchiveExtractor.escapes("a/b..c/d"))
    }
    @Test func corruptArchive() async throws {
        let s = try Scratch(); defer { s.remove() }
        let e = await kilnError { _ = try await runJob(try s.text("bad.zip", "not a zip"), .zip, .folder) }
        #expect(e == .corruptInput("bad.zip"))
    }
    @Test func rarIsUnsupported() { #expect(Registry.standard().targets(for: .rar).first?.support == .unsupported) }
}

@Suite struct FFmpegTests {
    /// A stand-in script: copies its input (the arg after -i) to its last argument, and records its arguments.
    func fake(_ s: Scratch) throws -> URL {
        let url = s.file("ffmpeg")
        try "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$0.args\"\nwhile [ \"$1\" != \"-i\" ]; do shift; done\nin=\"$2\"\nfor last; do :; done\ncp \"$in\" \"$last\"\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
    @Test func locatesOnlyExecutables() throws {
        let s = try Scratch(); defer { s.remove() }
        #expect(FFmpeg.locate(environment: ["PATH": s.dir.path]) == nil)
        let bin = try fake(s)
        #expect(FFmpeg.locate(environment: ["PATH": s.dir.path])?.path == bin.path)
    }
    @Test func withoutFFmpegTheExtraFormatsAreMarkedAndRefused() async throws {
        let s = try Scratch(); defer { s.remove() }
        let r = Registry.standard(ffmpeg: nil)
        #expect(r.targets(for: .wav).first { $0.format == .mp3 }?.support == .needsFFmpeg)
        #expect(r.targets(for: .mkv).allSatisfy { $0.support != .native || $0.format.isArchiveFile })
        let e = await kilnError { _ = try await JobRunner(registry: r).start(Job(input: try s.wav(), key: ConversionKey(.wav, .mp3))).result() }
        #expect(e == .needsFFmpeg)
    }
    @Test func withFFmpegPairsOpenUpAndNativeStillWins() async throws {
        let s = try Scratch(); defer { s.remove() }
        let bin = try fake(s)
        let r = Registry.standard(ffmpeg: bin)
        #expect(r.targets(for: .wav).first { $0.format == .mp3 }?.support == .native)
        #expect(r.converter(for: ConversionKey(.wav, .m4a)) is AudioConverter)
        let out = try await JobRunner(registry: r).start(Job(input: try s.wav(), key: ConversionKey(.wav, .mp3))).result()
        #expect(out.map(\.lastPathComponent) == ["tone.mp3"])
        let args = try String(contentsOf: s.file("ffmpeg.args"), encoding: .utf8)
        #expect(args.contains("libmp3lame") && args.contains("-nostdin"))
        // The input format is forced before -i and only local files are allowed.
        let lines = args.split(separator: "\n").map(String.init)
        #expect(lines.firstIndex(of: "-f")! < lines.firstIndex(of: "-i")! && lines[lines.firstIndex(of: "-f")! + 1] == "wav")
        #expect(lines.firstIndex(of: "-protocol_whitelist").map { lines[$0 + 1] } == "file")
    }
}

@Suite struct ToolTests {
    func run(_ id: ToolID, _ inputs: [URL]) async throws -> [URL] { try await JobRunner().start(tool: id, inputs: inputs).result() }
    func props(_ u: URL) -> [CFString: Any] { CGImageSourceCopyPropertiesAtIndex(CGImageSourceCreateWithURL(u as CFURL, nil)!, 0, nil) as! [CFString: Any] }

    @Test func stripMetadataRemovesGPSAndEXIFButKeepsPixels() async throws {
        let s = try Scratch(); defer { s.remove() }
        let src = try s.jpeg()
        #expect(props(src)[kCGImagePropertyGPSDictionary] != nil)   // the fixture really has GPS
        let out = try await run(.stripMetadata, [src])[0]
        let p = props(out)
        #expect(out.lastPathComponent == "photo clean.jpg")
        #expect(p[kCGImagePropertyGPSDictionary] == nil)
        #expect((p[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFMake] == nil)
        #expect((p[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifUserComment] == nil)
        #expect(p[kCGImagePropertyPixelWidth] as? Int == 64 && p[kCGImagePropertyPixelHeight] as? Int == 48)
    }
    @Test func compressMakesAJpegSmaller() async throws {
        let s = try Scratch(); defer { s.remove() }
        // Noise compresses badly, so quality matters.
        let n = 256, ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let px = ctx.data!.assumingMemoryBound(to: UInt8.self); var seed: UInt32 = 7
        for i in 0..<(ctx.bytesPerRow * n) { seed = seed &* 1664525 &+ 1013904223; px[i] = UInt8(truncatingIfNeeded: seed >> 24) }
        let src = s.file("noise.jpg")
        let d = CGImageDestinationCreateWithURL(src as CFURL, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(d, ctx.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary); CGImageDestinationFinalize(d)
        let out = try await run(.compressImage, [src])[0]
        let a = try FileManager.default.attributesOfItem(atPath: src.path)[.size] as! Int, b = try FileManager.default.attributesOfItem(atPath: out.path)[.size] as! Int
        #expect(b < a / 2, "\(b) vs \(a)")
    }
    @Test func resizeHalvesPixels() async throws {
        let s = try Scratch(); defer { s.remove() }
        let out = try await run(.resizeImage, [try s.png(w: 100, h: 60)])[0]
        #expect(out.lastPathComponent == "pic resized.png")
        #expect(props(out)[kCGImagePropertyPixelWidth] as? Int == 50 && props(out)[kCGImagePropertyPixelHeight] as? Int == 30)
    }
    @Test func rotateTurnsClockwise() async throws {
        let s = try Scratch(); defer { s.remove() }
        // 2x1 image: left pixel red, right pixel blue. Clockwise: it becomes 1x2 with red on top.
        let ctx = CGContext(data: nil, width: 2, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 1, y: 0, width: 1, height: 1))
        let src = s.file("rb.png")
        let d = CGImageDestinationCreateWithURL(src as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(d, ctx.makeImage()!, nil); CGImageDestinationFinalize(d)
        let out = try await run(.rotateImage, [src])[0]
        let img = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(out as CFURL, nil)!, 0, nil)!
        #expect(img.width == 1 && img.height == 2)
        let c = CGContext(data: nil, width: 1, height: 2, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.draw(img, in: CGRect(x: 0, y: 0, width: 1, height: 2))
        let p = c.data!.assumingMemoryBound(to: UInt8.self)   // memory row 0 is the top row
        #expect(p[0] == 255 && p[2] == 0, "top pixel should be red, got r=\(p[0]) b=\(p[2])")
    }
    @Test func mergeThenSplit() async throws {
        let s = try Scratch(); defer { s.remove() }
        let a = try s.pdf("a.pdf", pages: 2), b = try s.pdf("b.pdf", pages: 3)
        let merged = try await run(.mergePDF, [a, b])[0]
        #expect(merged.lastPathComponent == "a merged.pdf" && PDFDocument(url: merged)?.pageCount == 5)
        let split = try await run(.splitPDF, [merged])[0]
        #expect(try FileManager.default.contentsOfDirectory(atPath: split.path).count == 5)
        #expect(PDFDocument(url: split.appendingPathComponent("page-004.pdf"))?.pageCount == 1)
    }
    @Test func mergeNeedsTwoPDFsAndRefusesLockedOnes() async throws {
        let s = try Scratch(); defer { s.remove() }
        let a = try s.pdf("a.pdf")
        let e1 = await kilnError { _ = try await run(.mergePDF, [a]) }
        #expect(e1 != nil)
        let e2 = await kilnError { _ = try await run(.mergePDF, [a, try s.lockedPDF()]) }
        #expect(e2 == .encryptedPDF("locked.pdf"))
        #expect(!FileManager.default.fileExists(atPath: s.file("a merged.pdf").path))
    }
    @Test func videoTools() async throws {
        let s = try Scratch(); defer { s.remove() }
        let clip = try await s.movie()
        let audio = try await run(.extractAudio, [clip])[0]
        #expect(audio.lastPathComponent == "clip.m4a")
        let small = try await run(.compressVideo, [clip])[0]
        #expect(small.lastPathComponent == "clip compressed.mov" && AVURLAsset(url: small).isReadable)
    }
    @Test func toolsRefuseWrongFileTypes() async throws {
        let s = try Scratch(); defer { s.remove() }
        let e = await kilnError { _ = try await run(.compressImage, [try s.png()]) }   // PNG has no quality setting
        #expect(e != nil)
        #expect(Registry.standard().tool(.splitPDF)?.accepts([.pdf]) == true)
        #expect(Registry.standard().tool(.splitPDF)?.accepts([.png]) == false)
    }
}
