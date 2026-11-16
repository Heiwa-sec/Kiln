import Foundation

public enum FFmpeg {
    /// A copy the user installed (Homebrew, MacPorts, or on PATH). Kiln never bundles or downloads one.
    public static func locate(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        let dirs = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin"] + (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return dirs.map { URL(fileURLWithPath: $0).appendingPathComponent("ffmpeg") }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

/// Optional extra formats through a copy of ffmpeg the user installed. Never bundled or downloaded.
struct FFmpegConverter: Converter {
    let binary: URL
    var pairs: [ConversionKey] { Self.possible }

    private static let audioIn: [Format] = [.mp3, .m4a, .wav, .aiff, .flac, .caf, .ogg, .opus, .wma]
    private static let audioOut: [Format] = [.mp3, .m4a, .wav, .aiff, .flac, .ogg, .opus]
    private static let videoIn: [Format] = [.mp4, .mov, .mkv, .webm, .avi, .wmv]
    private static let videoOut: [Format] = [.mp4, .mov, .mkv, .webm, .avi, .wmv]

    /// Every pair ffmpeg could add. The registry keeps only those that need it; native converters win.
    static let possible: [ConversionKey] =
        audioIn.flatMap { i in audioOut.filter { $0 != i }.map { ConversionKey(i, $0) } }
        + videoIn.flatMap { i in videoOut.filter { $0 != i }.map { ConversionKey(i, $0) } }
        + videoIn.map { ConversionKey($0, .mp3) }

    static func demuxer(_ f: Format) -> String {
        switch f {
        case .mp4, .mov, .m4a: "mov"
        case .ogg, .opus: "ogg"
        case .wma, .wmv: "asf"
        case .mkv, .webm: "matroska"
        default: f.rawValue   // mp3, wav, aiff, flac, caf, avi
        }
    }

    func convert(input: URL, key: ConversionKey, output: Output, progress: @Sendable (Double) -> Void) async throws {
        let out = try output.url(ext: key.output.ext)
        // Force the demuxer from the file extension and allow only local files, so a file that is really a playlist
        // (HLS, concat) can't make ffmpeg read other local files or fetch URLs.
        var args = ["-hide_banner", "-nostdin", "-y", "-protocol_whitelist", "file", "-f", Self.demuxer(key.input), "-i", input.path]
        switch key.output {
        case .mp3: args += ["-vn", "-codec:a", "libmp3lame", "-q:a", "2"]
        case .ogg: args += ["-vn", "-codec:a", "libvorbis"]
        case .opus: args += ["-vn", "-codec:a", "libopus"]
        case .flac: args += ["-vn", "-codec:a", "flac"]
        case .m4a: args += ["-vn", "-codec:a", "aac"]
        case .wav: args += ["-vn", "-codec:a", "pcm_s16le"]
        default: break   // video containers: ffmpeg picks codecs from the extension
        }
        do { try await Run.exec(binary.path, args + [out.path]) }
        catch let f as Run.Failure { throw KilnError.io("ffmpeg stopped (exit \(f.status)): \(f.stderr.split(separator: "\n").last.map(String.init) ?? "")") }
    }
}
