import AppKit

/// Detects a file drag and which modifier is held. Uses only mouse monitors and a modifier poll, so it needs no permission (see SPIKE.md).
@MainActor final class DragWatcher {
    var onWheel: (([URL], WheelID) -> Void)?
    var onEnd: (() -> Void)?
    var onCancel: (() -> Void)?

    private var lastCount = NSPasteboard(name: .drag).changeCount
    private var files: [URL] = []
    private var dragging = false
    private var current: WheelID?
    private var timer: Timer?

    func start() {
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in MainActor.assumeIsolated { self?.dragged() } }
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in MainActor.assumeIsolated { self?.ended() } }
        // Escape needs the Accessibility permission to be seen from another app's drag. Without it, release off the wheel to cancel.
        if AXIsProcessTrusted() {
            NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
                if e.keyCode == 53 { MainActor.assumeIsolated { self?.escape() } }
            }
        }
    }

    private func dragged() {
        guard !dragging else { return }
        let pb = NSPasteboard(name: .drag)
        guard pb.changeCount != lastCount else { return }
        lastCount = pb.changeCount
        let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return }
        files = urls; dragging = true; current = nil
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
    }

    private func tick() {
        let flags = NSEvent.modifierFlags
        // Releasing the modifier keeps the wheel open; only pressing another one switches it.
        guard let w = WheelID.allCases.first(where: { flags.contains(Prefs.modifier(for: $0).flag) }), w != current else { return }
        current = w
        onWheel?(files, w)
    }

    private func ended() {
        guard dragging else { return }
        dragging = false; timer?.invalidate(); current = nil
        onEnd?()
    }

    private func escape() { if dragging, current != nil { onCancel?() } }
}
