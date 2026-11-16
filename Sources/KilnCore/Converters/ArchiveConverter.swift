import Foundation

/// Archives via the tools macOS ships (`zip`, `tar`, `gzip`). Nothing is bundled.
struct ArchiveCreator: Converter {
    let pairs: [ConversionKey] = []   // registered for every input through the registry
    func convert(input: URL, key: ConversionKey, output: Output, progress: @Sendable (Double) -> Void) async throws {
        let parent = input.deletingLastPathComponent()
        let name = "./" + input.lastPathComponent   // "./" so a name like "-x" or "@list" is never read as an option
        let isDir = (try? input.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        // gzip keeps the full original name ("note.txt.gz"), like the real tool, so extracting restores it.
        let out = try output.url(ext: key.output.ext, suffix: key.output == .gz && !input.pathExtension.isEmpty ? "." + input.pathExtension : "")
        switch key.output {
        case .zip: try await Run.exec("/usr/bin/zip", ["-r", "-q", out.path, name], cwd: parent)
        case .tar: try await Run.exec("/usr/bin/tar", ["-cf", out.path, "-C", parent.path, name])
        case .gz:
            guard !isDir else { throw KilnError.unsupportedPair(key) }
            try await Run.exec("/usr/bin/gzip", ["-c", "--", input.path], stdoutTo: out)
        default: throw KilnError.unsupportedPair(key)
        }
    }
}

struct ArchiveExtractor: Converter {
    let pairs = [Format.zip, .tar, .gz].map { ConversionKey($0, .folder) }

    func convert(input: URL, key: ConversionKey, output: Output, progress: @Sendable (Double) -> Void) async throws {
        let name = input.lastPathComponent
        if key.input == .gz {   // a single compressed file, not a tarball
            let folder = try output.folder(suffix: "")
            let target = folder.appendingPathComponent(input.deletingPathExtension().lastPathComponent)
            do { try await Run.exec("/usr/bin/gunzip", ["-c", "--", input.path], stdoutTo: target) }
            catch let f as Run.Failure { _ = f; throw KilnError.corruptInput(name) }
            return
        }
        // List first: refuse anything that could land outside the folder ("zip slip"). bsdtar reads zip and tar.
        let listing: String
        do { listing = try await Run.exec("/usr/bin/tar", ["-tf", input.path]) } catch is Run.Failure { throw KilnError.corruptInput(name) }
        if listing.split(separator: "\n").contains(where: { Self.escapes(String($0)) }) { throw KilnError.unsafeArchive(name) }
        let folder = try output.folder(suffix: "")
        do { try await Run.exec("/usr/bin/tar", ["-xf", input.path, "-C", folder.path]) } catch is Run.Failure { throw KilnError.corruptInput(name) }
    }

    static func escapes(_ entry: String) -> Bool {
        entry.hasPrefix("/") || entry.split(separator: "/", omittingEmptySubsequences: false).contains("..")
    }
}
