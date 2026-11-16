import Foundation

public enum CollisionRule: String, Sendable { case suffix, fail }

public enum Naming {
    /// "stem.ext", then "stem 2.ext", "stem 3.ext"... Never overwrites.
    public static func resolve(directory: URL, stem: String, ext: String, rule: CollisionRule,
                               exists: (URL) -> Bool) throws -> URL {
        func candidate(_ n: Int) -> URL {
            let name = n == 1 ? stem : "\(stem) \(n)"
            return directory.appendingPathComponent(ext.isEmpty ? name : "\(name).\(ext)")
        }
        let first = candidate(1)
        if !exists(first) { return first }
        if rule == .fail { throw KilnError.nameCollision(first.lastPathComponent) }
        for n in 2...999 where !exists(candidate(n)) { return candidate(n) }
        throw KilnError.nameCollision(first.lastPathComponent)
    }
}

/// Where one job writes. Tracks everything it created so a failed or cancelled job can clean up.
public final class Output: @unchecked Sendable {
    public let directory: URL
    public let stem: String
    public let rule: CollisionRule
    private let lock = NSLock()
    private var reserved: [URL] = []
    private let exists: @Sendable (URL) -> Bool
    public let options: ConversionOptions

    public init(directory: URL, stem: String, rule: CollisionRule, options: ConversionOptions = .standard,
                exists: @escaping @Sendable (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) {
        self.directory = directory; self.stem = stem; self.rule = rule; self.options = options; self.exists = exists
    }

    /// A free file URL. Not created yet; removed on failure if the converter wrote it.
    public func url(ext: String, suffix: String = "") throws -> URL {
        lock.lock(); defer { lock.unlock() }
        let u = try Naming.resolve(directory: directory, stem: stem + suffix, ext: ext, rule: rule) { [reserved, exists] in
            reserved.contains($0) || exists($0)
        }
        reserved.append(u)
        return u
    }

    /// A free folder URL, created.
    public func folder(suffix: String) throws -> URL {
        let u = try url(ext: "", suffix: suffix)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: false)
        return u
    }

    public var createdURLs: [URL] { lock.lock(); defer { lock.unlock() }; return reserved }

    public func removeCreated() {
        for u in createdURLs { try? FileManager.default.removeItem(at: u) }
    }
}
