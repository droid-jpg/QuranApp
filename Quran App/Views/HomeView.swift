import SwiftUI
import Combine
import UIKit

/// Today (REDESIGN §3.1): start listening in one tap, see the next prayer, read
/// one verse. Top to bottom: greeting and date, a search field that hands over to
/// the Quran tab, Recent (or Start listening), the next prayer, the verse of the
/// day, and a memorization row when something is being learned.
///
/// This view holds only the plain `audioServiceRef`. Everything that draws
/// playback (the rows' buttons, the verse's button) is a leaf that observes the
/// player itself, so an ayah advance doesn't re-render Today.
struct HomeView: View {
    @AppStorage("selectedTranslationId") private var translationId = Translation.fallbackId
    // Declared so Today repaints the moment the reading face changes.
    @AppStorage("readingFace") private var readingFace = ReadingFace.newYork.rawValue
    /// The bundled surah list: Today never waits on the network for its rows.
    @State private var surahs = QuranOfflineStore.shared.surahs()
    @State private var path = NavigationPath()

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<21: return "Good evening"
        default:      return "Good night"
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.sectionGap) {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        header
                        searchField
                    }

                    RecentSection(surahs: surahs) { number in open(surah: number) }

                    PrayerCard()

                    VerseCard(surahs: surahs) { number, ayah in open(surah: number, ayah: ayah) }

                    MemorizationRow()
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.lg)
            }
            .background(Palette.background)
            // No bar on Today, so cover the status bar: content scrolls under it otherwise.
            .overlay(alignment: .top) {
                GeometryReader { geo in
                    Palette.background
                        .frame(height: geo.safeAreaInsets.top)
                        .offset(y: -geo.safeAreaInsets.top)
                }
                .frame(height: 0)
                .accessibilityHidden(true)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: TodayRoute.self) { route in
                switch route {
                case .calendar:     IslamicCalendarView()
                case .prayerTimes:  PrayerTimesScreen()
                case .memorization: MemorizationHubView()
                case .reader(let number, let ayah):
                    if let idx = surahs.firstIndex(where: { $0.number == number }) {
                        SurahPageView(surahs: surahs, startIndex: idx, initialAyah: ayah)
                    }
                }
            }
            .task {
                if surahs.isEmpty {
                    surahs = (try? await QuranAPIService.shared.fetchSurahList()) ?? []
                }
            }
            .onChange(of: translationId) {
                Task { await DailyVerseService.shared.loadIfNeeded() }
            }
        }
        // Light tap on push only.
        .sensoryFeedback(trigger: path) { old, new in
            new.count > old.count ? .impact(weight: .light) : nil
        }
    }

    private func open(surah number: Int, ayah: Int? = nil) {
        path.append(TodayRoute.reader(surah: number, ayah: ayah))
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(greeting)
                .font(TypeScale.display)
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)

            NavigationLink(value: TodayRoute.calendar) {
                Text(HomeDates.today)
                    .font(TypeScale.secondary)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(minHeight: MinSize.hitTarget, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// Looks like a field; tapping it opens the Quran tab with its search focused.
    private var searchField: some View {
        Button {
            Haptics.tap()
            QuranSearchRequest.shared.open()
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(TypeScale.secondary)
                Text("Search surahs")
                    .font(TypeScale.body)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, Spacing.sm)
            .frame(minHeight: MinSize.hitTarget)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Spacing.xs))
            .overlay(RoundedRectangle(cornerRadius: Spacing.xs).strokeBorder(Palette.separator, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Where Today pushes to.
private enum TodayRoute: Hashable {
    case calendar, prayerTimes, memorization
    case reader(surah: Int, ayah: Int?)
}

// MARK: - Dates

enum HomeDates {
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"; return f
    }()

    /// The Hijri half of the date line. Umm al-Qura, the same civil calendar the
    /// Islamic Calendar screen uses, so the two never disagree by a day.
    private static let hijriFmt: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .islamicUmmAlQura)
        f.dateFormat = "d MMMM"
        return f
    }()

    /// "Mon 9 Nov · 29 Jumada I"
    static var today: String {
        let now = Date()
        return "\(dayFmt.string(from: now)) · \(hijriFmt.string(from: now))"
    }
}

// MARK: - Recent / Start listening

/// The last three surahs listened to, each a surah row whose subtitle says where
/// you were and whose play button resumes there (and with its repeat). With no
/// history, four well-loved surahs to start with. Observes the history, so a
/// change of ayah updates this leaf and not Today.
private struct RecentSection: View {
    let surahs: [Surah]
    let onOpen: (Int) -> Void

    @ObservedObject private var listening = ListeningSessionStore.shared

    /// Al-Faatiha, Yaseen, Al-Kahf, Al-Mulk.
    private static let starters = [1, 36, 18, 67]

    private func surah(_ number: Int) -> Surah? { surahs.first { $0.number == number } }

    /// "Ayah 142", or "Ayahs 255–257, repeating".
    private func subtitle(_ s: ListeningSession) -> String {
        let r = s.repeatState
        guard r.isOn else { return "Ayah \(s.ayah)" }
        return r.isSingleAyah ? "Ayah \(r.from), repeating" : "Ayahs \(r.from)–\(r.to), repeating"
    }

    var body: some View {
        let recents = listening.recents.filter { surah($0.surah) != nil }
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Eyebrow(recents.isEmpty ? "Start listening" : "Recent")
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                if recents.isEmpty {
                    ForEach(Array(Self.starters.enumerated()), id: \.element) { index, number in
                        if let s = surah(number) {
                            if index > 0 { Hairline() }
                            SurahRowView(surah: s, onOpen: { onOpen(number) })
                        }
                    }
                } else {
                    ForEach(Array(recents.enumerated()), id: \.element.surah) { index, session in
                        if let s = surah(session.surah) {
                            if index > 0 { Hairline() }
                            SurahRowView(surah: s, subtitle: subtitle(session), resume: session,
                                         onOpen: { onOpen(s.number) })
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Next prayer

/// The next prayer, its time and a countdown; the whole card opens Prayer Times.
/// Every state keeps the card's height, so the page below doesn't jump.
private struct PrayerCard: View {
    @EnvironmentObject private var service: PrayerTimesService
    @State private var now = Date()
    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    /// Tall enough for the "Allow location" state, the tallest.
    private static let height: CGFloat = 104

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; return f
    }()

    var body: some View {
        Group {
            switch service.fetchStatus {
            case .ready:
                if let times = service.prayerTimes {
                    ready(times)
                } else {
                    message("Couldn’t load prayer times", action: "Try again") {
                        service.requestAndFetch()
                    }
                }
            case .fetching:
                HStack(spacing: Spacing.sm) {
                    ProgressView()
                    Text("Getting prayer times…")
                        .font(TypeScale.body)
                        .foregroundStyle(Palette.textSecondary)
                    Spacer(minLength: 0)
                }
                .padding(Spacing.cardPadding)
            case .notDetermined, .denied:
                message("Prayer times need your location", action: "Allow location") {
                    if service.fetchStatus == .denied,
                       let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    } else {
                        service.requestAndFetch()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: Self.height, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Spacing.sm))
        .overlay(RoundedRectangle(cornerRadius: Spacing.sm).strokeBorder(Palette.separator, lineWidth: 1))
        .onReceive(ticker) { now = $0 }
    }

    private func ready(_ times: PrayerTimes) -> some View {
        let next = times.upcomingPrayer(at: now)
        return NavigationLink(value: TodayRoute.prayerTimes) {
            HStack(spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(next.name)
                            .font(TypeScale.heading)
                            .foregroundStyle(Palette.textPrimary)
                        Spacer(minLength: Spacing.xs)
                        Text(Self.timeFmt.string(from: next.date))
                            .font(TypeScale.heading.monospacedDigit())
                            .foregroundStyle(Palette.textPrimary)
                    }
                    Text("in \(Self.countdown(to: next.date, from: now))")
                        .font(TypeScale.secondary)
                        .foregroundStyle(Palette.textSecondary)
                }
                Image(systemName: "chevron.right")
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(Spacing.cardPadding)
            .frame(maxWidth: .infinity, minHeight: Self.height, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func message(_ text: String, action: String, perform: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(text)
                .font(TypeScale.body)
                .foregroundStyle(Palette.textPrimary)
            Button {
                Haptics.tap()
                perform()
            } label: {
                Text(action)
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.accent)
                    .frame(minHeight: MinSize.hitTarget, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.cardPadding)
    }

    /// "1 h 12 min", "12 min", "less than a minute".
    private static func countdown(to date: Date, from now: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        let h = minutes / 60, m = minutes % 60
        if h > 0 { return "\(h) h \(m) min" }
        if m > 0 { return "\(m) min" }
        return "less than a minute"
    }
}

/// Prayer Times, pushed from Today. Prayer times live inline on More today (there
/// is no separate screen yet), so this shows that same block on its own page.
private struct PrayerTimesScreen: View {
    @EnvironmentObject private var service: PrayerTimesService

    var body: some View {
        ScrollView {
            PrayerTimesCardView(service: service)
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.lg)
        }
        .background(Palette.background)
        .navigationTitle("Prayer Times")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The prayer symbols, shared with the notification toggles in Settings.
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

// MARK: - Verse of the day

/// Today's ayah: Arabic, the translation, a 44 pt play button. The text opens the
/// reader at that ayah; the button is its sibling so neither swallows the other's
/// tap. Observes the player (this leaf only) for the button's icon and an error.
private struct VerseCard: View {
    let surahs: [Surah]
    let onOpen: (_ surah: Int, _ ayah: Int) -> Void

    @ObservedObject private var service = DailyVerseService.shared
    @EnvironmentObject private var audioService: AudioService
    @AppStorage("arabicScript") private var arabicScript = ArabicScript.system.rawValue

    private func isCurrent(_ v: DailyVerse) -> Bool {
        audioService.currentAyah == v.ayahNumber && audioService.currentSurah == v.surahNumber
    }

    private func play(_ v: DailyVerse) {
        guard let surah = surahs.first(where: { $0.number == v.surahNumber }) else { return }
        Haptics.tap()
        if isCurrent(v) {
            PlayerEngine(audioService: audioService).playPause()
        } else {
            audioService.play(surah: v.surahNumber, startAyah: v.ayahNumber,
                              totalAyahs: surah.numberOfAyahs, surahName: v.surahName)
        }
    }

    var body: some View {
        if let v = service.verse {
            let reference = "\(v.surahName) \(v.ayahNumber)"
            let playing = isCurrent(v) && audioService.isPlaying
            let failed = isCurrent(v) && audioService.failedAyah != nil
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Eyebrow("Verse of the day")
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: Spacing.xs)
                    Text(reference)
                        .font(TypeScale.caption)
                        .foregroundStyle(Palette.textSecondary)
                }

                Button { onOpen(v.surahNumber, v.ayahNumber) } label: {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text(v.arabic)
                            .font(.appArabic(26))
                            .foregroundStyle(Palette.textPrimary)
                            .lineSpacing(Spacing.sm)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .environment(\.layoutDirection, .rightToLeft)
                        Text(v.translation)
                            .font(TypeScale.body)
                            .foregroundStyle(Palette.textPrimary)
                            .lineSpacing(Spacing.xxs)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                HStack(spacing: Spacing.xs) {
                    Spacer(minLength: 0)
                    if failed {
                        Text("Couldn’t play. Try again")
                            .font(TypeScale.secondary)
                            .foregroundStyle(Palette.danger)
                    }
                    Button { play(v) } label: {
                        PlayCircle(playing: playing, size: MinSize.listPlayButton)
                            .frame(width: MinSize.listPlayButton, height: MinSize.listPlayButton)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(playing ? "Pause" : "Play") \(reference)")
                }
            }
        } else if service.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: MinSize.surahRow)
        }
    }
}

// MARK: - Memorization

/// Shown only while at least one surah is Learning; opens the Memorization hub.
private struct MemorizationRow: View {
    @EnvironmentObject private var store: MemorizationStore

    var body: some View {
        if store.inProgressCount > 0 {
            NavigationLink(value: TodayRoute.memorization) {
                HStack(spacing: Spacing.sm) {
                    Text("\(Text("Memorization").foregroundStyle(Palette.textPrimary)) \(Text("· \(store.inProgressCount) learning, \(store.memorizedCount) memorized").foregroundStyle(Palette.textSecondary))")
                        .font(TypeScale.body)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: Spacing.xs)
                    Image(systemName: "chevron.right")
                        .font(TypeScale.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: MinSize.moreRow)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
