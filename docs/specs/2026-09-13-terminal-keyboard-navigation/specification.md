# Terminal keyboard navigation

Requirements: [U17](../../wip/2026-09-11-keyboard-navigation/requirements.md).
Structural realization: [Program Design](program-design.md).

The terminal user needs predictable scrolling at two scales, movement between
shell prompts, and a direct return to the bottom. Command-Shift keeps both reading step sizes together. Shell-prompt movement is
secondary because custom agent TUIs do not necessarily expose conversation turns
as shell markers. Agent-specific TUI navigation remains future work.

## Selected behavior

| Binding | Action |
| --- | --- |
| Command-Shift-I / K | Scroll up / down 90% of the terminal viewport |
| Command-Shift-J / L | Scroll up / down exactly 33% of the terminal viewport |
| Option-Shift-J / L | Previous / next Ghostty shell-integration prompt |
| Command-Option-K | Scroll to terminal bottom |
| Option-Shift-I / K | Unassigned; reserved in the design for future agent-TUI navigation |

T1. The seven bindings perform these actions on the terminal that owns the input,
including a drawer terminal. They must not act on another pane when the source is
stale or ineligible. Contextual/explicit command invocation retains its existing
focused/targeted terminal rules. No action changes the active arrangement.

T2. Ghostty owns viewport scaling, integer-row truncation, clamping, scrollback and
shell markers. Prompt navigation does not infer agent-message boundaries. Missing
markers or exhausted scrollback do not cause synthetic movement or a substitute
session. Scrolling never sends shortcut text to the shell as a fallback.

T3. Existing keyboard ownership guards remain. Sidebar and blocked transient owners
do not dispatch terminal actions; editor ingress keeps its existing responder rules.
Management continues permitting terminal-owned actions under its existing target
validation policy. This change introduces no new Management restriction.
Retain existing app-owned reservation/consumption behavior, command-repeat handling
and Cmd-K clear-scrollback suppression. Unmodified Option-I/J/K/L and the separate
Option-Shift-Up/Down pinned-pane design are unchanged. Inbox is disconnected and
hidden and has no role in this map.

T4. Command-bar labels, help and shortcut hints describe the selected amount/direction
through the existing command catalog. New scrolling commands have the same terminal
targeting and IPC authority as the existing scrolling commands. No new toolbar or
persistent help strip is introduced. Hints follow the selected table; neither old 25% hints nor the old bottom chord remain.

## Journey and proof

    terminal owns input -> decode exact binding -> validate source/target
                        -> Ghostty action -> scroll or prompt destination
    blocked keyboard owner / stale target -> existing rejection or consumption

Prove all seven bindings and both unassigned future-TUI combinations, no per-context
collisions, amount/direction at the runtime/Ghostty boundary, correct main/drawer
targeting, protected keyboard owners and display metadata. Demonstrate real terminal
scrollback movement, boundary clamping, return to bottom, and marked-prompt movement
in the isolated app. Source/unit checks do not establish native key delivery or actual
scrolling. Broader sidebar/preview work remains separate.
