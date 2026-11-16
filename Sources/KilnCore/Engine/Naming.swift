import Foundation

public enum CollisionRule: String, Sendable { case suffix, fail }

public enum Naming {
    /// True when anything is at the path, a dangling symlink included. `fileExists` follows links and would call a
    /// dangling link "free", and every writer would then follow it and create the file the link points at.
    public static func taken(_ url: URL) -> Bool { (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil }

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

/// Names claimed by jobs that are still running. Without this, two jobs in one folder (a.png and a.tiff both to JPG)
/// would each see "a.jpg" as free and the second would overwrite the first.
private final class InFlight: @unchecked Sendable {
    static let shared = InFlight()
    let lock = NSLock()
    var paths = Set<String>()
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
                exists: @escaping @Sendable (URL) -> Bool = { Naming.taken($0) }) {
        self.directory = directory; self.stem = stem; self.rule = rule; self.options = options; self.exists = exists
    }

    /// A free file URL. Not created yet; removed on failure if the converter wrote it.
    public func url(ext: String, suffix: String = "") throws -> URL {
        lock.lock(); defer { lock.unlock() }
        InFlight.shared.lock.lock(); defer { InFlight.shared.lock.unlock() }   // check and claim as one step across all jobs
        let u = try Naming.resolve(directory: directory, stem: stem + suffix, ext: ext, rule: rule) { [exists] in
            InFlight.shared.paths.contains($0.path) || exists($0)
        }
        reserved.append(u)
        InFlight.shared.paths.insert(u.path)
        return u
    }

    /// Call when the job is over: the files now exist, so the claim is no longer needed.
    public func release() {
        lock.lock(); let mine = reserved; lock.unlock()
        InFlight.shared.lock.lock(); mine.forEach { InFlight.shared.paths.remove($0.path) }; InFlight.shared.lock.unlock()
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
