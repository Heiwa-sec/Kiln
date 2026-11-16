import Foundation
import AVFoundation
import PDFKit

private func openPDF(_ url: URL) throws -> PDFDocument {
    guard let d = PDFDocument(url: url), d.pageCount > 0 else { throw KilnError.corruptInput(url.lastPathComponent) }
    if d.isLocked { throw KilnError.encryptedPDF(url.lastPathComponent) }
    return d
}

struct MergePDF: Tool {
    let id = ToolID.mergePDF, formats: Set<Format> = [.pdf], batch = true
    func accepts(_ given: [Format]) -> Bool { given.count >= 2 && given.allSatisfy(formats.contains) }
    func run(inputs: [URL], output: Output, progress: @Sendable (Double) -> Void) async throws {
        let merged = PDFDocument()
        for (n, url) in inputs.enumerated() {
            try Task.checkCancellation()
            let d = try openPDF(url)
            for i in 0..<d.pageCount { if let page = d.page(at: i) { merged.insert(page, at: merged.pageCount) } }
            progress(Double(n + 1) / Double(inputs.count))
        }
        let out = try output.url(ext: "pdf", suffix: " merged")
        guard merged.write(to: out) else { throw KilnError.io("couldn't write \(out.lastPathComponent)") }
    }
}

struct SplitPDF: Tool {
    let id = ToolID.splitPDF, formats: Set<Format> = [.pdf]
    func run(inputs: [URL], output: Output, progress: @Sendable (Double) -> Void) async throws {
        let d = try openPDF(inputs[0])
        let folder = try output.folder(suffix: " split")
        for i in 0..<d.pageCount {
            try Task.checkCancellation()
            guard let page = d.page(at: i) else { throw KilnError.corruptInput(inputs[0].lastPathComponent) }
            let one = PDFDocument(); one.insert(page, at: 0)
            let file = folder.appendingPathComponent(String(format: "page-%03d.pdf", i + 1))
            guard one.write(to: file) else { throw KilnError.io("couldn't write \(file.lastPathComponent)") }
            progress(Double(i + 1) / Double(d.pageCount))
        }
    }
}

struct CompressVideo: Tool {
    let id = ToolID.compressVideo, formats: Set<Format> = [.mp4, .mov]
    func run(inputs: [URL], output: Output, progress: @Sendable (Double) -> Void) async throws {
        let f = Format(url: inputs[0]) ?? .mp4
        let asset = AVURLAsset(url: inputs[0])
        guard (try? await asset.load(.isReadable)) == true else { throw KilnError.corruptInput(inputs[0].lastPathComponent) }
        try await Exporter.run(asset, preset: AVAssetExportPreset1280x720, type: f == .mov ? .mov : .mp4,
                               to: output.url(ext: f.ext, suffix: " compressed"), progress: progress)
    }
}

struct ExtractAudio: Tool {
    let id = ToolID.extractAudio, formats: Set<Format> = [.mp4, .mov]
    func run(inputs: [URL], output: Output, progress: @Sendable (Double) -> Void) async throws {
        try await VideoConverter().convert(input: inputs[0], key: ConversionKey(Format(url: inputs[0]) ?? .mp4, .m4a), output: output, progress: progress)
    }
}
