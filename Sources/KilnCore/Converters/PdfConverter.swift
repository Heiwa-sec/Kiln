import Foundation
import PDFKit
import ImageIO
import UniformTypeIdentifiers

struct PdfConverter: Converter {
    let pairs = [Format.png, .jpg, .txt, .md].map { ConversionKey(.pdf, $0) }
    func convert(input: URL, key: ConversionKey, output: Output, progress: @Sendable (Double) -> Void) async throws {
        let name = input.lastPathComponent
        guard let doc = PDFDocument(url: input), doc.pageCount > 0 else { throw KilnError.corruptInput(name) }
        if doc.isLocked { throw KilnError.encryptedPDF(name) }
        switch key.output {
        case .txt, .md:
            let pages = (0..<doc.pageCount).map { doc.page(at: $0)?.string ?? "" }
            if pages.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                throw KilnError.io("\u{201C}\(name)\u{201D} has no selectable text. It may be a scan: Kiln can't read text from pictures.")
            }
            let sep = key.output == .md ? "\n\n---\n\n" : "\n\n"
            try pages.joined(separator: sep).write(to: output.url(ext: key.output.ext), atomically: true, encoding: .utf8)
        default: // png, jpg: every page, 300 DPI, into a folder
            let folder = try output.folder(suffix: " pages")
            let type = key.output == .png ? UTType.png : UTType.jpeg
            for i in 0..<doc.pageCount {
                try Task.checkCancellation()
                guard let page = doc.page(at: i) else { throw KilnError.corruptInput(name) }
                let box = page.bounds(for: .mediaBox), scale = Double(output.options.pdfDPI) / 72
                if box.width * scale * box.height * scale > Double(Limits.imagePixels) { throw KilnError.tooLarge(name) }
                guard let image = Self.render(page, dpi: CGFloat(output.options.pdfDPI)) else { throw KilnError.corruptInput(name) }
                let file = folder.appendingPathComponent(String(format: "page-%03d.%@", i + 1, key.output.ext))
                guard let dest = CGImageDestinationCreateWithURL(file as CFURL, type.identifier as CFString, 1, nil)
                else { throw KilnError.io("can't write \(file.lastPathComponent)") }
                CGImageDestinationAddImage(dest, image, nil)
                guard CGImageDestinationFinalize(dest) else { throw KilnError.io("can't write \(file.lastPathComponent)") }
                progress(Double(i + 1) / Double(doc.pageCount))
            }
        }
    }

    private static func render(_ page: PDFPage, dpi: CGFloat) -> CGImage? {
        let box = page.bounds(for: .mediaBox)
        let s = dpi / 72
        let w = Int((box.width * s).rounded()), h = Int((box.height * s).rounded())
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                               space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                               bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: s, y: s)
        page.draw(with: .mediaBox, to: ctx)
        return ctx.makeImage()
    }
}
