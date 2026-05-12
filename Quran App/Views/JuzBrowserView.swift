import SwiftUI

struct JuzBrowserView: View {
    let surahs: [Surah]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(JuzData.boundaries, id: \.juz) { boundary in
                let startSurah = surahs.first { $0.number == boundary.startSurah }
                NavigationLink(destination: destination(boundary: boundary, surah: startSurah)) {
                    HStack(spacing: 14) {
                        // Juz number badge
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.teal.opacity(0.12))
                            Text("\(boundary.juz)")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.teal)
                        }
                        .frame(width: 40, height: 40)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Juz \(boundary.juz)")
                                .font(.body.bold())
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func destination(boundary: JuzBoundary, surah: Surah?) -> some View {
        if let surah {
            SurahDetailView(
                surah: surah,
                initialAyah: boundary.startAyah > 1 ? boundary.startAyah : nil
            )
        } else {
            Text("Surah not loaded yet. Return to the main list and try again.")
                .foregroundStyle(.secondary)
                .padding()
        }
    }
}
