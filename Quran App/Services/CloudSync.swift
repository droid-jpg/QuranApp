import Foundation

/// Mirrors the user's data — reading/appearance settings plus memorization,
/// bookmarks, reading streak and 99-Names progress — between local UserDefaults
/// and iCloud's key-value store, so it follows them across their devices.
///
/// Everything synced here is small structured state, well within iCloud KVS's
/// 1 MB budget. When iCloud is unavailable (not signed in, capability off) the
/// app keeps working against local storage and simply doesn't sync — the KVS
/// calls become no-ops and the UserDefaults values remain the source of truth.
///
/// Requires the `com.apple.developer.ubiquity-kvstore-identifier` entitlement
/// (enable iCloud ▸ Key-value storage on the app target).
///
/// ⚠️ DORMANT until iCloud is enabled. iCloud / Key-Value storage is only
/// available to the *paid* Apple Developer Program — it cannot be added on a
/// free "Personal Team", so the capability (and its entitlement) are
/// intentionally NOT set yet. With the entitlement absent, every KVS call here
/// is a silent no-op and the app runs entirely on local storage; nothing breaks.
/// Do not add the entitlement to the .entitlements file by hand — that makes
/// device code-signing fail. To activate: join the paid program, then in Xcode
/// use the app target ▸ Signing & Capabilities ▸ + Capability ▸ iCloud ▸
/// Key-Value storage, which writes the entitlement *and* registers it with
/// Apple. This sync code then starts working with no further changes.
final class CloudSync {
    static let shared = CloudSync()

    /// Posted (on the main queue) after values are pulled down from iCloud so the
    /// observable stores can reload their `@Published` state.
    static let didPull = Notification.Name("CloudSync.didPull")

    private let cloud = NSUbiquitousKeyValueStore.default
    private let standard = UserDefaults.standard
    private let group = UserDefaults(suiteName: "group.sami.Quran-App")

    /// Keys stored in `UserDefaults.standard` (settings + the stores that use it).
    private let standardKeys: [String] = [
        // Reading + appearance settings
        "colorSchemePreference", "selectedReciterId", "selectedTranslationId",
        "arabicFontSize", "translationFontSize", "transliterationFontSize",
        "showTranslation", "showTransliteration", "fillBlankUseTransliteration",
        // Prayer-notification settings
        "notifEnabled", "notifFajr", "notifDhuhr", "notifAsr", "notifMaghrib",
        "notifIsha", "notifSunrise", "notifMidnight", "notifPreReminder",
        "liveActivityEnabled",
        // Progress kept in the standard suite
        "quran_bookmarks_v1", "readingStreak", "lastReadDate",
    ]

    /// Keys stored in the shared App Group container.
    private let groupKeys: [String] = [
        "quran_memorization_v1", "quran_sr_cards_v1", "allah_names_status_v1",
    ]

    /// True while applying a pulled change, so the resulting UserDefaults writes
    /// don't immediately bounce back up to iCloud.
    private var isApplyingRemoteChange = false
    private var started = false

    private init() {}

    /// Wire up observers and do an initial two-way reconcile. Call once at launch.
    func start() {
        guard !started else { return }
        started = true

        let nc = NotificationCenter.default
        nc.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud, queue: .main
        ) { [weak self] note in
            let keys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
            self?.pull(keys: keys)
        }
        nc.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, !self.isApplyingRemoteChange else { return }
            self.pushAll()
        }

        cloud.synchronize()
        pull(keys: nil)   // seed from iCloud if another device already has data
        pushAll()         // and push whatever is already on this device
    }

    // MARK: - Local → iCloud

    private func pushAll() {
        for key in standardKeys { push(key, from: standard) }
        for key in groupKeys    { push(key, from: group) }
        cloud.synchronize()
    }

    private func push(_ key: String, from defaults: UserDefaults?) {
        guard let value = defaults?.object(forKey: key) else { return }
        cloud.set(value, forKey: key)
    }

    // MARK: - iCloud → Local

    /// Pull the given keys (or all tracked keys when `keys` is nil) from iCloud
    /// into the matching UserDefaults suite, then notify the stores to reload.
    private func pull(keys: [String]?) {
        let targets = keys ?? (standardKeys + groupKeys)
        isApplyingRemoteChange = true
        for key in targets {
            guard let value = cloud.object(forKey: key) else { continue }
            if standardKeys.contains(key) {
                standard.set(value, forKey: key)
            } else if groupKeys.contains(key) {
                group?.set(value, forKey: key)
            }
        }
        isApplyingRemoteChange = false
        NotificationCenter.default.post(name: CloudSync.didPull, object: nil)
    }
}
