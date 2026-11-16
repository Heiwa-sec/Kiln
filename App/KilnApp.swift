import AppKit
import KilnCore

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    private var controller: AppController?
    func applicationDidFinishLaunching(_ n: Notification) { Prefs.registerDefaults(); controller = AppController() }
    /// Opening Kiln again (Finder, Launchpad) shows Settings. This is the way back in when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ app: NSApplication, hasVisibleWindows: Bool) -> Bool { controller?.showSettings(); return true }
}

@MainActor final class AppController {
    private let registry = Registry.standard()
    private let model: WheelModel
    private let overlay: OverlayController
    private let watcher = DragWatcher()
    private let jobs: JobCenter
    private let hud: HUDController
    private let actions: FileActions
    private let keyboard: KeyboardMenuController
    private let settings = SettingsWindow()
    private let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    init() {
        model = WheelModel(registry: registry)
        overlay = OverlayController(model: model)
        jobs = JobCenter(registry: registry)
        hud = HUDController(jobs: jobs)
        actions = FileActions(jobs: jobs)
        keyboard = KeyboardMenuController(registry: registry)

        watcher.onWheel = { [overlay] files, wheel in overlay.show(files: files, wheel: wheel) }
        watcher.onEnd = { [overlay] in overlay.dragEnded() }
        watcher.onCancel = { [overlay] in overlay.hide() }
        overlay.onDrop = { [weak self] node, files, at in self?.perform(node, files, at) }
        watcher.start()

        keyboard.onApply = { [weak self] node, files, at in self?.perform(node, files, at) }
        keyboard.onMessage = { [weak self] m in self?.jobs.note(m); self?.hud.place(near: NSEvent.mouseLocation) }
        HotKey.onPress = { [weak self] in self?.keyboard.toggle() }
        registerHotKey()
        settings.onHotKeyChange = { [weak self] in self?.registerHotKey() }

        status.button?.image = NSImage(systemSymbolName: "flame", accessibilityDescription: "Kiln")
        let menu = NSMenu()
        let open = NSMenuItem(title: "Open Menu for Finder Selection", action: #selector(openMenu), keyEquivalent: ""); open.target = self
        let prefs = NSMenuItem(title: "Settings\u{2026}", action: #selector(openSettings), keyEquivalent: ","); prefs.target = self
        menu.addItem(open); menu.addItem(prefs); menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Kiln", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        status.menu = menu
        applyMenuBarPreference()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyMenuBarPreference() }
        }
    }

    private func applyMenuBarPreference() { status.isVisible = Prefs.d.bool(forKey: Prefs.Key.showMenuBar) }
    @objc private func openMenu() { keyboard.toggle() }
    @objc private func openSettings() { settings.show() }
    func showSettings() { settings.show() }
    private func registerHotKey() {
        let h = Prefs.hotkey
        if !HotKey.register(keyCode: h.code, modifiers: h.modifiers) { jobs.note("That shortcut is taken by another app. Pick another in Settings."); hud.place(near: NSEvent.mouseLocation) }
    }

    private func perform(_ node: WheelNode, _ files: [URL], _ at: NSPoint) {
        hud.place(near: at)
        switch node.command {
        case .convert(let f): jobs.convert(files, to: f)
        case .action(let a): actions.run(a, on: files)
        case .tool(let t): jobs.run(tool: t, on: files, title: node.title)
        case .none: break
        }
    }
}
