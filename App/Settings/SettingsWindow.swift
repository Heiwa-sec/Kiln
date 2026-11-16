import AppKit
import SwiftUI

struct SettingsRoot: View {
    var onHotKeyChange: () -> Void
    var body: some View {
        TabView {
            GeneralTab(onHotKeyChange: onHotKeyChange).tabItem { Label("General", systemImage: "gearshape") }
            QualityTab().tabItem { Label("Quality", systemImage: "slider.horizontal.3") }
            PairsTab().tabItem { Label("Compatibility", systemImage: "tablecells") }
            FoldersTab().tabItem { Label("Folders", systemImage: "folder") }
            AboutTab(onReset: onHotKeyChange).tabItem { Label("About", systemImage: "info.circle") }
        }
        .tint(Palette.accent)
        .frame(width: 640, height: 580)
    }
}

@MainActor final class SettingsWindow {
    private var window: NSWindow?
    var onHotKeyChange: () -> Void = {}
    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsRoot(onHotKeyChange: { [weak self] in self?.onHotKeyChange() })))
            w.title = "Kiln Settings"; w.styleMask = [.titled, .closable]; w.isReleasedWhenClosed = false; w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
