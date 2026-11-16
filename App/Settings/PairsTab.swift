import SwiftUI
import KilnCore

/// Which conversions this Mac can really do, read straight from the registry.
struct PairsTab: View {
    private let registry = Registry.standard()
    private let groups: [(String, [Format], [Format])] = [
        ("Images", [.jpg, .png, .webp, .heic, .tiff, .avif, .bmp, .gif, .svg], [.jpg, .png, .webp, .heic, .tiff, .avif, .bmp, .gif, .pdf]),
        ("PDF and text", [.pdf, .docx, .pages, .txt, .md, .rtf, .rtfd, .html], [.pdf, .docx, .pages, .txt, .md, .rtf, .rtfd, .html, .png, .jpg]),
        ("Tables and captions", [.csv, .tsv, .xlsx, .srt, .vtt], [.csv, .tsv, .xlsx, .srt, .vtt, .txt]),
        ("Audio", [.mp3, .m4a, .wav, .aiff, .flac, .caf, .ogg, .opus, .wma], [.mp3, .m4a, .wav, .aiff, .flac, .caf, .ogg, .opus]),
        ("Video", [.mp4, .mov, .mkv, .webm, .avi, .wmv], [.mp4, .mov, .mkv, .webm, .avi, .wmv, .gif, .m4a, .mp3]),
        ("Archives", [.folder, .zip, .tar, .gz, .rar], [.zip, .tar, .gz, .folder]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Text("\u{2713} works now").foregroundStyle(Palette.accent)
                    Text("ff needs ffmpeg").foregroundStyle(Palette.warn)
                    Text("\u{2013} not supported").foregroundStyle(.secondary)
                    Spacer()
                    Text(FFmpeg.locate() != nil ? "ffmpeg found" : "ffmpeg not installed").foregroundStyle(.secondary)
                }.font(.system(size: 11))
                ForEach(groups, id: \.0) { name, inputs, outputs in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(name).font(.headline)
                        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                            GridRow {
                                Text("from \u{2193}  to \u{2192}").font(.system(size: 9)).foregroundStyle(.secondary).frame(width: 78, alignment: .leading)
                                ForEach(outputs, id: \.self) { Text($0.label).font(.system(size: 9, weight: .semibold)).frame(width: 40, height: 22) }
                            }
                            ForEach(inputs, id: \.self) { i in
                                GridRow {
                                    Text(i.label).font(.system(size: 9, weight: .semibold)).frame(width: 78, height: 22, alignment: .leading)
                                    ForEach(outputs, id: \.self) { o in cell(i, o) }
                                }
                            }
                        }
                    }
                }
            }.padding(18)
        }
    }

    @ViewBuilder private func cell(_ i: Format, _ o: Format) -> some View {
        if i == o { Text("\u{00B7}").foregroundStyle(.tertiary).frame(width: 40, height: 22) }
        else {
            switch registry.support(ConversionKey(i, o)) {
            case .native: Text("\u{2713}").foregroundStyle(Palette.accent).frame(width: 40, height: 22)
            case .needsFFmpeg: Text("ff").font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.warn).frame(width: 40, height: 22)
            case .unsupported: Text("\u{2013}").foregroundStyle(.tertiary).frame(width: 40, height: 22)
            }
        }
    }
}
