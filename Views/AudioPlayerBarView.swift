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

                // Loop settings shortcut
                Button { viewModel.showLoopSheet = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.body)
                        .foregroundStyle(Color(.secondaryLabel))
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
