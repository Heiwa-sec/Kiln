import Foundation

public enum OutputLocation: Sendable, Equatable { case besideSource, folder(URL) }

public struct OutputPolicy: Sendable, Equatable {
    public var location: OutputLocation
    public var rule: CollisionRule
    public init(location: OutputLocation = .besideSource, rule: CollisionRule = .suffix) {
        self.location = location; self.rule = rule
    }
}

public struct Job: Sendable {
    public let input: URL
    public let key: ConversionKey
    public let policy: OutputPolicy
    public let options: ConversionOptions
    public init(input: URL, key: ConversionKey, policy: OutputPolicy = .init(), options: ConversionOptions = .standard) {
        self.input = input; self.key = key; self.policy = policy; self.options = options
    }
}

public final class JobHandle: Sendable {
    let task: Task<[URL], any Error>
    init(_ task: Task<[URL], any Error>) { self.task = task }
    public func cancel() { task.cancel() }
    /// Created files, or a `KilnError`.
    public func result() async throws -> [URL] { try await task.value }
}

public struct JobRunner: Sendable {
    public let registry: Registry
    public init(registry: Registry = .standard()) { self.registry = registry }

    private static func output(for first: URL, _ policy: OutputPolicy, _ options: ConversionOptions) -> Output {
        let dir: URL
        switch policy.location { case .besideSource: dir = first.deletingLastPathComponent(); case .folder(let f): dir = f }
        return Output(directory: dir, stem: first.deletingPathExtension().lastPathComponent, rule: policy.rule, options: options)
    }

    /// Runs `work` with cancellation checks around it. A failed or cancelled job deletes what it wrote.
    private static func guarded(_ first: URL, _ output: Output, progress: @Sendable (Double) -> Void,
                                _ work: () async throws -> Void) async throws -> [URL] {
        defer { output.release() }
        do {
            try Task.checkCancellation()
            try await work()
            try Task.checkCancellation()
            progress(1)
            return output.createdURLs
        } catch {
            output.removeCreated()
            throw KilnError.from(error, file: first.lastPathComponent)
        }
    }

    public func start(_ job: Job, progress: @escaping @Sendable (Double) -> Void = { _ in }) -> JobHandle {
        let registry = registry
        return JobHandle(Task.detached {
            guard let converter = registry.converter(for: job.key) else {
                throw registry.support(job.key) == .needsFFmpeg ? KilnError.needsFFmpeg : KilnError.unsupportedPair(job.key)
            }
            let output = Self.output(for: job.input, job.policy, job.options)
            return try await Self.guarded(job.input, output, progress: progress) {
                try await converter.convert(input: job.input, key: job.key, output: output, progress: progress)
            }
        })
    }

    /// Run a file tool on one input (or on all of them at once for batch tools like merge).
    public func start(tool id: ToolID, inputs: [URL], policy: OutputPolicy = .init(), progress: @escaping @Sendable (Double) -> Void = { _ in }) -> JobHandle {
        let tool = registry.tool(id)
        return JobHandle(Task.detached {
            guard let tool, let first = inputs.first, tool.accepts(inputs.compactMap { Format(url: $0) }), inputs.count == 1 || tool.batch
            else { throw KilnError.unsupportedPair(ConversionKey(inputs.first.flatMap { Format(url: $0) } ?? .png, .png)) }
            let output = Self.output(for: first, policy, .standard)
            return try await Self.guarded(first, output, progress: progress) {
                try await tool.run(inputs: inputs, output: output, progress: progress)
            }
        })
    }
}
