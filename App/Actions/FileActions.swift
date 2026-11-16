import AppKit
import QuickLookThumbnailing
import KilnCore

@MainActor final class FileActions {
    private let jobs: JobCenter
    private var floats: [FloatPanel] = []
    init(jobs: JobCenter) { self.jobs = jobs }

    func run(_ a: FileAction, on files: [URL]) {
        switch a {
        case .airdrop:
            NSApp.activate(ignoringOtherApps: true)
            NSSharingService(named: .sendViaAirDrop)?.perform(withItems: files)
        case .float:
            if Prefs.d.string(forKey: Prefs.Key.floatBehaviour) == "replace" { floats.forEach { $0.close() }; floats.removeAll() }
            for f in files { let p = FloatPanel(file: f) { [weak self] p in self?.floats.removeAll { $0 === p } }; floats.append(p) }
        case .copy:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects(files as [NSURL])
            jobs.note("Copied \(files.count == 1 ? files[0].lastPathComponent : "\(files.count) items") to the clipboard")
        case .copyPath:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(ShellQuote.line(files.map(\.path)), forType: .string)
            jobs.note("Copied \(files.count == 1 ? "path" : "\(files.count) paths")")
        case .terminal:
            let chosen = Prefs.d.string(forKey: Prefs.Key.terminalApp).map { URL(fileURLWithPath: $0) }
            guard let term = chosen ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
            let dirs = Set(files.map { u in (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true ? u : u.deletingLastPathComponent() })
            NSWorkspace.shared.open(Array(dirs), withApplicationAt: term, configuration: NSWorkspace.OpenConfiguration())
        case .move:
            move(files)
        }
    }

    private func move(_ files: [URL]) {
        var dest = Prefs.d.string(forKey: Prefs.Key.moveDestination).map { URL(fileURLWithPath: $0) }
        if dest == nil {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
            panel.prompt = "Move here"; panel.message = "Choose where Move puts files. Kiln remembers this; change it in Settings."
            NSApp.activate(ignoringOtherApps: true)
            guard panel.runModal() == .OK, let u = panel.url else { return }
            Prefs.d.set(u.path, forKey: Prefs.Key.moveDestination); dest = u
        }
        guard let dest else { return }
        for f in files {
            do {
                let target = try Naming.resolve(directory: dest, stem: f.deletingPathExtension().lastPathComponent, ext: f.pathExtension, rule: .suffix) { FileManager.default.fileExists(atPath: $0.path) }
                try FileManager.default.moveItem(at: f, to: target)
                jobs.note("Moved \(f.lastPathComponent) to \(dest.lastPathComponent)")
            } catch { jobs.rows.append(.init(title: f.lastPathComponent, state: .failed(KilnError.from(error, file: f.lastPathComponent).message))) }
        }
    }
}

/// A small always-on-top preview of a file. Drag it out to use the file; Escape or the corner button closes it.
final class FloatPanel: NSPanel {
    private let url: URL
    private let onClose: (FloatPanel) -> Void

    init(file: URL, onClose: @escaping (FloatPanel) -> Void) {
        url = file; self.onClose = onClose
        super.init(contentRect: NSRect(x: 0, y: 0, width: 180, height: 180), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = true; level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        contentView = FloatView(file: file, owner: self)
        let p = NSEvent.mouseLocation
        setFrameOrigin(NSPoint(x: p.x - 90, y: p.y - 90))
        orderFrontRegardless()
    }
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { close() }
    override func close() { super.close(); onClose(self) }
}

final class FloatView: NSView, NSDraggingSource {
    private let file: URL
    private unowned let owner: FloatPanel
    private let image = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var downAt: NSPoint?

    init(file: URL, owner: FloatPanel) {
        self.file = file; self.owner = owner
        super.init(frame: NSRect(x: 0, y: 0, width: 180, height: 180))
        wantsLayer = true; layer?.backgroundColor = NSColor(Palette.surface).cgColor; layer?.cornerRadius = 8
        image.frame = NSRect(x: 12, y: 36, width: 156, height: 132); image.imageScaling = .scaleProportionallyUpOrDown
        image.image = NSWorkspace.shared.icon(forFile: file.path)
        label.frame = NSRect(x: 8, y: 8, width: 164, height: 20); label.stringValue = file.lastPathComponent
        label.textColor = NSColor(Palette.text); label.font = .systemFont(ofSize: 11); label.alignment = .center; label.lineBreakMode = .byTruncatingMiddle
        addSubview(image); addSubview(label)
        let req = QLThumbnailGenerator.Request(fileAt: file, size: CGSize(width: 156, height: 132), scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { [weak self] rep, _ in
            if let img = rep?.nsImage { DispatchQueue.main.async { self?.image.image = img } }
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    func draggingSession(_ s: NSDraggingSession, sourceOperationMaskFor c: NSDraggingContext) -> NSDragOperation { .copy }
    override func mouseDown(with e: NSEvent) { downAt = e.locationInWindow; if e.clickCount == 2 { owner.close() } }
    override func mouseDragged(with e: NSEvent) {
        guard let d = downAt, hypot(e.locationInWindow.x - d.x, e.locationInWindow.y - d.y) > 4 else { return }
        downAt = nil
        let item = NSDraggingItem(pasteboardWriter: file as NSURL)
        item.setDraggingFrame(image.frame, contents: image.image)
        beginDraggingSession(with: [item], event: e, source: self)
    }
}
