import Foundation

/// Runs a system command with an argument array (never a shell), honoring task cancellation.
enum Run {
    struct Failure: Error { let status: Int32; let stderr: String }

    private final class Sink: @unchecked Sendable {
        private let lock = NSLock(); private var data = Data()
        func add(_ d: Data) { lock.lock(); data.append(d); lock.unlock() }
        var text: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self) }
    }

    /// Returns stdout, or writes it to `stdoutTo` when given. Throws `Failure` on a non-zero exit.
    @discardableResult
    static func exec(_ path: String, _ args: [String], cwd: URL? = nil, stdoutTo file: URL? = nil) async throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path); p.arguments = args; p.currentDirectoryURL = cwd
        let out = Pipe(), err = Pipe(), so = Sink(), se = Sink()
        var fileHandle: FileHandle?
        if let file {
            FileManager.default.createFile(atPath: file.path, contents: nil)
            fileHandle = try FileHandle(forWritingTo: file); p.standardOutput = fileHandle
        } else {
            p.standardOutput = out
            out.fileHandleForReading.readabilityHandler = { so.add($0.availableData) }
        }
        p.standardError = err
        err.fileHandleForReading.readabilityHandler = { se.add($0.availableData) }
        do {
            let result: String = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                    p.terminationHandler = { proc in
                        out.fileHandleForReading.readabilityHandler = nil; err.fileHandleForReading.readabilityHandler = nil
                        if file == nil { so.add(out.fileHandleForReading.readDataToEndOfFile()) }
                        se.add(err.fileHandleForReading.readDataToEndOfFile())
                        proc.terminationStatus == 0 ? cont.resume(returning: so.text) : cont.resume(throwing: Failure(status: proc.terminationStatus, stderr: se.text))
                    }
                    do { try p.run() } catch { cont.resume(throwing: error) }
                }
            } onCancel: { if p.isRunning { p.terminate() } }
            try fileHandle?.close()
            return result
        } catch {
            try? fileHandle?.close()
            if Task.isCancelled { throw CancellationError() }
            if let f = error as? Failure, f.stderr.localizedCaseInsensitiveContains("no space left") { throw KilnError.diskFull }
            throw error
        }
    }
}
