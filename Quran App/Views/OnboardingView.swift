import SwiftUI

/// First-launch flow: a short welcome, the two reading choices that matter most
/// (translation + reciter), the prayer calculation method, and contextual
/// permission asks for location and notifications — so the app never fires system
/// prompts cold. Choices write straight to `@AppStorage`, so they persist as the
/// app's live settings the moment onboarding ends.
struct OnboardingView: View {
    var onDone: () -> Void

    @EnvironmentObject private var prayerService: PrayerTimesService

    @AppStorage("selectedTranslationId") private var translationId = Translation.fallbackId
    @AppStorage("selectedReciterId")     private var reciterId = 7
    @AppStorage("prayerCalcMethod")      private var method = 2
    @AppStorage("notifEnabled")          private var notifEnabled = false
    @AppStorage("memoReminderEnabled")   private var memoReminderEnabled = false

    @State private var page = 0
    private let lastPage = 3

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcome.tag(0)
                reading.tag(1)
                prayer.tag(2)
                reminders.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.25), value: page)

            // Dots + primary button
            VStack(spacing: 18) {
                HStack(spacing: 7) {
                    ForEach(0...lastPage, id: \.self) { i in
                        Circle()
                            .fill(i == page ? Color.brand : Color(.tertiaryLabel))
                            .frame(width: i == page ? 8 : 6, height: i == page ? 8 : 6)
                    }
                }

                Button {
                    Haptics.tap()
                    if page == lastPage {
                        NotificationService.shared.scheduleMemorizationReminder()
                        onDone()
                    } else {
                        withAnimation { page += 1 }
                    }
                } label: {
                    Text(page == lastPage ? "Get Started" : "Continue")
                        .font(.appSerif(17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.brand)
                        .clipShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
    }

    // MARK: Pages

    private var welcome: some View {
        pageScaffold(
            icon: "moon.stars.fill",
            title: "As-salamu alaykum",
            subtitle: "A calm, focused way to read, listen to, and memorize the Qur'an — built around how memorization actually works."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                FeatureLine(icon: "repeat", text: "Loop any ayah to listen, recite, and chain it onto the ones before.")
                FeatureLine(icon: "graduationcap.fill", text: "Track a working ayah and let spaced repetition lock in the meaning.")
                FeatureLine(icon: "wifi.slash", text: "The full Qur'an is built in — read anywhere, no connection needed.")
            }
            .padding(.top, 8)
        }
    }

    private var reading: some View {
        pageScaffold(
            icon: "character.book.closed.fill",
            title: "Your reading",
            subtitle: "Pick the translation and reciter you like best. You can change these anytime in Settings."
        ) {
            VStack(spacing: 18) {
                pickerCard(title: "Translation") {
                    Picker("Translation", selection: $translationId) {
                        ForEach(Translation.all) { t in
                            Text("\(t.name) · \(t.language)").tag(t.id)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
                pickerCard(title: "Reciter") {
                    Picker("Reciter", selection: $reciterId) {
                        ForEach(Reciter.all) { r in
                            Text(r.name).tag(r.id)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
            }
        }
    }

    private var prayer: some View {
        pageScaffold(
            icon: "location.circle.fill",
            title: "Prayer times",
            subtitle: "Choose your calculation method, then allow location so times are accurate for where you are. Nothing leaves your device."
        ) {
            VStack(spacing: 18) {
                pickerCard(title: "Calculation method") {
                    Picker("Method", selection: $method) {
                        ForEach(PrayerCalcMethod.all) { m in
                            Text(m.name).tag(m.id)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
                Button {
                    Haptics.tap()
                    prayerService.requestAndFetch()
                } label: {
                    Label("Allow Location", systemImage: "location.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.brand)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.brand.opacity(0.12), in: Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var reminders: some View {
        pageScaffold(
            icon: "bell.badge.fill",
            title: "Stay consistent",
            subtitle: "A daily nudge keeps your memorization moving and your streak alive."
        ) {
            VStack(spacing: 18) {
                Button {
                    Haptics.tap()
                    Task {
                        let granted = await NotificationService.shared.requestPermission()
                        await MainActor.run {
                            notifEnabled = granted
                            memoReminderEnabled = granted
                        }
                    }
                } label: {
                    Label("Enable Reminders", systemImage: "bell.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.brand)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.brand.opacity(0.12), in: Rectangle())
                }
                .buttonStyle(.plain)

                Toggle("Daily memorization reminder", isOn: $memoReminderEnabled)
                    .padding(.horizontal, 4)
            }
        }
    }

    // MARK: Building blocks

    @ViewBuilder
    private func pageScaffold<Content: View>(
        icon: String, title: String, subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ZStack {
                        Circle().fill(Color.brand.opacity(0.12)).frame(width: 96, height: 96)
                        Image(systemName: icon)
                            .font(.system(size: 42))
                            .foregroundStyle(
                                LinearGradient(colors: [.brand, .brand.opacity(0.7)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                    }
                    .padding(.top, 40)

                    Text(title)
                        .font(.title.bold())
                        .multilineTextAlignment(.center)

                    Text(subtitle)
                        .font(.appSerif(15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)

                    content()
                        .padding(.top, 6)
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func pickerCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color(.secondarySystemBackground), in: Rectangle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FeatureLine: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.brand)
                .frame(width: 26)
            Text(text)
                .font(.appSerif(15))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
