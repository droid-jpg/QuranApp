import SwiftUI

/// The launch screen: carry on listening in one tap, the next prayer, one verse.
struct TodayView: View {
    @Environment(Player.self) private var player
    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sectionGap) {
                header.arrives(0)
                ContinueCard().arrives(1)
                PrayerCard().arrives(2)
                VerseCard().arrives(3)
                if player.recents.count > 1 {
                    EditorialSection(title: "Recent") {
                        VStack(spacing: 0) {
                            ForEach(player.recents.dropFirst().prefix(4)) { recent in
                                if let surah = QuranText.shared.surah(recent.surah) {
                                    SurahRow(surah: surah, subtitle: Self.subtitle(for: recent), recent: recent)
                                    Hairline()
                                }
                            }
                        }
                    }
                    .arrives(4)
                }
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.xl)
        }
        .background(Palette.background)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(Self.greeting)
                .font(TypeScale.display)
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Button {
                router.open(.calendar)
            } label: {
                HStack(spacing: Spacing.xxs) {
                    Text(Self.dateLine)
                    Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                }
                .font(TypeScale.secondary)
                .foregroundStyle(Palette.textSecondary)
                .frame(minHeight: MinSize.hitTarget, alignment: .top)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
        }
    }

    static func subtitle(for recent: Player.Recent) -> String {
        if let range = recent.repeatRange { return "Repeating \(range.label.lowercased())" }
        return "Ayah \(recent.ayah)"
    }

    private static var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 4..<12:  "Good morning"
        case 12..<17: "Good afternoon"
        default:      "Good evening"
        }
    }

    private static var dateLine: String {
        let now = Date()
        var hijri = Date.FormatStyle(date: .abbreviated, time: .omitted)
        hijri.calendar = Calendar(identifier: .islamicUmmAlQura)
        return "\(now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) · \(now.formatted(hijri.day().month(.wide)))"
    }
}

// MARK: - Continue listening

/// Where listening stopped, with one button that carries on from there. On a fresh
/// install it offers a few surahs to start with instead.
private struct ContinueCard: View {
    @Environment(Player.self) private var player
    @Environment(AppRouter.self) private var router

    var body: some View {
        if let surah = player.surah, player.hasSession {
            EditorialSection(title: player.isPlaying ? "Now playing" : "Continue listening") {
                HStack(spacing: Spacing.md) {
                    Button {
                        router.openReader(surah: surah.number, ayah: player.ayah)
                    } label: {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(surah.englishName)
                                .font(TypeScale.title)
                                .foregroundStyle(Palette.textPrimary)
                                .contentTransition(.opacity)
                            Text(player.statusLine)
                                .font(TypeScale.secondary)
                                .foregroundStyle(Palette.textSecondary)
                                .multilineTextAlignment(.leading)
                                .contentTransition(.numericText())
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .animation(Motion.standard, value: player.statusLine)
                        .animation(Motion.standard, value: surah)
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityHint("Opens the reader")

                    PlayPauseButton(size: 22, tint: Palette.onAccent) { player.toggle() }
                        .frame(width: MinSize.primaryPlay, height: MinSize.primaryPlay)
                        .background(Circle().fill(Color.brand))
                }
                .padding(.top, Spacing.xs)
            }
        } else {
            EditorialSection(title: "Start listening") {
                VStack(spacing: 0) {
                    ForEach([1, 36, 18, 67], id: \.self) { number in
                        if let surah = QuranText.shared.surah(number) {
                            SurahRow(surah: surah)
                            Hairline()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Next prayer

private struct PrayerCard: View {
    @EnvironmentObject private var prayer: PrayerTimesService
    @Environment(AppRouter.self) private var router

    var body: some View {
        EditorialSection(title: "Next prayer") {
            Button {
                switch prayer.fetchStatus {
                case .notDetermined, .denied: prayer.allowLocationAccess()
                case .failed: prayer.requestAndFetch()
                default: router.open(.prayerTimes)
                }
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    content
                    Spacer(minLength: Spacing.xs)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Palette.textTertiary)
                }
                .padding(.top, Spacing.xs)
                .frame(minHeight: MinSize.hitTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
        }
    }

    @ViewBuilder private var content: some View {
        if prayer.hasTodaysTimes, let times = prayer.prayerTimes {
            // Re-evaluated each minute, so the countdown and the prayer roll over.
            TimelineView(.everyMinute) { context in
                let next = times.upcomingPrayer(at: context.date)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                        Text(next.name)
                            .font(TypeScale.heading)
                            .foregroundStyle(Palette.textPrimary)
                        Text(next.date.formatted(date: .omitted, time: .shortened))
                            .font(TypeScale.heading.monospacedDigit())
                            .foregroundStyle(.brand)
                    }
                    Text("in \(PrayerCountdown.text(to: next.date, from: context.date))")
                        .font(TypeScale.secondary)
                        .foregroundStyle(Palette.textSecondary)
                        .contentTransition(.numericText(countsDown: true))
                }
                .animation(Motion.standard, value: next.date)
                .animation(Motion.standard, value: Int(context.date.timeIntervalSinceReferenceDate / 60))
            }
        } else {
            Text(message)
                .font(TypeScale.body)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.leading)
        }
    }

    private var message: String {
        switch prayer.fetchStatus {
        case .fetching:               "Getting prayer times…"
        case .failed:                 "Couldn't load prayer times. Tap to try again"
        case .notDetermined, .denied: "Allow location to see prayer times"
        case .ready:                  "Getting prayer times…"
        }
    }
}

// MARK: - Verse of the day

/// One of thirty ayahs, chosen by the day of the year and read from the bundled
/// text, so it is there instantly and offline.
private struct VerseCard: View {
    @Environment(Player.self) private var player
    @Environment(AppRouter.self) private var router

    private static let schedule: [(Int, Int)] = [
        (1,1),(2,255),(2,286),(3,173),(4,36),(6,162),(7,23),(9,51),(13,28),(14,7),
        (15,9),(17,80),(18,10),(20,25),(23,97),(24,35),(27,62),(28,24),(29,69),(33,41),
        (39,53),(40,60),(50,16),(51,56),(55,13),(57,4),(59,23),(67,1),(93,5),(94,5)
    ]

    private var verse: (surah: Surah, ayah: Ayah)? {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        let (s, a) = Self.schedule[day % Self.schedule.count]
        guard let surah = QuranText.shared.surah(s), let ayah = QuranText.shared.ayah(s, a) else { return nil }
        return (surah, ayah)
    }

    var body: some View {
        if let verse {
            EditorialSection(title: "Verse of the day", trailing: "\(verse.surah.englishName) \(verse.ayah.numberInSurah)") {
                Button {
                    router.openReader(surah: verse.surah.number, ayah: verse.ayah.numberInSurah)
                } label: {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text(verse.ayah.arabic)
                            .font(.appArabic(24))
                            .lineSpacing(10)
                            .foregroundStyle(Palette.textPrimary)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .environment(\.layoutDirection, .rightToLeft)
                        Text(verse.ayah.translation)
                            .font(.appSerif(17))
                            .foregroundStyle(Palette.textPrimary)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.top, Spacing.xs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                .accessibilityHint("Opens the reader at this ayah")

                OutlineChip(label: "Play from here", icon: "play.fill") {
                    Haptics.impact(.light)
                    player.play(verse.surah, from: verse.ayah.numberInSurah)
                }
                .padding(.top, Spacing.xxs)
            }
        }
    }
}
