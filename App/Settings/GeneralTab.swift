import AppKit
import SwiftUI
import ServiceManagement

/// Click, then press a shortcut (at least one modifier). Escape cancels.
struct ShortcutRecorder: NSViewRepresentable {
    var onRecord: (UInt32, NSEvent.ModifierFlags, String) -> Void
    final class V: NSView {
        var onRecord: ((UInt32, NSEvent.ModifierFlags, String) -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with e: NSEvent) {
            let mods = e.modifierFlags.intersection([.command, .option, .control, .shift])
            if e.keyCode == 53 { window?.makeFirstResponder(nil); return }
            guard !mods.isEmpty else { NSSound.beep(); return }
            var label = ""
            if mods.contains(.control) { label += "\u{2303}" }; if mods.contains(.option) { label += "\u{2325}" }
            if mods.contains(.shift) { label += "\u{21E7}" }; if mods.contains(.command) { label += "\u{2318}" }
            label += e.keyCode == 49 ? "Space" : (e.charactersIgnoringModifiers ?? "?").uppercased()
            onRecord?(UInt32(e.keyCode), mods, label)
            window?.makeFirstResponder(nil)
        }
    }
    func makeNSView(context: Context) -> V { let v = V(); v.onRecord = onRecord; return v }
    func updateNSView(_ v: V, context: Context) { v.onRecord = onRecord }
}

struct GeneralTab: View {
    var onHotKeyChange: () -> Void
    @AppStorage(Prefs.Key.modifierConvert) private var convert = Modifier.shift.rawValue
    @AppStorage(Prefs.Key.modifierTools) private var tools = Modifier.command.rawValue
    @AppStorage(Prefs.Key.modifierActions) private var actions = Modifier.control.rawValue
    @AppStorage(Prefs.Key.hotkeyLabel) private var hotkeyLabel = "\u{2325}Space"
    @AppStorage(Prefs.Key.showMenuBar) private var showMenuBar = true
    @AppStorage(Prefs.Key.sound) private var sound = false
    @AppStorage(Prefs.Key.haptic) private var haptic = true
    @AppStorage(Prefs.Key.revealResults) private var reveal = false
    @AppStorage(Prefs.Key.floatBehaviour) private var floatBehaviour = "new"
    @AppStorage(Prefs.Key.terminalApp) private var terminalApp = ""
    @State private var loginOn = SMAppService.mainApp.status == .enabled
    @State private var loginError = ""
    @State private var recording = false

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Open Kiln at login", isOn: Binding(get: { loginOn }, set: { on in
                    do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; loginOn = on; loginError = "" }
                    catch { loginOn = SMAppService.mainApp.status == .enabled; loginError = error.localizedDescription }
                }))
                if !loginError.isEmpty { Text(loginError).font(.footnote).foregroundStyle(Palette.warn) }
                Toggle("Show Kiln in the menu bar", isOn: $showMenuBar)
                if !showMenuBar { Text("To get back here, open Kiln again from Finder or Launchpad.").font(.footnote).foregroundStyle(.secondary) }
            }
            Section("Feedback") {
                Toggle("Sound", isOn: $sound)
                Toggle("Trackpad haptics", isOn: $haptic)
                Toggle("Show finished files in Finder", isOn: $reveal)
            }
            Section("Wheel keys (hold while dragging a file)") {
                picker("Convert", $convert, .convert); picker("Tools", $tools, .tools); picker("File actions", $actions, .actions)
            }
            Section("Keyboard menu") {
                HStack {
                    Text("Open on the Finder selection"); Spacer()
                    Button(recording ? "Press shortcut\u{2026}" : hotkeyLabel) { recording = true }.background(recording ? ShortcutRecorder { code, mods, label in
                        Prefs.d.set(Int(code), forKey: Prefs.Key.hotkeyCode); Prefs.d.set(Int(HotKey.carbonModifiers(mods)), forKey: Prefs.Key.hotkeyModifiers)
                        hotkeyLabel = label; recording = false; onHotKeyChange()
                    }.frame(width: 0, height: 0) : nil)
                }
            }
            Section("File actions") {
                Picker("Float", selection: $floatBehaviour) {
                    Text("Open a new float each time").tag("new"); Text("Replace the current float").tag("replace")
                }
                HStack {
                    Text("Terminal app"); Spacer()
                    Text(terminalApp.isEmpty ? "Terminal" : URL(fileURLWithPath: terminalApp).deletingPathExtension().lastPathComponent).foregroundStyle(.secondary)
                    Button("Choose\u{2026}") {
                        let p = NSOpenPanel(); p.allowedContentTypes = [.applicationBundle]; p.directoryURL = URL(fileURLWithPath: "/Applications"); p.prompt = "Use this app"
                        if p.runModal() == .OK, let u = p.url { terminalApp = u.path }
                    }
                    if !terminalApp.isEmpty { Button("Reset") { terminalApp = "" } }
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Two wheels can't share a key: picking one already in use swaps the two.
    private func picker(_ title: String, _ value: Binding<String>, _ wheel: WheelID) -> some View {
        Picker(title, selection: Binding(get: { value.wrappedValue }, set: { new in
            let old = value.wrappedValue
            for (w, b) in [(WheelID.convert, $convert), (.tools, $tools), (.actions, $actions)] where w != wheel && b.wrappedValue == new { b.wrappedValue = old }
            value.wrappedValue = new
        })) { ForEach(Modifier.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) } }
    }
}
