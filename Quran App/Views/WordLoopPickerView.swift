import SwiftUI

struct WordLoopPickerView: View {
    let ayah: Ayah
    let timings: [WordTiming]
    let isLoading: Bool
    let errorMessage: String?
    let onStart: (WordTiming, WordTiming) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var startId: Int? = nil
    @State private var endId: Int? = nil

    private var canLoop: Bool { startId != nil && endId != nil }

    private var instruction: String {
        if startId == nil    { return "Tap the first word to start the loop" }
        else if endId == nil { return "Tap the last word to end the loop" }
        else                 { return "Tap Loop to begin" }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading word timings…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                } else if timings.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 36))
                            .foregroundStyle(.orange)
                        Text("Word timings unavailable")
                            .font(.headline)
                        Text(errorMessage ?? "Could not load word-level timing data.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                } else {
                    // Instruction banner
                    Text(instruction)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(Color(.secondarySystemBackground))

                    ScrollView {
                        WordFlowView(timings: timings, startId: startId, endId: endId) { tapped in
                            handleTap(tapped)
                        }
                        .padding()

                        Text(ayah.translation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal)
                            .padding(.bottom)
                    }

                    if startId != nil {
                        Button(role: .destructive) {
                            startId = nil; endId = nil
                        } label: {
                            Label("Reset Selection", systemImage: "arrow.counterclockwise")
                                .font(.subheadline)
                        }
                        .padding(.bottom, 8)
                    }
                }
            }
            .navigationTitle("Word Loop — Ayah \(ayah.numberInSurah)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Loop") {
                        if let s = startId, let e = endId,
                           let start = timings.first(where: { $0.id == s }),
                           let end   = timings.first(where: { $0.id == e }) {
                            onStart(start, end)
                            dismiss()
                        }
                    }
                    .disabled(!canLoop)
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func handleTap(_ timing: WordTiming) {
        if startId == nil {
            startId = timing.id
        } else if endId == nil {
            if timing.id < startId! {
                endId = startId
                startId = timing.id
            } else if timing.id == startId {
                endId = timing.id   // single-word loop
            } else {
                endId = timing.id
            }
        } else {
            // Third tap resets and starts a new selection
            startId = timing.id
            endId = nil
        }
    }
}

// MARK: - Flow layout of word chips

struct WordFlowView: View {
    let timings: [WordTiming]
    let startId: Int?
    let endId: Int?
    let onTap: (WordTiming) -> Void

    var body: some View {
        // LazyVGrid with .rightToLeft environment: word 1 appears at top-right,
        // subsequent words fill left then wrap down — correct Arabic reading order.
        // More reliable than a custom Layout across all iOS versions.
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 70, maximum: 150), spacing: 8)],
            alignment: .trailing,
            spacing: 8
        ) {
            ForEach(timings) { timing in
                WordChip(timing: timing, state: chipState(for: timing.id))
                    .onTapGesture { onTap(timing) }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func chipState(for id: Int) -> WordChip.ChipState {
        guard let s = startId else { return .normal }
        if id == s {
            return endId == nil ? .start : (endId == s ? .single : .start)
        }
        guard let e = endId else { return .normal }
        if id == e { return .end }
        if id > s && id < e { return .inRange }
        return .normal
    }
}

// MARK: - Word chip

struct WordChip: View {
    enum ChipState { case normal, start, end, single, inRange }

    let timing: WordTiming
    let state: ChipState

    var body: some View {
        VStack(spacing: 2) {
            Text(timing.arabicText.isEmpty ? "—" : timing.arabicText)
                .font(.system(size: 19))
                .environment(\.layoutDirection, .rightToLeft)

            if !timing.transliteration.isEmpty {
                Text(timing.transliteration)
                    .font(.system(size: 10))
                    .foregroundStyle(state == .start || state == .end || state == .single
                                     ? .white.opacity(0.85) : .secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(bg)
        .foregroundStyle(fg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(border, lineWidth: state != .normal ? 1.5 : 0)
        )
        .scaleEffect(state == .start || state == .end || state == .single ? 1.05 : 1.0)
        .animation(.spring(duration: 0.2), value: state == .normal)
    }

    private var bg: Color {
        switch state {
        case .normal:               return Color(.tertiarySystemBackground)
        case .start, .end, .single: return .teal
        case .inRange:              return .teal.opacity(0.2)
        }
    }

    private var fg: Color {
        switch state {
        case .start, .end, .single: return .white
        default:                    return .primary
        }
    }

    private var border: Color {
        switch state {
        case .start, .end, .single: return .teal
        case .inRange:              return .teal.opacity(0.5)
        case .normal:               return .clear
        }
    }
}

