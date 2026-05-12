import SwiftUI
import Combine

struct SurahListView: View {
    @StateObject private var viewModel = SurahListViewModel()
    @EnvironmentObject private var store: MemorizationStore
    @EnvironmentObject private var prayerService: PrayerTimesService
    @State private var showJuzBrowser   = false
    @State private var showQuranSearch  = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.surahs.isEmpty {
                    ProgressView("Loading Surahs…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = viewModel.error, viewModel.surahs.isEmpty {
                    ErrorView(message: err) { Task { await viewModel.load() } }
                } else {
                    List {
                        // Verse of the Day
                        Section {
                            VerseOfDayCard()
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                        }

                        // Prayer times strip
                        if prayerService.fetchStatus == .ready {
                            Section {
                                PrayerTimesStrip(times: prayerService.prayerTimes)
                                    .listRowInsets(EdgeInsets())
                                    .listRowSeparator(.hidden)
                            }
                        }

                        // In-progress cards — only when there are some
                        if !store.inProgressNumbers.isEmpty {
                            Section {
                                InProgressCards(
                                    numbers: store.inProgressNumbers,
                                    surahs: viewModel.surahs
                                )
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                            } header: {
                                Text("Continue Memorizing")
                                    .font(.subheadline.bold())
                                    .textCase(nil)
                                    .foregroundStyle(.primary)
                            }
                        }

                        // Full surah list
                        Section {
                            ForEach(viewModel.filtered) { surah in
                                NavigationLink(destination: SurahDetailView(surah: surah)) {
                                    SurahRowView(surah: surah, status: store.status(for: surah.number))
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .searchable(text: $viewModel.searchText, prompt: "Search surah…")
                }
            }
            .navigationTitle("The Holy Quran")
            .navigationBarTitleDisplayMode(.large)
            .task { await viewModel.load() }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showJuzBrowser = true
                    } label: {
                        Image(systemName: "list.number")
                            .foregroundStyle(.primary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    StreakBadge()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showQuranSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                }
            }
            .sheet(isPresented: $showJuzBrowser) {
                JuzBrowserView(surahs: viewModel.surahs)
            }
            .sheet(isPresented: $showQuranSearch) {
                QuranSearchView()
            }
        }
    }
}

// MARK: - Prayer times strip

struct PrayerTimesStrip: View {
    let times: PrayerTimes?
    @State private var now = Date()
    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private let prayers: [(String, String)] = [
        ("Fajr",    "moon.stars.fill"),
        ("Dhuhr",   "sun.max.fill"),
        ("Asr",     "sun.horizon.fill"),
        ("Maghrib", "sunset.fill"),
        ("Isha",    "moon.fill"),
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(prayers, id: \.0) { (name, icon) in
                    if let time = prayerTime(named: name) {
                        PrayerCell(
                            name: name,
                            icon: icon,
                            time: time,
                            isNext: isNext(name: name),
                            now: now
                        )
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Color(.secondarySystemBackground))
        .onReceive(ticker) { now = $0 }
    }

    private func prayerTime(named name: String) -> Date? {
        guard let times else { return nil }
        switch name {
        case "Fajr":    return times.fajr
        case "Dhuhr":   return times.dhuhr
        case "Asr":     return times.asr
        case "Maghrib": return times.maghrib
        case "Isha":    return times.isha
        default:        return nil
        }
    }

    private func isNext(name: String) -> Bool {
        guard let times else { return false }
        return times.nextPrayer == name
    }
}

private struct PrayerCell: View {
    let name: String
    let icon: String
    let time: Date
    let isNext: Bool
    let now: Date

    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; return f
    }()

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: isNext ? .semibold : .regular))
                .foregroundStyle(isNext ? .teal : .secondary)

            Text(name)
                .font(.system(size: 11, weight: isNext ? .semibold : .regular))
                .foregroundStyle(isNext ? .teal : .secondary)

            Text(Self.fmt.string(from: time))
                .font(.system(size: 12, weight: isNext ? .bold : .regular).monospacedDigit())
                .foregroundStyle(isNext ? .primary : .secondary)

            if isNext {
                Text(countdown(to: time))
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.teal)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isNext ? Color.teal.opacity(0.08) : Color.clear)
        )
        .animation(.easeInOut(duration: 0.3), value: isNext)
    }

    private func countdown(to date: Date) -> String {
        let secs = max(0, date.timeIntervalSince(now))
        let h = Int(secs) / 3600
        let m = (Int(secs) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "now"
    }
}

// MARK: - In-progress cards

struct InProgressCards: View {
    let numbers: [Int]
    let surahs: [Surah]

    private func surah(for n: Int) -> Surah? { surahs.first { $0.number == n } }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(numbers, id: \.self) { n in
                    if let s = surah(for: n) {
                        NavigationLink(destination: SurahDetailView(surah: s)) {
                            InProgressCard(surah: s)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }
}

struct InProgressCard: View {
    let surah: Surah

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "circle.dotted.and.circle")
                    .foregroundStyle(.orange)
                    .font(.subheadline)
                Spacer()
                Text("\(surah.number)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color.orange)
                    .clipShape(Circle())
            }

            Spacer()

            Text(surah.name)
                .font(.system(size: 28, weight: .regular))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .environment(\.layoutDirection, .rightToLeft)

            VStack(alignment: .leading, spacing: 2) {
                Text(surah.englishName)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                Text("\(surah.numberOfAyahs) ayahs · \(surah.englishNameTranslation)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(width: 190, height: 140)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.orange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                )
        )
    }
}

// MARK: - Row

struct SurahRowView: View {
    let surah: Surah
    let status: MemorizationStatus

    var body: some View {
        HStack(spacing: 16) {
            NumberBadge(number: surah.number)

            VStack(alignment: .leading, spacing: 2) {
                Text(surah.englishName)
                    .font(.system(.body, weight: .semibold))
                Text(surah.englishNameTranslation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(surah.name)
                    .font(.system(size: 20))
                    .environment(\.layoutDirection, .rightToLeft)
                if status != .notStarted {
                    Image(systemName: status.icon)
                        .font(.caption)
                        .foregroundStyle(status.color)
                } else {
                    Text("\(surah.numberOfAyahs) ayahs")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct NumberBadge: View {
    let number: Int

    var body: some View {
        ZStack {
            Image(systemName: "seal")
                .font(.system(size: 38))
                .foregroundStyle(.teal.opacity(0.18))
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.teal)
        }
        .frame(width: 44, height: 44)
    }
}

// MARK: - Verse of the Day

struct VerseOfDayCard: View {
    @ObservedObject private var service = DailyVerseService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Label("Verse of the Day", systemImage: "sun.horizon.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                Spacer()
                if let v = service.verse {
                    Text("\(v.surahName) \(v.ayahNumber)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            if service.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else if let v = service.verse {
                VStack(alignment: .trailing, spacing: 10) {
                    Text(v.arabic)
                        .font(.system(size: 22, weight: .regular))
                        .multilineTextAlignment(.trailing)
                        .lineSpacing(8)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .environment(\.layoutDirection, .rightToLeft)

                    Text(v.translation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 0)
                .fill(Color.orange.opacity(0.05))
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.orange.opacity(0.5))
                .frame(width: 3)
        }
    }
}

// MARK: - Streak badge

private struct StreakBadge: View {
    private let streak = StreakService.shared.currentStreak
    var body: some View {
        if streak > 1 {
            HStack(spacing: 3) {
                Text("🔥")
                    .font(.subheadline)
                Text("\(streak)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.orange)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.12))
            .clipShape(Capsule())
        }
    }
}
