import SwiftUI
import KilnCore

struct QualityTab: View {
    enum Area: String, CaseIterable { case images = "Images", audio = "Audio", video = "Video & GIF", pdf = "PDF" }
    @State private var options = Prefs.options
    @State private var area = Area.images
    private let registry = Registry.standard()
    private var lossy: [Format] { [.jpg, .heic, .avif, .webp].filter { registry.converter(for: ConversionKey(.png, $0)) != nil } }
    private let imageTargets: [Format] = [.jpg, .png, .heic, .tiff, .bmp, .gif, .avif, .webp]

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $area) { ForEach(Area.allCases, id: \.self) { Text($0.rawValue) } }
                .pickerStyle(.segmented).labelsHidden().padding([.horizontal, .top], 16)
            Form {
                switch area {
                case .images:
                    Section("Quality of lossy formats") {
                        ForEach(lossy, id: \.self) { f in
                            Picker(f.label, selection: Binding(get: { options.image(f).quality ?? 0.75 }, set: { var s = options.image(f); s.quality = $0; options.setImage(f, s) })) {
                                Text("Small file").tag(0.5); Text("Balanced").tag(0.75); Text("High").tag(0.9); Text("Maximum").tag(1.0)
                            }
                        }
                    }
                    Section("All image results") {
                        Toggle("Keep metadata (camera, location, date)", isOn: Binding(get: { options.image(.jpg).preserveMetadata }, set: { v in setAll { $0.preserveMetadata = v } }))
                        Picker("Largest side", selection: Binding(get: { options.image(.jpg).maxEdge ?? 0 }, set: { v in setAll { $0.maxEdge = v == 0 ? nil : v } })) {
                            Text("Keep original size").tag(0); Text("4096 px").tag(4096); Text("2048 px").tag(2048); Text("1080 px").tag(1080)
                        }
                        Text("Smaller images are never enlarged.").font(.footnote).foregroundStyle(.secondary)
                    }
                case .audio:
                    Section("AAC (M4A) output") {
                        Picker("Bitrate per channel", selection: $options.aacKbpsPerChannel) {
                            Text("32 kbps (small)").tag(32); Text("64 kbps (balanced)").tag(64); Text("96 kbps").tag(96); Text("128 kbps (best)").tag(128)
                        }
                        Text("Stereo uses two channels, so 64 kbps gives a 128 kbps file.").font(.footnote).foregroundStyle(.secondary)
                    }
                case .video:
                    Section("MP4 and MOV output") {
                        Picker("Size", selection: $options.videoQuality) {
                            Text("Original size, best quality").tag(VideoQuality.highest); Text("Up to 1080p").tag(VideoQuality.p1080)
                            Text("Up to 720p").tag(VideoQuality.p720); Text("Up to 480p").tag(VideoQuality.p480)
                        }
                    }
                    Section("GIF output") {
                        Picker("Frames per second", selection: $options.gifFPS) { Text("5").tag(5); Text("10").tag(10); Text("15").tag(15) }
                        Picker("Longest clip", selection: $options.gifMaxSeconds) { Text("5 s").tag(5); Text("10 s").tag(10); Text("15 s").tag(15) }
                        Picker("Width", selection: $options.gifMaxEdge) { Text("320 px").tag(320); Text("480 px").tag(480); Text("640 px").tag(640) }
                        Text("GIFs grow quickly: longer, wider and faster all mean a bigger file.").font(.footnote).foregroundStyle(.secondary)
                    }
                case .pdf:
                    Section("PDF to images") {
                        Picker("Resolution", selection: $options.pdfDPI) { Text("150 DPI (small)").tag(150); Text("300 DPI").tag(300); Text("600 DPI (large)").tag(600) }
                    }
                }
                Section { Button("Restore defaults for these settings") { restore() } }
            }
            .formStyle(.grouped)
        }
        .onChange(of: options) { Prefs.options = $0 }
    }

    private func setAll(_ f: (inout ImageSetting) -> Void) { for t in imageTargets { var s = options.image(t); f(&s); options.setImage(t, s) } }

    private func restore() {
        let d = ConversionOptions.standard
        switch area {
        case .images: options.images = [:]
        case .audio: options.aacKbpsPerChannel = d.aacKbpsPerChannel
        case .video: options.videoQuality = d.videoQuality; options.gifFPS = d.gifFPS; options.gifMaxSeconds = d.gifMaxSeconds; options.gifMaxEdge = d.gifMaxEdge
        case .pdf: options.pdfDPI = d.pdfDPI
        }
    }
}
