import Foundation
import GhosttyKit

extension Ghostty.ActionRouter {
    static func handleObservedDisplayAction(
        _ actionTag: GhosttyActionTag,
        rawActionTag: UInt32,
        target: ghostty_target_s,
        action: ghostty_action_s,
        routingLookupProvider: @escaping GhosttyActionRoutingLookupProvider
    ) -> Bool? {
        switch actionTag {
        case .desktopNotification:
            guard
                let titlePointer = action.action.desktop_notification.title,
                let bodyPointer = action.action.desktop_notification.body
            else {
                logUnknownAction(
                    actionTag: rawActionTag,
                    target: target,
                    routingLookupProvider: routingLookupProvider
                )
                return false
            }
            return routeActionToTerminalRuntime(
                actionTag: rawActionTag,
                payload: .desktopNotification(
                    title: String(cString: titlePointer),
                    body: String(cString: bodyPointer)
                ),
                target: target,
                routingLookupProvider: routingLookupProvider,
                handledResult: false
            )
        case .promptTitle:
            return routeActionToTerminalRuntime(
                actionTag: rawActionTag,
                payload: .promptTitle(
                    scopeRawValue: UInt32(truncatingIfNeeded: action.action.prompt_title.rawValue)
                ),
                target: target,
                routingLookupProvider: routingLookupProvider,
                handledResult: false
            )
        case .rendererHealth:
            return routeActionToTerminalRuntime(
                actionTag: rawActionTag,
                payload: .rendererHealth(
                    rawValue: UInt32(truncatingIfNeeded: action.action.renderer_health.rawValue)
                ),
                target: target,
                routingLookupProvider: routingLookupProvider,
                handledResult: false
            )
        case .mouseShape:
            return routeActionToTerminalRuntime(
                actionTag: rawActionTag,
                payload: .mouseShape(
                    rawValue: UInt32(truncatingIfNeeded: action.action.mouse_shape.rawValue)
                ),
                target: target,
                routingLookupProvider: routingLookupProvider,
                handledResult: false
            )
        case .mouseVisibility:
            return routeActionToTerminalRuntime(
                actionTag: rawActionTag,
                payload: .mouseVisibility(
                    rawValue: UInt32(truncatingIfNeeded: action.action.mouse_visibility.rawValue)
                ),
                target: target,
                routingLookupProvider: routingLookupProvider,
                handledResult: false
            )
        case .mouseOverLink:
            let url: String?
            if let urlPtr = action.action.mouse_over_link.url, action.action.mouse_over_link.len > 0 {
                let data = Data(bytes: urlPtr, count: Int(action.action.mouse_over_link.len))
                guard let decodedURL = String(data: data, encoding: .utf8) else {
                    ghosttyLogger.warning(
                        "Dropped mouseOverLink action tag \(rawActionTag, privacy: .public): invalid UTF-8 payload"
                    )
                    return false
                }
                url = decodedURL
            } else {
                url = nil
            }
            return routeActionToTerminalRuntime(
                actionTag: rawActionTag,
                payload: .mouseOverLink(url),
                target: target,
                routingLookupProvider: routingLookupProvider,
                handledResult: false
            )
        case .scrollbar:
            return routeActionToTerminalRuntime(
                actionTag: rawActionTag,
                payload: .scrollbar(
                    total: action.action.scrollbar.total,
                    offset: action.action.scrollbar.offset,
                    length: action.action.scrollbar.len
                ),
                target: target,
                routingLookupProvider: routingLookupProvider,
                handledResult: false
            )
        default:
            return nil
        }
    }

    static func handleObservedInputAction(
        _ actionTag: GhosttyActionTag,
        rawActionTag: UInt32,
        target: ghostty_target_s,
        action: ghostty_action_s,
        routingLookupProvider: @escaping GhosttyActionRoutingLookupProvider
    ) -> Bool? {
        switch actionTag {
        case .keySequence:
            let trigger = action.action.key_sequence.trigger
            let key = keyValue(for: trigger)
            return routeActionToTerminalRuntime(
                actionTag: rawActionTag,
                payload: .keySequence(
                    active: action.action.key_sequence.active,
                    triggerTag: UInt32(truncatingIfNeeded: trigger.tag.rawValue),
                    key: key,
                    mods: trigger.mods.rawValue
                ),
                target: target,
                routingLookupProvider: routingLookupProvider,
                handledResult: false
            )
        case .keyTable:
            return routeActionToTerminalRuntime(
                actionTag: rawActionTag,
                payload: .keyTable(
                    tagRawValue: UInt32(truncatingIfNeeded: action.action.key_table.tag.rawValue),
                    activateName: keyTableActivateName(from: action.action.key_table)
                ),
                target: target,
                routingLookupProvider: routingLookupProvider,
                handledResult: false
            )
        case .secureInput:
            return routeActionToTerminalRuntime(
                actionTag: rawActionTag,
                payload: .secureInput(
                    modeRawValue: UInt32(truncatingIfNeeded: action.action.secure_input.rawValue)
                ),
                target: target,
                routingLookupProvider: routingLookupProvider,
                handledResult: false
            )
        case .readOnly:
            return routeActionToTerminalRuntime(
                actionTag: rawActionTag,
                payload: .readOnly(
                    modeRawValue: UInt32(truncatingIfNeeded: action.action.readonly.rawValue)
                ),
                target: target,
                routingLookupProvider: routingLookupProvider,
                handledResult: false
            )
        default:
            return nil
        }
    }

    static func handleObservedConfigurationAction(
        _ actionTag: GhosttyActionTag,
        rawActionTag: UInt32,
        target: ghostty_target_s,
        action: ghostty_action_s,
        routingLookupProvider: @escaping GhosttyActionRoutingLookupProvider
    ) -> Bool? {
        switch actionTag {
        case .colorChange:
            return routeActionToTerminalRuntime(
                actionTag: rawActionTag,
                payload: .colorChange(
                    kindRawValue: action.action.color_change.kind.rawValue,
                    red: action.action.color_change.r,
                    green: action.action.color_change.g,
                    blue: action.action.color_change.b
                ),
                target: target,
                routingLookupProvider: routingLookupProvider,
                handledResult: false
            )
        case .reloadConfig:
            return routeActionToTerminalRuntime(
                actionTag: rawActionTag,
                payload: .reloadConfig(soft: action.action.reload_config.soft),
                target: target,
                routingLookupProvider: routingLookupProvider,
                handledResult: false
            )
        case .configChange:
            return routeActionToTerminalRuntime(
                actionTag: rawActionTag,
                payload: .configChange,
                target: target,
                routingLookupProvider: routingLookupProvider,
                handledResult: false
            )
        default:
            return nil
        }
    }

    static func handleObservedSearchAction(
        _ actionTag: GhosttyActionTag,
        rawActionTag: UInt32,
        target: ghostty_target_s,
        action: ghostty_action_s,
        routingLookupProvider: @escaping GhosttyActionRoutingLookupProvider
    ) -> Bool? {
        switch actionTag {
        case .startSearch:
            return routeActionToTerminalRuntime(
                actionTag: rawActionTag,
                payload: .startSearch(action.action.start_search.needle.map { String(cString: $0) }),
                target: target,
                routingLookupProvider: routingLookupProvider,
                handledResult: false
            )
        case .endSearch:
            return routeActionToTerminalRuntime(
                actionTag: rawActionTag,
                payload: .endSearch,
                target: target,
                routingLookupProvider: routingLookupProvider,
                handledResult: false
            )
        case .searchTotal:
            return routeActionToTerminalRuntime(
                actionTag: rawActionTag,
                payload: .searchTotal(Int(action.action.search_total.total)),
                target: target,
                routingLookupProvider: routingLookupProvider,
                handledResult: false
            )
        case .searchSelected:
            return routeActionToTerminalRuntime(
                actionTag: rawActionTag,
                payload: .searchSelected(Int(action.action.search_selected.selected)),
                target: target,
                routingLookupProvider: routingLookupProvider,
                handledResult: false
            )
        default:
            return nil
        }
    }

    static func handleObservedControlAction(
        _ actionTag: GhosttyActionTag,
        rawActionTag: UInt32,
        target: ghostty_target_s,
        action: ghostty_action_s,
        routingLookupProvider: @escaping GhosttyActionRoutingLookupProvider
    ) -> Bool? {
        switch actionTag {
        case .openURL:
            guard let urlPointer = action.action.open_url.url else {
                logUnknownAction(
                    actionTag: rawActionTag,
                    target: target,
                    routingLookupProvider: routingLookupProvider
                )
                return false
            }
            let urlData = Data(bytes: urlPointer, count: Int(action.action.open_url.len))
            guard let url = String(data: urlData, encoding: .utf8) else {
                ghosttyLogger.warning(
                    "Dropped openURL action tag \(rawActionTag, privacy: .public): invalid UTF-8 payload"
                )
                return false
            }
            return routeActionToTerminalRuntime(
                actionTag: rawActionTag,
                payload: .openURL(
                    url: url,
                    kindRawValue: UInt32(truncatingIfNeeded: action.action.open_url.kind.rawValue)
                ),
                target: target,
                routingLookupProvider: routingLookupProvider,
                handledResult: false
            )
        case .progressReport:
            return routeActionToTerminalRuntime(
                actionTag: rawActionTag,
                payload: .progressReport(
                    stateRawValue: UInt32(truncatingIfNeeded: action.action.progress_report.state.rawValue),
                    progress: action.action.progress_report.progress
                ),
                target: target,
                routingLookupProvider: routingLookupProvider,
                handledResult: false
            )
        default:
            return nil
        }
    }

    private static func keyTableActivateName(from keyTable: ghostty_action_key_table_s) -> String? {
        guard keyTable.tag == GHOSTTY_KEY_TABLE_ACTIVATE,
            let namePtr = keyTable.value.activate.name
        else {
            return nil
        }

        let data = Data(bytes: namePtr, count: Int(keyTable.value.activate.len))
        guard let activateName = String(data: data, encoding: .utf8) else {
            ghosttyLogger.warning("Dropped keyTable activate payload: invalid UTF-8")
            return nil
        }
        return activateName
    }

    private static func keyValue(for trigger: ghostty_input_trigger_s) -> UInt32? {
        switch trigger.tag {
        case GHOSTTY_TRIGGER_PHYSICAL:
            return UInt32(truncatingIfNeeded: trigger.key.physical.rawValue)
        case GHOSTTY_TRIGGER_UNICODE:
            return trigger.key.unicode
        case GHOSTTY_TRIGGER_CATCH_ALL:
            return nil
        default:
            return nil
        }
    }
}
