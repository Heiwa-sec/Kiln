import AppKit

/// Optional sound and trackpad haptics. System sounds only; nothing is bundled.
enum Feedback {
    @MainActor static func tick() {
        if Prefs.d.bool(forKey: Prefs.Key.haptic) { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
        if Prefs.d.bool(forKey: Prefs.Key.sound) { NSSound(named: "Tink")?.play() }
    }
    @MainActor static func done() { if Prefs.d.bool(forKey: Prefs.Key.sound) { NSSound(named: "Glass")?.play() } }
    @MainActor static func failed() { if Prefs.d.bool(forKey: Prefs.Key.sound) { NSSound(named: "Basso")?.play() } }
}
