import SwiftUI

/// Settings as ruled blocks, in the app's own type. Pushed from More.
struct SettingsView: View {
    @AppStorage("colorSchemePreference") private var colorSchemeRaw = "system"
    @AppStorage("selectedReciterId")     private var selectedReciterId = 7
    @AppStorage("selectedTranslationId") private var translationId = Translation.fallbackId
    @AppStorage("prayerCalcMethod")      private var prayerCalcMethod = 2
    @AppStorage("prayerAsrSchool")       private var prayerAsrSchool = 0

    @Environment(Downloads.self) private var downloads
    @EnvironmentObject private var prayerService: PrayerTimesService
    @State private var theme = AppTheme.current
    @State private var showReadingType = false
    /// The edition being downloaded, while it is.
    @State private var downloadingTranslation: String?
    @State private var translationFailed = false
    @State private var storedBytes: Int64?
    @State private var confirmRemoveAudio = false

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
                }

                // ── Reading ───────────────────────────────────────────────
                EditorialSection(title: "Reading", icon: "textformat.size") {
                    EditorialNavRow(title: "Reading type",
                                    value: ReadingFace.current.displayName) {
                        Haptics.tap()
                        showReadingType = true
                    }

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
                    if downloadingTranslation != nil {
                        HStack(spacing: Spacing.xs) {
                            ProgressView().controlSize(.small)
                            Text("Downloading for offline reading…")
                                .font(TypeScale.secondary)
                                .foregroundStyle(Palette.textSecondary)
                        }
                        .padding(.top, Spacing.sm)
                    }
                }
                .onChange(of: translationId) { old, new in downloadTranslation(new, revertingTo: old) }

                // ── Reciter ───────────────────────────────────────────────
                EditorialSection(title: "Reciter", icon: "person.wave.2.fill") {
                    EditorialMenuRow(
                        title: "Voice", selection: $selectedReciterId,
                        options: Reciter.all.map { .init($0.id, $0.name) }
                    )
                }

                // ── Saved audio ───────────────────────────────────────────
                EditorialSection(title: "Saved audio", icon: "arrow.down.circle.fill") {
                    EditorialValueRow(
                        title: "On this iPhone",
                        value: storedBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "…"
                    )
                    Hairline().padding(.vertical, 13)
                    Button(role: .destructive) {
                        confirmRemoveAudio = true
                    } label: {
                        Text("Remove all saved audio")
                            .font(.appSerif(17))
                            .foregroundStyle(Palette.danger)
                            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled((storedBytes ?? 0) == 0)
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

                }

                // ── Prayer notifications ──────────────────────────────────
                PrayerNotificationsSection()

                // ── About ─────────────────────────────────────────────────
                EditorialSection(title: "About", icon: "info.circle.fill") {
                    EditorialValueRow(title: "Version", value: AppInfo.version)
                    Hairline().padding(.vertical, 13)
                    EditorialLinkRow(title: "Privacy policy", value: "Read", url: AppInfo.privacyPolicy)
                    Hairline().padding(.vertical, 13)
                    EditorialLinkRow(title: "Help and feedback", value: "Contact", url: AppInfo.support)
                }

                // ── Sources ───────────────────────────────────────────────
                EditorialSection(title: "Sources", icon: "books.vertical.fill") {
                    // Tanzil's licence asks for a link to tanzil.net wherever its text is used.
                    EditorialLinkRow(title: "Arabic text", value: "Tanzil Project",
                                     url: URL(string: "https://tanzil.net")!)
                    Hairline().padding(.vertical, 13)
                    EditorialLinkRow(title: "Translations", value: "alquran.cloud",
                                     url: URL(string: "https://alquran.cloud")!)
                    Hairline().padding(.vertical, 13)
                    EditorialLinkRow(title: "Audio, words, tafsir", value: "quran.com",
                                     url: URL(string: "https://quran.com")!)
                    Hairline().padding(.vertical, 13)
                    EditorialLinkRow(title: "Prayer times", value: "aladhan.com",
                                     url: URL(string: "https://aladhan.com")!)
                    Footnote("Each translation remains the copyright of its translator or publisher.")
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(Palette.background)
        .navigationTitle("Settings")
        .sheet(isPresented: $showReadingType) {
            ReadingTypeSheet()
        }
        .task { storedBytes = await Downloads.storedBytes() }
        .alert("Couldn't download that translation", isPresented: $translationFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check your connection and choose it again.")
        }
        .confirmationDialog("Remove all saved audio?", isPresented: $confirmRemoveAudio, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                downloads.removeAll()
                storedBytes = 0
            }
        } message: {
            Text("Surahs you play again will be saved again.")
        }
    }

    /// A translation other than the bundled one is fetched whole, once, when it is
    /// chosen. If that fails the selection goes back to what it was.
    private func downloadTranslation(_ id: String, revertingTo previous: String) {
        guard !QuranText.shared.isAvailable(id) else { return }
        downloadingTranslation = id
        Task {
            do {
                try await QuranText.shared.download(id)
            } catch {
                if translationId == id { translationId = previous }
                translationFailed = true
            }
            if downloadingTranslation == id { downloadingTranslation = nil }
        }
    }
}

// MARK: - Prayer notifications

/// The prayer notification switches. One view, shown in Settings and pushed from
/// Prayer Times ("Notifications"), so the two never drift apart. Turning the main
/// switch (or any prayer) on is what asks the system for permission; a refusal puts
/// the switch back off.
struct PrayerNotificationsSection: View {
    @AppStorage("notifEnabled")          private var notifEnabled = false
    @AppStorage("notifFajr")             private var notifFajr = true
    @AppStorage("notifDhuhr")            private var notifDhuhr = true
    @AppStorage("notifAsr")              private var notifAsr = true
    @AppStorage("notifMaghrib")          private var notifMaghrib = true
    @AppStorage("notifIsha")             private var notifIsha = true
    @AppStorage("notifSunrise")          private var notifSunrise = true
    @AppStorage("notifMidnight")         private var notifMidnight = true
    @AppStorage("notifPreReminder")      private var notifPreReminder = 10

    @EnvironmentObject private var prayerService: PrayerTimesService
    @State private var denied = false

    var body: some View {
                EditorialSection(title: "Prayer notifications", icon: "bell.fill") {
                    EditorialToggle(title: "Enable notifications", isOn: $notifEnabled)
                        .onChange(of: notifEnabled) { _, on in reschedule(askingPermission: on) }

                    if notifEnabled {
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

                    }
                }
        .notificationsDeniedAlert(isPresented: $denied)
    }

    @ViewBuilder
    private func prayerToggle(_ name: String, _ binding: Binding<Bool>) -> some View {
        HStack(spacing: 11) {
            Image(systemName: PrayerIcons.names[name] ?? "clock")
                .font(.label(13))
                .foregroundStyle(binding.wrappedValue ? Color.brand : Palette.textSecondary)
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
        .onChange(of: binding.wrappedValue) { _, on in reschedule(askingPermission: on) }
        .accessibilityElement(children: .combine)
    }

    /// Reschedules from the current switches. When something was just turned on,
    /// permission is requested first (the system alert, once); if refused, the main
    /// switch goes back off and nothing is scheduled.
    private func reschedule(askingPermission: Bool = false) {
        Task {
            if askingPermission, notifEnabled {
                let permission = await NotificationService.shared.ensurePermission()
                if permission != .granted { notifEnabled = false }
                if permission == .denied { denied = true }
            }
            prayerService.rescheduleNotifications()
        }
    }
}

/// "Notifications are off" with a way to the system settings, shown when the user
/// turns something on after refusing permission.
extension View {
    func notificationsDeniedAlert(isPresented: Binding<Bool>) -> some View {
        alert("Notifications are off", isPresented: isPresented) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Allow notifications for Quran in Settings to turn this on.")
        }
    }
}

// MARK: - App info

/// The version shown in About, and the pages About links to.
enum AppInfo {
    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    static let privacyPolicy = URL(string: "https://github.com/droid-jpg/QuranApp/blob/main/PRIVACY.md")!
    static let support = URL(string: "https://github.com/droid-jpg/QuranApp/issues")!
}

// MARK: - Footnote

/// The explanatory line that used to be a Form section footer.
struct Footnote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(TypeScale.secondary)
            .foregroundStyle(Palette.textSecondary)
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
                                    .font(.label(13, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(height: 46)

                        Text(theme.displayName)
                            .font(.label(13, weight: theme == selection ? .bold : .semibold))
                            .foregroundStyle(theme == selection
                                             ? Color(.label)
                                             : Palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(theme.displayName)
                .accessibilityAddTraits(theme == selection ? [.isButton, .isSelected] : .isButton)
            }
        }
        .animation(Motion.quick, value: selection)
    }
}
