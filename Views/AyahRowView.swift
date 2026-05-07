import SwiftUI

struct AyahRowView: View {
    let ayah: Ayah
    let isPlaying: Bool
    let onPlay: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 14) {

            // Top bar: play button + ayah number badge
            HStack {
                Button(action: onPlay) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(isPlaying ? .teal : Color(.secondaryLabel))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)

                Spacer()

                Text("\(ayah.numberInSurah)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(isPlaying ? Color.teal : Color(.tertiaryLabel))
                    .clipShape(Circle())
                    .animation(.spring(duration: 0.25), value: isPlaying)
            }

            // Arabic — right-aligned, large
            Text(ayah.arabic)
                .font(.system(size: 26, weight: .regular))
                .multilineTextAlignment(.trailing)
                .lineSpacing(10)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .environment(\.layoutDirection, .rightToLeft)

            Divider()

            // Transliteration
            Text(ayah.transliteration)
                .font(.system(size: 13, weight: .light))
                .italic()
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Translation
            Text(ayah.translation)
                .font(.system(size: 15))
                .foregroundStyle(.primary.opacity(0.85))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(isPlaying ? Color.teal.opacity(0.06) : Color.clear)
        .animation(.easeInOut(duration: 0.2), value: isPlaying)
    }
}
