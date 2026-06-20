import Foundation

struct CommandDisplayDescriptor: Equatable, Sendable {
    let provenance: CommandDisplayProvenance
    let label: String
    let helpText: String
    let compactTooltipText: String?
    let shortcutDisplayText: ShortcutDisplayText?
}

enum CommandDisplayProvenance: Equatable, Sendable {
    case appCommand(rawValue: String)
    case localAction(rawValue: String)
    case localShortcut(rawValue: String)
    case dynamicData(DynamicTooltipReason)
}

enum DynamicTooltipReason: Equatable, Sendable {
    case filesystemPath
    case userDataLabel
    case stateReadout
    case compositeMenuSummary
}

enum TooltipCopyStyle: Equatable, Sendable {
    case compact
    case helpText
    case label(includeShortcut: Bool = true)
}

enum ControlTooltipSource: Equatable, Sendable {
    case display(CommandDisplayDescriptor, style: TooltipCopyStyle = .compact)
    case dynamicData(DynamicTooltipReason, text: String, shortcut: ShortcutDisplayText? = nil)
}

enum ControlTooltipResolver {
    static func resolve(_ source: ControlTooltipSource) -> ControlTooltipRenderValue {
        switch source {
        case .display(let descriptor, let style):
            return resolveDisplay(descriptor, style: style)
        case .dynamicData(_, let text, let shortcut):
            return resolveText(text, shortcutDisplayText: shortcut, includesShortcut: true)
        }
    }

    private static func resolveDisplay(
        _ descriptor: CommandDisplayDescriptor,
        style: TooltipCopyStyle
    ) -> ControlTooltipRenderValue {
        let resolvedBaseText: String
        let shouldIncludeShortcut: Bool

        switch style {
        case .compact:
            resolvedBaseText = descriptor.compactTooltipText ?? descriptor.label
            shouldIncludeShortcut = true
        case .helpText:
            resolvedBaseText = descriptor.helpText
            shouldIncludeShortcut = true
        case .label(let includeShortcut):
            resolvedBaseText = descriptor.label
            shouldIncludeShortcut = includeShortcut
        }

        return resolveText(
            resolvedBaseText,
            shortcutDisplayText: descriptor.shortcutDisplayText,
            includesShortcut: shouldIncludeShortcut
        )
    }

    private static func resolveText(
        _ text: String,
        shortcutDisplayText: ShortcutDisplayText?,
        includesShortcut: Bool
    ) -> ControlTooltipRenderValue {
        guard includesShortcut, let shortcutDisplayText else {
            return ControlTooltipRenderValue(text: text, shortcutDisplayText: nil)
        }

        return ControlTooltipRenderValue(
            text: "\(text) (\(shortcutDisplayText.value))",
            shortcutDisplayText: shortcutDisplayText
        )
    }
}
