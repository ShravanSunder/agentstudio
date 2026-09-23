# Terminal navigation — selected design and implementation

The owner settled the terminal family and authorized implementation on 2026-09-13.
The selected map below is implemented and supersedes the earlier tested mapping.
Focused validation and [revised native terminal proof](terminal-native-v2-proof.md)
passed. The full aggregate passed at source HEAD `10383d28f` after main integration.
Independent terminal implementation review found no defects; the shared sidebar delivery
has corrected its snapshot-capture regression and is validating that correction;
fresh pinned timing proof remains outstanding.
The governing design review is [terminal-design-review-v2.md](terminal-design-review-v2.md).
The immutable implementation plan is
`tmp/plan-workflows/2026-09-13-terminal-keyboard-navigation-v2.md`.

## Existing execution system

Sources: [bindings](../../../Sources/AgentStudio/Core/Actions/Commands/AppShortcut.swift),
[typed actions](../../../Sources/AgentStudio/Features/Terminal/Hosting/TerminalSurfaceActionPerforming.swift),
and [dispatch](../../../Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager+TerminalActions.swift). These actions already enter Ghostty through
its binding-action API. No new terminal calculation engine is necessary.

Existing neighboring families: Command-J/L switches tabs; Option-I/J/K/L is pane/drawer
spatial movement; Command-Option-I/J/L is arrangement picker/previous/next. Command-
Shift-Enter is Zoom, Command-Shift-O opens the pane location in Finder. Do not assume
these chords are free. Inbox is already disconnected and hidden; the owner excludes
it from the active shortcut design. Its rejection cases do not define a future family.

## What Ghostty actually provides

Pinned producer source `82232ecde`, inspected after DeepWiki pointers:
- src/input/Binding.zig: negative fractional/line amounts move up; positive down.
  `jump_to_prompt` explicitly requires shell integration.
- src/Surface.zig: page movement uses the current viewport height; fractional movement
  scales that height; `scroll_to_selection` needs a selection; prompt jumps queue the
  terminal action rather than inspecting agent text.
- src/termio/Termio.zig and src/terminal/PageList.zig: prompt navigation searches marked
  prompts in the active screen. No matching marks means no movement. Row 0 is the top
  of retained history; offsets clamp at the active area.

A shell prompt is not automatically an agent conversation turn. A coding agent would
need compatible semantic marks for this action to traverse its turns. Full-screen /
alternate-screen content has different scrollback behavior; Ghostty cannot recover
conversation history that the application does not retain in that screen. Our exact
shell-integration propagation through zmx and individual agents is not runtime-proven
by this source inspection.

## Current owner decisions

After testing Codex's custom TUI, the owner moved ordinary scrolling onto
Command-Shift and kept shell-prompt navigation as the secondary Option-Shift pair.
Shell prompts still mean Ghostty markers; these are not a promised agent-message
navigation feature.

| Binding | Selected action |
| --- | --- |
| Command-Shift-I | Scroll up 90%: scroll_page_fractional:-0.9 |
| Command-Shift-K | Scroll down 90%: scroll_page_fractional:0.9 |
| Command-Shift-J | Scroll up 33%: scroll_page_fractional:-0.33 |
| Command-Shift-L | Scroll down 33%: scroll_page_fractional:0.33 |
| Option-Shift-J | Previous shell prompt: jump_to_prompt:-1 |
| Option-Shift-L | Next shell prompt: jump_to_prompt:1 |
| Command-Option-K | Terminal bottom: scroll_to_bottom |
| Option-Shift-I / K | Reserved for future agent-TUI navigation; unassigned now |

There is no top-jump shortcut. The two reserved keys have no app command or
consumption behavior yet. Option-Shift-Up/Down remains the separately selected
pinned-pane pair, whose sidebar implementation is tracked separately.

The small-step policy is exactly 0.33, not one-third. The unpublished quarter-page
command names become scrollSmallStepUp/Down so their identities describe the role.
The shared fractional Ghostty runtime path does not change.

Source implements this table and native main-terminal proof passed. Earlier 25%/old-modifier
native observations remain historical evidence, not proof of the revised mapping.
Provider-specific Codex, Claude Code and Cursor CLI findings are in the separate
[future-work research note](agent-tui-navigation-research.md); no key forwarding,
hooks, profile or renderer changes have been selected for that future work.
