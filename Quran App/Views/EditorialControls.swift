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
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 8)
                Text(currentLabel)
                    .font(.appSerif(16))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.label(13, weight: .bold))
                    .foregroundStyle(Palette.textTertiary)
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
                .foregroundStyle(Palette.textPrimary)
            if let caption {
                Text("— \(caption)")
                    .font(.appSerif(14))
                    .foregroundStyle(Palette.textSecondary)
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
                        .font(.label(14, weight: .medium))
                        .foregroundStyle(iconTint ?? Color.brand)
                        .frame(width: 22)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.appSerif(17))
                        .foregroundStyle(Palette.textPrimary)
                    if let caption {
                        Text(caption)
                            .font(.appSerif(14))
                            .foregroundStyle(Palette.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 8)
                if let value {
                    Text(value)
                        .font(.appSerif(16))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.label(13, weight: .bold))
                    .foregroundStyle(Palette.textTertiary)
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
                .foregroundStyle(Palette.textPrimary)
            Spacer(minLength: 8)
            Text(value)
                .font(.appSerif(16))
                .foregroundStyle(Palette.textSecondary)
        }
    }
}

/// "label ……… value ↗" row that opens a web page, for the About block.
struct EditorialLinkRow: View {
    let title: String
    let value: String
    let url: URL

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            Haptics.tap()
            openURL(url)
        } label: {
            HStack(spacing: 10) {
                Text(title)
                    .font(.appSerif(17))
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 8)
                Text(value)
                    .font(.appSerif(16))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                Image(systemName: "arrow.up.right")
                    .font(.label(12, weight: .bold))
                    .foregroundStyle(Palette.textTertiary)
            }
            .frame(minHeight: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isLink)
        .accessibilityHint("Opens \(value) in Safari")
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
                    // Sentence case, 13 pt, never shrunk or truncated. 36 pt tall drawn, 44 pt tappable.
                    Text(option.label)
                        .font(TypeScale.caption)
                        .foregroundStyle(on ? Color.brand : Palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.xs)
                        .frame(maxWidth: .infinity, minHeight: MinSize.segmentedControl)
                        .overlay(
                            Rectangle().strokeBorder(on ? Color.brand : Palette.separator,
                                                     lineWidth: 1)
                        )
                        .zIndex(on ? 1 : 0)
                        .padding(.vertical, (MinSize.hitTarget - MinSize.segmentedControl) / 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityShowsLargeContentViewer { Text(option.label) }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility5)
        .animation(Motion.standard, value: selection)
    }
}
