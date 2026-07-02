import ActivityKit
import Foundation

/// Manages the prayer-countdown Live Activity.
/// Started 10 minutes before each canonical prayer, dismissed when prayer time arrives.
@MainActor
final class PrayerLiveActivityService {
    static let shared = PrayerLiveActivityService()
    private var pendingTimers: [Timer] = []
    /// The prayer whose activity is currently live (or being started). Claimed
    /// synchronously so rapid, repeated scheduleAll calls can't spawn duplicates.
    private var activePrayerName: String?
    private init() {}

    func scheduleAll(for times: PrayerTimes) {
        cancelTimers()
        guard UserDefaults.standard.bool(forKey: "liveActivityEnabled") else {
            Task { await endAll() }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let prayers: [(String, Date)] = [
            ("Fajr",    times.fajr),
            ("Dhuhr",   times.dhuhr),
            ("Asr",     times.asr),
            ("Maghrib", times.maghrib),
            ("Isha",    times.isha),
        ]
        let now = Date()
        for (name, prayerDate) in prayers {
            let launchAt = prayerDate.addingTimeInterval(-10 * 60)
            if launchAt <= now && prayerDate > now {
                // Already in the 10-minute window — start immediately.
                Task { await start(name: name, time: prayerDate) }
            } else if launchAt > now {
                let delay = launchAt.timeIntervalSince(now)
                let t = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        await self?.start(name: name, time: prayerDate)
                    }
                }
                pendingTimers.append(t)
            }
        }
    }

    private func start(name: String, time: Date) async {
        // Already showing this prayer — don't fire a second banner.
        guard activePrayerName != name else { return }
        if Activity<PrayerCountdownAttributes>.activities.contains(where: {
            $0.attributes.prayerName == name
        }) {
            activePrayerName = name
            return
        }
        // Claim synchronously before any await so re-entrant calls bail out above.
        activePrayerName = name
        await endStaleActivities(keeping: name)

        let attrs   = PrayerCountdownAttributes(prayerName: name)
        let state   = PrayerCountdownAttributes.ContentState(
            prayerName: name, startTime: Date(), prayerTime: time)
        let content = ActivityContent(state: state, staleDate: time)
        do {
            let activity = try Activity<PrayerCountdownAttributes>.request(
                attributes: attrs, content: content, pushType: nil)
            // Hand dismissal to the system so it removes the activity at prayer
            // time even if the app is suspended (an in-app Timer can't fire then).
            // Text(timerInterval:) keeps counting down locally until removal, so
            // the banner disappears at the prayer instead of lingering / counting up.
            await activity.end(content, dismissalPolicy: .after(time))
        } catch {
            activePrayerName = nil
            print("[LiveActivity] Failed to start: \(error)")
        }
    }

    private func endStaleActivities(keeping name: String) async {
        for activity in Activity<PrayerCountdownAttributes>.activities
        where activity.attributes.prayerName != name {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func endAll() async {
        for activity in Activity<PrayerCountdownAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        activePrayerName = nil
    }

    private func cancelTimers() {
        pendingTimers.forEach { $0.invalidate() }
        pendingTimers.removeAll()
    }
}
