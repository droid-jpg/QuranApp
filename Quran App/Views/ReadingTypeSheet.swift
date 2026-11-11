import SwiftUI

/// The reader's type panel: which serif the English is set in, which face the
/// Arabic is set in, how big each runs, and what shows beneath each ayah.
///
/// Every row previews itself in its own face, so the choice is made by looking
/// rather than by reading a name.
struct ReadingTypeSheet: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("readingFace")   private var readingFace = ReadingFace.newYork.rawValue
    @AppStorage("arabicScript")  private var arabicScript = ArabicScript.system.rawValue
    @AppStorage("arabicFontSize")          private var arabicFontSize: Double = 26
    @AppStorage("translationFontSize")     private var translationFontSize: Double = 17
    @AppStorage("transliterationFontSize") private var transliterationFontSize: Double = 13
    @AppStorage("showTranslation")     private var showTranslation = true
    @AppStorage("showTransliteration") private var showTransliteration = true
    @AppStorage("immersiveReading")    private var immersiveReading = false

    private var face: ReadingFace { ReadingFace(rawValue: readingFace) ?? .newYork }
    private var script: ArabicScript { ArabicScript(rawValue: arabicScript) ?? .system }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // ── Translation face ──────────────────────────────────
                    Eyebrow("Translation face")
                        .padding(.bottom, 12)

                    VStack(spacing: 0) {
                        ForEach(Array(ReadingFace.allCases.enumerated()), id: \.element.id) { idx, f in
                            if idx > 0 { Hairline() }
                            Button {
                                Haptics.selection()
                                readingFace = f.rawValue
                            } label: {
                                HStack(spacing: 12) {
                                    Text(f.displayName)
                                        .font(f.font(size: 17, weight: .regular))
                                        .foregroundStyle(.primary)
                                    Text("— \(f.caption)")
                                        .font(f.font(size: 14, italic: f.isSerif))
                                        .foregroundStyle(Color.secondary)
                                    Spacer(minLength: 8)
                                    if f == face {
                                        Image(systemName: "checkmark")
                                            .font(.label(12, weight: .bold))
                                            .foregroundStyle(.brand)
                                    }
                                }
                                .padding(.vertical, 13)
                                .padding(.horizontal, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .overlay(Rectangle().strokeBorder(Color(.label).opacity(0.14), lineWidth: 1))

                    // ── Arabic script ─────────────────────────────────────
                    Eyebrow("Arabic script")
                        .padding(.top, 26)
                        .padding(.bottom, 12)

                    HStack(spacing: 8) {
                        ForEach(ArabicScript.allCases.filter(\.isAvailable)) { s in
                            Button {
                                Haptics.selection()
                                arabicScript = s.rawValue
                            } label: {
                                VStack(spacing: 6) {
                                    Text("قُرْآن")
                                        .font(s.font(size: 19))
                                        .foregroundStyle(s == script ? Color(.label) : Color(.label).opacity(0.75))
                                        .environment(\.layoutDirection, .rightToLeft)
                                    Eyebrow(s.displayName,
                                            tint: s == script ? .brand : Color.secondary,
                                            size: 9)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .overlay(
                                    Rectangle().strokeBorder(
                                        s == script ? Color.brand : Color(.label).opacity(0.18),
                                        lineWidth: 1
                                    )
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // ── Size ──────────────────────────────────────────────
                    Eyebrow("Size")
                        .padding(.top, 26)
                        .padding(.bottom, 14)

                    TypeSlider(label: "Arabic", value: $arabicFontSize, range: 18...44)
                    TypeSlider(label: "Translation", value: $translationFontSize, range: 13...26)
                        .padding(.top, 12)
                    if showTransliteration {
                        TypeSlider(label: "Translit.", value: $transliterationFontSize, range: 11...22)
                            .padding(.top, 12)
                    }

                    // ── Beneath each ayah ─────────────────────────────────
                    Hairline().padding(.top, 24).padding(.bottom, 16)

                    ToggleRow(title: "Show translation", isOn: $showTranslation)
                    Hairline().padding(.vertical, 14)
                    ToggleRow(title: "Show transliteration", isOn: $showTransliteration)
                    Hairline().padding(.vertical, 14)
                    ToggleRow(title: "Hide controls while reading", isOn: $immersiveReading)

                    // ── Live specimen ─────────────────────────────────────
                    Hairline().padding(.top, 24).padding(.bottom, 18)
                    Eyebrow("Preview").padding(.bottom, 14)
                    specimen
                        .padding(.bottom, 12)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .navigationTitle("Reading Type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        // The reader follows these live on its own. Everywhere else still sets
        // type through `Font.appSerif`, which reads UserDefaults behind SwiftUI's
        // back and so never learns of a change — this is what tells those screens.
        .onChange(of: readingFace) { _, _ in
            NotificationCenter.default.post(name: .readingTypeDidChange, object: nil)
        }
        .onChange(of: arabicScript) { _, _ in
            NotificationCenter.default.post(name: .readingTypeDidChange, object: nil)
        }
    }

    /// A real ayah at the chosen settings, so the sliders are judged against
    /// scripture rather than against a lorem line.
    private var specimen: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("هُوَ ٱلَّذِى جَعَلَ لَكُمُ ٱلْأَرْضَ ذَلُولًۭا فَٱمْشُوا۟ فِى مَنَاكِبِهَا")
                .font(.appArabic(arabicFontSize, scales: false))
                .lineSpacing(arabicFontSize * 0.62)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .environment(\.layoutDirection, .rightToLeft)

            HStack(alignment: .top, spacing: 12) {
                Text("15")
                    .font(.label(11, weight: .bold).monospacedDigit())
                    .foregroundStyle(.brand)
                    .frame(minWidth: 20, alignment: .leading)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 6) {
                    if showTransliteration {
                        Text("Huwal lazee ja‘ala lakumul arda zaloolan famshoo fee manaakibihaa")
                            .font(face.font(size: transliterationFontSize, italic: true, scales: false))
                            .foregroundStyle(Color.secondary)
                    }
                    if showTranslation {
                        Text("It is He who made the earth tame for you — so walk among its slopes and eat of His provision.")
                            .font(face.font(size: translationFontSize, scales: false))
                            .foregroundStyle(Color(.label).opacity(0.86))
                            .lineSpacing(3)
                    }
                }
            }
            .padding(.top, 16)
        }
        .animation(.easeOut(duration: 0.12), value: arabicFontSize)
        .animation(.easeOut(duration: 0.12), value: translationFontSize)
    }
}

// MARK: - Rows

private struct TypeSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack(spacing: 14) {
            Text(label)
                .font(.appSerif(14))
                .foregroundStyle(Color.secondary)
                .frame(width: 82, alignment: .leading)
            Slider(value: $value, in: range, step: 1)
                .tint(.brand)
            MetaText("\(Int(value))", size: 11)
                .frame(width: 22, alignment: .trailing)
        }
    }
}

/// One line at every reading face and size (AUDIT #22): the title shrinks a
/// little rather than wrap. The toggle carries the title as its label, so
/// VoiceOver reads the visible text.
private struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(.appSerif(17))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .tint(.brand)
    }
}
