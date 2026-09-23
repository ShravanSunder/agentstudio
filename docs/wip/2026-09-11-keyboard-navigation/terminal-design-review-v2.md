# Revised terminal map review

Owner revision: primary Command-Shift-I/K scrolls 90%, Command-Shift-J/L scrolls
33%, Option-Shift-J/L keeps shell prompt jumps, Command-Option-K goes to bottom.
Option-Shift-I/K is unassigned and reserved for future agent-TUI navigation.

Second normal design round: terminal_map_v2_design_review completed a three-artifact
delta review; terminal_map_v2_dispel completed scope defense. This round follows the
owner's substantive key/amount revision; it is not a third round or recovery.

Accepted F1: Program Design needed an explicit current-to-proposed identity cutover.
Parent corrected it to retain the existing page-down and fractional runtime path,
hard-rename unpublished quarter AppCommand/AppShortcut IDs to scrollSmallStepUp/Down,
remove the old raw IDs without aliases, and preserve the existing IPC exposure,
required pane target, privilege and no-argument contract. Dispel confirmed this is
required and no unrequested mechanism was added. Parent verified current source
predecessors and corrected Program Design. Revised design is ready for this bounded
implementation update. No new owner decision or third design round is needed.

RED: terminal-map-v2-red.log, exit 1, one test/eight issues: seven old or missing
bindings and the formerly assigned Option-Shift-K. Compilation passed.
Provider-specific future TUI navigation is independent research and not implementation
authority. Existing source-identity guard and all other ownership policies remain.
