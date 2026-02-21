import SwiftUI

// MARK: - CommandBarSearchField

/// Search input with scope icon and placeholder per scope.
/// Uses NSTextField wrapper for keyboard interception (arrows, Enter, Escape).
struct CommandBarSearchField: View {
    @Bindable var state: CommandBarState
    let onArrowUp: () -> Void
    let onArrowDown: () -> Void
    let onEnter: () -> Void
    let onBackspaceOnEmpty: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Scope icon
            Image(systemName: state.scopeIcon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary.opacity(0.35))
                .frame(width: 16, height: 16)

            // Text input with keyboard interception
            CommandBarTextField(
                text: $state.rawInput,
                placeholder: state.placeholder,
                onArrowUp: onArrowUp,
                onArrowDown: onArrowDown,
                onEnter: onEnter,
                onBackspaceOnEmpty: onBackspaceOnEmpty
            )
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }
}
