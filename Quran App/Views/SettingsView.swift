import SwiftUI

// SettingsView is presented as a NavigationLink destination inside MoreView's
// NavigationStack — it intentionally has no NavigationStack of its own.
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
    @AppStorage("translationFontSize")     private var translationFontSize: Double = 14
    @AppStorage("transliterationFontSize") private var transliterationFontSize: Double = 13

    @AppStorage("memoReminderEnabled") private var memoReminderEnabled = false
    @AppStorage("memoReminderHour")    private var memoReminderHour = 19
    @AppStorage("memoReminderMinute")  private var memoReminderMinute = 0

    @AppStorage("fillBlankUseTransliteration") private var fillBlankUseTransliteration = false
    @AppStorage("memorizationCardScript")          private var cardScript: MemorizationCardScript = .arabic
    @AppStorage("memorizationArabicFontSize")       private var cardArabicFontSize: Double = 30
    @AppStorage("memorizationTransliterationFontSize") private var cardTransliterationFontSize: Double = 18

    @EnvironmentObject private var prayerService: PrayerTimesService

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
        Form {
            // MARK: Appearance
            Section {
                Picker("Theme", selection: $colorSchemeRaw) {
                    Label("System", systemImage: "circle.lefthalf.filled").tag("system")
                    Label("Light",  systemImage: "sun.max").tag("light")
                    Label("Dark",   systemImage: "moon").tag("dark")
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Label("Appearance", systemImage: "paintbrush")
            }

            // MARK: Reading Text Size
            Section {
                FontSizeSlider(
                    title: "Arabic",
                    size: $arabicFontSize,
                    range: 18...44,
                    sample: "بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ",
                    rightToLeft: true
                )
                FontSizeSlider(
                    title: "Translation",
                    size: $translationFontSize,
                    range: 12...26,
                    sample: "In the name of Allah, the Most Gracious, the Most Merciful."
                )
                FontSizeSlider(
                    title: "Transliteration",
                    size: $transliterationFontSize,
                    range: 11...22,
                    sample: "Bismi Allāhi r-raḥmāni r-raḥīm",
                    italic: true
                )
            } header: {
                Label("Reading Text Size", systemImage: "textformat.size")
            } footer: {
                Text("Applies to the surah reading view.")
            }

            // MARK: Translation
            Section {
                Picker("Language", selection: languageBinding) {
                    ForEach(Translation.languages, id: \.self) { lang in
                        Text(lang).tag(lang)
                    }
                }
                Picker("Translation", selection: $translationId) {
                    ForEach(Translation.translations(in: Translation.selected.language)) { t in
                        Text(t.name).tag(t.id)
                    }
                }
            } header: {
                Label("Translation", systemImage: "character.book.closed")
            } footer: {
                Text("Sets the translation shown beneath each ayah.")
            }

            // MARK: Reciter
            Section {
                Picker("Reciter", selection: $selectedReciterId) {
                    ForEach(Reciter.all) { reciter in
                        Text(reciter.name).tag(reciter.id)
                    }
                }
            } header: {
                Label("Reciter", systemImage: "person.wave.2")
            } footer: {
                Text("Changes apply when you next play an ayah.")
            }

            // MARK: Memorization
            Section {
                Picker("Card display", selection: $cardScript) {
                    ForEach(MemorizationCardScript.allCases) { s in
                        Text(s.title).tag(s)
                    }
                }
                if cardScript.showsArabic {
                    FontSizeSlider(
                        title: "Card Arabic",
                        size: $cardArabicFontSize,
                        range: 22...46,
                        sample: "بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ",
                        rightToLeft: true
                    )
                }
                if cardScript.showsTransliteration {
                    FontSizeSlider(
                        title: "Card Transliteration",
                        size: $cardTransliterationFontSize,
                        range: 13...30,
                        sample: "Bismi Allāhi r-raḥmāni r-raḥīm",
                        italic: true
                    )
                }
            } header: {
                Label("Memorization Cards", systemImage: "rectangle.on.rectangle.angled")
            } footer: {
                Text("Sets what the ayah shows on review cards — Arabic, transliteration, or both — and their sizes.")
            }

            Section {
                Picker("Fill-in-the-blank hint", selection: $fillBlankUseTransliteration) {
                    Text("Translation").tag(false)
                    Text("Transliteration").tag(true)
                }
            } header: {
                Label("Memorization", systemImage: "graduationcap")
            } footer: {
                Text("Choose what's shown beneath the ayah when you reveal a fill-in-the-blank review card.")
            }

            // MARK: Memorization Reminder
            Section {
                Toggle("Daily reminder", isOn: $memoReminderEnabled)
                    .onChange(of: memoReminderEnabled) { rescheduleMemoReminder() }
                if memoReminderEnabled {
                    DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
                        .onChange(of: memoReminderHour) { rescheduleMemoReminder() }
                        .onChange(of: memoReminderMinute) { rescheduleMemoReminder() }
                }
            } header: {
                Label("Memorization Reminder", systemImage: "bell.badge")
            } footer: {
                Text("A daily nudge to continue memorizing the ayah you're working on.")
            }

            // MARK: Prayer Calculation
            Section {
                Picker("Method", selection: $prayerCalcMethod) {
                    ForEach(PrayerCalcMethod.all) { m in
                        Text(m.name).tag(m.id)
                    }
                }
                .onChange(of: prayerCalcMethod) { prayerService.refetchForSettingsChange() }

                Picker("Asr (juristic)", selection: $prayerAsrSchool) {
                    Text("Standard").tag(0)
                    Text("Hanafi").tag(1)
                }
                .onChange(of: prayerAsrSchool) { prayerService.refetchForSettingsChange() }
            } header: {
                Label("Prayer Calculation", systemImage: "location.circle")
            } footer: {
                Text("Sets the twilight angles and Asr method used to compute your local prayer times.")
            }

            // MARK: Prayer Notifications
            Section {
                Toggle("Enable Prayer Notifications", isOn: $notifEnabled)
                    .onChange(of: notifEnabled) { reschedule() }

                if notifEnabled {
                    Toggle("Live Activity (10 min countdown)", isOn: $liveActivityEnabled)
                        .onChange(of: liveActivityEnabled) { reschedule() }
                    Toggle("Fajr",    isOn: $notifFajr)    .onChange(of: notifFajr)    { reschedule() }
                    Toggle("Dhuhr",   isOn: $notifDhuhr)   .onChange(of: notifDhuhr)   { reschedule() }
                    Toggle("Asr",     isOn: $notifAsr)     .onChange(of: notifAsr)     { reschedule() }
                    Toggle("Maghrib", isOn: $notifMaghrib) .onChange(of: notifMaghrib) { reschedule() }
                    Toggle("Isha",    isOn: $notifIsha)    .onChange(of: notifIsha)    { reschedule() }
                    Toggle("Sunrise", isOn: $notifSunrise).onChange(of: notifSunrise) { reschedule() }
                    Toggle("Midnight", isOn: $notifMidnight).onChange(of: notifMidnight) { reschedule() }

                    Picker("Pre-prayer reminder", selection: $notifPreReminder) {
                        Text("None").tag(0)
                        Text("5 min").tag(5)
                        Text("10 min").tag(10)
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                    }
                    .onChange(of: notifPreReminder) { reschedule() }
                }
            } header: {
                Label("Prayer Notifications", systemImage: "bell")
            } footer: {
                if notifEnabled {
                    Text("Notifications use your local prayer times based on location.")
                }
            }

            // MARK: About
            Section {
                LabeledContent("Data source", value: "alquran.cloud")
                LabeledContent("Audio source", value: "everyayah.com")
            } header: {
                Label("About", systemImage: "info.circle")
            }
        }
        .navigationTitle("Settings")
        .task {
            if notifEnabled {
                _ = await NotificationService.shared.requestPermission()
            }
        }
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

// MARK: - Font size slider

private struct FontSizeSlider: View {
    let title: String
    @Binding var size: Double
    let range: ClosedRange<Double>
    let sample: String
    var rightToLeft: Bool = false
    var italic: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Int(size)) pt")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            // Live preview at the chosen size
            Text(sample)
                .font(.system(size: size))
                .italic(italic)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: rightToLeft ? .trailing : .leading)
                .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight)
                .animation(.easeOut(duration: 0.12), value: size)

            Slider(value: $size, in: range, step: 1)
                .tint(.brand)
        }
        .padding(.vertical, 4)
    }
}
