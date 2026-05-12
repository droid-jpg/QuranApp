import SwiftUI

// SettingsView is presented as a NavigationLink destination inside MoreView's
// NavigationStack — it intentionally has no NavigationStack of its own.
struct SettingsView: View {
    @AppStorage("colorSchemePreference") private var colorSchemeRaw = "system"
    @AppStorage("selectedReciterId")     private var selectedReciterId = 7
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

    @EnvironmentObject private var prayerService: PrayerTimesService

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
}
