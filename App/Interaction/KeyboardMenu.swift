import AppKit
import SwiftUI
import KilnCore

/// The files Finder has selected. Needs the Automation permission (Kiln controlling Finder); macOS asks the first time.
enum FinderSelection {
    enum Result { case files([URL]), notFinder, denied, empty, failed(String) }

    @MainActor static func current() -> Result {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else { return .notFinder }
        var err: NSDictionary?
        // Return a real AppleScript list, not text: file names may contain newlines.
        let script = NSAppleScript(source: """
            tell application "Finder"
                set out to {}
                repeat with a in (selection as alias list)
                    set end of out to POSIX path of a
                end repeat
                return out
            end tell
            """)
        guard let result = script?.executeAndReturnError(&err) else {
            if (err?[NSAppleScript.errorNumber] as? Int) == -1743 { return .denied }
            return .failed((err?[NSAppleScript.errorMessage] as? String) ?? "unknown error")
        }
        let paths = AppleEventPaths.paths(from: result)
        let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }
        if existing.count != paths.count { return .failed("Finder reported files that don't exist. Nothing was done.") }
        return paths.isEmpty ? .empty : .files(paths.map { URL(fileURLWithPath: $0) })
    }
}

@MainActor final class KeyboardMenuModel: ObservableObject {
    struct Row: Identifiable { let node: WheelNode; let header: Bool; var id: String { node.id + (header ? ".h" : "") } }
    let wheels: WheelModel
    @Published var selected = 0
    init(registry: Registry) { wheels = WheelModel(registry: registry) }

    var wheel: WheelID { wheels.wheel }
    var rows: [Row] { wheels.inner.flatMap { n in n.children.isEmpty ? [Row(node: n, header: false)] : [Row(node: n, header: true)] + n.children.map { Row(node: $0, header: false) } } }
    private func selectable(_ i: Int) -> Bool { rows.indices.contains(i) && !rows[i].header && rows[i].node.runnable }

    func open(files: [URL], wheel: WheelID) { wheels.files = files; switchTo(wheel) }
    func switchTo(_ w: WheelID) { wheels.wheel = w; selected = rows.indices.first(where: selectable) ?? 0 }
    func move(_ d: Int) {
        var i = selected + d
        while rows.indices.contains(i) { if selectable(i) { selected = i; return }; i += d }
    }
    var current: WheelNode? { selectable(selected) ? rows[selected].node : nil }
}

struct KeyboardMenuView: View {
    @ObservedObject var model: KeyboardMenuModel
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(model.wheels.hubTitle).font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(model.wheel.title).font(.system(size: 11)).foregroundStyle(Palette.textDim)
            }.padding(.bottom, 6)
            ForEach(Array(model.rows.enumerated()), id: \.element.id) { i, row in
                if row.header {
                    Text(row.node.title.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.textDim).padding(.top, 6)
                } else {
                    let on = i == model.selected
                    HStack { Image(systemName: row.node.symbol).frame(width: 18); Text(row.node.title); Spacer() }
                        .font(.system(size: 13)).padding(.vertical, 4).padding(.horizontal, 8)
                        .foregroundStyle(on ? Palette.onAccent : (row.node.runnable ? Palette.text : Palette.textDim))
                        .background(on ? Palette.accent : Color.clear).clipShape(RoundedRectangle(cornerRadius: 5))
                }
            }
            Text("\u{2191}\u{2193} move   Return apply   Esc close   modifier keys switch wheel").font(.system(size: 10)).foregroundStyle(Palette.textDim).padding(.top, 8)
        }
        .foregroundStyle(Palette.text).padding(14).frame(width: 340, alignment: .leading).background(Palette.surface).clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

final class KeyPanel: NSPanel {
    var onKey: ((NSEvent) -> Void)?
    var onFlags: ((NSEvent.ModifierFlags) -> Void)?
    override var canBecomeKey: Bool { true }
    override func keyDown(with e: NSEvent) { onKey?(e) }
    override func flagsChanged(with e: NSEvent) { onFlags?(e.modifierFlags) }
}

@MainActor final class KeyboardMenuController {
    var onApply: ((WheelNode, [URL], NSPoint) -> Void)?
    var onMessage: ((String) -> Void)?
    private let model: KeyboardMenuModel
    private let panel: KeyPanel
    private let host: NSHostingView<KeyboardMenuView>
    private var resign: NSObjectProtocol?

    init(registry: Registry) {
        model = KeyboardMenuModel(registry: registry)
        host = NSHostingView(rootView: KeyboardMenuView(model: model))
        panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 200), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true; panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = host
        panel.onKey = { [weak self] e in self?.key(e) }
        panel.onFlags = { [weak self] f in self?.flags(f) }
        resign = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    func toggle() {
        if panel.isVisible { hide(); return }
        switch FinderSelection.current() {
        case .files(let urls): show(urls)
        case .notFinder: onMessage?("Select files in Finder, then press the shortcut.")
        case .empty: onMessage?("Nothing is selected in Finder.")
        case .denied: onMessage?("Allow Kiln to control Finder: System Settings \u{203A} Privacy & Security \u{203A} Automation.")
        case .failed(let m): onMessage?("Couldn't read the Finder selection: \(m)")
        }
    }

    private func show(_ files: [URL]) {
        model.open(files: files, wheel: .convert)
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        guard let f = NSScreen.at(NSEvent.mouseLocation)?.visibleFrame else { return }
        panel.setFrame(NSRect(x: f.midX - size.width / 2, y: f.midY - size.height / 2 + f.height * 0.12, width: size.width, height: size.height), display: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func hide() { panel.orderOut(nil) }

    private func key(_ e: NSEvent) {
        switch Int(e.keyCode) {
        case 126: model.move(-1)      // up
        case 125: model.move(1)       // down
        case 53: hide()               // escape
        case 36, 76:                  // return, enter
            guard let node = model.current else { NSSound.beep(); return }
            let at = NSPoint(x: panel.frame.midX, y: panel.frame.minY)
            let files = model.wheels.files
            hide(); onApply?(node, files, at)
        default: NSSound.beep()
        }
    }

    /// A wheel's modifier key switches to that wheel, as holding it does for a drag.
    private func flags(_ f: NSEvent.ModifierFlags) {
        if let w = WheelID.allCases.first(where: { f.contains(Prefs.modifier(for: $0).flag) }), w != model.wheel { model.switchTo(w) }
    }
}
