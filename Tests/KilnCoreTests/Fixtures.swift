import Foundation
import AVFoundation
import CoreText
import PDFKit
import ImageIO
import UniformTypeIdentifiers
@testable import KilnCore

/// A scratch folder inside the project (never outside it), removed when the test ends.
struct Scratch {
    let dir: URL
    init() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        dir = root.appendingPathComponent(".scratch/tests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    func file(_ name: String) -> URL { dir.appendingPathComponent(name) }
    func remove() { try? FileManager.default.removeItem(at: dir) }

    func png(_ name: String = "pic.png", w: Int = 40, h: Int = 30) throws -> URL {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.8, green: 0.3, blue: 0.1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let url = file(name)
        let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(d, ctx.makeImage()!, nil); CGImageDestinationFinalize(d)
        return url
    }

    func pdf(_ name: String = "doc.pdf", pages: Int = 2) throws -> URL {
        let url = file(name)
        var box = CGRect(x: 0, y: 0, width: 200, height: 100)
        let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
        for i in 1...pages {
            ctx.beginPDFPage(nil)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Hello Kiln page \(i)"))
            ctx.textPosition = CGPoint(x: 10, y: 50); CTLineDraw(line, ctx)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return url
    }

    func lockedPDF() throws -> URL {
        let plain = try pdf("plain.pdf")
        let url = file("locked.pdf")
        _ = PDFDocument(url: plain)!.write(to: url, withOptions: [.userPasswordOption: "pw", .ownerPasswordOption: "pw"])
        return url
    }

    func wav(_ name: String = "tone.wav", seconds: Double = 0.5) throws -> URL {
        let url = file(name)
        let f = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100,
                                AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false])
        let n = AVAudioFrameCount(44100 * seconds)
        let b = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: n)!
        b.frameLength = n
        for i in 0..<Int(n) { b.floatChannelData![0][i] = Float(sin(Double(i) * 2 * .pi * 440 / 44100)) * 0.5 }
        try f.write(from: b)
        return url
    }

    func text(_ name: String, _ s: String) throws -> URL {
        let url = file(name); try s.write(to: url, atomically: true, encoding: .utf8); return url
    }
}

func runJob(_ input: URL, _ i: Format, _ o: Format, policy: OutputPolicy = .init()) async throws -> [URL] {
    try await JobRunner().start(Job(input: input, key: ConversionKey(i, o), policy: policy)).result()
}

func kilnError(_ body: () async throws -> Void) async -> KilnError? {
    do { try await body(); return nil } catch { return error as? KilnError }
}

extension Scratch {
    /// Tiny H.264 clip (64x64, 10 fps) with an optional 440 Hz tone, built from generated data only.
    func movie(_ name: String = "clip.mov", seconds: Int = 1, audio: Bool = true) async throws -> URL {
        let videoOnly = file(audio ? "v-\(name)" : name)
        let w = try AVAssetWriter(outputURL: videoOnly, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes:
            [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64])
        w.add(input); w.startWriting(); w.startSession(atSourceTime: .zero)
        for i in 0..<(10 * seconds) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 5_000_000) }
            var pb: CVPixelBuffer?
            CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32BGRA, nil, &pb)
            CVPixelBufferLockBaseAddress(pb!, [])
            memset(CVPixelBufferGetBaseAddress(pb!), Int32(40 + i * 10), CVPixelBufferGetDataSize(pb!))
            CVPixelBufferUnlockBaseAddress(pb!, [])
            adaptor.append(pb!, withPresentationTime: CMTime(value: Int64(i), timescale: 10))
        }
        input.markAsFinished(); await w.finishWriting()
        guard audio else { return videoOnly }
        let comp = AVMutableComposition()
        let v = AVURLAsset(url: videoOnly), a = AVURLAsset(url: try wav("t-\(name).wav", seconds: Double(seconds)))
        let range = CMTimeRange(start: .zero, duration: CMTime(seconds: Double(seconds), preferredTimescale: 600))
        try comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
            .insertTimeRange(range, of: try await v.loadTracks(withMediaType: .video)[0], at: .zero)
        try comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
            .insertTimeRange(range, of: try await a.loadTracks(withMediaType: .audio)[0], at: .zero)
        let out = file(name)
        try await Exporter.run(comp, preset: AVAssetExportPresetPassthrough, type: .mov, to: out) { _ in }
        return out
    }

    func jpeg(_ name: String = "photo.jpg", gps: Bool = true) throws -> URL {
        let png = try png("src-\(name).png", w: 64, h: 48)
        let src = CGImageSourceCreateWithURL(png as CFURL, nil)!
        let url = file(name)
        let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        var props: [CFString: Any] = [kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "KilnCam"],
                                      kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "secret"],
                                      kCGImagePropertyOrientation: 1]
        if gps { props[kCGImagePropertyGPSDictionary] = [kCGImagePropertyGPSLatitude: 12.5, kCGImagePropertyGPSLatitudeRef: "N",
                                                          kCGImagePropertyGPSLongitude: 45.5, kCGImagePropertyGPSLongitudeRef: "E"] }
        CGImageDestinationAddImageFromSource(d, src, 0, props as CFDictionary)
        CGImageDestinationFinalize(d)
        return url
    }

    /// Hand-built stored zip, so a "../" entry can exist (normal zip tools refuse to write one).
    func rawZip(_ name: String, entries: [(String, String)]) throws -> URL {
        func crc(_ d: [UInt8]) -> UInt32 {
            var c: UInt32 = 0xFFFF_FFFF
            for b in d { c ^= UInt32(b); for _ in 0..<8 { c = (c & 1) != 0 ? (c >> 1) ^ 0xEDB8_8320 : c >> 1 } }
            return ~c
        }
        func le<T: FixedWidthInteger>(_ v: T) -> [UInt8] { (0..<MemoryLayout<T>.size).map { UInt8(truncatingIfNeeded: v >> (8 * $0)) } }
        var body: [UInt8] = [], central: [UInt8] = []
        for (n, text) in entries {
            let nameB = Array(n.utf8), data = Array(text.utf8), c = crc(data), off = UInt32(body.count)
            body += le(UInt32(0x04034b50)) + le(UInt16(20)) + le(UInt16(0)) + le(UInt16(0)) + le(UInt32(0)) + le(c) + le(UInt32(data.count)) + le(UInt32(data.count)) + le(UInt16(nameB.count)) + le(UInt16(0)) + nameB + data
            central += le(UInt32(0x02014b50)) + le(UInt16(20)) + le(UInt16(20)) + le(UInt16(0)) + le(UInt16(0)) + le(UInt32(0)) + le(c) + le(UInt32(data.count)) + le(UInt32(data.count)) + le(UInt16(nameB.count)) + le(UInt16(0)) + le(UInt16(0)) + le(UInt16(0)) + le(UInt16(0)) + le(UInt32(0)) + le(off) + nameB
        }
        let eocd = le(UInt32(0x06054b50)) + le(UInt16(0)) + le(UInt16(0)) + le(UInt16(entries.count)) + le(UInt16(entries.count)) + le(UInt32(central.count)) + le(UInt32(body.count)) + le(UInt16(0))
        let url = file(name); try Data(body + central + eocd).write(to: url); return url
    }
}

extension Scratch {
    /// Random-looking pixels, so quality settings visibly change the file size.
    func noisePNG(_ name: String = "noise.png", n: Int = 200) throws -> URL {
        let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let px = ctx.data!.assumingMemoryBound(to: UInt8.self); var seed: UInt32 = 99
        for i in 0..<(ctx.bytesPerRow * n) { seed = seed &* 1664525 &+ 1013904223; px[i] = UInt8(truncatingIfNeeded: seed >> 24) }
        let url = file(name)
        let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(d, ctx.makeImage()!, nil); CGImageDestinationFinalize(d)
        return url
    }
}

func runJob(_ input: URL, _ i: Format, _ o: Format, options: ConversionOptions) async throws -> [URL] {
    try await JobRunner().start(Job(input: input, key: ConversionKey(i, o), options: options)).result()
}

func fileSize(_ u: URL) -> Int { (try? FileManager.default.attributesOfItem(atPath: u.path)[.size] as? Int) ?? 0 }
