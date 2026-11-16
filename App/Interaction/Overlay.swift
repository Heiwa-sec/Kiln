import AppKit
import SwiftUI
import KilnCore

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Registered drag destination. Flipped so drag locations match SwiftUI's y-down space.
final class DropView: NSView {
    let model: WheelModel
    var onDrop: ((WheelNode) -> Void)?
    override var isFlipped: Bool { true }

    init(model: WheelModel, frame: NSRect) {
        self.model = model
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        let host = NSHostingView(rootView: WheelView(model: model))
        host.frame = bounds; host.autoresizingMask = [.width, .height]
        addSubview(host)
    }
    required init?(coder: NSCoder) { nil }

    /// Point the model at the drag, and say whether a drop here would do anything.
    private func track(_ s: NSDraggingInfo) -> NSDragOperation {
        let p = convert(s.draggingLocation, from: nil)
        model.point(dx: p.x - model.center.x, dy: p.y - model.center.y)
        return model.hoveredNode?.runnable == true ? .copy : []
    }
    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation { track(s) }
    override func draggingUpdated(_ s: NSDraggingInfo) -> NSDragOperation { track(s) }
    override func draggingExited(_ s: NSDraggingInfo?) { model.leave() }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool {
        _ = track(s)
        guard let node = model.hoveredNode, node.runnable else { return false }
        onDrop?(node)
        return true
    }
}

@MainActor final class OverlayController {
    let model: WheelModel
    var onDrop: ((WheelNode, [URL], NSPoint) -> Void)?
    private let panel: OverlayPanel
    private let side: CGFloat = 400
    private var hideWork: DispatchWorkItem?

    init(model: WheelModel) {
        self.model = model
        let r = NSRect(x: 0, y: 0, width: side, height: side)
        panel = OverlayPanel(contentRect: r, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let dropView = DropView(model: model, frame: r)
        panel.contentView = dropView
        dropView.onDrop = { [weak self] node in
            guard let self else { return }
            let at = NSEvent.mouseLocation
            hide()
            onDrop?(node, model.files, at)
        }
    }

    /// Open at the cursor, or switch wheel if already open. The wheel keeps its place.
    func show(files: [URL], wheel: WheelID) {
        hideWork?.cancel()
        if !panel.isVisible {
            let p = NSEvent.mouseLocation
            let o = NSScreen.keepOnScreen(NSPoint(x: p.x - side / 2, y: p.y - side / 2), size: panel.frame.size, near: p)
            panel.setFrameOrigin(o)
            model.center = CGPoint(x: p.x - o.x, y: o.y + side - p.y)   // the view is flipped
            model.files = files
            panel.orderFrontRegardless()
        }
        model.wheel = wheel
    }

    /// The drag ended. Give a drop on the panel a moment to arrive, then close.
    func dragEnded() {
        let w = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
    }

    func hide() { hideWork?.cancel(); panel.orderOut(nil); model.leave() }
}
