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
            if state.isNested {
                CommandBarScopePill(
                    parent: state.scopePillParent,
                    child: state.scopePillChild,
                    onDismiss: { state.popToRoot() }
                )
            } else {
                scopeIconView
            }

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

    @ViewBuilder
    private var scopeIconView: some View {
        if state.scopeIconIsOcticon {
            OcticonImage(name: state.scopeIcon, size: 16)
                .foregroundStyle(.primary.opacity(0.35))
        } else {
            Image(systemName: state.scopeIcon)
                .font(.system(size: AppStyle.textBase, weight: .medium))
                .foregroundStyle(.primary.opacity(0.35))
                .frame(width: 16, height: 16)
        }
    }
}
