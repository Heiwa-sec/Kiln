import Foundation

public enum FileKind: String, Sendable, CaseIterable {
    case image, pdf, document, slides, table, subtitle, audio, video, archive

    /// Targets the product advertises per kind. Anything not backed by a converter shows as unsupported.
    public var claimedOutputs: [Format] {
        switch self {
        case .image: [.jpg, .png, .webp, .heic, .tiff, .avif, .bmp, .gif, .pdf]
        case .pdf: [.png, .jpg, .txt, .md, .docx, .pages, .pptx, .xlsx, .epub]
        case .document: [.docx, .pages, .md, .txt, .epub, .rtf, .rtfd, .html]
        case .slides: [.pdf, .jpg, .png]
        case .table: [.xlsx, .ods, .csv, .tsv, .pdf]
        case .subtitle: [.srt, .vtt, .txt]
        case .audio: [.mp3, .m4a, .wav, .flac, .ogg, .opus, .aiff, .wma]
        case .video: [.mp4, .mov, .mkv, .webm, .avi, .wmv, .gif, .mp3]
        case .archive: [.folder]   // extracting; creating archives is offered for every input by the registry
        }
    }
}

public enum Format: String, Sendable, CaseIterable, Hashable {
    case jpg, png, webp, heic, tiff, avif, bmp, gif, svg
    case pdf
    case docx, pages, md, txt, epub, rtf, rtfd, html
    case ppt, pptx
    case xlsx, ods, xls, csv, tsv
    case srt, vtt
    case mp3, m4a, wav, flac, ogg, opus, aiff, wma, caf
    case mp4, mov, mkv, webm, avi, wmv
    case zip, tar, gz, rar
    case folder

    public var kind: FileKind {
        switch self {
        case .jpg, .png, .webp, .heic, .tiff, .avif, .bmp, .gif, .svg: .image
        case .pdf: .pdf
        case .docx, .pages, .md, .txt, .epub, .rtf, .rtfd, .html: .document
        case .ppt, .pptx: .slides
        case .xlsx, .ods, .xls, .csv, .tsv: .table
        case .srt, .vtt: .subtitle
        case .mp3, .m4a, .wav, .flac, .ogg, .opus, .aiff, .wma, .caf: .audio
        case .mp4, .mov, .mkv, .webm, .avi, .wmv: .video
        case .zip, .tar, .gz, .rar, .folder: .archive
        }
    }

    public var ext: String { rawValue }
    public var label: String { rawValue.uppercased() }

    private static let aliases = ["jpeg": Format.jpg, "tif": .tiff, "htm": .html, "markdown": .md, "m4v": .mp4, "aif": .aiff, "tgz": .gz]

    public init?(ext: String) {
        let e = ext.lowercased()
        guard let f = Format(rawValue: e) ?? Format.aliases[e] else { return nil }
        self = f
    }

    public init?(url: URL) {
        if let f = Format(ext: url.pathExtension), f != .folder { self = f; return }
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
        self = .folder
    }

    public var isArchiveFile: Bool { [.zip, .tar, .gz, .rar].contains(self) }

    /// Targets for an input format, minus itself.
    public var claimedTargets: [Format] { kind.claimedOutputs.filter { $0 != self } }
}

public struct ConversionKey: Hashable, Sendable {
    public let input: Format
    public let output: Format
    public init(_ input: Format, _ output: Format) { self.input = input; self.output = output }
}
