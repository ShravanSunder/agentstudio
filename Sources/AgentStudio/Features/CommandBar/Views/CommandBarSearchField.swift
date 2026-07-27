import AgentStudioCore
import AgentStudioInfrastructure
import SwiftUI

// MARK: - CommandBarSearchField

/// Search input with scope icon and placeholder per scope.
/// Uses NSTextField wrapper for keyboard interception (arrows, Enter, Escape).
package struct CommandBarSearchField: View {
    @Bindable var state: CommandBarState
    let octiconLoader: OcticonLoader
    let onArrowUp: () -> Void
    let onArrowDown: () -> Void
    let onEnter: (EnterModifier) -> Void
    let onShortcutTrigger: (ShortcutTrigger) -> Bool
    let onBackspaceOnEmpty: () -> Void

    package init(
        state: CommandBarState,
        octiconLoader: OcticonLoader,
        onArrowUp: @escaping () -> Void,
        onArrowDown: @escaping () -> Void,
        onEnter: @escaping (EnterModifier) -> Void,
        onShortcutTrigger: @escaping (ShortcutTrigger) -> Bool,
        onBackspaceOnEmpty: @escaping () -> Void
    ) {
        self.state = state
        self.octiconLoader = octiconLoader
        self.onArrowUp = onArrowUp
        self.onArrowDown = onArrowDown
        self.onEnter = onEnter
        self.onShortcutTrigger = onShortcutTrigger
        self.onBackspaceOnEmpty = onBackspaceOnEmpty
    }

    package var body: some View {
        HStack(spacing: 10) {
            if state.isNested, let pillLabel = state.scopePillLabel {
                CommandBarScopePill(
                    label: pillLabel,
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
                onShortcutTrigger: onShortcutTrigger,
                onBackspaceOnEmpty: onBackspaceOnEmpty
            )
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    @ViewBuilder
    private var scopeIconView: some View {
        if state.scopeIconIsOcticon {
            OcticonImage(name: state.scopeIcon, size: 16, loader: octiconLoader)
                .foregroundStyle(.primary.opacity(0.35))
        } else {
            Image(systemName: state.scopeIcon)
                .font(.system(size: AppStyles.General.Typography.textBase, weight: .medium))
                .foregroundStyle(.primary.opacity(0.35))
                .frame(width: 16, height: 16)
        }
    }
}
