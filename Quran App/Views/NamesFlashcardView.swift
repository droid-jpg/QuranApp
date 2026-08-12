import SwiftUI
import AVFoundation

struct NamesFlashcardView: View {
    @EnvironmentObject private var store: NamesStore
    @Environment(\.dismiss) private var dismiss

    @State private var currentIndex = 0
    @State private var isFlipped = false
    @State private var dragOffset: CGSize = .zero

    private let names = AllahName.all

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress
                HStack {
                    Text("\(currentIndex + 1) / \(names.count)")
                        .font(.appSerif(15))
                        .foregroundStyle(.secondary)
                    Spacer()
                    StatusCycleButton(name: names[currentIndex], store: store)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                ProgressView(value: Double(currentIndex + 1), total: Double(names.count))
                    .tint(.brand)
                    .padding(.horizontal, 20)

                Spacer()

                // Flashcard
                flashcard
                    .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
                    .offset(dragOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { dragOffset = CGSize(width: $0.translation.width, height: 0) }
                            .onEnded { val in
                                withAnimation(.spring(duration: 0.3)) { dragOffset = .zero }
                                if val.translation.width < -60 { advance(by: 1) }
                                else if val.translation.width > 60 { advance(by: -1) }
                            }
                    )
                    .onTapGesture {
                        withAnimation(.spring(duration: 0.4)) { isFlipped.toggle() }
                    }

                Spacer()

                // Navigation buttons
                HStack(spacing: 40) {
                    Button { advance(by: -1) } label: {
                        Image(systemName: "arrow.left.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(currentIndex > 0 ? .brand : Color(.tertiaryLabel))
                    }
                    .disabled(currentIndex == 0)

                    // Audio button
                    AudioSpeakButton(text: names[currentIndex].arabic)

                    Button { advance(by: 1) } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(currentIndex < names.count - 1 ? .brand : Color(.tertiaryLabel))
                    }
                    .disabled(currentIndex == names.count - 1)
                }
                .padding(.bottom, 32)
            }
            .navigationTitle("Flashcards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var flashcard: some View {
        let name = names[currentIndex]
        ZStack {
            // Front — Arabic
            if !isFlipped {
                VStack(spacing: 20) {
                    Text(name.arabic)
                        .font(.system(size: 56, weight: .regular))
                        .multilineTextAlignment(.center)
                        .environment(\.layoutDirection, .rightToLeft)

                    Text("Tap to reveal")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: 280)
                .padding(32)
                .background(
                    Rectangle()
                        .fill(Color(.secondarySystemBackground))
                        .shadow(color: .black.opacity(0.1), radius: 12, y: 4)
                )
                .padding(.horizontal, 24)
            } else {
                // Back — transliteration + meaning
                VStack(spacing: 16) {
                    Text(name.transliteration)
                        .font(.title.bold())
                        .foregroundStyle(.brand)
                    Text(name.meaning)
                        .font(.appSerif(19))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)
                    Text("#\(name.id)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: 280)
                .padding(32)
                .background(
                    Rectangle()
                        .fill(Color.brand.opacity(0.08))
                        .overlay(Rectangle().stroke(Color.brand.opacity(0.3), lineWidth: 1))
                        .shadow(color: .black.opacity(0.1), radius: 12, y: 4)
                )
                .padding(.horizontal, 24)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            }
        }
    }

    private func advance(by delta: Int) {
        let next = currentIndex + delta
        guard next >= 0, next < names.count else { return }
        withAnimation(.spring(duration: 0.35)) {
            isFlipped = false
            currentIndex = next
        }
    }
}

// MARK: - Status cycle button

private struct StatusCycleButton: View {
    let name: AllahName
    @ObservedObject var store: NamesStore

    var body: some View {
        let status = store.status(for: name.id)
        Button { store.cycle(for: name.id) } label: {
            Label(statusLabel(status), systemImage: statusIcon(status))
                .font(.caption.bold())
                .foregroundStyle(statusColor(status))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(statusColor(status).opacity(0.12))
                .clipShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func statusLabel(_ s: NamesStore.NameStatus) -> String {
        switch s {
        case .notStarted: return "Not Started"
        case .memorized:  return "Memorized"
        }
    }
    private func statusIcon(_ s: NamesStore.NameStatus) -> String {
        switch s {
        case .notStarted: return "circle"
        case .memorized:  return "checkmark.circle.fill"
        }
    }
    private func statusColor(_ s: NamesStore.NameStatus) -> Color {
        switch s {
        case .notStarted: return .secondary
        case .memorized:  return .brand
        }
    }
}

// MARK: - Audio speak button (AVSpeechSynthesizer)

struct AudioSpeakButton: View {
    let text: String
    /// The flashcard wants a big tappable speaker; the 99-Names register wants a
    /// glyph the size of its neighbours. Hard-coding 28pt made every list row
    /// shout, so callers set it.
    var size: CGFloat = 28

    @State private var isSpeaking = false
    @State private var synth = AVSpeechSynthesizer()

    var body: some View {
        Button {
            if isSpeaking {
                synth.stopSpeaking(at: .immediate)
                isSpeaking = false
            } else {
                speak()
            }
        } label: {
            Image(systemName: isSpeaking ? "speaker.wave.3.fill" : "speaker.wave.2")
                .font(.system(size: size))
                .foregroundStyle(isSpeaking ? Color.brand : Color(.label).opacity(0.35))
                .symbolEffect(.bounce, value: isSpeaking)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func speak() {
        // Ensure speech plays through the speaker even during silence mode
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        let u = AVSpeechUtterance(string: text)
        u.voice = bestArabicVoice()
        u.rate = 0.44          // Natural cadence — 0.38 sounds robotic, 0.5 is AVSpeechUtteranceDefaultSpeechRate
        u.pitchMultiplier = 1.0
        u.volume = 1.0
        u.postUtteranceDelay = 0.2
        synth.speak(u)
        isSpeaking = true
        // Estimate duration from character count at the chosen rate
        let duration = max(1.2, Double(text.count) * 0.28)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            if !self.synth.isSpeaking { self.isSpeaking = false }
        }
    }

    private func bestArabicVoice() -> AVSpeechSynthesisVoice? {
        // 1. Try Apple's modern Eloquence / neural voice identifiers first.
        //    These are the high-quality voices shipped with iOS 16+ and 17+.
        let preferredIdentifiers: [String] = [
            "com.apple.eloquence.ar-SA.Majed",       // iOS 16+ Eloquence (neural)
            "com.apple.voice.enhanced.ar-SA.Majed",  // Enhanced quality
            "com.apple.ttsbundle.Majed-premium",      // Premium bundle
            "com.apple.ttsbundle.Majed-enhanced",     // Enhanced bundle
        ]
        for id in preferredIdentifiers {
            if let voice = AVSpeechSynthesisVoice(identifier: id) { return voice }
        }

        // 2. Fall back: pick the highest-quality Arabic voice available on device.
        let arVoices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("ar") }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }

        return arVoices.first ?? AVSpeechSynthesisVoice(language: "ar-SA")
    }
}

#Preview {
    NamesFlashcardView()
        .environmentObject(NamesStore())
}
