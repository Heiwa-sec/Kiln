import AppKit
import KilnCore

enum FileAction: String { case airdrop, float, copy, move, copyPath, terminal }

enum WheelCommand: Equatable {
    case convert(Format)
    case tool(ToolID)
    case action(FileAction)
}

struct WheelNode: Identifiable {
    let id: String
    let title: String
    let symbol: String
    var children: [WheelNode] = []
    var command: WheelCommand?
    var enabled = true
    var runnable: Bool { enabled && command != nil }
}

/// What the wheel shows for the files being dragged, and what the pointer is over.
@MainActor final class WheelModel: ObservableObject {
    @Published var wheel: WheelID = .convert { didSet { rebuild() } }
    @Published private(set) var inner: [WheelNode] = []
    @Published private(set) var activeGroup: Int?
    @Published private(set) var zone: WheelGeometry.Zone = .outside
    @Published var center: CGPoint = .zero   // wheel centre in the drop view
    var files: [URL] = [] { didSet { rebuild() } }
    let registry: Registry
    let geometry = WheelGeometry.standard
    init(registry: Registry) { self.registry = registry }

    var outer: [WheelNode] { activeGroup.map { inner[$0].children } ?? [] }

    var hubTitle: String { files.count == 1 ? files[0].lastPathComponent : "\(files.count) files" }

    var hoveredNode: WheelNode? {
        switch zone {
        case .inner(let i) where i < inner.count: inner[i]
        case .outer(let i) where i < outer.count: outer[i]
        default: nil
        }
    }

    /// Update from the pointer, relative to the wheel centre.
    func point(dx: Double, dy: Double) {
        let z = geometry.zone(dx: dx, dy: dy, innerCount: inner.count, outerCount: outer.count)
        if case .inner(let i) = z, i < inner.count {
            let want = inner[i].children.isEmpty ? nil : i
            if want == activeGroup { cancelSwitch() }
            else if activeGroup == nil { activeGroup = want }
            else if pending.map({ $0.group != want }) ?? true { scheduleSwitch(to: want) }   // dwell: crossing a wedge on the way to the outer ring must not swap it
        } else { cancelSwitch() }
        if z != zone {
            zone = z
            if hoveredNode?.runnable == true { Feedback.tick() }
        }
    }

    func leave() { cancelSwitch(); zone = .outside }

    private var pending: (group: Int?, task: Task<Void, Never>)?
    private func cancelSwitch() { pending?.task.cancel(); pending = nil }
    private func scheduleSwitch(to g: Int?) {
        cancelSwitch()
        pending = (g, Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            self?.activeGroup = g; self?.pending = nil
        })
    }

    private func rebuild() {
        cancelSwitch(); activeGroup = nil; zone = .outside
        inner = switch wheel {
        case .convert: convertNodes()
        case .tools: toolNodes()
        case .actions: actionNodes()
        }
    }

    private static func groupTitle(_ k: FileKind) -> String {
        switch k {
        case .image: "Image"; case .pdf: "PDF"; case .document: "Text"; case .slides: "Slides"; case .table: "Sheet"
        case .subtitle: "Captions"; case .audio: "Audio"; case .video: "Video"; case .archive: "Archive"
        }
    }

    private func convertNodes() -> [WheelNode] {
        // A target is usable when at least one of the dragged files can become it.
        var usable: [Format: Bool] = [:]
        for f in Set(files.compactMap { Format(url: $0) }) {
            for t in registry.targets(for: f) { usable[t.format] = usable[t.format] == true || t.support == .native }
        }
        let groups = Dictionary(grouping: Format.allCases.filter { usable[$0] != nil }, by: \.kind).mapValues { formats in
            formats.map { WheelNode(id: "c.\($0.rawValue)", title: $0.label, symbol: "arrow.right", command: .convert($0), enabled: usable[$0] == true) }
        }
        let kinds = FileKind.allCases.filter { groups[$0] != nil }
        if kinds.count == 1 { return groups[kinds[0]] ?? [] }   // one kind: show its formats directly
        return kinds.compactMap { k in
            guard let ch = groups[k] else { return nil }
            return ch.count == 1 ? ch[0] : WheelNode(id: "g.\(k.rawValue)", title: Self.groupTitle(k), symbol: "square.stack", children: ch)
        }
    }

    private func toolNodes() -> [WheelNode] {
        let formats = files.compactMap { Format(url: $0) }
        let usable = formats.count == files.count   // a file of unknown type disables every tool
        func t(_ id: ToolID, _ title: String, _ sym: String) -> WheelNode {
            WheelNode(id: "t.\(id.rawValue)", title: title, symbol: sym, command: .tool(id), enabled: usable && registry.tool(id)?.accepts(formats) == true)
        }
        return [
            WheelNode(id: "g.shrink", title: "Shrink", symbol: "arrow.down.right.and.arrow.up.left", children: [t(.compressImage, "Compress", "photo"), t(.resizeImage, "Resize", "arrow.up.left.and.arrow.down.right"), t(.compressVideo, "Compress video", "film")]),
            WheelNode(id: "g.fix", title: "Fix", symbol: "wrench", children: [t(.rotateImage, "Rotate", "rotate.right"), t(.stripMetadata, "Strip metadata", "eraser")]),
            WheelNode(id: "g.pdf", title: "PDF", symbol: "doc", children: [t(.mergePDF, "Merge", "doc.on.doc"), t(.splitPDF, "Split", "scissors")]),
            t(.extractAudio, "Extract audio", "waveform"),
        ]
    }

    private func actionNodes() -> [WheelNode] {
        func a(_ x: FileAction, _ title: String, _ sym: String) -> WheelNode { WheelNode(id: "a.\(x.rawValue)", title: title, symbol: sym, command: .action(x)) }
        return [a(.airdrop, "AirDrop", "dot.radiowaves.left.and.right"), a(.float, "Float", "pin"), a(.copy, "Copy", "doc.on.clipboard"),
                a(.move, "Move", "folder"), a(.copyPath, "Copy Path", "link"), a(.terminal, "Terminal", "terminal")]
    }
}
