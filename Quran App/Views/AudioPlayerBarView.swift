import SwiftUI

struct AudioPlayerBarView: View {
    @ObservedObject var viewModel: SurahDetailViewModel
    @EnvironmentObject private var audioService: AudioService

    var body: some View {
        VStack(spacing: 6) {
            // Progress bar
            ProgressView(value: audioService.progress)
                .tint(.teal)
                .padding(.horizontal)

            HStack(spacing: 16) {
                // Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.surah.englishName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let ayah = audioService.currentAyah {
                        Text("Ayah \(ayah)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }

                Spacer()

                // Loop mode indicator
                if viewModel.loopSettings.mode != .off {
                    Image(systemName: viewModel.loopSettings.mode == .single ? "repeat.1" : "repeat")
                        .font(.caption)
                        .foregroundStyle(.teal)
                }

                // Playback speed
                Menu {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0] as [Float], id: \.self) { rate in
                        Button {
                            audioService.setPlaybackRate(rate)
                        } label: {
                            HStack {
                                Text(rate == 1.0 ? "1× (Normal)" : "\(rate, specifier: "%.2g")×")
                                if audioService.playbackRate == rate {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Text(audioService.playbackRate == 1.0 ? "1×" : "\(audioService.playbackRate, specifier: "%.2g")×")
                        .font(.caption.bold())
                        .foregroundStyle(audioService.playbackRate != 1.0 ? .teal : Color(.secondaryLabel))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                // Stop
                Button { audioService.stop() } label: {
                    Image(systemName: "stop.fill")
                        .font(.body)
                        .foregroundStyle(Color(.secondaryLabel))
                }
                .buttonStyle(.plain)

                // Play / Pause
                Button { audioService.togglePlayPause() } label: {
                    Image(systemName: audioService.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(Color.teal)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .padding(.top, 8)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.12), radius: 10, y: -3)
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }
}
