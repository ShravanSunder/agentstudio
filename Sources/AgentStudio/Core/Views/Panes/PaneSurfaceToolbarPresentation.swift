import AgentStudioInfrastructure
import Foundation

@MainActor
package struct PaneSurfaceToolbarAction {
    package enum SelectionEmphasis: Equatable, Sendable {
        case standard
        case accent
    }

    package struct State: Equatable, Sendable {
        package let label: String
        package let accessibilityIdentifier: String
        package let icon: CommandIcon
        package let tooltip: ControlTooltipRenderValue
        package let isEnabled: Bool
        package let isSelected: Bool
        package let visibleLabel: String?
        package let selectionEmphasis: SelectionEmphasis

        package init(
            label: String,
            accessibilityIdentifier: String,
            icon: CommandIcon,
            tooltip: ControlTooltipRenderValue,
            isEnabled: Bool,
            isSelected: Bool,
            visibleLabel: String? = nil,
            selectionEmphasis: SelectionEmphasis = .standard
        ) {
            self.label = label
            self.accessibilityIdentifier = accessibilityIdentifier
            self.icon = icon
            self.tooltip = tooltip
            self.isEnabled = isEnabled
            self.isSelected = isSelected
            self.visibleLabel = visibleLabel
            self.selectionEmphasis = selectionEmphasis
        }
    }

    package let state: State
    package let perform: @MainActor @Sendable () -> Void

    package init(
        state: State,
        perform: @escaping @MainActor @Sendable () -> Void
    ) {
        self.state = state
        self.perform = perform
    }

    package func resolving(isEnabled: Bool, isSelected: Bool) -> Self {
        Self(
            state: State(
                label: state.label,
                accessibilityIdentifier: state.accessibilityIdentifier,
                icon: state.icon,
                tooltip: state.tooltip,
                isEnabled: isEnabled,
                isSelected: isSelected,
                visibleLabel: state.visibleLabel,
                selectionEmphasis: state.selectionEmphasis
            ),
            perform: perform
        )
    }

    package func projectingPresentation(
        label: String,
        icon: CommandIcon,
        tooltip: ControlTooltipRenderValue,
        isEnabled: Bool,
        isSelected: Bool,
        visibleLabel: String? = nil,
        selectionEmphasis: SelectionEmphasis? = nil
    ) -> Self {
        Self(
            state: State(
                label: label,
                accessibilityIdentifier: state.accessibilityIdentifier,
                icon: icon,
                tooltip: tooltip,
                isEnabled: isEnabled,
                isSelected: isSelected,
                visibleLabel: visibleLabel,
                selectionEmphasis: selectionEmphasis ?? state.selectionEmphasis
            ),
            perform: perform
        )
    }

    package func projectingVisibleLabel(_ visibleLabel: String?) -> Self {
        Self(
            state: State(
                label: state.label,
                accessibilityIdentifier: state.accessibilityIdentifier,
                icon: state.icon,
                tooltip: state.tooltip,
                isEnabled: state.isEnabled,
                isSelected: state.isSelected,
                visibleLabel: visibleLabel,
                selectionEmphasis: state.selectionEmphasis
            ),
            perform: perform
        )
    }
}

@MainActor
package struct TerminalModeToolbarActions {
    package let zoomAction: PaneSurfaceToolbarAction?
    package let viewerAction: PaneSurfaceToolbarAction?

    package init(
        zoomAction: PaneSurfaceToolbarAction?,
        viewerAction: PaneSurfaceToolbarAction?
    ) {
        self.zoomAction = zoomAction
        self.viewerAction = viewerAction
    }
}

@MainActor
package struct TerminalToolbarModel {
    package let modeActions: TerminalModeToolbarActions?
    package let showArrangementsAction: PaneSurfaceToolbarAction?

    package init(
        modeActions: TerminalModeToolbarActions? = nil,
        showArrangementsAction: PaneSurfaceToolbarAction? = nil
    ) {
        self.modeActions = modeActions
        self.showArrangementsAction = showArrangementsAction
    }
}

@MainActor
package struct WebviewToolbarModel {
    package let showArrangementsAction: PaneSurfaceToolbarAction?

    package init(showArrangementsAction: PaneSurfaceToolbarAction? = nil) {
        self.showArrangementsAction = showArrangementsAction
    }
}

@MainActor
package struct CodeViewerToolbarModel {
    package let showArrangementsAction: PaneSurfaceToolbarAction?

    package init(showArrangementsAction: PaneSurfaceToolbarAction? = nil) {
        self.showArrangementsAction = showArrangementsAction
    }
}

@MainActor
package struct UnsupportedToolbarModel {
    package let showArrangementsAction: PaneSurfaceToolbarAction?

    package init(showArrangementsAction: PaneSurfaceToolbarAction? = nil) {
        self.showArrangementsAction = showArrangementsAction
    }
}

@MainActor
package struct ViewerToolbarModel {
    package let showArrangementsAction: PaneSurfaceToolbarAction?

    package init(showArrangementsAction: PaneSurfaceToolbarAction? = nil) {
        self.showArrangementsAction = showArrangementsAction
    }
}

@MainActor
package struct ZoomToolbarModel {
    package let viewerAction: PaneSurfaceToolbarAction?
    package let zoomAction: PaneSurfaceToolbarAction?
    package let showArrangementsAction: PaneSurfaceToolbarAction?

    package init(
        viewerAction: PaneSurfaceToolbarAction?,
        zoomAction: PaneSurfaceToolbarAction?,
        showArrangementsAction: PaneSurfaceToolbarAction? = nil
    ) {
        self.viewerAction = viewerAction
        self.zoomAction = zoomAction
        self.showArrangementsAction = showArrangementsAction
    }
}

@MainActor
package enum PaneSurfaceToolbarPresentation {
    case terminal(TerminalToolbarModel)
    case webview(WebviewToolbarModel)
    case codeViewer(CodeViewerToolbarModel)
    case unsupported(UnsupportedToolbarModel)
    case viewer(ViewerToolbarModel)
    case zoom(ZoomToolbarModel)
    case hidden

    package var reservesToolbarLayout: Bool {
        if case .hidden = self {
            return false
        }
        return true
    }

    package var leadingActions: [PaneSurfaceToolbarAction] {
        switch self {
        case .terminal:
            []
        case .webview:
            []
        case .codeViewer:
            []
        case .unsupported:
            []
        case .viewer:
            []
        case .zoom:
            []
        case .hidden:
            []
        }
    }

    package var contextActions: [PaneSurfaceToolbarAction] {
        switch self {
        case .terminal(let model):
            guard let modeActions = model.modeActions else { return [] }
            return [modeActions.zoomAction, modeActions.viewerAction].compactMap(\.self)
        case .zoom(let model):
            return [model.zoomAction, model.viewerAction].compactMap(\.self)
        case .webview, .codeViewer, .unsupported, .viewer, .hidden:
            return []
        }
    }

    package var actions: [PaneSurfaceToolbarAction] {
        leadingActions + contextActions
    }

    package var zoomAction: PaneSurfaceToolbarAction? {
        switch self {
        case .terminal(let model):
            model.modeActions?.zoomAction
        case .zoom(let model):
            model.zoomAction
        case .webview, .codeViewer, .unsupported, .viewer, .hidden:
            nil
        }
    }

    package var showArrangementsAction: PaneSurfaceToolbarAction? {
        switch self {
        case .terminal(let model):
            model.showArrangementsAction
        case .webview(let model):
            model.showArrangementsAction
        case .codeViewer(let model):
            model.showArrangementsAction
        case .unsupported(let model):
            model.showArrangementsAction
        case .viewer(let model):
            model.showArrangementsAction
        case .zoom(let model):
            model.showArrangementsAction
        case .hidden:
            nil
        }
    }
}

package enum PaneSurfaceToolbarPlacement: Equatable, Sendable {
    case normalMainPane
    case drawerChild
    case zoomChild
}

@MainActor
package enum PaneSurfaceToolbarResolver {
    package static func resolve(
        content: PaneContent,
        placement: PaneSurfaceToolbarPlacement,
        terminalModeActions: TerminalModeToolbarActions? = nil,
        showArrangementsAction: PaneSurfaceToolbarAction? = nil
    ) -> PaneSurfaceToolbarPresentation {
        if placement == .zoomChild {
            return .hidden
        }

        let resolvedTerminalModeActions =
            placement == .normalMainPane
            ? terminalModeActions.map { actions in
                TerminalModeToolbarActions(
                    zoomAction: actions.zoomAction.map { zoomAction in
                        zoomAction.projectingPresentation(
                            label: zoomAction.state.label,
                            icon: zoomAction.state.icon,
                            tooltip: zoomAction.state.tooltip,
                            isEnabled: zoomAction.state.isEnabled,
                            isSelected: false,
                            visibleLabel: nil
                        )
                    },
                    viewerAction: actions.viewerAction.map { viewerAction in
                        viewerAction.resolving(
                            isEnabled: viewerAction.state.isEnabled,
                            isSelected: false
                        )
                    }
                )
            }
            : nil

        switch content {
        case .terminal:
            return .terminal(
                TerminalToolbarModel(
                    modeActions: resolvedTerminalModeActions,
                    showArrangementsAction: showArrangementsAction
                )
            )
        case .webview:
            return .webview(
                WebviewToolbarModel(
                    showArrangementsAction: showArrangementsAction
                )
            )
        case .bridgePanel:
            return .viewer(
                ViewerToolbarModel(
                    showArrangementsAction: showArrangementsAction
                )
            )
        case .codeViewer:
            return .codeViewer(
                CodeViewerToolbarModel(
                    showArrangementsAction: showArrangementsAction
                )
            )
        case .unsupported:
            return .unsupported(
                UnsupportedToolbarModel(
                    showArrangementsAction: showArrangementsAction
                )
            )
        }
    }

    package static func resolveZoom(
        viewerPresentation: ZoomViewerPresentation,
        viewerAction: PaneSurfaceToolbarAction?,
        zoomAction: PaneSurfaceToolbarAction?,
        showArrangementsAction: PaneSurfaceToolbarAction? = nil
    ) -> PaneSurfaceToolbarPresentation {
        let viewerState: (isEnabled: Bool, isSelected: Bool) =
            switch viewerPresentation {
            case .unavailable:
                (false, false)
            case .retryable, .retainedHidden:
                (true, false)
            case .retainedVisible:
                (true, true)
            }

        return .zoom(
            ZoomToolbarModel(
                viewerAction: viewerAction.map { viewerAction in
                    viewerAction.resolving(
                        isEnabled: viewerState.isEnabled,
                        isSelected: viewerState.isSelected
                    )
                },
                zoomAction: zoomAction.map { zoomAction in
                    zoomAction.resolving(
                        isEnabled: true,
                        isSelected: true
                    )
                    .projectingPresentation(
                        label: zoomAction.state.label,
                        icon: zoomAction.state.icon,
                        tooltip: zoomAction.state.tooltip,
                        isEnabled: true,
                        isSelected: true,
                        visibleLabel: "Zoomed",
                        selectionEmphasis: .accent
                    )
                },
                showArrangementsAction: showArrangementsAction
            )
        )
    }
}
