import SwiftUI
import Combine

/// The dashboard, rebuilt as a quiet editorial list. Everything that used to be
/// a tinted card is now a ruled block: a hairline, a small-caps eyebrow, and the
/// content set in the reading serif. The accent survives as a mark — the scrub
/// line, the play circles, the working-ayah rule — and nothing else is filled.
struct HomeView: View {
    @EnvironmentObject private var memorizationStore: MemorizationStore
    @EnvironmentObject private var srStore: MemorizationSRStore
    @EnvironmentObject private var targetStore: MemorizationTargetStore
    @EnvironmentObject private var audioService: AudioService
    @EnvironmentObject private var prayerService: PrayerTimesService
    @StateObject private var listVM = SurahListViewModel()
    @ObservedObject private var dailyVerse = DailyVerseService.shared
    @ObservedObject private var listening = ListeningSessionStore.shared
    @AppStorage("selectedTranslationId") private var translationId = Translation.fallbackId
    // Declared so the dashboard repaints the moment the reading face changes.
    @AppStorage("readingFace") private var readingFace = ReadingFace.newYork.rawValue
    @State private var showReview = false
    @State private var activeDrill: PlayerDrill? = nil

    private var isPlayerActive: Bool { audioService.currentAyah != nil }

    // MARK: - Listening actions

    /// The resume block's play button. When the saved session is already loaded in
    /// the player this is a plain play/pause; otherwise it restores the session —
    /// same ayah, same loop, same position inside the ayah.
    private func toggleResume(_ session: ListeningSession) {
        Haptics.tap()
        if audioService.currentAyah != nil && audioService.currentSurah == session.surah {
            audioService.togglePlayPause()
        } else {
            audioService.resume(session)
        }
    }

    /// Run one of the three acquisition drills against the current target, straight
    /// from the dashboard — the same presets the reader's player uses.
    private func runDrill(_ drill: PlayerDrill, target t: MemorizationTarget) {
        Haptics.impact(.light)
        withAnimation(AppAnim.springFast) { activeDrill = drill }
        let settings: LoopSettings
        switch drill {
        case .listen:      settings = .listen(ayah: t.workingAyah)
        case .repeatAfter: settings = .repeatAfter(ayah: t.workingAyah)
        // Chain the working ayah onto the couple before it — long enough to bind
        // them together, short enough not to replay half a surah every tap.
        case .chain:       settings = .chain(from: max(1, t.workingAyah - 2), through: t.workingAyah)
        }
        audioService.playLoop(surah: t.surah, settings: settings,
                              totalAyahs: t.totalAyahs, surahName: t.surahName)
    }

    private func ayahCount(of surah: Int) -> Int? {
        listVM.surahs.first { $0.number == surah }?.numberOfAyahs
    }

    /// One-tap starts for when there's nothing to resume.
    private var quickStarts: [QuickStartRail.QuickStart] {
        var items: [QuickStartRail.QuickStart] = []

        if let v = dailyVerse.verse, let total = ayahCount(of: v.surahNumber) {
            items.append(.init(id: "votd", label: "Verse of day",
                               icon: "sun.horizon.fill", tint: .orange) {
                Haptics.tap()
                activeDrill = nil
                audioService.play(surah: v.surahNumber, startAyah: v.ayahNumber,
                                  loop: .listen(ayah: v.ayahNumber, repeatCount: 1),
                                  totalAyahs: total, surahName: v.surahName)
            })
        }

        if let s = listening.session, s.isLoop {
            items.append(.init(id: "lastloop", label: s.loopLabel, icon: "repeat") {
                Haptics.tap()
                activeDrill = nil
                audioService.playLoop(surah: s.surah, settings: s.loop,
                                      totalAyahs: s.totalAyahs, surahName: s.surahName)
            })
        }

        if let juz = JuzData.boundaries.first(where: { $0.juz == 30 }),
           let total = ayahCount(of: juz.startSurah) {
            let name = listVM.surahs.first { $0.number == juz.startSurah }?.englishName ?? ""
            items.append(.init(id: "juz30", label: "Juz 30") {
                Haptics.tap()
                activeDrill = nil
                // Sequential mode rolls on through the following surahs on its own.
                audioService.play(surah: juz.startSurah, startAyah: juz.startAyah,
                                  loop: LoopSettings(), totalAyahs: total, surahName: name)
            })
        }

        return items
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12:  return "Good morning."
        case 12..<17: return "Good afternoon."
        case 17..<21: return "Good evening."
        default:      return "Good night."
        }
    }

    /// A notable (non-recurring) Islamic event happening today or tomorrow, for the
    /// home line. Recurring fasts (Mon/Thu, White Days) are excluded so it only
    /// surfaces genuine occasions.
    private var featuredEvent: (occ: EventOccurrence, isToday: Bool)? {
        let cal = Calendar.current
        let today = Date()
        if let occ = IslamicEvent.events(on: today).first(where: { $0.event.recurrence == .none }) {
            return (occ, true)
        }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: today),
           let occ = IslamicEvent.events(on: tomorrow).first(where: { $0.event.recurrence == .none }) {
            return (occ, false)
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // ── Masthead ──────────────────────────────────────────
                    Masthead(streak: StreakService.shared.currentStreak)
                        .padding(.horizontal, 24)
                        .padding(.top, 18)
                        .staggeredAppear(delay: 0.04)

                    // ── Greeting ──────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 8) {
                        Text(greeting)
                            .font(.appSerif(27))
                            .foregroundStyle(.primary)
                        Eyebrow(HomeDates.today, size: 10)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 18)
                    .staggeredAppear(delay: 0.06)

                    // ── Holiday line (today / tomorrow) ───────────────────
                    if let ev = featuredEvent {
                        HolidayLine(occurrence: ev.occ, isToday: ev.isToday)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 18)
                            .staggeredAppear(delay: 0.07)
                    }

                    // ── Now playing / resume ──────────────────────────────
                    // Top slot, because "hear Qur'an" is the shortest path into
                    // the app and it used to cost a tab switch and 114 rows.
                    if let session = listening.session {
                        ResumeListeningSection(
                            session: session,
                            surahs: listVM.surahs,
                            audioService: audioService,
                            onToggle: { toggleResume(session) }
                        )
                        .padding(.horizontal, 24)
                        .padding(.bottom, 14)
                        .staggeredAppear(delay: 0.075)
                    }

                    // ── One-tap starts ────────────────────────────────────
                    if !quickStarts.isEmpty {
                        QuickStartRail(items: quickStarts)
                            .padding(.bottom, 18)
                            .staggeredAppear(delay: 0.09)
                    }

                    // ── Memorizing (current target) ───────────────────────
                    if let t = targetStore.target,
                       let idx = listVM.surahs.firstIndex(where: { $0.number == t.surah }) {
                        MemorizingSection(
                            target: t,
                            surahs: listVM.surahs,
                            startIndex: idx,
                            activeDrill: activeDrill,
                            onDrill: { runDrill($0, target: t) }
                        )
                        .padding(.horizontal, 24)
                        .padding(.bottom, 18)
                        .staggeredAppear(delay: 0.11)
                    }

                    // ── Next prayer ───────────────────────────────────────
                    if prayerService.fetchStatus == .ready {
                        NextPrayerSection(times: prayerService.prayerTimes)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 18)
                            .staggeredAppear(delay: 0.13)
                    }

                    // ── Verse of the day ──────────────────────────────────
                    // Hidden entirely when the verse hasn't arrived — a lone
                    // eyebrow over nothing reads as a broken section.
                    if dailyVerse.verse != nil || dailyVerse.isLoading {
                        VerseOfDaySection(
                            surahs: listVM.surahs,
                            onPlay: { verse in
                                guard let total = ayahCount(of: verse.surahNumber) else { return }
                                Haptics.tap()
                                activeDrill = nil
                                audioService.play(
                                    surah: verse.surahNumber, startAyah: verse.ayahNumber,
                                    loop: .listen(ayah: verse.ayahNumber, repeatCount: 1),
                                    totalAyahs: total, surahName: verse.surahName
                                )
                            }
                        )
                        .padding(.horizontal, 24)
                        .padding(.bottom, 18)
                        .staggeredAppear(delay: 0.16)
                    }

                    // ── Due for review ────────────────────────────────────
                    if srStore.dueCount() > 0 {
                        DueReviewSection(count: srStore.dueCount()) {
                            Haptics.tap()
                            showReview = true
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 18)
                        .staggeredAppear(delay: 0.19)
                    }

                    // ── Other surahs in progress ──────────────────────────
                    // The active target already has its own block above, so it
                    // is excluded here — this row is the rest of the backlog.
                    let otherInProgress = memorizationStore.inProgressNumbers
                        .filter { $0 != targetStore.target?.surah }
                    if !otherInProgress.isEmpty && !listVM.surahs.isEmpty {
                        EditorialSection(title: "In progress",
                                         icon: "circle.dotted.and.circle",
                                         iconTint: .orange,
                                         trailing: "\(otherInProgress.count)") {
                            EmptyView()
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 13)
                        .staggeredAppear(delay: 0.21)

                        InProgressRail(numbers: otherInProgress, surahs: listVM.surahs)
                            .padding(.bottom, 18)
                            .staggeredAppear(delay: 0.23)
                    }

                    // ── Progress summary ──────────────────────────────────
                    ProgressSection(store: memorizationStore, surahs: listVM.surahs)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                        .staggeredAppear(delay: 0.26)
                }
                .padding(.bottom, 28)
            }
            // The masthead is the title now — the nav bar would only repeat it.
            .toolbar(.hidden, for: .navigationBar)
            // Audio never leaves the tab: what Home starts, Home can also pause,
            // resume and stop without a trip to the reader.
            .safeAreaInset(edge: .bottom) {
                if isPlayerActive {
                    HomeMiniPlayer(audioService: audioService, surahs: listVM.surahs)
                        .padding(.bottom, 6)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(AppAnim.spring, value: isPlayerActive)
            .task { await listVM.load() }
            .onChange(of: translationId) {
                Task { await dailyVerse.loadIfNeeded() }
            }
            .onChange(of: audioService.currentAyah) { _, ayah in
                if ayah == nil { activeDrill = nil }
            }
            .fullScreenCover(isPresented: $showReview) {
                ReviewSessionView(store: srStore, initialCards: srStore.dueItems())
            }
        }
    }
}

// MARK: - Dates

enum HomeDates {
    // Abbreviated: at small-caps with letterspacing, the full "TUESDAY, 11
    // AUGUST · 28 SAFAR" runs nearly the width of the page and reads as another
    // paragraph rather than a dateline.
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"; return f
    }()

    /// The Hijri half of the dateline. Umm al-Qura, the same civil calendar the
    /// Islamic Calendar screen uses, so the two never disagree by a day.
    private static let hijriFmt: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .islamicUmmAlQura)
        f.dateFormat = "d MMMM"
        return f
    }()

    static var today: String {
        let now = Date()
        return "\(dayFmt.string(from: now)) · \(hijriFmt.string(from: now))"
    }
}

// MARK: - Masthead

/// The wordmark, a rule that runs to the streak, and the streak itself. Replaces
/// the large navigation title so the page starts as a page, not as chrome.
private struct Masthead: View {
    let streak: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("Holy Quran")
                .font(.appSerif(32, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Rectangle()
                .fill(Color.rule)
                .frame(height: 1)
                .alignmentGuide(.firstTextBaseline) { d in d[.bottom] + 5 }
            if streak > 0 {
                MetaText("\(streak) DAY\(streak == 1 ? "" : "S")", size: 10)
                    .accessibilityLabel("\(streak) day streak")
            }
        }
    }
}

// MARK: - Holiday line

private struct HolidayLine: View {
    let occurrence: EventOccurrence
    let isToday: Bool

    var body: some View {
        NavigationLink {
            IslamicCalendarView()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: occurrence.event.kind.icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(occurrence.event.kind.color)
                Text(occurrence.event.name)
                    .font(.appSerif(16))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                MetaText(isToday ? "TODAY" : "TOMORROW",
                         tint: occurrence.event.kind.color, size: 9.5)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color(.label).opacity(0.3))
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .overlay(Rectangle().strokeBorder(occurrence.event.kind.color.opacity(0.35), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hapticTap()
    }
}

// MARK: - Memorizing

/// The surah + ayah the user is actively memorizing. The heading opens the reader
/// at the working ayah; underneath, the three acquisition drills — Listen, Repeat,
/// Chain — start straight from the dashboard in the same language the reader's
/// player uses, so a drill is one tap from opening the app.
private struct MemorizingSection: View {
    let target: MemorizationTarget
    let surahs: [Surah]
    let startIndex: Int
    let activeDrill: PlayerDrill?
    let onDrill: (PlayerDrill) -> Void

    var body: some View {
        EditorialSection(title: "Memorizing",
                         icon: "graduationcap.fill",
                         trailing: "\(Int((target.fraction * 100).rounded()))%") {
            VStack(alignment: .leading, spacing: 0) {
                NavigationLink {
                    SurahPageView(surahs: surahs, startIndex: startIndex, initialAyah: target.workingAyah)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(target.surahName)
                            .font(.appSerif(21, weight: .medium))
                            .foregroundStyle(.primary)
                        Text(target.isComplete
                             ? "memorized"
                             : "ayah \(target.workingAyah) of \(target.totalAyahs)")
                            .font(.appSerif(16))
                            .foregroundStyle(Color(.label).opacity(0.5))
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color(.label).opacity(0.3))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hapticTap()

                RuleProgress(fraction: target.fraction)
                    .padding(.top, 13)

                HStack(spacing: 8) {
                    OutlineButton(label: "Listen", on: activeDrill == .listen) { onDrill(.listen) }
                    OutlineButton(label: "Repeat", on: activeDrill == .repeatAfter) { onDrill(.repeatAfter) }
                    OutlineButton(label: "Chain", on: activeDrill == .chain) { onDrill(.chain) }
                }
                .padding(.top, 15)
            }
        }
    }
}

// MARK: - Next prayer

/// The upcoming prayer, its countdown, and the rest of the day as one ruled
/// line of metadata. No expansion: the whole day already fits.
struct NextPrayerSection: View {
    let times: PrayerTimes?
    @State private var now = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var nextEntry: (name: String, time: Date)? {
        guard let t = times else { return nil }
        let canonical: [(String, Date)] = [
            ("Fajr", t.fajr), ("Dhuhr", t.dhuhr),
            ("Asr",  t.asr),  ("Maghrib", t.maghrib), ("Isha", t.isha),
        ]
        for (name, date) in canonical where date > now { return (name, date) }
        // After Isha — next Fajr is +1 day
        return ("Fajr", t.fajr.addingTimeInterval(86_400))
    }

    var body: some View {
        Group {
            if let entry = nextEntry, let t = times {
                EditorialSection(title: "Next prayer",
                                 // The prayer's own symbol, so the section is
                                 // recognisable before the name is read.
                                 icon: Self.prayerIcons[entry.name] ?? "clock",
                                 trailing: "in \(countdown(to: entry.time))",
                                 trailingTint: .brand) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(entry.name)
                                .font(.appSerif(21, weight: .medium))
                            Text(Self.timeFmt.string(from: entry.time))
                                .font(.appSerif(17).monospacedDigit())
                                .foregroundStyle(Color(.label).opacity(0.5))
                        }

                        Text(restOfDay(t, excluding: entry.name))
                            .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                            .kerning(0.9)
                            .foregroundStyle(Color(.label).opacity(0.38))
                            .padding(.top, 11)
                    }
                }
            }
        }
        .onReceive(ticker) { now = $0 }
    }

    /// "FAJR 5:12 · DHUHR 1:24 · ASR 5:02 · ISHA 9:41" — the day at a glance,
    /// minus whichever prayer is already spelled out above.
    private func restOfDay(_ t: PrayerTimes, excluding: String) -> String {
        let canonical: [(String, Date)] = [
            ("Fajr", t.fajr), ("Dhuhr", t.dhuhr),
            ("Asr", t.asr), ("Maghrib", t.maghrib), ("Isha", t.isha),
        ]
        return canonical
            .filter { $0.0 != excluding }
            .map { "\($0.0.uppercased()) \(Self.compactFmt.string(from: $0.1))" }
            .joined(separator: " · ")
    }

    private func countdown(to date: Date) -> String {
        let secs = max(0, Int(date.timeIntervalSince(now)))
        let h = secs / 3600
        let m = (secs % 3600) / 60
        let s = secs % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    // Static: called every ticker tick while visible, so a per-call formatter
    // would churn.
    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; return f
    }()

    private static let compactFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm"; return f
    }()

    static let prayerIcons: [String: String] = [
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

/// Today's ayah set as scripture: Arabic at reading size, the translation in the
/// serif underneath, and the reference as metadata. The whole block opens the
/// reader; the play button is a sibling, because nested buttons swallow taps.
private struct VerseOfDaySection: View {
    let surahs: [Surah]
    let onPlay: (DailyVerse) -> Void

    @ObservedObject private var service = DailyVerseService.shared
    @AppStorage("arabicScript") private var arabicScript = ArabicScript.system.rawValue

    private func startIndex(_ v: DailyVerse) -> Int? {
        surahs.firstIndex { $0.number == v.surahNumber }
    }

    var body: some View {
        EditorialSection(title: "Verse of the day",
                         icon: "sun.horizon.fill",
                         iconTint: .orange,
                         trailing: service.verse.map { "\($0.surahName) \($0.ayahNumber)" }) {
            Group {
                if service.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else if let v = service.verse {
                    ZStack(alignment: .bottomTrailing) {
                        Group {
                            if let idx = startIndex(v) {
                                NavigationLink {
                                    SurahPageView(surahs: surahs, startIndex: idx, initialAyah: v.ayahNumber)
                                } label: { verse(v) }
                                    .buttonStyle(.plain)
                                    .hapticTap()
                            } else {
                                verse(v)
                            }
                        }

                        Button { onPlay(v) } label: {
                            PlayCircle(playing: false, size: 34)
                        }
                        .buttonStyle(CardButtonStyle(scale: 0.92))
                        .accessibilityLabel("Play verse of the day")
                    }
                }
            }
        }
    }

    private func verse(_ v: DailyVerse) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(v.arabic)
                .font(.appArabic(24))
                .lineSpacing(14)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .environment(\.layoutDirection, .rightToLeft)
                .padding(.top, 4)

            Text(v.translation)
                .font(.appSerif(17))
                .foregroundStyle(Color(.label).opacity(0.72))
                .lineSpacing(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(4)
                .padding(.top, 13)
                .padding(.trailing, 44)   // room for the play circle
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Due for review

private struct DueReviewSection: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        EditorialSection(title: "Review",
                         icon: "arrow.triangle.2.circlepath",
                         trailing: "\(count) due", trailingTint: .brand) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(count) ayah\(count == 1 ? "" : "s") ready to recall")
                    .font(.appSerif(17))
                    .foregroundStyle(Color(.label).opacity(0.72))
                Spacer(minLength: 8)
            }
            .padding(.bottom, 13)

            OutlineButton(label: "Start review", on: true, action: action)
        }
    }
}

// MARK: - In-progress rail

private struct InProgressRail: View {
    let numbers: [Int]
    let surahs: [Surah]

    private func surah(for n: Int) -> Surah? { surahs.first { $0.number == n } }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(numbers, id: \.self) { n in
                    if let s = surah(for: n),
                       let idx = surahs.firstIndex(where: { $0.number == n }) {
                        NavigationLink(destination: SurahPageView(surahs: surahs, startIndex: idx)) {
                            MemorizationStatusCard(
                                surah: s,
                                accent: .orange,
                                icon: "circle.dotted.and.circle",
                                subtitle: "\(s.numberOfAyahs) ayahs · \(s.englishNameTranslation)"
                            )
                        }
                        .buttonStyle(CardButtonStyle())
                        .hapticTap()
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - Progress summary

/// The whole-Quran picture, kept last because it's the slowest-moving number on
/// the page. Taps into the juz-filterable overview.
private struct ProgressSection: View {
    @ObservedObject var store: MemorizationStore
    let surahs: [Surah]
    @State private var showOverview = false

    private struct Stats {
        let memorized: Int
        let inProgress: Int
        let total: Int
    }

    private var stats: Stats {
        Stats(
            memorized:  surahs.filter { store.status(for: $0.number) == .memorized  }.count,
            inProgress: surahs.filter { store.status(for: $0.number) == .inProgress }.count,
            total:      surahs.count
        )
    }

    var body: some View {
        let st = stats
        let total = Double(max(st.total, 1))

        Button { Haptics.tap(); showOverview = true } label: {
            EditorialSection(title: "Memorization",
                             icon: "square.grid.3x3.fill",
                             iconTint: Color(.label).opacity(0.4),
                             trailing: "\(st.memorized)/\(st.total) surahs") {
                VStack(alignment: .leading, spacing: 0) {
                    GeometryReader { geo in
                        HStack(spacing: 0) {
                            Rectangle().fill(Color.brand)
                                .frame(width: geo.size.width * Double(st.memorized) / total)
                            Rectangle().fill(Color.orange)
                                .frame(width: geo.size.width * Double(st.inProgress) / total)
                            Rectangle().fill(Color(.label).opacity(0.16))
                        }
                    }
                    .frame(height: 1.5)

                    HStack(spacing: 16) {
                        StatDot(color: .brand,  value: st.memorized,  label: "Memorized")
                        StatDot(color: .orange, value: st.inProgress, label: "In progress")
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color(.label).opacity(0.3))
                    }
                    .padding(.top, 13)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showOverview) {
            MemorizationOverviewSheet()
        }
    }
}
