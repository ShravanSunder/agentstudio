import AppKit
import Foundation
import SwiftUI

enum ZoomManagementTitle {
    static func text(
        sourceOrdinal: Int?,
        activeArrangementName: String?
    ) -> String? {
        guard let sourceOrdinal else { return nil }
        let arrangementName =
            activeArrangementName?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !arrangementName.isEmpty else { return nil }
        return "\(sourceOrdinal) · \(arrangementName) · Zoom"
    }
}

@MainActor
struct ZoomPresentationChild {
    let paneId: UUID
    let paneSlot: ViewRegistry.PaneViewSlot
    let toolbarPresentation: PaneSurfaceToolbarPresentation
}

@MainActor
struct ZoomPresentationRenderState {
    let layout: Layout
    let children: [ZoomPresentationChild]
    let isCompanionVisible: Bool
    let parentToolbar: PaneSurfaceToolbarPresentation
}

@MainActor
struct ZoomPresentationContainer: View {
    let tabId: UUID?
    let sourcePaneId: UUID
    let sourceOrdinal: Int?
    let sourceContent: AnyView
    let companionContent: AnyView?
    let isCompanionVisible: Bool
    let parentToolbarPresentation: PaneSurfaceToolbarPresentation
    let store: WorkspaceStore
    let repoCache: RepoCacheAtom
    let appLifecycleStore: AppLifecycleAtom
    let closeTransitionCoordinator: PaneCloseTransitionCoordinator
    let paneInboxPresentation: PaneInboxPresentation?
    let workspaceWindowId: UUID?
    let actionDispatcher: PaneActionDispatching
    let onPaneFocusTrigger: PaneFocusTriggerHandler
    let onFocusPane: (UUID) -> Void
    let onOpenPaneGitHub: (UUID) -> Void
    let notificationCountForWorktree: (UUID) -> Int
    let viewRegistry: ViewRegistry
    let surfaceId: String
    let renderedPaneIds: Set<UUID>

    @State private var splitRatio: CGFloat
    @State private var zoomHovered = false
    @State private var showArrangementsHovered = false
    @State private var showsZoomToolbarLabel = false
    @State private var paneFrames: [UUID: CGRect] = [:]
    @State private var iconBarFrame: CGRect = .zero
    @State private var drawerDismissCoordinateView: NSView?

    init(
        tabId: UUID? = nil,
        sourcePaneId: UUID,
        sourceOrdinal: Int?,
        sourceContent: AnyView,
        companionContent: AnyView?,
        isCompanionVisible: Bool = true,
        parentToolbarPresentation: PaneSurfaceToolbarPresentation,
        splitRatio: Double,
        store: WorkspaceStore,
        repoCache: RepoCacheAtom = RepoCacheAtom(),
        appLifecycleStore: AppLifecycleAtom = AppLifecycleAtom(),
        closeTransitionCoordinator: PaneCloseTransitionCoordinator = PaneCloseTransitionCoordinator(),
        paneInboxPresentation: PaneInboxPresentation? = nil,
        workspaceWindowId: UUID? = nil,
        actionDispatcher: PaneActionDispatching,
        onPaneFocusTrigger: @escaping PaneFocusTriggerHandler,
        onFocusPane: @escaping (UUID) -> Void = { _ in },
        onOpenPaneGitHub: @escaping (UUID) -> Void = { _ in },
        notificationCountForWorktree: @escaping (UUID) -> Int = { _ in 0 },
        viewRegistry: ViewRegistry,
        surfaceId: String,
        renderedPaneIds: Set<UUID>
    ) {
        self.tabId = tabId
        self.sourcePaneId = sourcePaneId
        self.sourceOrdinal = sourceOrdinal
        self.sourceContent = sourceContent
        self.companionContent = companionContent
        self.isCompanionVisible = isCompanionVisible
        self.parentToolbarPresentation = parentToolbarPresentation
        self.store = store
        self.repoCache = repoCache
        self.appLifecycleStore = appLifecycleStore
        self.closeTransitionCoordinator = closeTransitionCoordinator
        self.paneInboxPresentation = paneInboxPresentation
        self.workspaceWindowId = workspaceWindowId
        self.actionDispatcher = actionDispatcher
        self.onPaneFocusTrigger = onPaneFocusTrigger
        self.onFocusPane = onFocusPane
        self.onOpenPaneGitHub = onOpenPaneGitHub
        self.notificationCountForWorktree = notificationCountForWorktree
        self.viewRegistry = viewRegistry
        self.surfaceId = surfaceId
        self.renderedPaneIds = renderedPaneIds
        _splitRatio = State(initialValue: CGFloat(splitRatio))
    }

    var body: some View {
        GeometryReader { tabGeometry in
            ZStack {
                VStack(spacing: 0) {
                    SplitView(
                        .horizontal,
                        viewerPresentationSplit,
                        left: { sourceContent },
                        right: {
                            companionContent
                        },
                        onEqualize: {
                            splitRatio = 0.5
                            persistSplitRatio(0.5)
                        },
                        showsDivider: isCompanionVisible,
                        reservesDividerSpace: companionContent != nil,
                        onResizeEnd: {
                            persistSplitRatio(splitRatio)
                        }
                    )

                    parentToolbar
                }

                drawerPanelOverlay(tabSize: tabGeometry.size)

                if atom(\.managementLayer).isActive {
                    zoomManagementChrome
                }
            }
            .coordinateSpace(name: "tabContainer")
            .background(
                DrawerDismissCoordinateSpaceBridge { view in
                    if drawerDismissCoordinateView !== view {
                        drawerDismissCoordinateView = view
                    }
                }
                .allowsHitTesting(false)
            )
            .onPreferenceChange(PaneFramePreferenceKey.self) { paneFrames = $0 }
            .onPreferenceChange(DrawerIconBarFrameKey.self) { iconBarFrame = $0 }
        }
        .onAppear {
            viewRegistry.surfaceRenderedIds(surfaceId, ids: renderedPaneIds)
        }
        .onChange(of: renderedPaneIds) { _, paneIds in
            viewRegistry.surfaceRenderedIds(surfaceId, ids: paneIds)
        }
        .onDisappear {
            viewRegistry.unregisterSurface(surfaceId)
        }
    }

    private func persistSplitRatio(_ splitRatio: CGFloat) {
        guard let tabId else { return }
        store.panePresentationAtom.setZoomSplitRatio(
            Double(splitRatio),
            inTab: tabId
        )
    }

    private var viewerPresentationSplit: Binding<CGFloat> {
        Binding(
            get: {
                isCompanionVisible ? splitRatio : 1
            },
            set: { newSplitRatio in
                guard isCompanionVisible else { return }
                splitRatio = newSplitRatio
            }
        )
    }

    @ViewBuilder
    private var parentToolbar: some View {
        if case .zoom(let toolbarModel) = parentToolbarPresentation {
            let zoomAction = toolbarModel.zoomAction.projectingVisibleLabel(
                showsZoomToolbarLabel ? toolbarModel.zoomAction.state.visibleLabel : nil
            )
            PaneSurfaceToolbarHost(
                anchorPaneId: sourcePaneId,
                locationTargetPaneId: sourcePaneId,
                drawer: store.paneAtom.pane(sourcePaneId)?.drawer,
                leadingToolbarActions: [],
                contextToolbarActions: [zoomAction, toolbarModel.viewerAction],
                store: store,
                paneInboxPresentation: paneInboxPresentation,
                workspaceWindowId: workspaceWindowId,
                actionDispatcher: actionDispatcher,
                onPaneFocusTrigger: onPaneFocusTrigger
            )
            .fixedSize(horizontal: false, vertical: true)
            .onAppear {
                withAnimation(.easeInOut(duration: AppStyles.General.Animation.standard)) {
                    showsZoomToolbarLabel = true
                }
            }
        }
    }

    @ViewBuilder
    private var zoomManagementChrome: some View {
        if case .zoom(let toolbarModel) = parentToolbarPresentation {
            ZStack {
                Rectangle()
                    .fill(Color.black)
                    .opacity(AppStyles.Shell.ManagementLayer.modeDimmingOpacity)
                    .allowsHitTesting(false)

                VStack {
                    HStack {
                        Spacer()
                        if let zoomManagementTitle {
                            zoomManagementTitleView(zoomManagementTitle)
                        }
                        Spacer()
                    }
                    .padding(AppStyles.General.Spacing.standard)
                    Spacer()
                }
                .allowsHitTesting(false)

                VStack {
                    HStack(spacing: AppStyles.General.Spacing.standard) {
                        managementCircleButton(
                            action: toolbarModel.zoomAction,
                            isHovered: zoomHovered,
                            accessibilityIdentifier: "paneManagement.zoom"
                        )
                        .onHover { zoomHovered = $0 }

                        if let showArrangementsAction = toolbarModel.showArrangementsAction {
                            managementCircleButton(
                                action: showArrangementsAction,
                                isHovered: showArrangementsHovered,
                                accessibilityIdentifier: "paneManagement.showArrangements"
                            )
                            .onHover { showArrangementsHovered = $0 }
                        }

                        Spacer()
                    }
                    .padding(AppStyles.General.Spacing.standard)
                    Spacer()
                }
            }
        }
    }

    private var zoomManagementTitle: String? {
        let activeArrangementName =
            tabId
            .flatMap { store.tabLayoutAtom.tab($0) }?
            .activeArrangement
            .name
        return ZoomManagementTitle.text(
            sourceOrdinal: sourceOrdinal,
            activeArrangementName: activeArrangementName
        )
    }

    private func zoomManagementTitleView(_ title: String) -> some View {
        Text(title)
            .font(.system(size: AppStyles.Shell.ManagementLayer.actionIconSize, weight: .bold))
            .foregroundStyle(
                .white.opacity(AppStyles.Shell.ManagementLayer.iconOpacity(isHovered: false))
            )
            .padding(.horizontal, AppStyles.General.Spacing.standard)
            .frame(height: AppStyles.Shell.ManagementLayer.actionSize)
            .background(
                Capsule()
                    .fill(
                        Color.black.opacity(
                            AppStyles.Shell.ManagementLayer.backgroundOpacity(isHovered: false)
                        )
                    )
                    .shadow(color: .black.opacity(AppStyles.General.Stroke.visible), radius: 4, y: 2)
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .background {
                AccessibilityLabelBridge(
                    identifier: "paneManagement.zoomTitle",
                    label: title
                )
            }
    }

    @ViewBuilder
    private func drawerPanelOverlay(tabSize: CGSize) -> some View {
        if let tabId {
            DrawerPanelOverlay(
                store: store,
                repoCache: repoCache,
                viewRegistry: viewRegistry,
                appLifecycleStore: appLifecycleStore,
                closeTransitionCoordinator: closeTransitionCoordinator,
                tabId: tabId,
                paneFrames: paneFrames,
                tabSize: tabSize,
                iconBarFrame: iconBarFrame,
                actionDispatcher: actionDispatcher,
                onPaneFocusTrigger: onPaneFocusTrigger,
                onFocusPane: onFocusPane,
                paneInboxPresentation: paneInboxPresentation,
                onOpenPaneGitHub: onOpenPaneGitHub,
                notificationCountForWorktree: notificationCountForWorktree,
                drawerDropTarget: nil,
                dismissCoordinateView: drawerDismissCoordinateView,
                workspaceWindowId: workspaceWindowId,
                dragSourcePaneId: nil
            )
        }
    }

    private func managementCircleButton(
        action: PaneSurfaceToolbarAction,
        isHovered: Bool,
        accessibilityIdentifier: String
    ) -> some View {
        Button(action: action.perform) {
            Group {
                switch action.state.icon {
                case .system(let symbol):
                    Image(systemName: symbol.rawValue)
                        .font(.system(size: AppStyles.Shell.ManagementLayer.actionIconSize, weight: .bold))
                case .octicon(let symbol):
                    OcticonImage(
                        name: symbol.rawValue,
                        size: AppStyles.Shell.ManagementLayer.actionIconSize
                    )
                }
            }
            .foregroundStyle(
                .white.opacity(
                    AppStyles.Shell.ManagementLayer.iconOpacity(isHovered: isHovered)
                )
            )
            .frame(
                width: AppStyles.Shell.ManagementLayer.actionSize,
                height: AppStyles.Shell.ManagementLayer.actionSize
            )
            .background(
                Circle()
                    .fill(
                        Color.black.opacity(
                            AppStyles.Shell.ManagementLayer.backgroundOpacity(isHovered: isHovered)
                        )
                    )
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!action.state.isEnabled)
        .controlHelp(action.state.tooltip)
        .accessibilityHidden(true)
        .background {
            AccessibilityPressBridge(
                identifier: accessibilityIdentifier,
                label: action.state.label,
                isEnabled: action.state.isEnabled,
                action: action.perform
            )
        }
    }

    static func resolveRenderState(
        presentation: ZoomPresentation,
        viewRegistry: ViewRegistry,
        parentToolbar: PaneSurfaceToolbarPresentation
    ) -> ZoomPresentationRenderState? {
        guard case .zoom = parentToolbar else {
            return nil
        }
        let sourcePaneSlot = viewRegistry.slot(for: presentation.sourcePaneId)
        guard sourcePaneSlot.host != nil else {
            return nil
        }

        var children = [
            ZoomPresentationChild(
                paneId: presentation.sourcePaneId,
                paneSlot: sourcePaneSlot,
                toolbarPresentation: .hidden
            )
        ]

        let layout: Layout
        let isCompanionVisible: Bool
        switch presentation.viewerPresentation {
        case .unavailable, .retryable:
            layout = Layout(paneId: presentation.sourcePaneId)
            isCompanionVisible = false

        case .retainedHidden(let companionPaneId), .retainedVisible(let companionPaneId):
            let companionPaneSlot = viewRegistry.slot(for: companionPaneId)
            guard companionPaneSlot.host != nil else {
                return nil
            }

            children.append(
                ZoomPresentationChild(
                    paneId: companionPaneId,
                    paneSlot: companionPaneSlot,
                    toolbarPresentation: .hidden
                )
            )
            let sourceRatio = presentation.transientSplitRatio ?? 0.5
            layout = Layout(
                panes: [
                    Layout.PaneEntry(paneId: presentation.sourcePaneId, ratio: sourceRatio),
                    Layout.PaneEntry(paneId: companionPaneId, ratio: 1 - sourceRatio),
                ],
                dividerIds: [UUIDv7.generate()]
            )
            if case .retainedVisible = presentation.viewerPresentation {
                isCompanionVisible = true
            } else {
                isCompanionVisible = false
            }
        }

        return ZoomPresentationRenderState(
            layout: layout,
            children: children,
            isCompanionVisible: isCompanionVisible,
            parentToolbar: parentToolbar
        )
    }
}
