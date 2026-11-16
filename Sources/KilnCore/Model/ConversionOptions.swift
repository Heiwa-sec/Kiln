import Foundation

public struct ImageSetting: Codable, Sendable, Equatable {
    public var quality: Double?          // 0...1 for lossy formats; nil = leave to ImageIO
    public var preserveMetadata = true
    public var maxEdge: Int?             // longest side in pixels; nil = keep the original size
    public init(quality: Double? = nil, preserveMetadata: Bool = true, maxEdge: Int? = nil) {
        self.quality = quality; self.preserveMetadata = preserveMetadata; self.maxEdge = maxEdge
    }
}

public enum VideoQuality: String, Codable, Sendable, CaseIterable {
    case highest, p1080, p720, p480
    var preset: String {
        switch self { case .highest: "AVAssetExportPresetHighestQuality"; case .p1080: "AVAssetExportPreset1920x1080"
                      case .p720: "AVAssetExportPreset1280x720"; case .p480: "AVAssetExportPreset640x480" }
    }
}

/// What the user can tune in Settings. Stored as JSON; `standard` is what you get with nothing changed.
public struct ConversionOptions: Codable, Sendable, Equatable {
    public static let lossy: Set<Format> = [.jpg, .heic, .avif, .webp]
    public var images: [String: ImageSetting] = [:]   // keyed by output format
    public var aacKbpsPerChannel = 64
    public var pdfDPI = 300
    public var videoQuality = VideoQuality.highest
    public var gifFPS = 10
    public var gifMaxSeconds = 10
    public var gifMaxEdge = 480
    public init() {}
    public static let standard = ConversionOptions()

    public func image(_ f: Format) -> ImageSetting {
        images[f.rawValue] ?? ImageSetting(quality: Self.lossy.contains(f) ? 0.75 : nil)
    }
    public mutating func setImage(_ f: Format, _ s: ImageSetting) { images[f.rawValue] = s }
}
