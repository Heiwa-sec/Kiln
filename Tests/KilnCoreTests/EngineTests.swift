import Testing
import Foundation
@testable import KilnCore

@Suite struct NamingTests {
    @Test func freeNameIsKept() throws {
        let u = try Naming.resolve(directory: URL(fileURLWithPath: "/x"), stem: "a", ext: "png", rule: .suffix) { _ in false }
        #expect(u.lastPathComponent == "a.png")
    }
    @Test func collisionsGetNumberedSuffix() throws {
        let taken: Set<String> = ["a.png", "a 2.png"]
        let u = try Naming.resolve(directory: URL(fileURLWithPath: "/x"), stem: "a", ext: "png", rule: .suffix) { taken.contains($0.lastPathComponent) }
        #expect(u.lastPathComponent == "a 3.png")
    }
    @Test func failRuleThrowsNameCollision() {
        #expect(throws: KilnError.nameCollision("a.png")) {
            try Naming.resolve(directory: URL(fileURLWithPath: "/x"), stem: "a", ext: "png", rule: .fail) { _ in true }
        }
    }
    @Test func folderNamesHaveNoExtension() throws {
        let u = try Naming.resolve(directory: URL(fileURLWithPath: "/x"), stem: "a pages", ext: "", rule: .suffix) { _ in false }
        #expect(u.lastPathComponent == "a pages")
    }
    @Test func outputNeverHandsOutTheSameNameTwice() throws {
        let o = Output(directory: URL(fileURLWithPath: "/x"), stem: "a", rule: .suffix) { _ in false }
        #expect(try o.url(ext: "png").lastPathComponent == "a.png")
        #expect(try o.url(ext: "png").lastPathComponent == "a 2.png")
    }
}

@Suite struct ErrorMappingTests {
    @Test func diskFullFromCocoa() { #expect(KilnError.from(NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)) == .diskFull) }
    @Test func diskFullFromPOSIX() { #expect(KilnError.from(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))) == .diskFull) }
    @Test func diskFullThroughUnderlyingError() {
        let inner = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
        #expect(KilnError.from(NSError(domain: "X", code: 1, userInfo: [NSUnderlyingErrorKey: inner])) == .diskFull)
    }
    @Test func cancellation() { #expect(KilnError.from(CancellationError()) == .cancelled) }
    @Test func existsMapsToCollision() {
        #expect(KilnError.from(NSError(domain: NSCocoaErrorDomain, code: NSFileWriteFileExistsError), file: "a.png") == .nameCollision("a.png"))
    }
    @Test func unknownBecomesIO() { if case .io = KilnError.from(NSError(domain: "X", code: 9)) {} else { Issue.record("expected .io") } }
    @Test func everyCaseHasADistinctMessage() {
        let all: [KilnError] = [.unsupportedPair(ConversionKey(.png, .docx)), .corruptInput("a.png"), .nameCollision("a.png"),
                                .diskFull, .cancelled, .encryptedPDF("a.pdf"), .needsFFmpeg, .unsafeInput("a.zip"), .tooLarge("a.pdf"), .io("x")]
        #expect(Set(all.map(\.message)).count == all.count)
    }
}

@Suite struct RegistryTests {
    let r = Registry.standard()
    @Test func knowsRealPairs() {
        #expect(r.converter(for: ConversionKey(.png, .jpg)) != nil)
        #expect(r.converter(for: ConversionKey(.pdf, .txt)) != nil)
        #expect(r.converter(for: ConversionKey(.wav, .m4a)) != nil)
    }
    @Test func noIdentityPairs() { #expect(r.pairs.allSatisfy { $0.input != $0.output }) }
    @Test func unsupportedPairsAreMarked() {
        let t = r.targets(for: .pdf)
        #expect(t.first { $0.format == .docx }?.support == .unsupported)
        #expect(t.first { $0.format == .png }?.support == .native)
        #expect(r.targets(for: .svg).filter { !$0.format.isArchiveFile }.allSatisfy { $0.support == .unsupported })
    }
    @Test func reportsPairCount() { print("registry pair count:", r.pairCount); #expect(r.pairCount > 30) }
    @Test func extensionsMapToFormats() {
        #expect(Format(ext: "JPEG") == .jpg); #expect(Format(ext: "tif") == .tiff); #expect(Format(ext: "xyz") == nil)
    }
}

/// Stand-in converter for runner behavior: writes a file, then waits or fails.
struct Stub: Converter {
    enum Mode: Sendable { case wait, diskFull }
    let mode: Mode
    var pairs: [ConversionKey] { [ConversionKey(.png, .jpg)] }
    func convert(input: URL, key: ConversionKey, output: Output, progress: @Sendable (Double) -> Void) async throws {
        try Data("partial".utf8).write(to: output.url(ext: "jpg"))
        switch mode {
        case .diskFull: throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        case .wait: while true { try Task.checkCancellation(); try await Task.sleep(nanoseconds: 10_000_000) }
        }
    }
}

@Suite struct RunnerTests {
    func runner(_ m: Stub.Mode) -> JobRunner { var r = Registry(); r.register(Stub(mode: m)); return JobRunner(registry: r) }

    @Test func unsupportedPairIsTyped() async throws {
        let s = try Scratch(); defer { s.remove() }
        let e = await kilnError { _ = try await runJob(try s.png(), .png, .docx) }
        #expect(e == .unsupportedPair(ConversionKey(.png, .docx)))
    }
    @Test func cancelRemovesPartialOutput() async throws {
        let s = try Scratch(); defer { s.remove() }
        let h = runner(.wait).start(Job(input: try s.png(), key: ConversionKey(.png, .jpg)))
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(FileManager.default.fileExists(atPath: s.file("pic.jpg").path))
        h.cancel()
        let e = await kilnError { _ = try await h.result() }
        #expect(e == .cancelled)
        #expect(!FileManager.default.fileExists(atPath: s.file("pic.jpg").path))
    }
    @Test func diskFullIsTypedAndCleansUp() async throws {
        let s = try Scratch(); defer { s.remove() }
        let e = await kilnError { _ = try await runner(.diskFull).start(Job(input: try s.png(), key: ConversionKey(.png, .jpg))).result() }
        #expect(e == .diskFull)
        #expect(!FileManager.default.fileExists(atPath: s.file("pic.jpg").path))
    }
    @Test func secondRunGetsSuffixAndKeepsFirst() async throws {
        let s = try Scratch(); defer { s.remove() }
        let src = try s.png()
        let a = try await runJob(src, .png, .tiff), b = try await runJob(src, .png, .tiff)
        #expect(a.map(\.lastPathComponent) == ["pic.tiff"]); #expect(b.map(\.lastPathComponent) == ["pic 2.tiff"])
    }
    @Test func failRuleReportsCollision() async throws {
        let s = try Scratch(); defer { s.remove() }
        let src = try s.png(); _ = try await runJob(src, .png, .tiff)
        let e = await kilnError { _ = try await runJob(src, .png, .tiff, policy: .init(rule: .fail)) }
        #expect(e == .nameCollision("pic.tiff"))
    }
    @Test func customOutputFolder() async throws {
        let s = try Scratch(); defer { s.remove() }
        let out = s.file("out"); try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let r = try await runJob(try s.png(), .png, .tiff, policy: .init(location: .folder(out)))
        #expect(r[0].deletingLastPathComponent().path == out.path)
    }
}

@Suite struct ShellQuoteTests {
    static let nasty = ["/tmp/plain.png", "/tmp/with space.png", "/tmp/a;touch pwned", "/tmp/$(id).png", "/tmp/`id`", "/tmp/it's.png",
                        "/tmp/a\nb.png", "/tmp/a|b&c>d<e", "/tmp/*?[x]", "/tmp/~#!.png", "/tmp/back\\slash", "/tmp/\"dq\"", "/tmp/émoji 🔥.png", "-rf", "", "/tmp/esc\u{1B}[201~x", "/tmp/cr\rx", "/tmp/^u\u{15}x", "/tmp/del\u{7F}x", "/tmp/it's\u{1B}[0m\n"]

    @Test func safePathsAreLeftAlone() { #expect(ShellQuote.quote("/Users/a/b-c_d.png") == "/Users/a/b-c_d.png") }

    /// The real check: a shell must hand back exactly the original string.
    @Test(arguments: nasty) func realShellSeesTheOriginalPath(_ path: String) throws {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "printf %s \(ShellQuote.quote(path))"]
        let pipe = Pipe(); p.standardOutput = pipe
        try p.run(); p.waitUntilExit()
        #expect(String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self) == path)
    }

    @Test func noRawControlCharacterSurvivesInTheQuotedText() {
        for name in Self.nasty {
            let q = ShellQuote.quote(name)
            #expect(!q.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }, "raw control character in \(q.debugDescription)")
        }
    }

    @Test func manyPathsStayOnOneLine() { #expect(!ShellQuote.line(["/a b", "/c\nd"]).replacingOccurrences(of: "'/c\nd'", with: "").contains("\n")) }
}

@Suite struct AppleEventPathsTests {
    @Test func aPathWithANewlineStaysOneItem() {
        let list = NSAppleEventDescriptor.list()
        list.insert(NSAppleEventDescriptor(string: "/tmp/a\n/etc/passwd"), at: 1)
        list.insert(NSAppleEventDescriptor(string: "/tmp/b"), at: 2)
        #expect(AppleEventPaths.paths(from: list) == ["/tmp/a\n/etc/passwd", "/tmp/b"])
    }
    @Test func emptyListAndSingleString() {
        #expect(AppleEventPaths.paths(from: NSAppleEventDescriptor.list()).isEmpty)
        #expect(AppleEventPaths.paths(from: NSAppleEventDescriptor(string: "/tmp/x")) == ["/tmp/x"])
    }
}
