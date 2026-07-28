import Foundation

@MainActor
struct PaneSurfaceToolbarAction {
    enum SelectionEmphasis: Equatable, Sendable {
        case standard
        case accent
    }

    struct State: Equatable, Sendable {
        let label: String
        let accessibilityIdentifier: String
        let icon: CommandIcon
        let tooltip: ControlTooltipRenderValue
        let isEnabled: Bool
        let isSelected: Bool
        let visibleLabel: String?
        let selectionEmphasis: SelectionEmphasis

        init(
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

    let state: State
    let perform: @MainActor @Sendable () -> Void

    func resolving(isEnabled: Bool, isSelected: Bool) -> Self {
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

    func projectingPresentation(
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

    func projectingVisibleLabel(_ visibleLabel: String?) -> Self {
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
struct TerminalModeToolbarActions {
    let zoomAction: PaneSurfaceToolbarAction
    let viewerAction: PaneSurfaceToolbarAction
}

@MainActor
struct TerminalToolbarModel {
    let modeActions: TerminalModeToolbarActions?
    let showArrangementsAction: PaneSurfaceToolbarAction?

    init(
        modeActions: TerminalModeToolbarActions? = nil,
        showArrangementsAction: PaneSurfaceToolbarAction? = nil
    ) {
        self.modeActions = modeActions
        self.showArrangementsAction = showArrangementsAction
    }
}

@MainActor
struct WebviewToolbarModel {
    let showArrangementsAction: PaneSurfaceToolbarAction?

    init(showArrangementsAction: PaneSurfaceToolbarAction? = nil) {
        self.showArrangementsAction = showArrangementsAction
    }
}

@MainActor
struct CodeViewerToolbarModel {
    let showArrangementsAction: PaneSurfaceToolbarAction?

    init(showArrangementsAction: PaneSurfaceToolbarAction? = nil) {
        self.showArrangementsAction = showArrangementsAction
    }
}

@MainActor
struct UnsupportedToolbarModel {
    let showArrangementsAction: PaneSurfaceToolbarAction?

    init(showArrangementsAction: PaneSurfaceToolbarAction? = nil) {
        self.showArrangementsAction = showArrangementsAction
    }
}

@MainActor
struct ViewerToolbarModel {
    let showArrangementsAction: PaneSurfaceToolbarAction?

    init(showArrangementsAction: PaneSurfaceToolbarAction? = nil) {
        self.showArrangementsAction = showArrangementsAction
    }
}

@MainActor
struct ZoomToolbarModel {
    let viewerAction: PaneSurfaceToolbarAction
    let zoomAction: PaneSurfaceToolbarAction
    let showArrangementsAction: PaneSurfaceToolbarAction?

    init(
        viewerAction: PaneSurfaceToolbarAction,
        zoomAction: PaneSurfaceToolbarAction,
        showArrangementsAction: PaneSurfaceToolbarAction? = nil
    ) {
        self.viewerAction = viewerAction
        self.zoomAction = zoomAction
        self.showArrangementsAction = showArrangementsAction
    }
}

@MainActor
enum PaneSurfaceToolbarPresentation {
    case terminal(TerminalToolbarModel)
    case webview(WebviewToolbarModel)
    case codeViewer(CodeViewerToolbarModel)
    case unsupported(UnsupportedToolbarModel)
    case viewer(ViewerToolbarModel)
    case zoom(ZoomToolbarModel)
    case hidden

    var reservesToolbarLayout: Bool {
        if case .hidden = self {
            return false
        }
        return true
    }

    var leadingActions: [PaneSurfaceToolbarAction] {
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

    var contextActions: [PaneSurfaceToolbarAction] {
        switch self {
        case .terminal(let model):
            guard let modeActions = model.modeActions else { return [] }
            return [modeActions.zoomAction, modeActions.viewerAction]
        case .zoom(let model):
            return [model.zoomAction, model.viewerAction]
        case .webview, .codeViewer, .unsupported, .viewer, .hidden:
            return []
        }
    }

    var actions: [PaneSurfaceToolbarAction] {
        leadingActions + contextActions
    }

    var zoomAction: PaneSurfaceToolbarAction? {
        switch self {
        case .terminal(let model):
            model.modeActions?.zoomAction
        case .zoom(let model):
            model.zoomAction
        case .webview, .codeViewer, .unsupported, .viewer, .hidden:
            nil
        }
    }

    var showArrangementsAction: PaneSurfaceToolbarAction? {
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

enum PaneSurfaceToolbarPlacement: Equatable, Sendable {
    case normalMainPane
    case drawerChild
    case zoomChild
}

@MainActor
enum PaneSurfaceToolbarResolver {
    static func resolve(
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
                    zoomAction: actions.zoomAction.projectingPresentation(
                        label: actions.zoomAction.state.label,
                        icon: actions.zoomAction.state.icon,
                        tooltip: actions.zoomAction.state.tooltip,
                        isEnabled: actions.zoomAction.state.isEnabled,
                        isSelected: false,
                        visibleLabel: nil
                    ),
                    viewerAction: actions.viewerAction.resolving(
                        isEnabled: actions.viewerAction.state.isEnabled,
                        isSelected: false
                    )
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

    static func resolveZoom(
        viewerPresentation: ZoomViewerPresentation,
        viewerAction: PaneSurfaceToolbarAction,
        zoomAction: PaneSurfaceToolbarAction,
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
                viewerAction: viewerAction.resolving(
                    isEnabled: viewerState.isEnabled,
                    isSelected: viewerState.isSelected
                ),
                zoomAction: zoomAction.resolving(
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
                ),
                showArrangementsAction: showArrangementsAction
            )
        )
    }
}
