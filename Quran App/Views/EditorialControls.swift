import SwiftUI

// Form controls in the app's own idiom, so Settings and the sheets stop looking
// like a different app than the reader. A grouped `Form` draws rounded cards and
// SF labels no matter what you do to its rows — these are the ruled equivalents.

/// One choice in an `EditorialMenuRow` / `EditorialSegmented`.
struct EditorialOption<Value: Hashable>: Identifiable {
    let value: Value
    let label: String

    var id: Value { value }

    init(_ value: Value, _ label: String) {
        self.value = value
        self.label = label
    }
}

// MARK: - Rows

/// Label on the left, current value and a chevron on the right, tapping opens a
/// menu. The ruled stand-in for `Picker` in a Form.
struct EditorialMenuRow<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [EditorialOption<Value>]

    private var currentLabel: String {
        options.first { $0.value == selection }?.label ?? "—"
    }

    var body: some View {
        Menu {
            ForEach(options) { option in
                Button {
                    Haptics.selection()
                    selection = option.value
                } label: {
                    if option.value == selection {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Text(title)
                    .font(.appSerif(17))
                    .foregroundStyle(Color(.label))
                Spacer(minLength: 8)
                Text(currentLabel)
                    .font(.appSerif(16))
                    .foregroundStyle(Color(.label).opacity(0.5))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color(.label).opacity(0.3))
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
        .accessibilityValue(currentLabel)
    }
}

/// A labelled switch. `Toggle` itself is fine — only its label needed the serif.
struct EditorialToggle: View {
    let title: String
    var caption: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.appSerif(17))
                .foregroundStyle(Color(.label))
            if let caption {
                Text("— \(caption)")
                    .font(.appSerif(14, italic: true))
                    .foregroundStyle(Color(.label).opacity(0.45))
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(.brand)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A row that pushes or presents something. Same shape as `EditorialMenuRow` so
/// a settings list reads as one column.
struct EditorialNavRow: View {
    let title: String
    var value: String? = nil
    var icon: String? = nil
    var iconTint: Color? = nil
    var caption: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(iconTint ?? Color.brand)
                        .frame(width: 22)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.appSerif(17))
                        .foregroundStyle(Color(.label))
                    if let caption {
                        Text(caption)
                            .font(.appSerif(13.5, italic: true))
                            .foregroundStyle(Color(.label).opacity(0.45))
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 8)
                if let value {
                    Text(value)
                        .font(.appSerif(16))
                        .foregroundStyle(Color(.label).opacity(0.5))
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(.label).opacity(0.3))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Read-only "label ……… value" row, for the About block.
struct EditorialValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.appSerif(17))
                .foregroundStyle(Color(.label))
            Spacer(minLength: 8)
            Text(value)
                .font(.appSerif(16))
                .foregroundStyle(Color(.label).opacity(0.5))
        }
    }
}

// MARK: - Segmented

/// The outlined segmented control. Segments share one hairline between them, and
/// the selected one's border wins where they overlap.
struct EditorialSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [EditorialOption<Value>]

    var body: some View {
        HStack(spacing: -1) {
            ForEach(options) { option in
                let on = option.value == selection
                Button {
                    Haptics.selection()
                    selection = option.value
                } label: {
                    Text(option.label.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .kerning(1.1)
                        .foregroundStyle(on ? Color.brand : Color(.label).opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .overlay(
                            Rectangle().strokeBorder(on ? Color.brand : Color(.label).opacity(0.18),
                                                     lineWidth: 1)
                        )
                        .zIndex(on ? 1 : 0)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .animation(AppAnim.smooth, value: selection)
    }
}

// MARK: - Slider

/// "Arabic ——●—— 26" — a labelled slider with the value as metadata.
struct EditorialSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var labelWidth: CGFloat = 82

    var body: some View {
        HStack(spacing: 14) {
            Text(label)
                .font(.appSerif(15))
                .foregroundStyle(Color(.label).opacity(0.6))
                .frame(width: labelWidth, alignment: .leading)
            Slider(value: $value, in: range, step: 1)
                .tint(.brand)
            MetaText("\(Int(value))", size: 11)
                .frame(width: 24, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Type specimen slider
//
// Same control, but with a live sample of what the size does. Used by the
// reading-size settings, where a number alone means nothing.

struct EditorialSpecimenSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let sample: String
    var rightToLeft: Bool = false
    var italic: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            EditorialSlider(label: label, value: $value, range: range)

            Text(sample)
                .font(rightToLeft ? .appArabic(value) : .appSerif(value, italic: italic))
                .foregroundStyle(Color(.label).opacity(0.55))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: rightToLeft ? .trailing : .leading)
                .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight)
                .animation(.easeOut(duration: 0.12), value: value)
        }
    }
}
