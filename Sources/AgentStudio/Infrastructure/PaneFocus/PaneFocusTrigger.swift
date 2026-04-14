import Foundation

enum PaneFocusTrigger: Sendable, Equatable {
    case contentClick(PaneContentClickFocusTrigger)
    case tabClick(PaneTabClickFocusTrigger)
    case drawer(PaneDrawerFocusTrigger)
    case keyboard(PaneKeyboardFocusTrigger)
    case mode(PaneModeFocusTrigger)
    case refocusRequest(PaneRefocusRequestTrigger)
    case command(PaneCommandFocusTrigger)
}

struct PaneContentClickFocusTrigger: Sendable, Equatable {
    enum Location: Sendable, Equatable {
        case content
        case chrome
    }

    enum ClickPhase: Sendable, Equatable {
        case completed
    }

    let targetPaneId: UUID
    let location: Location
    let clickPhase: ClickPhase
}

struct PaneTabClickFocusTrigger: Sendable, Equatable {
    let targetTabId: UUID
}

enum PaneDrawerFocusTrigger: Sendable, Equatable {
    case selectPane(parentPaneId: UUID, drawerPaneId: UUID)
    case toggle(parentPaneId: UUID)
}

enum PaneKeyboardFocusTrigger: Sendable, Equatable {
    case moveToPane(tabId: UUID, paneId: UUID, paneKind: PaneFocusContext.PaneKind)
}

struct PaneModeFocusTrigger: Sendable, Equatable {
    enum Transition: Sendable, Equatable {
        case enteredManagementMode
        case exitedManagementMode
    }

    enum Source: Sendable, Equatable {
        case keyboardShortcut
        case command
    }

    let transition: Transition
    let source: Source
}

struct PaneRefocusRequestTrigger: Sendable, Equatable {
    enum Reason: Sendable, Equatable {
        case explicit
        case windowBecameKey
        case managementModeExited
    }

    let reason: Reason
}

enum PaneCommandFocusTrigger: Sendable, Equatable {
    case focusPane(tabId: UUID, paneId: UUID)
    case selectTab(UUID)
    case paneCreated(paneId: UUID, paneKind: PaneFocusContext.PaneKind)
}
