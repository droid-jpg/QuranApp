import SwiftUI

struct JuzBrowserView: View {
    let surahs: [Surah]
    @Environment(\.dismiss) private var dismiss
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            List(JuzData.boundaries, id: \.juz) { boundary in
                let startSurah = surahs.first { $0.number == boundary.startSurah }
                let startIndex = startSurah.flatMap { s in
                    surahs.firstIndex(where: { $0.number == s.number })
                }
                NavigationLink(value: JuzRoute(
                    startIndex: startIndex,
                    initialAyah: boundary.startAyah > 1 ? boundary.startAyah : nil
                )) {
                    HStack(spacing: 14) {
                        // Juz number badge
                        ZStack {
                            Rectangle()
                                .fill(Color.brand.opacity(0.12))
                            Text("\(boundary.juz)")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.brand)
                        }
                        .frame(width: 40, height: 40)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Juz \(boundary.juz)")
                                .font(.appSerif(17, weight: .semibold))
                            if let s = startSurah {
                                Text("\(s.englishName) \(boundary.startAyah == 1 ? "" : "· Ayah \(boundary.startAyah)")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if let s = startSurah {
                            Text(s.name)
                                .font(.system(size: 18))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Browse by Juz")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: JuzRoute.self) { route in
                if let idx = route.startIndex {
                    SurahPageView(surahs: surahs, startIndex: idx, initialAyah: route.initialAyah)
                } else {
                    Text("Surah not loaded yet. Return to the main list and try again.")
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { Haptics.tap(); dismiss() }
                }
            }
        }
        // Light tap on push only. Replaces a per-row gesture that, on List
        // rows, fired the haptic on the content but didn't navigate.
        .sensoryFeedback(trigger: path) { old, new in
            new.count > old.count ? .impact(weight: .light) : nil
        }
    }
}

private struct JuzRoute: Hashable {
    let startIndex: Int?
    let initialAyah: Int?
}
