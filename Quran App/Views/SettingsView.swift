import SwiftUI

/// Settings, rebuilt as ruled blocks rather than a grouped `Form`. Same settings,
/// same order, but the page now reads like the rest of the app: hairlines, small-
/// caps eyebrows with a glyph, and serif labels.
///
/// Presented as a NavigationLink destination inside MoreView's NavigationStack —
/// it intentionally has no NavigationStack of its own.
struct SettingsView: View {
    @AppStorage("colorSchemePreference") private var colorSchemeRaw = "system"
    @AppStorage("selectedReciterId")     private var selectedReciterId = 7
    @AppStorage("selectedTranslationId") private var translationId = Translation.fallbackId
    @AppStorage("notifEnabled")          private var notifEnabled = false
    @AppStorage("notifFajr")             private var notifFajr = true
    @AppStorage("notifDhuhr")            private var notifDhuhr = true
    @AppStorage("notifAsr")              private var notifAsr = true
    @AppStorage("notifMaghrib")          private var notifMaghrib = true
    @AppStorage("notifIsha")             private var notifIsha = true
    @AppStorage("notifSunrise")          private var notifSunrise = true
    @AppStorage("notifMidnight")         private var notifMidnight = true
    @AppStorage("notifPreReminder")      private var notifPreReminder = 10
    @AppStorage("liveActivityEnabled")   private var liveActivityEnabled = false
    @AppStorage("prayerCalcMethod")      private var prayerCalcMethod = 2
    @AppStorage("prayerAsrSchool")       private var prayerAsrSchool = 0

    @AppStorage("arabicFontSize")          private var arabicFontSize: Double = 26
    @AppStorage("translationFontSize")     private var translationFontSize: Double = 17
    @AppStorage("transliterationFontSize") private var transliterationFontSize: Double = 13
    @AppStorage("readingFace")             private var readingFace = ReadingFace.newYork.rawValue

    @AppStorage("memoReminderEnabled") private var memoReminderEnabled = false
    @AppStorage("memoReminderHour")    private var memoReminderHour = 19
    @AppStorage("memoReminderMinute")  private var memoReminderMinute = 0

    @AppStorage("fillBlankUseTransliteration") private var fillBlankUseTransliteration = false
    @AppStorage("memorizationCardScript")              private var cardScript: MemorizationCardScript = .arabic
    @AppStorage("memorizationArabicFontSize")          private var cardArabicFontSize: Double = 30
    @AppStorage("memorizationTransliterationFontSize") private var cardTransliterationFontSize: Double = 18

    @EnvironmentObject private var prayerService: PrayerTimesService
    @State private var theme = AppTheme.current
    @State private var showReadingType = false

    /// Picking a language selects that language's first translation. The getter
    /// derives the current language from the selected edition, so no extra state.
    private var languageBinding: Binding<String> {
        Binding(
            get: { Translation.selected.language },
            set: { lang in
                if let first = Translation.translations(in: lang).first {
                    translationId = first.id
                }
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {

                // ── Appearance ────────────────────────────────────────────
                EditorialSection(title: "Appearance", icon: "circle.lefthalf.filled") {
                    EditorialSegmented(
                        selection: $colorSchemeRaw,
                        options: [.init("system", "System"), .init("light", "Light"), .init("dark", "Dark")]
                    )
                }

                // ── Colour theme ──────────────────────────────────────────
                EditorialSection(title: "Colour theme", icon: "circle.hexagongrid.fill",
                                 trailing: theme.displayName) {
                    ThemePicker(selection: $theme)
                        .padding(.top, 4)
                    Footnote("The accent used across the app, the reader, and your widgets. \(theme.caption).")
                }

                // ── Reading ───────────────────────────────────────────────
                EditorialSection(title: "Reading", icon: "textformat.size") {
                    EditorialNavRow(title: "Reading type",
                                    value: ReadingFace.current.displayName) {
                        Haptics.tap()
                        showReadingType = true
                    }
                    .padding(.bottom, 16)

                    EditorialSpecimenSlider(
                        label: "Arabic", value: $arabicFontSize, range: 18...44,
                        sample: "بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ", rightToLeft: true
                    )
                    .padding(.bottom, 16)

                    EditorialSpecimenSlider(
                        label: "Translation", value: $translationFontSize, range: 13...26,
                        sample: "In the name of Allah, the Most Gracious, the Most Merciful."
                    )
                    .padding(.bottom, 16)

                    EditorialSpecimenSlider(
                        label: "Translit.", value: $transliterationFontSize, range: 11...22,
                        sample: "Bismi Allāhi r-raḥmāni r-raḥīm", italic: true
                    )

                    Footnote("Applies to the surah reading view.")
                }

                // ── Translation ───────────────────────────────────────────
                EditorialSection(title: "Translation", icon: "character.book.closed.fill") {
                    EditorialMenuRow(
                        title: "Language", selection: languageBinding,
                        options: Translation.languages.map { .init($0, $0) }
                    )
                    Hairline().padding(.vertical, 13)
                    EditorialMenuRow(
                        title: "Edition", selection: $translationId,
                        options: Translation.translations(in: Translation.selected.language)
                            .map { .init($0.id, $0.name) }
                    )
                    Footnote("Sets the translation shown beneath each ayah.")
                }

                // ── Reciter ───────────────────────────────────────────────
                EditorialSection(title: "Reciter", icon: "person.wave.2.fill") {
                    EditorialMenuRow(
                        title: "Voice", selection: $selectedReciterId,
                        options: Reciter.all.map { .init($0.id, $0.name) }
                    )
                    Footnote("Changes apply when you next play an ayah.")
                }

                // ── Memorization cards ────────────────────────────────────
                EditorialSection(title: "Memorization cards", icon: "rectangle.on.rectangle.angled") {
                    EditorialMenuRow(
                        title: "Card display", selection: $cardScript,
                        options: MemorizationCardScript.allCases.map { .init($0, $0.title) }
                    )
                    if cardScript.showsArabic {
                        Hairline().padding(.vertical, 13)
                        EditorialSpecimenSlider(
                            label: "Arabic", value: $cardArabicFontSize, range: 22...46,
                            sample: "بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ", rightToLeft: true
                        )
                    }
                    if cardScript.showsTransliteration {
                        Hairline().padding(.vertical, 13)
                        EditorialSpecimenSlider(
                            label: "Translit.", value: $cardTransliterationFontSize, range: 13...30,
                            sample: "Bismi Allāhi r-raḥmāni r-raḥīm", italic: true
                        )
                    }
                    Footnote("What the ayah shows on review cards — Arabic, transliteration, or both — and their sizes.")
                }

                // ── Memorization ──────────────────────────────────────────
                EditorialSection(title: "Memorization", icon: "graduationcap.fill") {
                    EditorialMenuRow(
                        title: "Fill-in-the-blank hint", selection: $fillBlankUseTransliteration,
                        options: [.init(false, "Translation"), .init(true, "Transliteration")]
                    )
                    Footnote("What's shown beneath the ayah when you reveal a fill-in-the-blank card.")
                }

                // ── Memorization reminder ─────────────────────────────────
                EditorialSection(title: "Memorization reminder", icon: "bell.badge.fill") {
                    EditorialToggle(title: "Daily reminder", isOn: $memoReminderEnabled)
                        .onChange(of: memoReminderEnabled) { rescheduleMemoReminder() }

                    if memoReminderEnabled {
                        Hairline().padding(.vertical, 13)
                        HStack {
                            Text("Time")
                                .font(.appSerif(17))
                            Spacer()
                            DatePicker("", selection: reminderTime, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .onChange(of: memoReminderHour) { rescheduleMemoReminder() }
                                .onChange(of: memoReminderMinute) { rescheduleMemoReminder() }
                        }
                    }
                    Footnote("A daily nudge to continue memorizing the ayah you're working on.")
                }

                // ── Prayer calculation ────────────────────────────────────
                EditorialSection(title: "Prayer calculation", icon: "location.circle.fill") {
                    EditorialMenuRow(
                        title: "Method", selection: $prayerCalcMethod,
                        options: PrayerCalcMethod.all.map { .init($0.id, $0.name) }
                    )
                    .onChange(of: prayerCalcMethod) { prayerService.refetchForSettingsChange() }

                    Hairline().padding(.vertical, 13)

                    EditorialMenuRow(
                        title: "Asr (juristic)", selection: $prayerAsrSchool,
                        options: [.init(0, "Standard"), .init(1, "Hanafi")]
                    )
                    .onChange(of: prayerAsrSchool) { prayerService.refetchForSettingsChange() }

                    Footnote("The twilight angles and Asr method used to compute your local prayer times.")
                }

                // ── Prayer notifications ──────────────────────────────────
                EditorialSection(title: "Prayer notifications", icon: "bell.fill") {
                    EditorialToggle(title: "Enable notifications", isOn: $notifEnabled)
                        .onChange(of: notifEnabled) { reschedule() }

                    if notifEnabled {
                        Hairline().padding(.vertical, 13)
                        EditorialToggle(title: "Live Activity", caption: "10 min countdown",
                                        isOn: $liveActivityEnabled)
                            .onChange(of: liveActivityEnabled) { reschedule() }

                        Hairline().padding(.vertical, 13)
                        Eyebrow("Which ones").padding(.bottom, 11)

                        prayerToggle("Fajr", $notifFajr)
                        prayerToggle("Sunrise", $notifSunrise)
                        prayerToggle("Dhuhr", $notifDhuhr)
                        prayerToggle("Asr", $notifAsr)
                        prayerToggle("Maghrib", $notifMaghrib)
                        prayerToggle("Isha", $notifIsha)
                        prayerToggle("Midnight", $notifMidnight)

                        Hairline().padding(.vertical, 13)
                        EditorialMenuRow(
                            title: "Pre-prayer reminder", selection: $notifPreReminder,
                            options: [.init(0, "None"), .init(5, "5 min"), .init(10, "10 min"),
                                      .init(15, "15 min"), .init(30, "30 min")]
                        )
                        .onChange(of: notifPreReminder) { reschedule() }

                        Footnote("Notifications use your local prayer times based on location.")
                    }
                }

                // ── About ─────────────────────────────────────────────────
                EditorialSection(title: "About", icon: "info.circle.fill") {
                    EditorialValueRow(title: "Arabic text", value: "Tanzil Project · tanzil.net")
                    Hairline().padding(.vertical, 13)
                    EditorialValueRow(title: "Data source", value: "alquran.cloud")
                    Hairline().padding(.vertical, 13)
                    EditorialValueRow(title: "Audio source", value: "everyayah.com")
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showReadingType) {
            ReadingTypeSheet()
        }
        .task {
            if notifEnabled {
                _ = await NotificationService.shared.requestPermission()
            }
        }
    }

    @ViewBuilder
    private func prayerToggle(_ name: String, _ binding: Binding<Bool>) -> some View {
        HStack(spacing: 11) {
            Image(systemName: NextPrayerSection.prayerIcons[name] ?? "clock")
                .font(.system(size: 12))
                .foregroundStyle(binding.wrappedValue ? Color.brand : Color(.label).opacity(0.3))
                .frame(width: 18)
            Text(name)
                .font(.appSerif(16))
            Spacer(minLength: 8)
            Toggle("", isOn: binding)
                .labelsHidden()
                .tint(.brand)
                .scaleEffect(0.85)
                .frame(width: 46, alignment: .trailing)
        }
        .padding(.bottom, 4)
        .onChange(of: binding.wrappedValue) { reschedule() }
        .accessibilityElement(children: .combine)
    }

    private func reschedule() {
        Task {
            if notifEnabled {
                _ = await NotificationService.shared.requestPermission()
            }
            prayerService.rescheduleNotifications()
        }
    }

    /// DatePicker works in `Date`; the reminder is stored as hour/minute so it's
    /// timezone-agnostic. This bridges the two.
    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                var c = DateComponents(); c.hour = memoReminderHour; c.minute = memoReminderMinute
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { newDate in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                memoReminderHour = c.hour ?? 19
                memoReminderMinute = c.minute ?? 0
            }
        )
    }

    private func rescheduleMemoReminder() {
        Task {
            if memoReminderEnabled {
                _ = await NotificationService.shared.requestPermission()
            }
            NotificationService.shared.scheduleMemorizationReminder()
        }
    }
}

// MARK: - Footnote

/// The explanatory line that used to be a Form section footer.
struct Footnote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.appSerif(13.5, italic: true))
            .foregroundStyle(Color(.label).opacity(0.42))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
    }
}

// MARK: - Theme picker

/// A row of swatches. Selecting one writes through `AppTheme.set`, which
/// persists to the App Group (so widgets follow) and tells the root scene to
/// repaint — the whole app changes colour under you, live.
private struct ThemePicker: View {
    @Binding var selection: AppTheme

    private let columns = [GridItem(.adaptive(minimum: 62), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
            ForEach(AppTheme.allCases) { theme in
                Button {
                    Haptics.selection()
                    selection = theme
                    AppTheme.set(theme)
                } label: {
                    VStack(spacing: 7) {
                        ZStack {
                            Circle()
                                .fill(theme.swatch)
                                .frame(width: 32, height: 32)
                            if theme == selection {
                                Circle()
                                    .strokeBorder(theme.swatch, lineWidth: 1.5)
                                    .frame(width: 44, height: 44)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(height: 46)

                        Text(theme.displayName.uppercased())
                            .font(.system(size: 8.5, weight: theme == selection ? .bold : .semibold))
                            .kerning(0.9)
                            .foregroundStyle(theme == selection
                                             ? Color(.label)
                                             : Color(.label).opacity(0.45))
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(theme.displayName)
                .accessibilityAddTraits(theme == selection ? [.isButton, .isSelected] : .isButton)
            }
        }
        .animation(.easeOut(duration: 0.15), value: selection)
    }
}
