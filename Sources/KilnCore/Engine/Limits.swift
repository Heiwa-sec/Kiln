import Foundation

/// Upper bounds on what Kiln will read or render, so one odd file can't exhaust memory.
enum Limits {
    static let textBytes = 100 * 1024 * 1024
    static let imagePixels = 200_000_000

    /// Text-like inputs are read whole, so refuse the very large ones.
    static func checkText(_ url: URL) throws {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if size > textBytes { throw KilnError.tooLarge(url.lastPathComponent) }
    }
}
