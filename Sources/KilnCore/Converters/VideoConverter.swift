import AVFoundation
import ImageIO
import UniformTypeIdentifiers

struct VideoConverter: Converter {
    let pairs = [Format.mp4, .mov].flatMap { i in [Format.mp4, .mov, .m4a, .gif].filter { $0 != i }.map { ConversionKey(i, $0) } }
    func convert(input: URL, key: ConversionKey, output: Output, progress: @Sendable (Double) -> Void) async throws {
        let asset = AVURLAsset(url: input)
        guard (try? await asset.load(.isReadable)) == true, ((try? await asset.load(.tracks)) ?? []).isEmpty == false
        else { throw KilnError.corruptInput(input.lastPathComponent) }
        switch key.output {
        case .gif: try await gif(asset, options: output.options, to: output.url(ext: "gif"), progress: progress)
        case .m4a:
            guard await Exporter.hasAudio(asset) else { throw KilnError.io("\u{201C}\(input.lastPathComponent)\u{201D} has no audio track.") }
            try await Exporter.run(asset, preset: AVAssetExportPresetAppleM4A, type: .m4a, to: output.url(ext: "m4a"), progress: progress)
        default:
            try await Exporter.run(asset, preset: output.options.videoQuality.preset, type: key.output == .mp4 ? .mp4 : .mov,
                                   to: output.url(ext: key.output.ext), progress: progress)
        }
    }

    /// Length, frame rate and width come from Settings (defaults 10 s, 10 fps, 480 px): GIFs grow fast.
    private func gif(_ asset: AVAsset, options: ConversionOptions, to url: URL, progress: @Sendable (Double) -> Void) async throws {
        let fps = Double(max(options.gifFPS, 1))
        let seconds = min(try await asset.load(.duration).seconds, Double(options.gifMaxSeconds))
        let n = max(Int(seconds * fps), 1)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true; gen.maximumSize = CGSize(width: options.gifMaxEdge, height: options.gifMaxEdge)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, n, nil) else { throw KilnError.io("can't create GIF") }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for i in 0..<n {
            try Task.checkCancellation()
            let frame = try await gen.image(at: CMTime(seconds: Double(i) / fps, preferredTimescale: 600)).image
            CGImageDestinationAddImage(dest, frame, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]] as CFDictionary)
            progress(Double(i + 1) / Double(n))
        }
        guard CGImageDestinationFinalize(dest) else { throw KilnError.io("couldn't write the GIF") }
    }
}
