import SwiftUI

/// Displays the surah as a continuous Arabic text block in mushaf style.
struct MushafView: View {
    let surah: Surah
    let ayahs: [Ayah]

    @Environment(\.dismiss) private var dismiss
    @State private var fontSize: CGFloat = 26

    private var fullText: AttributedString {
        var result = AttributedString()
        for ayah in ayahs {
            // Strip the leading Bismillah from ayah 1 (it's shown separately in the header)
            let text = (ayah.numberInSurah == 1 && surah.number != 1 && surah.number != 9)
                ? stripBismillah(ayah.arabic)
                : ayah.arabic
            var chunk = AttributedString(text + " ")
            chunk.font = .system(size: fontSize, weight: .regular)
            result += chunk
            // Verse end marker with number
            var marker = AttributedString("﴿\(arabicNumber(ayah.numberInSurah))﴾ ")
            marker.font = .system(size: fontSize * 0.75)
            marker.foregroundColor = .brand.opacity(0.8)
            result += marker
        }
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Surah name header
                    VStack(spacing: 6) {
                        Text(surah.name)
                            .font(.system(size: 42, weight: .regular))
                            .environment(\.layoutDirection, .rightToLeft)
                        Text(surah.englishName)
                            .font(.appSerif(20, weight: .medium))
                        Text(surah.englishNameTranslation)
                            .font(.appSerif(15))
                            .foregroundStyle(.secondary)
                        if surah.number != 1 && surah.number != 9 {
                            Text("بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ")
                                .font(.system(size: 24, weight: .regular))
                                .multilineTextAlignment(.center)
                                .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(20)
                    .background(Color.brand.opacity(0.06))
                    .clipShape(Rectangle())
                    .padding(.horizontal)

                    // Continuous Arabic text
                    if ayahs.isEmpty {
                        ProgressView("Loading…")
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        Text(fullText)
                            .multilineTextAlignment(.trailing)
                            .lineSpacing(fontSize * 0.6)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .environment(\.layoutDirection, .rightToLeft)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 40)
                    }
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle("Mushaf")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        Button { fontSize = max(18, fontSize - 2) } label: {
                            Image(systemName: "textformat.size.smaller")
                        }
                        Button { fontSize = min(40, fontSize + 2) } label: {
                            Image(systemName: "textformat.size.larger")
                        }
                    }
                }
            }
        }
    }

    private func stripBismillah(_ text: String) -> String {
        let words = text.components(separatedBy: " ")
        return words.count > 4 ? words.dropFirst(4).joined(separator: " ") : text
    }

    private func arabicNumber(_ n: Int) -> String {
        let arabicDigits: [Character] = ["٠","١","٢","٣","٤","٥","٦","٧","٨","٩"]
        return String(String(n).compactMap { c in
            guard let d = c.wholeNumberValue else { return nil }
            return arabicDigits[d]
        })
    }
}
