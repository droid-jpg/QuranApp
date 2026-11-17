import SwiftUI

/// First launch: a short welcome, the two reading choices that matter most
/// (translation and reciter), then the prayer calculation method with the location
/// ask, so the app never fires a system prompt cold. Choices write straight to
/// `@AppStorage`, so they are the app's live settings the moment this ends.
struct OnboardingView: View {
    var onDone: () -> Void

    @EnvironmentObject private var prayerService: PrayerTimesService

    @AppStorage("selectedTranslationId") private var translationId = Translation.fallbackId
    @AppStorage("selectedReciterId")     private var reciterId = 7
    @AppStorage("prayerCalcMethod")      private var method = 2

    @State private var page = 0
    private let lastPage = 2

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcome.tag(0)
                reading.tag(1)
                prayer.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(Motion.standard, value: page)

            // Dots + primary button
            VStack(spacing: 18) {
                HStack(spacing: 7) {
                    ForEach(0...lastPage, id: \.self) { i in
                        Circle()
                            .fill(i == page ? Color.brand : Palette.textTertiary)
                            .frame(width: i == page ? 8 : 6, height: i == page ? 8 : 6)
                    }
                }
                .animation(Motion.spring, value: page)
                .accessibilityHidden(true)

                Button {
                    Haptics.tap()
                    if page == lastPage {
                        onDone()
                    } else {
                        withAnimation(Motion.standard) { page += 1 }
                    }
                } label: {
                    Text(page == lastPage ? "Get Started" : "Continue")
                        .font(.appSerif(17, weight: .semibold))
                        .foregroundStyle(Palette.onAccent)
                        .contentTransition(.opacity)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.brand)
                }
                .buttonStyle(CardButtonStyle(scale: 0.98))
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
        .background(Palette.background.ignoresSafeArea())
    }

    // MARK: Pages

    private var welcome: some View {
        pageScaffold(
            icon: "moon.stars.fill",
            title: "As-salamu alaykum",
            subtitle: "A calm, focused way to read and listen to the Quran."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                FeatureLine(icon: "play.fill", text: "Play any surah from the list, and follow the recitation word by word.")
                FeatureLine(icon: "repeat", text: "Tap two ayahs to repeat everything between them.")
                FeatureLine(icon: "wifi.slash", text: "The whole Quran is built in, and what you play is kept for offline.")
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
            VStack(spacing: 0) {
                Hairline()
                EditorialMenuRow(
                    title: "Translation", selection: $translationId,
                    options: Translation.all.map { .init($0.id, "\($0.name) · \($0.language)") }
                )
                .padding(.vertical, 14)
                Hairline()
                EditorialMenuRow(
                    title: "Reciter", selection: $reciterId,
                    options: Reciter.all.map { .init($0.id, $0.name) }
                )
                .padding(.vertical, 14)
                Hairline()
            }
        }
    }

    private var prayer: some View {
        pageScaffold(
            icon: "location.circle.fill",
            title: "Prayer times",
            subtitle: "Choose your calculation method, then allow location so the times are right for where you are. Only a position rounded to about a kilometre is used to fetch them."
        ) {
            VStack(spacing: 0) {
                Hairline()
                EditorialMenuRow(
                    title: "Method", selection: $method,
                    options: PrayerCalcMethod.all.map { .init($0.id, $0.name) }
                )
                .padding(.vertical, 14)
                Hairline()
                locationRow
                    .padding(.top, 18)
            }
        }
    }

    /// The location ask, which turns into its own answer once it has one.
    @ViewBuilder private var locationRow: some View {
        switch prayerService.fetchStatus {
        case .ready, .fetching:
            Label(prayerService.fetchStatus == .ready ? "Prayer times are ready" : "Getting prayer times…",
                  systemImage: prayerService.fetchStatus == .ready ? "checkmark.circle.fill" : "location.fill")
                .font(TypeScale.body)
                .foregroundStyle(.brand)
                .contentTransition(.symbolEffect(.replace))
                .frame(maxWidth: .infinity, minHeight: MinSize.hitTarget)
                .transition(.opacity)
        case .notDetermined, .denied, .failed:
            OutlineButton(label: prayerService.fetchStatus == .failed ? "Try again" : "Allow location",
                          icon: "location.fill", on: true) {
                Haptics.tap()
                prayerService.allowLocationAccess()
            }
        }
    }

    // MARK: Building blocks

    @ViewBuilder
    private func pageScaffold<Content: View>(
        icon: String, title: String, subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                ZStack {
                    Circle().fill(Palette.highlight).frame(width: 96, height: 96)
                    Image(systemName: icon)
                        .font(.system(size: 42))
                        .foregroundStyle(.brand)
                }
                .padding(.top, 40)

                Text(title)
                    .font(TypeScale.display)
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text(subtitle)
                    .font(.appSerif(16))
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)

                content()
                    .padding(.top, 6)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Palette.background)
    }
}

private struct FeatureLine: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.label(16))
                .foregroundStyle(.brand)
                .frame(width: 26)
            Text(text)
                .font(.appSerif(16))
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
