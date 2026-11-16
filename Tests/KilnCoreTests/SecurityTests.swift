import Testing
import Foundation
import CoreGraphics
@testable import KilnCore

/// Hostile or oversized input: Kiln must refuse cleanly, write nothing outside its folder, and not exhaust memory.
@Suite struct SecurityTests {
    @Test func hugeTextInputIsRefusedBeforeItIsRead() async throws {
        let s = try Scratch(); defer { s.remove() }
        let big = s.file("big.srt")
        FileManager.default.createFile(atPath: big.path, contents: nil)
        let h = try FileHandle(forWritingTo: big); try h.truncate(atOffset: UInt64(Limits.textBytes + 1)); try h.close()   // sparse: no real disk use
        let e = await kilnError { _ = try await runJob(big, .srt, .vtt) }
        #expect(e == .tooLarge("big.srt"))
    }

    @Test func aPageThatWouldNeedGigabytesIsRefused() async throws {
        let s = try Scratch(); defer { s.remove() }
        let url = s.file("huge.pdf")
        var box = CGRect(x: 0, y: 0, width: 20000, height: 20000)
        let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
        ctx.beginPDFPage(nil); ctx.endPDFPage(); ctx.closePDF()
        let e = await kilnError { _ = try await runJob(url, .pdf, .png) }
        #expect(e == .tooLarge("huge.pdf"))
        #expect(!FileManager.default.fileExists(atPath: s.file("huge pages").path))
    }

    /// A PNG whose header claims 20000 x 20000 pixels (400 million), with no pixel data behind it.
    @Test func anImageClaimingHugeDimensionsIsRefused() async throws {
        let s = try Scratch(); defer { s.remove() }
        func crc(_ d: [UInt8]) -> UInt32 { var c: UInt32 = 0xFFFF_FFFF; for b in d { c ^= UInt32(b); for _ in 0..<8 { c = (c & 1) != 0 ? (c >> 1) ^ 0xEDB8_8320 : c >> 1 } }; return ~c }
        func be(_ v: UInt32) -> [UInt8] { [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: v >> $0) } }
        func chunk(_ type: String, _ data: [UInt8]) -> [UInt8] { be(UInt32(data.count)) + Array(type.utf8) + data + be(crc(Array(type.utf8) + data)) }
        let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + chunk("IHDR", be(20000) + be(20000) + [8, 2, 0, 0, 0]) + chunk("IEND", [])
        let url = s.file("bomb.png"); try Data(png).write(to: url)
        let e = await kilnError { _ = try await runJob(url, .png, .jpg) }
        #expect(e == .tooLarge("bomb.png") || e == .corruptInput("bomb.png"))   // either way it stops before allocating
        #expect(!FileManager.default.fileExists(atPath: s.file("bomb.jpg").path))
    }

    /// An archive with a link followed by a file "inside" the link: the classic way to write outside the folder.
    @Test func extractionNeverWritesThroughASymlink() async throws {
        let s = try Scratch(); defer { s.remove() }
        let outside = s.file("outside"); try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let src = s.file("src"); try FileManager.default.createDirectory(at: src.appendingPathComponent("real"), withIntermediateDirectories: true)
        try "payload".write(to: src.appendingPathComponent("real/pwned.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: src.appendingPathComponent("link"), withDestinationURL: outside)
        let evil = s.file("evil.tar")
        try await Run.exec("/usr/bin/tar", ["-cf", evil.path, "-C", src.path, "-s", "#^real/#link/#", "link", "real/pwned.txt"])
        let e = await kilnError { _ = try await runJob(evil, .tar, .folder) }
        #expect(e != nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: s.file("evil").path))   // the half-extracted folder is removed
    }

    @Test func zippingKeepsSymlinksAsLinksInsteadOfFollowingThem() async throws {
        let s = try Scratch(); defer { s.remove() }
        let f = s.file("f"); try FileManager.default.createDirectory(at: f, withIntermediateDirectories: true)
        try "data".write(to: f.appendingPathComponent("target.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(atPath: f.appendingPathComponent("ln").path, withDestinationPath: "target.txt")
        let zip = try await runJob(f, .folder, .zip)[0]
        let listing = try await Run.exec("/usr/bin/tar", ["-tvf", zip.path])
        #expect(listing.split(separator: "\n").contains { $0.hasPrefix("l") && $0.contains("ln ->") }, "\(listing)")
    }

    @Test func anRTFDPackageContainingALinkIsRefused() async throws {
        let s = try Scratch(); defer { s.remove() }
        let pkg = try await runJob(try s.text("note.txt", "hello"), .txt, .rtfd)[0]
        try FileManager.default.createSymbolicLink(atPath: pkg.appendingPathComponent("stolen.txt").path, withDestinationPath: "/etc/hosts")
        let e = await kilnError { _ = try await runJob(pkg, .rtfd, .txt) }
        #expect(e == .unsafeInput("note.rtfd"))
    }
}
