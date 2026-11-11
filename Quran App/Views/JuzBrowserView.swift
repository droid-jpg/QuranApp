import SwiftUI

/// The Juz sheet: one row per juz in the surah row's shape, with the same play
/// button. Play starts at the juz's first surah and ayah and keeps going (playback
/// rolls into the next surah by itself).
struct JuzBrowserView: View {
    let surahs: [Surah]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.audioServiceRef) private var audioService
    @State private var path = NavigationPath()

    private func surah(_ number: Int) -> Surah? { surahs.first { $0.number == number } }

    /// "An-Naba to An-Nas", with the app's own surah names; one name when the
    /// juz lies inside a single surah.
    private func subtitle(for b: JuzBoundary) -> String {
        let start = surah(b.startSurah)?.englishName ?? "Surah \(b.startSurah)"
        let end = surah(b.endSurah)?.englishName ?? "Surah \(b.endSurah)"
        return start == end ? start : "\(start) to \(end)"
    }

    var body: some View {
        NavigationStack(path: $path) {
            List(JuzData.boundaries, id: \.juz) { boundary in
                let start = surah(boundary.startSurah)
                SurahRow(
                    leading: "\(boundary.juz)",
                    title: "Juz \(boundary.juz)",
                    subtitle: subtitle(for: boundary),
                    arabic: start?.name ?? "",
                    playSurah: boundary.startSurah,
                    playName: "Juz \(boundary.juz)",
                    onOpen: {
                        guard let start,
                              let idx = surahs.firstIndex(where: { $0.number == start.number })
                        else { return }
                        path.append(JuzRoute(startIndex: idx,
                                             initialAyah: boundary.startAyah > 1 ? boundary.startAyah : nil))
                    },
                    onPlay: {
                        guard let start, let audioService else { return }
                        SurahPlayer.toggle(start, startAyah: boundary.startAyah, audio: audioService)
                    }
                )
                .listRowInsets(EdgeInsets(top: 0, leading: Spacing.screenMargin,
                                          bottom: 0, trailing: Spacing.screenMargin))
                .listRowBackground(Palette.background)
                .listRowSeparatorTint(Palette.separator)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .navigationTitle("Juz")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: JuzRoute.self) { route in
                SurahPageView(surahs: surahs, startIndex: route.startIndex, initialAyah: route.initialAyah)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { Haptics.tap(); dismiss() }
                }
            }
        }
        // Light tap on push only.
        .sensoryFeedback(trigger: path) { old, new in
            new.count > old.count ? .impact(weight: .light) : nil
        }
    }
}

private struct JuzRoute: Hashable {
    let startIndex: Int
    let initialAyah: Int?
}
