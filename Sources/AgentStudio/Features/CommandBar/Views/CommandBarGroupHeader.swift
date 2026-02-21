import SwiftUI

// MARK: - CommandBarGroupHeader

/// Title-case group header in accent-muted color (Linear style, NOT uppercased).
struct CommandBarGroupHeader: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.accentColor.opacity(0.50))
            .padding(.top, 8)
            .padding(.bottom, 4)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
