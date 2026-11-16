import Foundation
import ImageIO
import CoreGraphics

/// Formats ImageIO can both read and write here, so a tool never promises what it can't save.
private var editable: Set<Format> { ImageIOKit.readable.intersection(ImageIOKit.writable) }

private func prepare(_ input: URL, _ output: Output, suffix: String) throws -> (CGImageSource, Format, URL) {
    let src = try ImageIOKit.source(input)
    guard let f = Format(url: input) else { throw KilnError.corruptInput(input.lastPathComponent) }
    return (src, f, try output.url(ext: f.ext, suffix: suffix))
}

/// Re-encode JPEG or HEIC at lower quality.
struct CompressImage: Tool {
    let id = ToolID.compressImage, formats: Set<Format> = [.jpg, .heic]
    static let quality = 0.6
    func run(inputs: [URL], output: Output, progress: @Sendable (Double) -> Void) async throws {
        let (src, f, out) = try prepare(inputs[0], output, suffix: " compressed")
        guard let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { throw KilnError.corruptInput(inputs[0].lastPathComponent) }
        var props = ImageIOKit.properties(src)
        [kCGImagePropertyPixelWidth, kCGImagePropertyPixelHeight].forEach { props[$0] = nil }
        props[kCGImageDestinationLossyCompressionQuality] = Self.quality
        try ImageIOKit.write(image, as: f, to: out, properties: props)
    }
}

/// Half the pixel size, same format. Applies EXIF orientation.
struct ResizeImage: Tool {
    let id = ToolID.resizeImage
    var formats: Set<Format> { editable }
    func run(inputs: [URL], output: Output, progress: @Sendable (Double) -> Void) async throws {
        let (src, f, out) = try prepare(inputs[0], output, suffix: " resized")
        guard let image = ImageIOKit.upright(src, maxEdge: ImageIOKit.longestSide(src) / 2) else { throw KilnError.corruptInput(inputs[0].lastPathComponent) }
        try ImageIOKit.write(image, as: f, to: out)
    }
}

/// 90 degrees clockwise.
struct RotateImage: Tool {
    let id = ToolID.rotateImage
    var formats: Set<Format> { editable }
    func run(inputs: [URL], output: Output, progress: @Sendable (Double) -> Void) async throws {
        let (src, f, out) = try prepare(inputs[0], output, suffix: " rotated")
        guard let image = ImageIOKit.upright(src, maxEdge: ImageIOKit.longestSide(src)),
              let ctx = CGContext(data: nil, width: image.height, height: image.width, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw KilnError.corruptInput(inputs[0].lastPathComponent) }
        ctx.concatenate(CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: CGFloat(image.width)))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let rotated = ctx.makeImage() else { throw KilnError.io("can't rotate") }
        try ImageIOKit.write(rotated, as: f, to: out)
    }
}

/// Remove EXIF, GPS, TIFF, IPTC and maker data, keeping the orientation so the picture stays upright.
struct StripMetadata: Tool {
    let id = ToolID.stripMetadata, formats: Set<Format> = [.jpg, .png, .heic, .tiff]
    func run(inputs: [URL], output: Output, progress: @Sendable (Double) -> Void) async throws {
        let (src, f, out) = try prepare(inputs[0], output, suffix: " clean")
        guard let uti = f.imageUTI, let dest = CGImageDestinationCreateWithURL(out as CFURL, uti as CFString, 1, nil)
        else { throw KilnError.io("can't write the image") }
        var opts: [CFString: Any] = [kCGImagePropertyOrientation: ImageIOKit.properties(src)[kCGImagePropertyOrientation] ?? 1]
        for k in [kCGImagePropertyExifDictionary, kCGImagePropertyExifAuxDictionary, kCGImagePropertyGPSDictionary, kCGImagePropertyTIFFDictionary,
                  kCGImagePropertyIPTCDictionary, kCGImagePropertyMakerAppleDictionary, kCGImagePropertyJFIFDictionary] { opts[k] = kCFNull }
        CGImageDestinationAddImageFromSource(dest, src, 0, opts as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw KilnError.io("couldn't write the image") }
    }
}
