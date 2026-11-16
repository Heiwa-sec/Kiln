import AppKit
import ServiceManagement

/// Removes Kiln: login item, settings, then the app itself (to the Trash, so it can be put back).
@MainActor enum Uninstall {
    static func run() {
        try? SMAppService.mainApp.unregister()
        Prefs.resetAll()
        NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { _, error in
            DispatchQueue.main.async {
                guard let error else { NSApp.terminate(nil); return }
                let alert = NSAlert(error: error)
                alert.messageText = "Kiln could not move itself to the Trash"
                alert.informativeText = "Drag Kiln to the Trash yourself. Its settings were already removed."
                alert.runModal()
            }
        }
    }
}
