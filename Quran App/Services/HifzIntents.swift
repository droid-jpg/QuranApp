import AppIntents
import Foundation

/// Cross-process hand-off for App Intents that need the running app to act (audio
/// playback lives on the app's `AudioService`, which an out-of-process intent can't
/// reach directly). The intent writes a request into the shared App Group; the app
/// performs and clears it the next time it comes to the foreground.
enum HifzIntentAction {
    static let key = "pending_hifz_action_v1"
    static let continueMemorizing = "continueMemorizing"

    static func set(_ action: String) {
        UserDefaults(suiteName: sharedAppGroup)?.set(action, forKey: key)
    }

    /// Reads and clears the pending action (one-shot).
    static func take() -> String? {
        let d = UserDefaults(suiteName: sharedAppGroup)
        let v = d?.string(forKey: key)
        d?.removeObject(forKey: key)
        return v
    }
}

/// "Hey Siri, continue memorizing" — brings up the app and starts looping the ayah
/// currently being memorized, chained after the couple of ayahs before it, with a
/// pause after each so it can be recited. Built for hands-free practice in the car.
struct ContinueMemorizingIntent: AppIntent {
    static var title: LocalizedStringResource = "Continue Memorizing"
    static var description = IntentDescription(
        "Loops the ayah you're currently memorizing — chained after the ones before it — so you can recite along hands-free."
    )
    /// Bring the app forward so its audio engine can play (and keep playing in the
    /// background afterward).
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        HifzIntentAction.set(HifzIntentAction.continueMemorizing)
        return .result()
    }
}

/// Registers the spoken phrases with Siri / Shortcuts. Auto-discovered because it
/// lives in the app target.
struct QuranAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ContinueMemorizingIntent(),
            phrases: [
                "Continue memorizing with \(.applicationName)",
                "Continue my memorization in \(.applicationName)",
                "Resume memorizing in \(.applicationName)",
                "Keep memorizing with \(.applicationName)"
            ],
            shortTitle: "Continue Memorizing",
            systemImageName: "graduationcap.fill"
        )
    }
}
