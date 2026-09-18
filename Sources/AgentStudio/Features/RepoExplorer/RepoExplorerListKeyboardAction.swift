import AgentStudioCore
import Foundation

enum RepoExplorerListKeyboardAction: Equatable, Sendable {
    case moveSelectionUp
    case moveSelectionDown
    case moveToParentOrCollapseGroup
    case moveToFirstChildOrExpandGroup
    case activateSelection
    case returnFocus
    case activateNumberedDestination(Int)

    var trigger: ShortcutTrigger {
        ShortcutTrigger(key: inputKey, modifiers: [])
    }

    var actionSpec: ActionSpec {
        switch self {
        case .moveSelectionUp:
            ActionSpec(
                label: "Previous Sidebar Item",
                helpText: "Select the previous sidebar destination or group",
                icon: .system(.arrowUp)
            )
        case .moveSelectionDown:
            ActionSpec(
                label: "Next Sidebar Item",
                helpText: "Select the next sidebar destination or group",
                icon: .system(.arrowDown)
            )
        case .moveToParentOrCollapseGroup:
            ActionSpec(
                label: "Sidebar Parent",
                helpText: "Collapse the selected group or select the parent group",
                icon: .system(.arrowLeft)
            )
        case .moveToFirstChildOrExpandGroup:
            ActionSpec(
                label: "Sidebar Child",
                helpText: "Expand the selected group or select its first destination",
                icon: .system(.arrowRight)
            )
        case .activateSelection:
            ActionSpec(
                label: "Open Sidebar Selection",
                helpText: "Open the selected sidebar destination or toggle its group",
                icon: .system(.arrowRightCircle)
            )
        case .returnFocus:
            ActionSpec(
                label: "Leave Sidebar",
                helpText: "Return keyboard focus to the workspace",
                icon: .system(.xmark)
            )
        case .activateNumberedDestination(let digit):
            ActionSpec(
                label: "Open Sidebar Destination \(digit)",
                helpText: "Open numbered sidebar destination \(digit)",
                icon: .system(.circle)
            )
        }
    }

    static func resolve(_ trigger: ShortcutTrigger) -> Self? {
        guard trigger.modifiers.isEmpty else { return nil }
        return switch trigger.key {
        case .arrow(.up): .moveSelectionUp
        case .arrow(.down): .moveSelectionDown
        case .arrow(.left): .moveToParentOrCollapseGroup
        case .arrow(.right): .moveToFirstChildOrExpandGroup
        case .enter: .activateSelection
        case .escape: .returnFocus
        case .character(let key): numberedDestinationAction(for: key)
        }
    }

    private var inputKey: ShortcutInputKey {
        switch self {
        case .moveSelectionUp: .arrow(.up)
        case .moveSelectionDown: .arrow(.down)
        case .moveToParentOrCollapseGroup: .arrow(.left)
        case .moveToFirstChildOrExpandGroup: .arrow(.right)
        case .activateSelection: .enter
        case .returnFocus: .escape
        case .activateNumberedDestination(let digit): .character(Self.characterKey(for: digit))
        }
    }

    private static func numberedDestinationAction(
        for key: ShortcutCharacterKey
    ) -> Self? {
        switch key {
        case .digit1: .activateNumberedDestination(1)
        case .digit2: .activateNumberedDestination(2)
        case .digit3: .activateNumberedDestination(3)
        case .digit4: .activateNumberedDestination(4)
        case .digit5: .activateNumberedDestination(5)
        case .digit6: .activateNumberedDestination(6)
        case .digit7: .activateNumberedDestination(7)
        case .digit8: .activateNumberedDestination(8)
        case .digit9: .activateNumberedDestination(9)
        default: nil
        }
    }

    private static func characterKey(for digit: Int) -> ShortcutCharacterKey {
        switch digit {
        case 1: .digit1
        case 2: .digit2
        case 3: .digit3
        case 4: .digit4
        case 5: .digit5
        case 6: .digit6
        case 7: .digit7
        case 8: .digit8
        case 9: .digit9
        default: preconditionFailure("Sidebar destination digit must be between 1 and 9")
        }
    }
}

enum RepoExplorerListKeyboardEffect: Equatable, Sendable {
    case commandRequest(RepoExplorerCommandPresentationRequest)
    case toggleGroup(groupID: String)
    case setGroupExpanded(groupID: String, isExpanded: Bool)
    case focusPane(paneID: UUID)
}
