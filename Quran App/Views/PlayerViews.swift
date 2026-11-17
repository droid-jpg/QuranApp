import SwiftUI

// The mini player, Now Playing, and the one Repeat control. All three read the same
// `Player`, so they cannot disagree about what is playing or what is repeating.

// MARK: - Status line

extension Player {
    /// One sentence for where playback is, used by the mini player and Now Playing.
    var statusLine: String {
        guard let surah, ayah > 0 else { return "Tap play to start listening" }
        if failed { return "Couldn't play. Tap play to try again" }
        if isLoading { return "Loading ayah \(ayah)…" }
        if let loop = wordLoop, !loop.once { return "Ayah \(ayah) · repeating words \(loop.from)–\(loop.to)" }
        if let range = repeatRange {
            return range.from == range.to
                ? "Repeating ayah \(range.from) · \(range.timesLabel)"
                : "Ayah \(ayah) · repeating \(range.from)–\(range.to) · \(range.timesLabel)"
        }
        return "Ayah \(ayah) of \(surah.numberOfAyahs)"
    }
}

// MARK: - Mini player

struct MiniPlayer: View {
    @Environment(Player.self) private var player
    @Environment(AppRouter.self) private var router

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Button {
                Haptics.tap()
                router.showNowPlaying = true
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(player.surah?.englishName ?? "Al-Faatiha")
                        .font(TypeScale.rowTitleCompact)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    Text(player.statusLine)
                        .font(.caption)
                        .foregroundStyle(player.failed ? Palette.danger : Palette.textSecondary)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Now Playing")
            .accessibilityValue("\(player.surah?.englishName ?? ""), \(player.statusLine)")

            if player.repeatRange != nil {
                Image(systemName: "repeat")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.brand)
                    .accessibilityHidden(true)
            }

            PlayPauseButton(size: 20) {
                if player.hasSession {
                    player.toggle()
                } else if let first = QuranText.shared.surah(1) {
                    player.play(first)
                }
            }
            .frame(width: MinSize.hitTarget, height: MinSize.hitTarget)

            Button {
                Haptics.tap()
                player.next()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 36, height: MinSize.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.textPrimary)
            .disabled(!player.hasSession)
            .accessibilityLabel("Next ayah")
        }
        .padding(.leading, Spacing.md)
        .padding(.trailing, Spacing.xs)
        .animation(Motion.standard, value: player.statusLine)
    }
}

/// Play, pause, or a spinner while the ayah is being fetched.
struct PlayPauseButton: View {
    @Environment(Player.self) private var player
    var size: CGFloat = 20
    var tint: Color = Palette.textPrimary
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.impact(.light)
            action()
        } label: {
            ZStack {
                if player.isLoading && player.isPlaying {
                    ProgressView().tint(tint)
                } else {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: size, weight: .semibold))
                        .foregroundStyle(tint)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(CardButtonStyle(scale: 0.9))
        .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
    }
}

// MARK: - Repeat

/// The one Repeat control. Off: one tap repeats the current ayah, or opens the reader
/// to pick a range. On: the same menu changes how many times, or turns it off.
struct RepeatMenu<Label: View>: View {
    @Environment(Player.self) private var player
    @Environment(AppRouter.self) private var router
    /// Called for "Choose ayahs…" instead of opening the reader, when the menu already
    /// sits inside the reader.
    var onChooseAyahs: (() -> Void)? = nil
    @ViewBuilder var label: Label

    var body: some View {
        Menu {
            if let range = player.repeatRange {
                Section("Repeating \(range.label.lowercased())") {
                    Picker("Times", selection: Binding(get: { range.times }, set: { player.setRepeatTimes($0) })) {
                        ForEach(RepeatRange.timeChoices, id: \.self) { times in
                            Text(times == 0 ? "Until I stop it" : "\(times) times").tag(times)
                        }
                    }
                }
            }
            Section {
                if player.hasSession, player.repeatRange.map({ $0.from != $0.to || $0.from != player.ayah }) ?? true {
                    Button("Repeat this ayah", systemImage: "repeat.1") {
                        Haptics.success()
                        player.repeatCurrentAyah()
                    }
                }
                Button("Choose ayahs…", systemImage: "text.line.first.and.arrowtriangle.forward") {
                    if let onChooseAyahs {
                        onChooseAyahs()
                    } else if let surah = player.surah {
                        router.openReader(surah: surah.number, ayah: max(1, player.ayah), pickRepeat: true)
                    }
                }
                .disabled(player.surah == nil && onChooseAyahs == nil)
            }
            if player.repeatRange != nil {
                Button("Turn off repeat", systemImage: "xmark", role: .destructive) {
                    Haptics.tap()
                    player.clearRepeat()
                }
            }
        } label: {
            label
        }
        .accessibilityLabel("Repeat")
        .accessibilityValue(player.repeatRange.map { "\($0.label), \($0.timesLabel)" } ?? "Off")
    }
}

// MARK: - Now Playing

struct NowPlayingView: View {
    @Environment(Player.self) private var player
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @AppStorage("selectedReciterId") private var reciterId = Reciter.all[0].id

    private var currentAyah: Ayah? {
        player.surah.flatMap { QuranText.shared.ayah($0.number, player.ayah) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, Spacing.xl)

            // The ayah being recited, large, with the word highlight.
            ScrollView {
                if let ayah = currentAyah {
                    VStack(spacing: Spacing.md) {
                        RecitedArabic(ayah: ayah, font: .appArabic(30))
                            .multilineTextAlignment(.center)
                            .lineSpacing(12)
                            .environment(\.layoutDirection, .rightToLeft)
                        Text(ayah.translation)
                            .font(.appSerif(17))
                            .foregroundStyle(Palette.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.lg)
                    .id(ayah.numberInSurah)
                    .transition(.opacity)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .animation(Motion.standard, value: player.ayah)

            ProgressLine()
                .padding(.bottom, Spacing.xs)
            Text(player.statusLine)
                .font(TypeScale.secondary)
                .foregroundStyle(player.failed ? Palette.danger : Palette.textSecondary)
                .contentTransition(.numericText())
                .animation(Motion.standard, value: player.statusLine)

            transport
                .padding(.vertical, Spacing.lg)
            options
                .padding(.bottom, Spacing.md)
        }
        .padding(.horizontal, Spacing.lg)
        .background(Palette.surfaceRaised.ignoresSafeArea())
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(spacing: Spacing.xxs) {
            Text(player.surah?.englishName ?? "Nothing playing")
                .font(TypeScale.title)
                .foregroundStyle(Palette.textPrimary)
            if let surah = player.surah {
                Text("\(surah.englishNameTranslation) · \(Reciter.selected.name)")
                    .font(TypeScale.secondary)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var transport: some View {
        HStack(spacing: Spacing.xl) {
            transportButton("backward.end.fill", "Previous ayah") { player.previous() }
            PlayPauseButton(size: 26, tint: Palette.onAccent) { player.toggle() }
                .frame(width: MinSize.nowPlayingPlay, height: MinSize.nowPlayingPlay)
                .background(Circle().fill(Color.brand))
            transportButton("forward.end.fill", "Next ayah") { player.next() }
        }
        .disabled(!player.hasSession)
    }

    private func transportButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 56, height: 56)
                .contentShape(Rectangle())
        }
        .buttonStyle(CardButtonStyle(scale: 0.88))
        .accessibilityLabel(label)
    }

    private var options: some View {
        HStack(spacing: 0) {
            RepeatMenu {
                optionLabel(player.repeatRange == nil ? "Repeat" : "\(player.repeatRange!.label) · \(player.repeatRange!.timesLabel)",
                            icon: "repeat", on: player.repeatRange != nil)
            }

            Menu {
                Picker("Speed", selection: Binding(get: { player.rate }, set: { player.setRate($0) })) {
                    ForEach(Player.rateChoices, id: \.self) { rate in
                        Text(Self.rateLabel(rate)).tag(rate)
                    }
                }
            } label: {
                optionLabel(Self.rateLabel(player.rate), icon: "gauge.with.dots.needle.50percent", on: player.rate != 1)
            }

            // Everything used rarely lives here, off the main surface.
            Menu {
                if let surah = player.surah {
                    Button("Go to ayah in the reader", systemImage: "book") {
                        router.openReader(surah: surah.number, ayah: player.ayah)
                    }
                }
                Picker("Pause after each ayah", systemImage: "pause.circle",
                       selection: Binding(get: { player.pauseAfterAyah }, set: { player.setPauseAfterAyah($0) })) {
                    ForEach(PauseAfterAyah.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
                Picker("Reciter", systemImage: "person.wave.2", selection: $reciterId) {
                    ForEach(Reciter.all) { Text($0.name).tag($0.id) }
                }
                .pickerStyle(.menu)
                if player.hasSession {
                    Button("Close player", systemImage: "xmark", role: .destructive) {
                        player.close()
                        dismiss()
                    }
                }
            } label: {
                optionLabel("More", icon: "ellipsis", on: player.pauseAfterAyah != .off)
            }
        }
    }

    private func optionLabel(_ text: String, icon: String, on: Bool) -> some View {
        VStack(spacing: Spacing.xxs) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .frame(height: 22)
            Text(text)
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(on ? Color.brand : Palette.textSecondary)
        .frame(maxWidth: .infinity, minHeight: MinSize.hitTarget)
        .contentShape(Rectangle())
    }

    static func rateLabel(_ rate: Float) -> String {
        rate == 1 ? "1×" : "\(rate.formatted(.number.precision(.fractionLength(0...2))))×"
    }
}

/// The line that fills as the ayah plays. Its own view, so the 20 Hz updates redraw
/// only this.
private struct ProgressLine: View {
    @Environment(Player.self) private var player

    var body: some View {
        RuleProgress(fraction: player.progress, tint: .brand, height: 2)
            .animation(.linear(duration: 0.06), value: player.progress)
            .accessibilityHidden(true)
    }
}

// MARK: - Arabic that follows the recitation

/// An ayah's Arabic with the word being recited in the accent colour. Only the ayah
/// that is playing is drawn with this, so the word updates redraw one text.
struct RecitedArabic: View {
    @Environment(Player.self) private var player
    let ayah: Ayah
    let font: Font

    var body: some View {
        Text(text).font(font)
    }

    private var text: AttributedString {
        let words = ayah.arabic.split(separator: " ").map(String.init)
        guard player.isCurrent(ayah.surah), player.ayah == ayah.numberInSurah,
              let current = player.wordPosition,
              let positions = WordAlignment.positions(for: words, timedCount: player.timedWordCount)
        else { return AttributedString(ayah.arabic) }

        var result = AttributedString()
        for (index, word) in words.enumerated() {
            var part = AttributedString(index == 0 ? word : " " + word)
            if positions[index] == current { part.foregroundColor = Palette.accent }
            result += part
        }
        return result
    }
}
