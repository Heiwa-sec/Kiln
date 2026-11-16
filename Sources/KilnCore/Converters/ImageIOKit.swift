import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// The few ImageIO steps every image converter and tool shares.
enum ImageIOKit {
    /// Formats this macOS can read and write, asked of ImageIO at launch (WebP and AVIF vary by version).
    static let readable = formats(CGImageSourceCopyTypeIdentifiers())
    static let writable = formats(CGImageDestinationCopyTypeIdentifiers())

    private static func formats(_ ids: CFArray?) -> Set<Format> {
        let have = Set(ids as? [String] ?? [])
        return Set(Format.allCases.filter { $0.imageUTI.map(have.contains) ?? false })
    }

    static func source(_ url: URL) throws -> CGImageSource {
        guard let s = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(s) > 0 else { throw KilnError.corruptInput(url.lastPathComponent) }
        let p = properties(s)
        guard let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int, w > 0, h > 0
        else { throw KilnError.corruptInput(url.lastPathComponent) }
        if Limits.tooManyPixels(w, h) { throw KilnError.tooLarge(url.lastPathComponent) }
        return s
    }

    static func properties(_ s: CGImageSource) -> [CFString: Any] { CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any] ?? [:] }

    static func longestSide(_ s: CGImageSource) -> Int {
        let p = properties(s)
        return max(p[kCGImagePropertyPixelWidth] as? Int ?? 1, p[kCGImagePropertyPixelHeight] as? Int ?? 1)
    }

    /// The first image with its EXIF orientation applied, shrunk so its longest side is at most `maxEdge`.
    static func upright(_ s: CGImageSource, maxEdge: Int) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(s, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: max(maxEdge, 1)] as CFDictionary)
    }

    /// JPEG has no alpha: composite on white.
    static func flattened(_ image: CGImage) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let r = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(r); ctx.draw(image, in: r)
        return ctx.makeImage()
    }

    /// Write one bitmap, with optional container properties (quality, metadata).
    static func write(_ image: CGImage, as f: Format, to url: URL, properties: [CFString: Any] = [:]) throws {
        guard let uti = f.imageUTI, let dest = CGImageDestinationCreateWithURL(url as CFURL, uti as CFString, 1, nil)
        else { throw KilnError.unsupportedPair(ConversionKey(f, f)) }
        CGImageDestinationAddImage(dest, f == .jpg ? (flattened(image) ?? image) : image, properties as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw KilnError.io("couldn't write \(url.lastPathComponent)") }
    }
}

extension Format {
    var imageUTI: String? {
        switch self {
        case .jpg: UTType.jpeg.identifier
        case .png: UTType.png.identifier
        case .heic: UTType.heic.identifier
        case .tiff: UTType.tiff.identifier
        case .bmp: UTType.bmp.identifier
        case .gif: UTType.gif.identifier
        case .webp: UTType.webP.identifier
        case .avif: UTType("public.avif")?.identifier
        default: nil
        }
    }
}
