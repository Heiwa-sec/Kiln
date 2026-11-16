import Foundation
import ImageIO
import CoreGraphics

struct ImageConverter: Converter {
    let pairs: [ConversionKey] = {
        let out = ImageIOKit.writable.union([.pdf])
        return ImageIOKit.readable.flatMap { i in out.filter { $0 != i }.map { ConversionKey(i, $0) } }
    }()

    func convert(input: URL, key: ConversionKey, output: Output, progress: @Sendable (Double) -> Void) async throws {
        let src = try ImageIOKit.source(input)
        guard let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { throw KilnError.corruptInput(input.lastPathComponent) }
        let out = try output.url(ext: key.output.ext)
        if key.output == .pdf {
            var box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            guard let ctx = CGContext(out as CFURL, mediaBox: &box, nil) else { throw KilnError.io("can't create PDF") }
            ctx.beginPDFPage(nil); ctx.draw(image, in: box); ctx.endPDFPage(); ctx.closePDF()
            return
        }
        let setting = output.options.image(key.output)
        var frame = image
        var props = ImageIOKit.properties(src)
        [kCGImagePropertyPixelWidth, kCGImagePropertyPixelHeight].forEach { props[$0] = nil }
        if let edge = setting.maxEdge, max(image.width, image.height) > edge, let small = ImageIOKit.upright(src, maxEdge: edge) {
            frame = small; props[kCGImagePropertyOrientation] = 1   // already upright
        }
        if !setting.preserveMetadata { props = props[kCGImagePropertyOrientation].map { [kCGImagePropertyOrientation: $0] } ?? [:] }
        if let q = setting.quality, ConversionOptions.lossy.contains(key.output) { props[kCGImageDestinationLossyCompressionQuality] = q }
        try ImageIOKit.write(frame, as: key.output, to: out, properties: props)
    }
}
