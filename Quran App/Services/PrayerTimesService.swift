import Foundation
import CoreLocation
import Combine
import WidgetKit

/// Prayer times, a month at a time.
///
/// One request fetches a whole month for the last known location and it is kept on
/// disk, so today's times, other days, the notifications and the lock-screen widget
/// all work without a network until the month runs out. Location is only looked up
/// when a new month has to be fetched or the user asks.
@MainActor
class PrayerTimesService: NSObject, ObservableObject {
    @Published var prayerTimes: PrayerTimes?
    @Published var fetchStatus: FetchStatus = .notDetermined

    /// `failed` is a visible dead end ("Couldn't load prayer times" + Try again).
    enum FetchStatus { case notDetermined, denied, fetching, ready, failed }

    private let manager = CLLocationManager()
    private var watchdog: Task<Void, Never>?
    private var months: [String: [String: [String: String]]] = [:]   // "yyyy-MM" -> "dd" -> name -> "HH:mm"

    private static let appGroup = "group.com.saminukta.Quran-App"

    /// The place the cached months were calculated for.
    private var place: (lat: Double, lon: Double)? {
        get {
            let d = UserDefaults.standard
            guard d.object(forKey: "prayerLat") != nil else { return nil }
            return (d.double(forKey: "prayerLat"), d.double(forKey: "prayerLon"))
        }
        set {
            UserDefaults.standard.set(newValue?.lat, forKey: "prayerLat")
            UserDefaults.standard.set(newValue?.lon, forKey: "prayerLon")
        }
    }

    var hasTodaysTimes: Bool {
        guard let t = prayerTimes else { return false }
        return Calendar.current.isDateInToday(t.fajr)
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        if let today = times(for: Date()) {
            prayerTimes = today
            fetchStatus = .ready
        } else {
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways: fetchStatus = .fetching
            case .denied, .restricted:                     fetchStatus = .denied
            default:                                       fetchStatus = .notDetermined
            }
        }
    }

    // MARK: - Entry points

    /// The user-chosen path ("Allow location", "Try again"): asks for permission if it
    /// has never been asked, then fetches.
    func requestAndFetch() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: locate()
        default: fetchStatus = .denied
        }
    }

    /// The silent path (launch, returning to the app, the screen appearing): never
    /// prompts, and does nothing at all while this month is on disk.
    func refreshIfNeeded() {
        if let today = times(for: Date()) {
            if !hasTodaysTimes { prayerTimes = today }
            fetchStatus = .ready
            publish()
            return
        }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if fetchStatus == .fetching, watchdog != nil { return }
            if let place { fetchMonth(containing: Date(), at: place) } else { locate() }
        case .denied, .restricted: fetchStatus = .denied
        default: fetchStatus = .notDetermined
        }
    }

    /// The calculation method or Asr school changed: the cached months no longer apply.
    func refetchForSettingsChange() {
        months.removeAll()
        try? FileManager.default.removeItem(at: Self.directory)
        prayerTimes = nil
        refreshIfNeeded()
    }

    func rescheduleNotifications() { publish() }

    /// Times for a day near today, from the cache, fetching that month if it is missing.
    func fetchTimings(dayOffset: Int) async -> PrayerTimes? {
        guard let date = Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) else { return nil }
        if let cached = times(for: date) { return cached }
        guard let place else { return nil }
        await download(month: date, at: place)
        return times(for: date)
    }

    // MARK: - Location

    private func locate() {
        fetchStatus = .fetching
        startWatchdog()
        manager.requestLocation()
    }

    private func startWatchdog() {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, let self, self.fetchStatus == .fetching else { return }
            self.finish(ok: false)
        }
    }

    private func finish(ok: Bool) {
        watchdog?.cancel()
        watchdog = nil
        if let today = times(for: Date()) {
            prayerTimes = today
            fetchStatus = .ready
            publish()
        } else {
            fetchStatus = ok ? .ready : .failed
        }
    }

    // MARK: - Month cache

    private static let directory = AppFiles.directory("PrayerTimes")

    private static func monthKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    private func month(_ key: String) -> [String: [String: String]]? {
        if let hit = months[key] { return hit }
        let file = Self.directory.appendingPathComponent("\(key).json")
        guard let saved = AppFiles.read([String: [String: String]].self, from: file) else { return nil }
        months[key] = saved
        return saved
    }

    private func times(for date: Date) -> PrayerTimes? {
        let day = String(format: "%02d", Calendar.current.component(.day, from: date))
        guard let timings = month(Self.monthKey(date))?[day] else { return nil }
        return PrayerTimes(timings: timings, on: date)
    }

    private func fetchMonth(containing date: Date, at place: (lat: Double, lon: Double)) {
        fetchStatus = .fetching
        startWatchdog()
        Task {
            await download(month: date, at: place)
            finish(ok: times(for: Date()) != nil)
        }
    }

    private func download(month date: Date, at place: (lat: Double, lon: Double)) async {
        let c = Calendar.current.dateComponents([.year, .month], from: date)
        let query = "latitude=\(place.lat)&longitude=\(place.lon)&method=\(PrayerCalcMethod.selectedMethodId)&school=\(PrayerCalcMethod.selectedSchool)"
        guard let url = URL(string: "https://api.aladhan.com/v1/calendar/\(c.year ?? 0)/\(c.month ?? 0)?\(query)"),
              let (data, _) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 15)),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let days = root["data"] as? [[String: Any]] else { return }

        var result: [String: [String: String]] = [:]
        for day in days {
            guard let timings = day["timings"] as? [String: String],
                  let date = (day["date"] as? [String: Any])?["gregorian"] as? [String: Any],
                  let number = date["day"] as? String else { continue }
            // "05:22 (EST)" -> "05:22"
            result[number] = timings.mapValues { String($0.prefix(5)) }
        }
        guard !result.isEmpty else { return }
        let key = Self.monthKey(date)
        months[key] = result
        AppFiles.write(result, to: Self.directory.appendingPathComponent("\(key).json"))
    }

    // MARK: - Notifications and widget

    /// Hands the coming days to the notifications and to the lock-screen widget.
    private func publish() {
        let cal = Calendar.current
        let days: [PrayerTimes] = (0..<10).compactMap { offset in
            cal.date(byAdding: .day, value: offset, to: Date()).flatMap(times(for:))
        }
        guard !days.isEmpty else { return }
        NotificationService.shared.schedule(days: days)

        let now = Date()
        let events = days.flatMap(\.named)
            .filter { $0.time > now }
            .sorted { $0.time < $1.time }
            .prefix(60)
            .map { ["n": $0.name, "t": String($0.time.timeIntervalSince1970)] }
        if let data = try? JSONEncoder().encode(Array(events)) {
            UserDefaults(suiteName: Self.appGroup)?.set(data, forKey: "prayerEvents")
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

extension PrayerTimesService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.first else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Rounded to about a kilometre: enough for prayer times, and it keeps the
            // exact position out of the request and off disk.
            let place = ((loc.coordinate.latitude * 100).rounded() / 100, (loc.coordinate.longitude * 100).rounded() / 100)
            if let old = self.place, abs(old.lat - place.0) > 0.2 || abs(old.lon - place.1) > 0.2 {
                self.months.removeAll()
                try? FileManager.default.removeItem(at: Self.directory)
            }
            self.place = place
            self.fetchMonth(containing: Date(), at: place)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in self?.finish(ok: false) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                if !self.hasTodaysTimes { self.locate() }
            case .denied, .restricted:
                if !self.hasTodaysTimes { self.fetchStatus = .denied }
            default: break
            }
        }
    }
}

struct PrayerTimes {
    let fajr: Date
    let sunrise: Date
    let dhuhr: Date
    let asr: Date
    let maghrib: Date
    let isha: Date
    let islamicMidnight: Date

    /// Ordered for display — Sunrise sits after Fajr, Islamic Midnight after Isha.
    var named: [(name: String, time: Date)] {
        [("Fajr", fajr), ("Sunrise", sunrise), ("Dhuhr", dhuhr), ("Asr", asr),
         ("Maghrib", maghrib), ("Isha", isha), ("Midnight", islamicMidnight)]
    }

    private var canonical: [(name: String, time: Date)] {
        [("Fajr", fajr), ("Dhuhr", dhuhr), ("Asr", asr), ("Maghrib", maghrib), ("Isha", isha)]
    }

    /// The prayer being observed now: the latest one whose time has passed. Fajr ends
    /// at sunrise and Isha at Islamic midnight, after which nothing is current.
    func currentPrayer(at now: Date) -> String? {
        var current: String?
        for (name, time) in canonical where time <= now { current = name }
        if current == "Fajr" && now >= sunrise { return nil }
        if current == "Isha" && now >= islamicMidnight { return nil }
        return current
    }

    /// The next prayer and when. After Isha it is tomorrow's Fajr.
    func upcomingPrayer(at now: Date) -> (name: String, date: Date) {
        for (name, time) in canonical where time > now { return (name, time) }
        return ("Fajr", fajr.addingTimeInterval(86400))
    }
}

extension PrayerTimes {
    /// From one day's "HH:mm" timings.
    init?(timings: [String: String], on date: Date) {
        func time(_ name: String) -> Date? {
            let parts = (timings[name] ?? "").split(separator: ":").compactMap { Int($0) }
            guard parts.count >= 2 else { return nil }
            return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: date)
        }
        guard let fajr = time("Fajr"), let sunrise = time("Sunrise"), let dhuhr = time("Dhuhr"),
              let asr = time("Asr"), let maghrib = time("Maghrib"), let isha = time("Isha") else { return nil }
        // Islamic midnight: halfway between Maghrib and the next Fajr.
        let nextFajr = fajr.addingTimeInterval(86400)
        self.init(fajr: fajr, sunrise: sunrise, dhuhr: dhuhr, asr: asr, maghrib: maghrib, isha: isha,
                  islamicMidnight: maghrib.addingTimeInterval(nextFajr.timeIntervalSince(maghrib) / 2))
    }
}

/// The symbol for each of the day's seven events.
enum PrayerIcons {
    static let names: [String: String] = [
        "Fajr":     "moon.stars.fill",
        "Sunrise":  "sunrise.fill",
        "Dhuhr":    "sun.max.fill",
        "Asr":      "sun.horizon.fill",
        "Maghrib":  "sunset.fill",
        "Isha":     "moon.fill",
        "Midnight": "moon.zzz.fill",
    ]
}
