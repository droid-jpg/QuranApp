import SwiftUI
import Combine

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
    @State private var showReview = false
    @State private var activeDrill: PlayerDrill? = nil

    private var isPlayerActive: Bool { audioService.currentAyah != nil }

    // MARK: - Listening actions

    /// The resume hero's play button. When the saved session is already loaded in
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
            items.append(.init(id: "votd", label: "Verse of the day",
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
        case 5..<12:  return "Good Morning"
        case 12..<17: return "Good Afternoon"
        case 17..<21: return "Good Evening"
        default:       return "Good Night"
        }
    }

    /// A notable (non-recurring) Islamic event happening today or tomorrow, for the
    /// home chip. Recurring fasts (Mon/Thu, White Days) are excluded so the chip
    /// only surfaces genuine occasions. Holidays sort ahead of fasting days.
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

                    // ── Hero ──────────────────────────────────────────────
                    HomeHeroHeader(greeting: greeting, streak: StreakService.shared.currentStreak)
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                        .padding(.bottom, featuredEvent == nil ? 24 : 14)
                        .staggeredAppear(delay: 0.04)

                    // ── Holiday chip (today / tomorrow) ───────────────────
                    if let ev = featuredEvent {
                        HolidayChip(occurrence: ev.occ, isToday: ev.isToday)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                            .staggeredAppear(delay: 0.07)
                    }

                    // ── Resume listening (the 1b hero) ────────────────────
                    // Top slot, because "hear Qur'an" is the shortest path into
                    // the app and it used to cost a tab switch and 114 rows.
                    if let session = listening.session {
                        ResumeListeningCard(
                            session: session,
                            surahs: listVM.surahs,
                            audioService: audioService,
                            onToggle: { toggleResume(session) }
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                        .staggeredAppear(delay: 0.075)
                    }

                    // ── One-tap starts ────────────────────────────────────
                    if !quickStarts.isEmpty {
                        QuickStartRail(items: quickStarts)
                            .padding(.bottom, 22)
                            .staggeredAppear(delay: 0.09)
                    }

                    // ── Continue memorizing (current target) ──────────────
                    if let t = targetStore.target,
                       let idx = listVM.surahs.firstIndex(where: { $0.number == t.surah }) {
                        ContinueMemorizingCard(
                            target: t,
                            surahs: listVM.surahs,
                            startIndex: idx,
                            activeDrill: activeDrill,
                            onDrill: { runDrill($0, target: t) }
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                        .staggeredAppear(delay: 0.11)
                    }

                    // ── Next prayer ───────────────────────────────────────
                    if prayerService.fetchStatus == .ready {
                        NextPrayerCard(times: prayerService.prayerTimes)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 24)
                            .staggeredAppear(delay: 0.10)
                    }

                    // ── Verse of the Day (card carries its own title) ─────
                    if let verse = dailyVerse.verse,
                       let idx = listVM.surahs.firstIndex(where: { $0.number == verse.surahNumber }) {
                        NavigationLink {
                            SurahPageView(surahs: listVM.surahs, startIndex: idx, initialAyah: verse.ayahNumber)
                        } label: {
                            VerseOfDayCard(reservesPlaySlot: true)
                        }
                        .buttonStyle(CardButtonStyle())
                        .hapticTap()
                        // Sibling of the link, not a child: every card that has
                        // audio now has a play, and nested buttons don't work.
                        .overlay(alignment: .topTrailing) {
                            if let total = ayahCount(of: verse.surahNumber) {
                                Button {
                                    Haptics.tap()
                                    activeDrill = nil
                                    audioService.play(
                                        surah: verse.surahNumber, startAyah: verse.ayahNumber,
                                        loop: .listen(ayah: verse.ayahNumber, repeatCount: 1),
                                        totalAyahs: total, surahName: verse.surahName
                                    )
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 10, weight: .bold))
                                        Text("Play")
                                            .font(.system(size: 11, weight: .bold))
                                    }
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Color.orange.opacity(0.14), in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 11)
                                .padding(.trailing, 14)
                                .accessibilityLabel("Play verse of the day")
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                        .staggeredAppear(delay: 0.20)
                    } else {
                        VerseOfDayCard()
                            .padding(.horizontal, 16)
                            .padding(.bottom, 24)
                            .staggeredAppear(delay: 0.20)
                    }

                    // ── Due for Review ────────────────────────────────────
                    if srStore.dueCount() > 0 {
                        DueReviewCard(count: srStore.dueCount()) {
                            Haptics.tap()
                            showReview = true
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                        .staggeredAppear(delay: 0.22)
                    }

                    // ── Other surahs in progress ──────────────────────────
                    // The active target already has the hero card above, so it
                    // is excluded here — this row is the rest of the backlog.
                    let otherInProgress = memorizationStore.inProgressNumbers
                        .filter { $0 != targetStore.target?.surah }
                    if !otherInProgress.isEmpty && !listVM.surahs.isEmpty {
                        SectionHeader(title: "In Progress", systemImage: "circle.dotted.and.circle", tint: .orange)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 10)
                            .staggeredAppear(delay: 0.25)
                        ContinueMemorizingRow(
                            numbers: otherInProgress,
                            surahs: listVM.surahs
                        )
                        .padding(.bottom, 24)
                        .staggeredAppear(delay: 0.28)
                    }

                    // ── Progress summary ──────────────────────────────────
                    HomeProgressCard(store: memorizationStore, surahs: listVM.surahs)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .staggeredAppear(delay: 0.38)
                }
                .padding(.bottom, 20)
            }
            .background(alignment: .top) {
                HomeAurora()
                    .ignoresSafeArea(edges: .top)
            }
            // "The Holy Quran" is the Quran tab's title; the dashboard carries
            // the app name so the two tabs read as distinct places.
            .navigationTitle("Al-Faatiha")
            .navigationBarTitleDisplayMode(.large)
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

// MARK: - Aurora backdrop

/// A whisper of brand color behind the large title and hero header. Static
/// (content scrolls over it) and masked to fade out well before mid-screen so
/// the dashboard below stays on the plain system background.
private struct HomeAurora: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0],   [0.5, 0],   [1, 0],
                [0, 0.4], [0.6, 0.5], [1, 0.4],
                [0, 1],   [0.5, 1],   [1, 1],
            ],
            colors: [
                .brand, .mint, .brand,
                .mint,  .brand, .cyan,
                .clear, .clear, .clear,
            ]
        )
        .opacity(scheme == .dark ? 0.14 : 0.09)
        .frame(height: 300)
        .mask(
            LinearGradient(colors: [.black, .black, .clear],
                           startPoint: .top, endPoint: .bottom)
        )
        .allowsHitTesting(false)
    }
}

// MARK: - Due for review card

private struct DueReviewCard: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.brand.opacity(0.12))
                        .frame(width: 52, height: 52)
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.brand)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Due for Review")
                        .font(.title3.bold())
                    Text("\(count) ayah\(count == 1 ? "" : "s") ready")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("Start")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(LinearGradient.brandHero)
                    .clipShape(Capsule())
            }
            .padding(16)
            .tintedCard(.brand)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Continue memorizing (current target)

/// The surah + ayah the user is actively memorizing. The header opens the reader
/// at the working ayah; underneath, the three acquisition drills — Listen, Repeat,
/// Chain — start straight from the dashboard in the same language the reader's
/// player uses, so a drill is one tap from opening the app.
///
/// The filled hero treatment moved to the resume card above; this one is tinted so
/// the dashboard has exactly one filled card.
private struct ContinueMemorizingCard: View {
    let target: MemorizationTarget
    let surahs: [Surah]
    let startIndex: Int
    let activeDrill: PlayerDrill?
    let onDrill: (PlayerDrill) -> Void

    var body: some View {
        VStack(spacing: 14) {
            NavigationLink {
                SurahPageView(surahs: surahs, startIndex: startIndex, initialAyah: target.workingAyah)
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 7) {
                        Image(systemName: "graduationcap.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.brand)
                        Text(target.isComplete
                             ? "Memorized · \(target.surahName)"
                             : "Memorizing · \(target.surahName) \(target.workingAyah)")
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text("\(Int((target.fraction * 100).rounded()))%")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption2.bold())
                            .foregroundStyle(.tertiary)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(.tertiarySystemFill))
                            Capsule().fill(LinearGradient.brandHero)
                                .frame(width: max(0, geo.size.width * target.fraction))
                        }
                    }
                    .frame(height: 5)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hapticTap()

            HStack(spacing: 8) {
                DrillButton(icon: "repeat", label: "Listen",
                            on: activeDrill == .listen) { onDrill(.listen) }
                DrillButton(icon: "pause.circle", label: "Repeat",
                            on: activeDrill == .repeatAfter) { onDrill(.repeatAfter) }
                DrillButton(icon: "link", label: "Chain",
                            on: activeDrill == .chain) { onDrill(.chain) }
            }
        }
        .padding(16)
        .tintedCard(.brand)
    }
}

// MARK: - Hero header

private struct HomeHeroHeader: View {
    let greeting: String
    let streak: Int

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMMM d"; return f
    }()

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.title.bold())
                    .fontDesign(.serif)
                Text(Self.dayFmt.string(from: Date()))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if streak > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                    Text("\(streak)")
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.orange.opacity(0.25), lineWidth: 1))
                .accessibilityLabel("\(streak) day streak")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Holiday chip

private struct HolidayChip: View {
    let occurrence: EventOccurrence
    let isToday: Bool

    var body: some View {
        NavigationLink {
            IslamicCalendarView()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: occurrence.event.kind.icon)
                    .font(.caption.bold())
                    .foregroundStyle(occurrence.event.kind.color)

                Text(occurrence.event.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(isToday ? "Today" : "Tomorrow")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(occurrence.event.kind.color, in: Capsule())

                Image(systemName: "chevron.right")
                    .font(.caption2.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(occurrence.event.kind.color.opacity(0.12), in: Capsule())
            .overlay(
                Capsule().strokeBorder(occurrence.event.kind.color.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .hapticTap()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Next prayer card

struct NextPrayerCard: View {
    let times: PrayerTimes?
    @State private var now = Date()
    @State private var expanded = false
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private static let prayerIcons: [String: String] = [
        "Fajr":     "moon.stars.fill",
        "Sunrise":  "sunrise.fill",
        "Dhuhr":    "sun.max.fill",
        "Asr":      "sun.horizon.fill",
        "Maghrib":  "sunset.fill",
        "Isha":     "moon.fill",
        "Midnight": "moon.zzz.fill",
    ]

    private var nextEntry: (name: String, icon: String, time: Date)? {
        guard let t = times else { return nil }
        let canonical: [(String, Date)] = [
            ("Fajr", t.fajr), ("Dhuhr", t.dhuhr),
            ("Asr",  t.asr),  ("Maghrib", t.maghrib), ("Isha", t.isha),
        ]
        for (name, date) in canonical where date > now {
            return (name, Self.prayerIcons[name] ?? "clock", date)
        }
        // After Isha — next Fajr is +1 day
        let tomorrowFajr = t.fajr.addingTimeInterval(86_400)
        return ("Fajr", "moon.stars.fill", tomorrowFajr)
    }

    var body: some View {
        Group {
            if let entry = nextEntry {
                VStack(spacing: 0) {
                    // Header (always visible) — tap to expand the full day
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.brand.opacity(0.12))
                                .frame(width: 52, height: 52)
                            Image(systemName: entry.icon)
                                .font(.system(size: 22))
                                .foregroundStyle(.brand)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Next Prayer")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(entry.name)
                                .font(.title3.bold())
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(countdown(to: entry.time))
                                .font(.title3.bold().monospacedDigit())
                                .foregroundStyle(.brand)
                            Text(timeString(entry.time))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Image(systemName: "chevron.down")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                            .padding(.leading, 2)
                    }

                    if expanded, let t = times {
                        Divider()
                            .padding(.top, 14)
                            .padding(.bottom, 2)
                        ForEach(t.named, id: \.name) { item in
                            prayerRow(name: item.name, time: item.time, isNext: item.name == entry.name)
                        }
                    }
                }
                .padding(16)
                .tintedCard(.brand)
                .contentShape(Rectangle())
                .onTapGesture {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        expanded.toggle()
                    }
                }
            }
        }
        .onReceive(ticker) { now = $0 }
    }

    @ViewBuilder
    private func prayerRow(name: String, time: Date, isNext: Bool) -> some View {
        let isPast = time < now
        HStack(spacing: 12) {
            Image(systemName: Self.prayerIcons[name] ?? "clock")
                .font(.footnote)
                .foregroundStyle(isNext ? .brand : .secondary)
                .frame(width: 20)
            Text(name)
                .font(.subheadline)
                .fontWeight(isNext ? .semibold : .regular)
                .foregroundStyle(isNext ? .brand : .primary)
            Spacer()
            Text(timeString(time))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(isNext ? .brand : .secondary)
        }
        // Dim prayers that have already passed (the upcoming one stays full strength).
        .opacity(isPast && !isNext ? 0.45 : 1)
        .padding(.vertical, 7)
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

    // Static: this is called every ticker tick (once per second while visible),
    // so allocating a DateFormatter per call would churn.
    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; return f
    }()

    private func timeString(_ date: Date) -> String {
        Self.timeFmt.string(from: date)
    }
}

// MARK: - Continue Memorizing row

private struct ContinueMemorizingRow: View {
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
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Progress summary card (global; taps into the juz-filterable overview)

private struct HomeProgressCard: View {
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
            VStack(spacing: 12) {
                // Header row
                HStack {
                    Text("Memorization Progress")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(st.memorized)/\(st.total) surahs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption2.bold())
                        .foregroundStyle(.tertiary)
                }

                // Progress bar
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        Rectangle().fill(Color.green)
                            .frame(width: geo.size.width * Double(st.memorized) / total)
                        Rectangle().fill(Color.orange)
                            .frame(width: geo.size.width * Double(st.inProgress) / total)
                        Rectangle().fill(Color(.tertiarySystemFill))
                    }
                }
                .frame(height: 6)
                .clipShape(Capsule())

                // Legend
                HStack(spacing: 16) {
                    StatDot(color: .green,  value: st.memorized,  label: "Memorized")
                    StatDot(color: .orange, value: st.inProgress, label: "In Progress")
                }
            }
            .padding(16)
            .tintedCard(Color(.systemGray), fillOpacity: 0.04, strokeOpacity: 0.12)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showOverview) {
            MemorizationOverviewSheet()
        }
    }
}

