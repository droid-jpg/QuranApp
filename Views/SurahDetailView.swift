import SwiftUI

struct SurahDetailView: View {
    let surah: Surah
    @StateObject private var viewModel: SurahDetailViewModel
    @EnvironmentObject private var audioService: AudioService

    init(surah: Surah) {
        self.surah = surah
        _viewModel = StateObject(wrappedValue: SurahDetailViewModel(surah: surah))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    SurahHeaderView(surah: surah)

                    if viewModel.isLoading {
                        ProgressView("Loading ayahs…")
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else if let err = viewModel.error {
                        ErrorView(message: err) { Task { await viewModel.loadAyahs() } }
                    } else {
                        ForEach(viewModel.ayahs) { ayah in
                            AyahRowView(
                                ayah: ayah,
                                isPlaying: audioService.isPlaying
                                    && audioService.currentSurah == surah.number
                                    && audioService.currentAyah == ayah.numberInSurah
                            ) {
                                viewModel.playAyah(ayah.numberInSurah, audioService: audioService)
                            }
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                // Padding so last ayah isn't hidden behind player bar
                .padding(.bottom, audioService.currentSurah == surah.number ? 100 : 0)
            }

            if audioService.currentSurah == surah.number {
                AudioPlayerBarView(viewModel: viewModel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: audioService.currentSurah)
        .navigationTitle(surah.englishName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { viewModel.showLoopSheet = true } label: {
                    Image(systemName: viewModel.loopSettings.mode != .off ? "repeat" : "repeat")
                        .symbolVariant(viewModel.loopSettings.mode != .off ? .fill : .none)
                        .foregroundStyle(viewModel.loopSettings.mode != .off ? .teal : .primary)
                }
            }
        }
        .sheet(isPresented: $viewModel.showLoopSheet) {
            LoopSettingsSheet(
                settings: viewModel.loopSettings,
                totalAyahs: surah.numberOfAyahs
            ) { newSettings in
                viewModel.applyLoopSettings(newSettings, audioService: audioService)
            }
        }
        .task { await viewModel.loadAyahs() }
    }
}

// MARK: - Surah header

struct SurahHeaderView: View {
    let surah: Surah

    var body: some View {
        VStack(spacing: 10) {
            Text(surah.name)
                .font(.system(size: 38, weight: .regular))
                .environment(\.layoutDirection, .rightToLeft)

            Text(surah.englishNameTranslation)
                .font(.title3)
                .foregroundStyle(.secondary)

            HStack(spacing: 20) {
                Label("\(surah.numberOfAyahs) Ayahs", systemImage: "text.alignright")
                Label(surah.revelationType,
                      systemImage: surah.revelationType == "Meccan" ? "sun.horizon" : "building.2")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // Bismillah — excluded for Al-Fatiha (1) and At-Tawbah (9)
            if surah.number != 1 && surah.number != 9 {
                Text("بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ")
                    .font(.system(size: 22))
                    .multilineTextAlignment(.center)
                    .environment(\.layoutDirection, .rightToLeft)
                    .padding(.top, 6)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.teal.opacity(0.06))
    }
}
