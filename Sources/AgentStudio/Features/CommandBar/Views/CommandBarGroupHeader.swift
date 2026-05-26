import SwiftUI

// MARK: - CommandBarGroupHeader

/// Title-case group header in accent-muted color (Linear style, NOT uppercased).
struct CommandBarGroupHeader: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.system(size: AppStyles.CommandBar.Rows.groupHeaderFontSize, weight: .semibold))
            .foregroundStyle(Color.accentColor.opacity(AppStyles.CommandBar.Rows.groupHeaderOpacity))
            .padding(.top, 8)
            .padding(.bottom, 4)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
