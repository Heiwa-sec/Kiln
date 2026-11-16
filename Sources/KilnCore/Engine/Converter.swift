import Foundation

public protocol Converter: Sendable {
    var pairs: [ConversionKey] { get }
    /// Write results through `output`. Report 0...1 and throw `CancellationError` when the task is cancelled.
    func convert(input: URL, key: ConversionKey, output: Output,
                 progress: @Sendable (Double) -> Void) async throws
}

public enum Support: Sendable, Equatable { case native, needsFFmpeg, unsupported }

public struct Target: Sendable, Equatable {
    public let format: Format
    public let support: Support
}

public struct Registry: Sendable {
    private var table: [ConversionKey: any Converter] = [:]
    private var creators: [Format: any Converter] = [:]   // zip, tar, gz: any input
    private var toolTable: [ToolID: any Tool] = [:]
    public init() {}

    public mutating func register(_ c: any Converter) { for p in c.pairs { table[p] = c } }
    public mutating func register(_ t: any Tool) { toolTable[t.id] = t }
    mutating func registerCreator(_ c: any Converter, for outputs: [Format]) { for o in outputs { creators[o] = c } }

    public func converter(for key: ConversionKey) -> (any Converter)? {
        if let c = table[key] { return c }
        guard let c = creators[key.output], !key.input.isArchiveFile, !(key.output == .gz && key.input == .folder) else { return nil }
        return c
    }
    public func tool(_ id: ToolID) -> (any Tool)? { toolTable[id] }
    public var pairCount: Int { table.count }
    public var pairs: [ConversionKey] { Array(table.keys) }

    public func support(_ key: ConversionKey) -> Support {
        converter(for: key) != nil ? .native : (FFmpegConverter.possible.contains(key) ? .needsFFmpeg : .unsupported)
    }

    /// Every advertised target for an input, marked supported or not. The UI greys out `.unsupported`.
    public func targets(for input: Format) -> [Target] {
        let wanted = input.isArchiveFile ? [Format.folder] : input.claimedTargets + [.zip, .tar, .gz]
        return wanted.map { Target(format: $0, support: support(ConversionKey(input, $0))) }
    }

    /// `ffmpeg` is looked up on this Mac; pass nil to leave the optional path off.
    public static func standard(ffmpeg: URL? = FFmpeg.locate()) -> Registry {
        var r = Registry()
        if let ffmpeg { r.register(FFmpegConverter(binary: ffmpeg)) }   // first, so native converters win any shared pair
        r.register(ImageConverter()); r.register(PdfConverter()); r.register(DocumentConverter())
        r.register(SubtitleConverter()); r.register(TableConverter()); r.register(AudioConverter()); r.register(VideoConverter())
        r.register(ArchiveExtractor()); r.registerCreator(ArchiveCreator(), for: [.zip, .tar, .gz])
        for t: any Tool in [CompressImage(), ResizeImage(), RotateImage(), StripMetadata(), MergePDF(), SplitPDF(), CompressVideo(), ExtractAudio()] { r.register(t) }
        return r
    }
}
