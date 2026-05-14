import SwiftUI

struct UnreadCountBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(
                .system(
                    size: AppStyles.Components.NotificationBadge.fontSize,
                    weight: .semibold
                )
            )
            .padding(.horizontal, AppStyles.Components.NotificationBadge.horizontalPadding)
            .padding(.vertical, AppStyles.Components.NotificationBadge.verticalPadding)
            .background(Capsule().fill(.red))
            .foregroundStyle(.white)
            .fixedSize()
    }
}
