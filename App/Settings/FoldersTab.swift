import AppKit
import SwiftUI
import KilnCore

@MainActor private func chooseFolder(_ prompt: String) -> String? {
    let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true; p.prompt = prompt
    return p.runModal() == .OK ? p.url?.path : nil
}

struct FoldersTab: View {
    @AppStorage(Prefs.Key.outputFolder) private var outputFolder = ""
    @AppStorage(Prefs.Key.collisionRule) private var rule = CollisionRule.suffix.rawValue
    @AppStorage(Prefs.Key.moveDestination) private var moveDest = ""
    var body: some View {
        Form {
            Section("Where results go") {
                HStack {
                    Text(outputFolder.isEmpty ? "Beside the original file" : outputFolder).lineLimit(1).truncationMode(.middle); Spacer()
                    Button("Choose folder\u{2026}") { if let p = chooseFolder("Save results here") { outputFolder = p } }
                    if !outputFolder.isEmpty { Button("Beside original") { outputFolder = "" } }
                }
                Picker("If the name is taken", selection: $rule) {
                    Text("Add a number (photo 2.png)").tag(CollisionRule.suffix.rawValue)
                    Text("Stop and tell me").tag(CollisionRule.fail.rawValue)
                }
                Text("Kiln never overwrites a file.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Move action") {
                HStack {
                    Text(moveDest.isEmpty ? "Asks the first time you use Move" : moveDest).lineLimit(1).truncationMode(.middle); Spacer()
                    Button("Choose\u{2026}") { if let p = chooseFolder("Move files here") { moveDest = p } }
                    if !moveDest.isEmpty { Button("Reset") { moveDest = "" } }
                }
            }
        }
        .formStyle(.grouped)
    }
}
