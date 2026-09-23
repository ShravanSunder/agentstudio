import AgentStudioCore
import AgentStudioInfrastructure
import AppKit
import SwiftUI

@MainActor
final class PaneManagementContextMenuPresenter: NSObject, NSMenuDelegate {
    private let octiconLoader: OcticonLoader
    private var actionsByTag: [Int: () -> Void] = [:]
    private var destinationActionTags: Set<Int> = []
    private var nextActionTag = 0
    private var destinationProvider: (() -> [PaneMoveDestinationMenuPresenter.Destination])?
    private weak var moveDestinationMenu: NSMenu?

    init(octiconLoader: OcticonLoader) {
        self.octiconLoader = octiconLoader
    }

    func present(
        extractPresentation: PaneLeafCommandPresentation?,
        movePresentation: PaneLeafCommandPresentation?,
        destinationProvider: @escaping () -> [PaneMoveDestinationMenuPresenter.Destination],
        event: NSEvent,
        in view: NSView
    ) -> Bool {
        guard
            let menu = makeMenu(
                extractPresentation: extractPresentation,
                movePresentation: movePresentation,
                destinationProvider: destinationProvider
            )
        else {
            return false
        }

        NSMenu.popUpContextMenu(menu, with: event, for: view)
        resetPresentation()
        return true
    }

    func makeMenu(
        extractPresentation: PaneLeafCommandPresentation?,
        movePresentation: PaneLeafCommandPresentation?,
        destinationProvider: @escaping () -> [PaneMoveDestinationMenuPresenter.Destination]
    ) -> NSMenu? {
        resetPresentation()
        guard extractPresentation != nil || movePresentation != nil else { return nil }

        let menu = makeEmptyMenu()
        if let extractPresentation {
            addAction(
                title: extractPresentation.spec.label,
                icon: extractPresentation.spec.icon,
                isEnabled: extractPresentation.isEnabled,
                to: menu,
                perform: extractPresentation.perform
            )
        }

        if let movePresentation {
            let destinationMenu = makeEmptyMenu()
            destinationMenu.delegate = self
            self.destinationProvider = destinationProvider
            moveDestinationMenu = destinationMenu

            let moveItem = NSMenuItem(
                title: movePresentation.spec.label,
                action: nil,
                keyEquivalent: ""
            )
            moveItem.image = image(
                for: movePresentation.spec.icon,
                accessibilityDescription: movePresentation.spec.label
            )
            moveItem.isEnabled = movePresentation.isEnabled
            moveItem.submenu = destinationMenu
            menu.addItem(moveItem)
        }

        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === moveDestinationMenu else { return }

        for actionTag in destinationActionTags {
            actionsByTag[actionTag] = nil
        }
        destinationActionTags.removeAll(keepingCapacity: true)
        menu.removeAllItems()

        for destination in destinationProvider?() ?? [] {
            let actionTag = addAction(
                title: destination.title,
                icon: nil,
                isEnabled: true,
                to: menu,
                perform: destination.perform
            )
            destinationActionTags.insert(actionTag)
        }
    }

    private func resetPresentation() {
        actionsByTag.removeAll(keepingCapacity: true)
        destinationActionTags.removeAll(keepingCapacity: true)
        nextActionTag = 0
        destinationProvider = nil
        moveDestinationMenu?.delegate = nil
        moveDestinationMenu = nil
    }

    @discardableResult
    private func addAction(
        title: String,
        icon: CommandIcon?,
        isEnabled: Bool,
        to menu: NSMenu,
        perform: @escaping () -> Void
    ) -> Int {
        let actionTag = nextActionTag
        nextActionTag += 1
        actionsByTag[actionTag] = perform

        let item = NSMenuItem(
            title: title,
            action: #selector(activateMenuItem(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.tag = actionTag
        item.image = image(for: icon, accessibilityDescription: title)
        item.isEnabled = isEnabled
        menu.addItem(item)
        return actionTag
    }

    private func image(
        for icon: CommandIcon?,
        accessibilityDescription: String
    ) -> NSImage? {
        guard let icon else { return nil }
        switch icon {
        case .system:
            return icon.nsImage(accessibilityDescription: accessibilityDescription)
        case .octicon(let symbol):
            return octiconLoader.image(named: symbol.rawValue)
        }
    }

    private func makeEmptyMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        return menu
    }

    @objc
    private func activateMenuItem(_ sender: NSMenuItem) {
        actionsByTag[sender.tag]?()
    }
}

@MainActor
struct PaneManagementContextMenuCaptureBridge: NSViewRepresentable {
    let isEnabled: Bool
    let onContextMenuRequest: (NSEvent, NSView) -> Bool

    func makeNSView(context _: Context) -> PaneManagementContextMenuCaptureView {
        let view = PaneManagementContextMenuCaptureView()
        view.update(isEnabled: isEnabled, onContextMenuRequest: onContextMenuRequest)
        return view
    }

    func updateNSView(
        _ nsView: PaneManagementContextMenuCaptureView,
        context _: Context
    ) {
        nsView.update(isEnabled: isEnabled, onContextMenuRequest: onContextMenuRequest)
    }

    static func dismantleNSView(
        _ nsView: PaneManagementContextMenuCaptureView,
        coordinator _: ()
    ) {
        nsView.detach()
    }
}

@MainActor
final class PaneManagementContextMenuCaptureView: NSView {
    typealias ContextMenuRequest = (NSEvent, NSView) -> Bool
    typealias EventMonitorInstaller = (
        NSEvent.EventTypeMask,
        @escaping (NSEvent) -> NSEvent?
    ) -> Any?
    typealias EventMonitorRemover = (Any) -> Void

    private let eventMonitorInstaller: EventMonitorInstaller
    private let eventMonitorRemover: EventMonitorRemover
    private var isEnabled = false
    private var onContextMenuRequest: ContextMenuRequest = { _, _ in false }
    private var eventMonitor: Any?

    var hasInstalledEventMonitor: Bool { eventMonitor != nil }

    override init(frame frameRect: NSRect) {
        eventMonitorInstaller = { eventMask, eventHandler in
            NSEvent.addLocalMonitorForEvents(
                matching: eventMask,
                handler: eventHandler
            )
        }
        eventMonitorRemover = NSEvent.removeMonitor
        super.init(frame: frameRect)
    }

    init(
        frame frameRect: NSRect,
        eventMonitorInstaller: @escaping EventMonitorInstaller,
        eventMonitorRemover: @escaping EventMonitorRemover
    ) {
        self.eventMonitorInstaller = eventMonitorInstaller
        self.eventMonitorRemover = eventMonitorRemover
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    isolated deinit {
        removeEventMonitor()
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateEventMonitorRegistration()
    }

    func update(
        isEnabled: Bool,
        onContextMenuRequest: @escaping ContextMenuRequest
    ) {
        self.isEnabled = isEnabled
        self.onContextMenuRequest = onContextMenuRequest
        updateEventMonitorRegistration()
    }

    func detach() {
        isEnabled = false
        onContextMenuRequest = { _, _ in false }
        removeEventMonitor()
    }

    func processContextMenuEvent(_ event: NSEvent) -> NSEvent? {
        guard Self.isContextMenuGesture(event) else { return event }
        guard isEnabled else { return event }
        guard let window, event.windowNumber == window.windowNumber else { return event }
        guard !isHiddenOrHasHiddenAncestor else { return event }

        let location = convert(event.locationInWindow, from: nil)
        guard visibleRect.contains(location) else { return event }
        return onContextMenuRequest(event, self) ? nil : event
    }

    static func isContextMenuGesture(_ event: NSEvent) -> Bool {
        event.type == .rightMouseDown
            || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
    }

    private func updateEventMonitorRegistration() {
        guard isEnabled, window != nil else {
            removeEventMonitor()
            return
        }
        guard eventMonitor == nil else { return }

        eventMonitor = eventMonitorInstaller(
            [.rightMouseDown, .leftMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            return self.processContextMenuEvent(event)
        }
    }

    private func removeEventMonitor() {
        guard let eventMonitor else { return }
        eventMonitorRemover(eventMonitor)
        self.eventMonitor = nil
    }
}
