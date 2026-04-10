import SwiftUI

// MARK: - CommandBarFooter

/// Dynamic keyboard hints footer for the selected item.
struct CommandBarFooter: View {
    let hints: [FooterHint]

    var body: some View {
        HStack(spacing: 16) {
            ForEach(hints) { hint in
                footerHint(hint.key, hint.label)
            }
        }
        .frame(height: 32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }

    private func footerHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: AppStyle.textXs, weight: .medium, design: .monospaced))
            Text(label)
                .font(.system(size: AppStyle.textXs))
        }
        .foregroundStyle(.primary.opacity(0.3))
    }
}
