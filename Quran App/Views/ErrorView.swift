import SwiftUI

struct ErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .accessibilityHidden(true)
                .foregroundStyle(.orange)
            Text("Something went wrong")
                .font(.appSerif(17, weight: .semibold))
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            Button("Try Again", action: retry)
                .buttonStyle(.bordered)
                .tint(.brand)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}
