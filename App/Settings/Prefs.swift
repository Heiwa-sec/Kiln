import AppKit
import KilnCore

enum Modifier: String, CaseIterable {
    case shift, command, control, option
    var flag: NSEvent.ModifierFlags {
        switch self { case .shift: .shift; case .command: .command; case .control: .control; case .option: .option }
    }
    var title: String { rawValue.capitalized }
}

enum WheelID: String, CaseIterable { case convert, tools, actions }

/// Every UserDefaults key the app reads or writes. Documented in README.
enum Prefs {
    enum Key {
        static let modifierConvert = "wheel.modifier.convert"   // Modifier raw value, default shift
        static let modifierTools = "wheel.modifier.tools"       // default command
        static let modifierActions = "wheel.modifier.actions"   // default control
        static let outputFolder = "output.folder"               // path string; absent = beside source
        static let collisionRule = "output.collisionRule"       // "suffix" | "fail", default suffix
        static let moveDestination = "actions.moveDestination"  // path string; absent = ask first time
        static let hotkeyCode = "menu.hotkey.keyCode"           // virtual key code, default 49 (Space)
        static let hotkeyModifiers = "menu.hotkey.modifiers"    // Carbon modifier mask, default Option
        static let showMenuBar = "general.showMenuBar"          // Bool, default true
        static let sound = "feedback.sound"                     // Bool, default false
        static let haptic = "feedback.haptic"                   // Bool, default true
        static let revealResults = "results.reveal"             // Bool, default false: show finished files in Finder
        static let floatBehaviour = "float.behaviour"           // "new" (default) or "replace"
        static let terminalApp = "terminal.appPath"             // path to a .app; absent = Terminal
        static let options = "conversion.options"               // JSON of ConversionOptions; absent = defaults
        static let hotkeyLabel = "menu.hotkey.label"            // display text, default "\u{2325}Space"
    }
    static var d: UserDefaults { .standard }

    static func registerDefaults() {
        d.register(defaults: [Key.showMenuBar: true, Key.haptic: true, Key.sound: false, Key.revealResults: false, Key.floatBehaviour: "new"])
    }

    static var options: ConversionOptions {
        get { d.data(forKey: Key.options).flatMap { try? JSONDecoder().decode(ConversionOptions.self, from: $0) } ?? .standard }
        set { d.set(try? JSONEncoder().encode(newValue), forKey: Key.options) }
    }

    /// Every setting Kiln has ever stored lives in this one domain.
    static func resetAll() { if let id = Bundle.main.bundleIdentifier { d.removePersistentDomain(forName: id) } }

    static func modifier(for w: WheelID) -> Modifier {
        let (key, fallback): (String, Modifier) = switch w {
        case .convert: (Key.modifierConvert, .shift)
        case .tools: (Key.modifierTools, .command)
        case .actions: (Key.modifierActions, .control)
        }
        return d.string(forKey: key).flatMap(Modifier.init) ?? fallback
    }

    static var hotkey: (code: UInt32, modifiers: UInt32) {
        (UInt32(d.object(forKey: Key.hotkeyCode) as? Int ?? 49), UInt32(d.object(forKey: Key.hotkeyModifiers) as? Int ?? 0x800))   // 0x800 = optionKey
    }

    static var outputPolicy: OutputPolicy {
        OutputPolicy(location: d.string(forKey: Key.outputFolder).map { .folder(URL(fileURLWithPath: $0)) } ?? .besideSource,
                     rule: d.string(forKey: Key.collisionRule).flatMap(CollisionRule.init) ?? .suffix)
    }
}
