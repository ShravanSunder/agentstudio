# Agent TUI navigation: future work

Research snapshot: 2026-09-13. This is source/documentation evidence, not runtime
proof against the user's installed agents. The selected terminal family stays in
[the keyboard map](keyboard-map.md). Option-Shift-I/K remains unassigned.

## Different owners of movement

```text
Agent Studio shortcut -> Ghostty scrollback / shell markers
Agent's own shortcut  -> agent transcript / logical conversation turns
```

Ghostty can visit marked shell prompts. An agent must emit useful markers for
those destinations to correspond to conversation turns. A terminal viewport and
an agent's virtual transcript need not contain the same history.

| Agent | Evidence found | Limit of this evidence |
| --- | --- | --- |
| Claude Code | Official accessibility docs explicitly describe OSC 133 turn-boundary markers and mention Ghostty. Fullscreen transcript mode has Ctrl-O, then `{` / `}` for previous/next prompt. | Documentation does not settle marker emission across every renderer/configuration. No local integration proof yet. |
| Codex | Released 0.154.0 pager supports line, page, half-page and top/bottom movement. Semantic older/newer user-message movement also exists in backtrack preview. | Preview is coupled to editing: Enter forks for editing. No separate configurable semantic pager action was found. Installed version was not checked. |
| Cursor CLI | Documented prompt history, diff review and `/rewind` have distinct purposes. | No documented read-only rendered-turn jump was found; this is not proof the binary lacks one. Rewind changes conversation/files and cannot stand in for scrolling. |

Codex's backtrack preview can be traversed without committing an edit. Do not
describe it as having no read-only semantic navigation. The relevant distinction
is that navigation shares the edit-preview interaction, while its pager exposes
viewport movement. The research lanes found no Codex-authored OSC 133 turn markers
in the inspected release/main sources; arbitrary subprocess output was outside
that claim.

## Primary sources

- [Claude Code turn markers](https://code.claude.com/docs/en/accessibility#jump-between-turns)
- [Claude Code fullscreen transcript](https://code.claude.com/docs/en/fullscreen)
- [Claude Code transcript viewer](https://code.claude.com/docs/en/interactive-mode#transcript-viewer)
- [Codex 0.154.0 pager defaults](https://github.com/openai/codex/blob/6b9826e3aa83b1a5947db50f4332cb9c65f1b340/codex-rs/tui/src/keymap.rs#L1706-L1724)
- [Codex backtrack input](https://github.com/openai/codex/blob/6b9826e3aa83b1a5947db50f4332cb9c65f1b340/codex-rs/tui/src/app_backtrack/legacy_input.rs)
- [Cursor CLI use](https://cursor.com/docs/cli/using)
- [Cursor slash commands](https://cursor.com/docs/cli/reference/slash-commands)

Primary snapshots used by the research lanes are under
`tmp/research-workflows/2026-09-13-agent-tui-navigation/sources/`. Parent rechecked
the cached Claude marker/transcript text and Codex pager defaults. Provider behavior
must be tested on the relevant installed version before a future integration design.

## Delivery boundary

No agent adapters, blind transcript-mode macros, hooks, profile edits, text parsing
or key forwarding are part of this PR. Future design must establish the agent-owned
navigation contract and the return-to-input behavior before consuming the reserved
Option-Shift-I/K pair. Existing Option-Shift-J/L means Ghostty shell-prompt movement.
