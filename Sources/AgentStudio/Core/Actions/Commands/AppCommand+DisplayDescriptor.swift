import Foundation

extension AppCommandSpec {
    var actionSpec: ActionSpec {
        ActionSpec(
            label: label,
            helpText: helpText,
            icon: icon
        )
    }

    func commandDisplayDescriptor(
        compactTooltipText: String? = nil,
        shortcutTextOverride: ShortcutDisplayText? = nil
    ) -> CommandDisplayDescriptor {
        commandDisplayDescriptor(
            compactTooltipText: compactTooltipText,
            shortcutDisplayText: shortcutTextOverride ?? commandBarShortcutTrigger?.displayText
        )
    }

    private func commandDisplayDescriptor(
        compactTooltipText: String?,
        shortcutDisplayText: ShortcutDisplayText?
    ) -> CommandDisplayDescriptor {
        CommandDisplayDescriptor(
            provenance: .appCommand(rawValue: command.rawValue),
            label: label,
            helpText: helpText,
            compactTooltipText: compactTooltipText,
            shortcutDisplayText: shortcutDisplayText
        )
    }

    var controlToolTip: String {
        controlToolTip()
    }

    func controlTooltipSource(
        textOverride: String? = nil,
        includeShortcut: Bool = true,
        shortcutTextOverride: ShortcutDisplayText? = nil
    ) -> ControlTooltipSource {
        let shortcutDisplayText =
            if includeShortcut {
                shortcutTextOverride ?? commandBarShortcutTrigger?.displayText
            } else {
                Optional<ShortcutDisplayText>.none
            }
        let descriptor = commandDisplayDescriptor(
            compactTooltipText: textOverride,
            shortcutDisplayText: shortcutDisplayText
        )
        let style: TooltipCopyStyle =
            if textOverride != nil || commandBarShortcutTrigger != nil {
                .compact
            } else {
                .helpText
            }
        return .display(descriptor, style: style)
    }

    func controlTooltipRenderValue(
        textOverride: String? = nil,
        includeShortcut: Bool = true,
        shortcutTextOverride: ShortcutDisplayText? = nil
    ) -> ControlTooltipRenderValue {
        ControlTooltipResolver.resolve(
            controlTooltipSource(
                textOverride: textOverride,
                includeShortcut: includeShortcut,
                shortcutTextOverride: shortcutTextOverride
            ))
    }

    func controlToolTip(
        textOverride: String? = nil,
        includeShortcut: Bool = true,
        shortcutTextOverride: ShortcutDisplayText? = nil
    ) -> String {
        controlTooltipRenderValue(
            textOverride: textOverride,
            includeShortcut: includeShortcut,
            shortcutTextOverride: shortcutTextOverride
        ).text
    }
}
