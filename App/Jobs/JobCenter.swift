import AppKit
import SwiftUI
import KilnCore

@MainActor final class JobCenter: ObservableObject {
    enum State { case running, done([URL]), failed(String), info(String) }
    struct Row: Identifiable {
        var id = UUID()
        var title: String
        var progress = 0.0
        var state: State
        var handle: JobHandle?
    }
    @Published var rows: [Row] = []
    var onChange: (() -> Void)?
    let runner: JobRunner
    init(registry: Registry) { runner = JobRunner(registry: registry) }

    var isBusy: Bool { rows.contains { if case .running = $0.state { true } else { false } } }
    var hasFailures: Bool { rows.contains { if case .failed = $0.state { true } else { false } } }

    func note(_ text: String) { add(Row(title: text, state: .info(""))) }

    func convert(_ files: [URL], to format: Format) {
        for url in files {
            guard let from = Format(url: url), runner.registry.converter(for: ConversionKey(from, format)) != nil else {
                add(Row(title: url.lastPathComponent, state: .failed("Skipped: Kiln can't convert this to \(format.label).")))
                continue
            }
            track(title: "\(url.lastPathComponent)  \u{2192}  \(format.label)", name: url.lastPathComponent) { hook in
                runner.start(Job(input: url, key: ConversionKey(from, format), policy: Prefs.outputPolicy, options: Prefs.options), progress: hook)
            }
        }
    }

    func run(tool id: ToolID, on files: [URL], title: String) {
        guard let tool = runner.registry.tool(id) else { return }
        for group in tool.batch ? [files] : files.map({ [$0] }) {
            let name = group.count == 1 ? group[0].lastPathComponent : "\(group.count) files"
            guard tool.accepts(group.compactMap { Format(url: $0) }) else {
                add(Row(title: name, state: .failed("Skipped: \(title) doesn't apply to this.")))
                continue
            }
            track(title: "\(name)  \u{2192}  \(title)", name: name) { hook in
                runner.start(tool: id, inputs: group, policy: Prefs.outputPolicy, progress: hook)
            }
        }
    }

    private func track(title: String, name: String, _ start: (@escaping @Sendable (Double) -> Void) -> JobHandle) {
        let id = UUID()
        let handle = start { p in Task { @MainActor in self.update(id) { $0.progress = p } } }
        add(Row(id: id, title: title, state: .running, handle: handle))
        Task {
            do {
                let out = try await handle.result()
                update(id) { $0.state = .done(out); $0.progress = 1 }
                Feedback.done()
                if Prefs.d.bool(forKey: Prefs.Key.revealResults) { NSWorkspace.shared.activateFileViewerSelecting(out) }
            } catch {
                update(id) { $0.state = .failed(KilnError.from(error, file: name).message) }
                Feedback.failed()
            }
            onChange?()
        }
    }

    func dismiss(_ id: UUID) { rows.removeAll { $0.id == id }; onChange?() }
    func dismissFinished() { rows.removeAll { if case .running = $0.state { false } else { true } }; onChange?() }

    private func add(_ r: Row) { rows.append(r); onChange?() }
    private func update(_ id: UUID, _ f: (inout Row) -> Void) {
        if let i = rows.firstIndex(where: { $0.id == id }) { f(&rows[i]) }
    }
}
