import AVFoundation

enum Exporter {
    private final class Box: @unchecked Sendable { let session: AVAssetExportSession; init(_ s: AVAssetExportSession) { session = s } }

    static func run(_ asset: AVAsset, preset: String, type: AVFileType, to url: URL, progress: @Sendable (Double) -> Void) async throws {
        guard let s = AVAssetExportSession(asset: asset, presetName: preset), s.supportedFileTypes.contains(type)
        else { throw KilnError.io("this Mac can't export that format") }
        s.outputURL = url; s.outputFileType = type
        let box = Box(s)
        await withTaskCancellationHandler {
            async let finished: Void = box.session.export()
            while [.unknown, .waiting, .exporting].contains(box.session.status) {
                progress(Double(box.session.progress)); try? await Task.sleep(nanoseconds: 100_000_000)
            }
            await finished
        } onCancel: { box.session.cancelExport() }
        switch s.status {
        case .completed: return
        case .cancelled: throw CancellationError()
        default: throw s.error ?? KilnError.io("export failed")
        }
    }

    static func hasAudio(_ asset: AVAsset) async -> Bool { ((try? await asset.loadTracks(withMediaType: .audio)) ?? []).isEmpty == false }
}
