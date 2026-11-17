import SwiftUI
import UIKit

// MARK: - Ayah actions

/// What you can do with one ayah: four buttons for the things done often, and rows
/// for the things done sometimes (word by word, tafsir, copy).
struct AyahActionsSheet: View {
    let surah: Surah
    let ayah: Ayah
    /// Starts choosing a repeat range with this ayah as its first.
    let onRepeat: () -> Void

    @Environment(Player.self) private var player
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var bookmarks: BookmarkStore
    @State private var detent: PresentationDetent = .height(310)
    @State private var copied = false

    private var isBookmarked: Bool { bookmarks.isBookmarked(surah: surah.number, ayah: ayah.numberInSurah) }

    private var shareText: String {
        "\(ayah.arabic)\n\n\(ayah.translation)\n\n\(surah.englishName) \(surah.number):\(ayah.numberInSurah)"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.md) {
                HStack(spacing: Spacing.xs) {
                    ActionButton(title: "Play", icon: "play.fill") {
                        player.play(surah, from: ayah.numberInSurah)
                        dismiss()
                    }
                    ActionButton(title: "Repeat", icon: "repeat") {
                        dismiss()
                        onRepeat()
                    }
                    ActionButton(title: isBookmarked ? "Saved" : "Bookmark",
                                 icon: isBookmarked ? "bookmark.fill" : "bookmark", on: isBookmarked) {
                        Haptics.selection()
                        bookmarks.toggle(surahNumber: surah.number, surahName: surah.englishName,
                                         surahArabicName: surah.name, ayahNumber: ayah.numberInSurah,
                                         arabic: ayah.arabic, translation: ayah.translation)
                    }
                    ShareLink(item: shareText) {
                        ActionButton.label(title: "Share", icon: "square.and.arrow.up", on: false)
                    }
                    .buttonStyle(CardButtonStyle(scale: 0.95))
                }

                VStack(spacing: 0) {
                    Hairline()
                    NavigationLink {
                        WordByWordView(surah: surah, ayah: ayah)
                            .onAppear { detent = .large }
                    } label: {
                        SheetRow(title: "Word by word", icon: "character.book.closed")
                    }
                    Hairline()
                    NavigationLink {
                        TafsirView(surah: surah, ayah: ayah)
                            .onAppear { detent = .large }
                    } label: {
                        SheetRow(title: "Tafsir", icon: "text.book.closed")
                    }
                    Hairline()
                    Button {
                        UIPasteboard.general.string = shareText
                        Haptics.success()
                        withAnimation(Motion.standard) { copied = true }
                    } label: {
                        SheetRow(title: copied ? "Copied" : "Copy", icon: copied ? "checkmark" : "doc.on.doc", chevron: false)
                    }
                    Hairline()
                }
                .buttonStyle(RowPressStyle())

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.top, Spacing.xs)
            .background(Palette.surfaceRaised)
            // Back from Word by word or Tafsir: the sheet shrinks to fit these rows again.
            .onAppear { detent = .height(310) }
            .navigationTitle("\(surah.englishName) \(ayah.numberInSurah)")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.height(310), .large], selection: $detent)
        .presentationDragIndicator(.visible)
    }
}

private struct ActionButton: View {
    let title: String
    let icon: String
    var on = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.impact(.light)
            action()
        } label: {
            Self.label(title: title, icon: icon, on: on)
        }
        .buttonStyle(CardButtonStyle(scale: 0.95))
    }

    static func label(title: String, icon: String, on: Bool) -> some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .frame(height: 24)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: on)
            Text(title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(on ? Color.brand : Palette.textPrimary)
        .frame(maxWidth: .infinity, minHeight: MinSize.ayahActionButton)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(on ? Color.brand : Palette.separator, lineWidth: 1))
        .contentShape(Rectangle())
        .animation(Motion.standard, value: on)
    }
}

private struct SheetRow: View {
    let title: String
    let icon: String
    var chevron = true

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(.brand)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 28)
            Text(title)
                .font(TypeScale.rowTitle)
                .foregroundStyle(Palette.textPrimary)
                .contentTransition(.opacity)
            Spacer()
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

// MARK: - Word by word

/// Each word with its meaning. Tap a word to hear it. "Repeat words" is the tucked-away
/// word loop: turn it on, tap the first and the last word, and that stretch repeats.
struct WordByWordView: View {
    let surah: Surah
    let ayah: Ayah

    @Environment(Player.self) private var player
    @State private var words: [WordMeaning]?
    @State private var failed = false
    @State private var hasAudio = true
    @State private var choosing = false
    @State private var first: Int?

    /// The words repeating now, if they are this ayah's.
    private var loop: Player.WordLoop? {
        guard player.isCurrent(surah.number), let loop = player.wordLoop,
              loop.ayah == ayah.numberInSurah, !loop.once else { return nil }
        return loop
    }

    private var recited: Int? {
        player.isCurrent(surah.number) && player.ayah == ayah.numberInSurah && player.isPlaying ? player.wordPosition : nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                if let words {
                    FlowLayout(spacing: Spacing.xs, lineSpacing: Spacing.sm, rightToLeft: true) {
                        ForEach(words) { word in
                            Button { tap(word.position) } label: { chip(word) }
                                .buttonStyle(CardButtonStyle(scale: 0.94))
                        }
                    }
                    .frame(maxWidth: .infinity)

                    if hasAudio {
                        controls
                            .animation(Motion.standard, value: choosing)
                            .animation(Motion.standard, value: first)
                            .animation(Motion.standard, value: loop)
                    } else {
                        Text("Word audio isn't available for this reciter offline yet.")
                            .font(TypeScale.secondary)
                            .foregroundStyle(Palette.textSecondary)
                    }
                } else if failed {
                    ContentUnavailableView {
                        Label("Couldn't load the words", systemImage: "wifi.slash")
                    } description: {
                        Text("They are saved for offline use after the first time.")
                    } actions: {
                        Button("Try again") { Task { await load() } }
                    }
                } else {
                    ProgressView().padding(.top, Spacing.xxl)
                }
            }
            .padding(Spacing.screenMargin)
        }
        .background(Palette.surfaceRaised)
        .navigationTitle("Word by word")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func chip(_ word: WordMeaning) -> some View {
        let inLoop = loop.map { ($0.from...$0.to).contains(word.position) } ?? false
        let marked = first == word.position || inLoop
        return VStack(spacing: 3) {
            Text(word.arabic)
                .font(.appArabic(26))
                .foregroundStyle(recited == word.position ? Color.brand : Palette.textPrimary)
            Text(word.transliteration)
                .font(.caption.italic())
                .foregroundStyle(Palette.textSecondary)
            Text(word.meaning)
                .font(.caption)
                .foregroundStyle(Palette.textPrimary)
        }
        .lineLimit(1)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .frame(minHeight: MinSize.hitTarget)
        .background(RoundedRectangle(cornerRadius: 10).fill(marked ? Palette.highlight : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(marked ? Color.brand : Palette.separator, lineWidth: 1))
        .animation(Motion.standard, value: marked)
        .animation(Motion.quick, value: recited == word.position)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var controls: some View {
        if let loop {
            OutlineButton(label: "Stop repeating words \(loop.from)–\(loop.to)", icon: "stop.fill", on: true) {
                player.stopWords()
            }
        } else if choosing {
            VStack(spacing: Spacing.xs) {
                Text(first == nil ? "Tap the first word" : "Now tap the last word")
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.textPrimary)
                    .contentTransition(.opacity)
                Button("Cancel") {
                    choosing = false
                    first = nil
                }
                .frame(minHeight: MinSize.hitTarget)
            }
        } else {
            OutlineButton(label: "Repeat words", icon: "repeat") {
                Haptics.tap()
                choosing = true
            }
        }
    }

    private func tap(_ position: Int) {
        guard hasAudio else { return }
        if choosing {
            if let start = first {
                Haptics.success()
                choosing = false
                first = nil
                Task {
                    await player.playWords(in: surah, ayah: ayah.numberInSurah,
                                           from: min(start, position), to: max(start, position), once: false)
                }
            } else {
                Haptics.selection()
                first = position
            }
        } else {
            Haptics.tap()
            Task { await player.playWords(in: surah, ayah: ayah.numberInSurah, from: position, to: position, once: true) }
        }
    }

    private func load() async {
        failed = false
        do {
            words = try await WordMeanings.shared.words(surah: surah.number)[ayah.numberInSurah] ?? []
        } catch {
            failed = true
        }
        hasAudio = await player.hasTimings(for: surah.number)
    }
}

// MARK: - Tafsir

struct TafsirView: View {
    let surah: Surah
    let ayah: Ayah

    @State private var text: String?
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                if let text {
                    Text(TafsirService.shared.sourceName)
                        .font(TypeScale.caption)
                        .foregroundStyle(Palette.textSecondary)
                    Text(text.isEmpty ? "No commentary for this ayah." : text)
                        .font(.appSerif(17))
                        .foregroundStyle(Palette.textPrimary)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                } else if failed {
                    ContentUnavailableView {
                        Label("Couldn't load the tafsir", systemImage: "wifi.slash")
                    } description: {
                        Text("It is saved for offline use after the first time.")
                    } actions: {
                        Button("Try again") { Task { await load() } }
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, Spacing.xxl)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.screenMargin)
        }
        .background(Palette.surfaceRaised)
        .navigationTitle("Tafsir")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        failed = false
        do {
            text = try await TafsirService.shared.tafsir(surah: surah.number)[ayah.numberInSurah] ?? ""
        } catch {
            failed = true
        }
    }
}
