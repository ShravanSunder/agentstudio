import SwiftUI

struct EmptyArrangementPlaceholderView: View {
    static let title = "No panes visible"

    var body: some View {
        VStack(spacing: AppStyles.General.Spacing.standard) {
            Image(systemName: "rectangle.split.3x1")
                .font(.system(size: AppStyles.General.Typography.text2xl, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(Self.title)
                .font(.system(size: AppStyles.General.Typography.textSm, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}
