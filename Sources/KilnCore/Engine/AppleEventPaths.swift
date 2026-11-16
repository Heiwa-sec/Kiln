import Foundation

public enum AppleEventPaths {
    /// Paths from an AppleScript result, read item by item. Never split text on newlines: macOS file names may contain them.
    public static func paths(from d: NSAppleEventDescriptor) -> [String] {
        if d.numberOfItems > 0 { return (1...d.numberOfItems).compactMap { d.atIndex($0)?.stringValue } }
        return d.stringValue.map { [$0] } ?? []
    }
}
