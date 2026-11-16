import Foundation

public enum ToolID: String, Sendable, CaseIterable {
    case compressImage, resizeImage, rotateImage, stripMetadata, mergePDF, splitPDF, compressVideo, extractAudio
}

/// A file tool (Command wheel). Unlike a conversion it has no target format.
public protocol Tool: Sendable {
    var id: ToolID { get }
    /// Input formats the tool can work on.
    var formats: Set<Format> { get }
    /// True when all inputs go into one run (merge). Otherwise the runner calls `run` once per file.
    var batch: Bool { get }
    func accepts(_ formats: [Format]) -> Bool
    func run(inputs: [URL], output: Output, progress: @Sendable (Double) -> Void) async throws
}

public extension Tool {
    var batch: Bool { false }
    func accepts(_ given: [Format]) -> Bool { !given.isEmpty && given.allSatisfy(formats.contains) }
}
