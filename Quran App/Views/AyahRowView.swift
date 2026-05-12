import SwiftUI

struct AyahRowView: View {
    let ayah: Ayah
    let surahName: String
    let isPlaying: Bool
    let isWordLooping: Bool
    let wordTimings: [WordTiming]?   // nil = not yet loaded; [] = loaded but empty/error
    let isLoadingTimings: Bool
    let wordTimingsError: String?
    let onPlay: () -> Void
    let onWordLoop: (WordTiming, WordTiming) -> Void
    let onRequestTimings: () -> Void

    @AppStorage("showTranslation")      private var showTranslation     = true
    @AppStorage("showTransliteration")  private var showTransliteration = true
    @AppStorage("arabicFontSize")       private var arabicFontSize: Double = 26

    @State private var showWordPicker = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 14) {
            HStack(spacing: 10) {
                // Play / pause
                Button(action: onPlay) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(isPlaying ? .teal : Color(.secondaryLabel))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)

                // Word loop
                Button {
                    onRequestTimings()
                    showWordPicker = true
                } label: {
                    Group {
                        if isLoadingTimings {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Image(systemName: "text.word.spacing")
                                .font(.system(size: 18))
                                .foregroundStyle(isWordLooping ? Color.teal : Color(.tertiaryLabel))
                                .symbolVariant(isWordLooping ? .fill : .none)
                        }
                    }
                    .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showWordPicker) {
                    WordLoopPickerView(
                        ayah: ayah,
                        timings: wordTimings ?? [],
                        isLoading: isLoadingTimings,
                        errorMessage: wordTimingsError
                    ) { start, end in
                        onWordLoop(start, end)
                    }
                }

                Spacer()

                Text("\(ayah.numberInSurah)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(isPlaying ? Color.teal : Color(.tertiaryLabel))
                    .clipShape(Circle())
                    .animation(.spring(duration: 0.25), value: isPlaying)
            }

            // Arabic text
            Text(ayah.arabic)
                .font(.system(size: arabicFontSize, weight: .regular))
                .multilineTextAlignment(.trailing)
                .lineSpacing(10)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .environment(\.layoutDirection, .rightToLeft)

            if showTransliteration || showTranslation {
                Divider()
            }

            // Transliteration
            if showTransliteration {
                Text(ayah.transliteration)
                    .font(.system(size: 13, weight: .light))
                    .italic()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Translation
            if showTranslation {
                Text(ayah.translation)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary.opacity(0.85))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(isPlaying ? Color.teal.opacity(0.06) : Color.clear)
        .animation(.easeInOut(duration: 0.2), value: isPlaying)
        .contextMenu {
            ShareLink(item: shareText()) {
                Label("Share Ayah", systemImage: "square.and.arrow.up")
            }
            ShareLink(item: shareTextWithTranslation()) {
                Label("Share with Translation", systemImage: "doc.text")
            }
        }
    }

    // MARK: - Share helpers

    private func shareText() -> String {
        """
        \(ayah.arabic)

        [\(surahName) \(ayah.numberInSurah)]
        """
    }

    private func shareTextWithTranslation() -> String {
        """
        \(ayah.arabic)

        \(ayah.translation)

        [\(surahName) \(ayah.numberInSurah)]
        """
    }
}
