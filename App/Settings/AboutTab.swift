import SwiftUI

struct AboutTab: View {
    var onReset: () -> Void
    private enum Confirm: String, Identifiable { case reset, uninstall; var id: String { rawValue } }
    @State private var confirm: Confirm?
    private var version: String { (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev" }
    var body: some View {
        Form {
            Section {
                LabeledContent("Kiln", value: "version \(version)")
                LabeledContent("Network", value: "none: everything runs on this Mac")
                LabeledContent("License", value: "MIT")
                Text("Kiln is an independent project, not affiliated with any other app.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Your data") {
                Text("Kiln stores only these settings (in the dev.kiln.Kiln defaults domain). It keeps no history and no copies of your files.").font(.footnote)
                Button("Reset all settings\u{2026}") { confirm = .reset }
            }
            Section("Remove Kiln") {
                Text("Moves Kiln to the Trash and deletes its settings. Files you converted are not touched.").font(.footnote)
                Button("Uninstall Kiln\u{2026}", role: .destructive) { confirm = .uninstall }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(confirm == .uninstall ? "Move Kiln to the Trash and delete its settings?" : "Reset every Kiln setting to its default?",
                            isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), presenting: confirm) { c in
            if c == .uninstall { Button("Uninstall", role: .destructive) { Uninstall.run() } }
            else { Button("Reset", role: .destructive) { Prefs.resetAll(); onReset() } }
        }
    }
}
