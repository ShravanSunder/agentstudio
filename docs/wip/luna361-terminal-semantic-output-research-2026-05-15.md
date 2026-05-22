# LUNA-361 Terminal Semantic Output Research

Date: 2026-05-15
Branch: `notification-osc-smoke-semantic-output`

## Current Finding

Agent Studio has terminal activity facts, but it does not currently receive raw
terminal output text as a runtime event.

Live today:

- Ghostty semantic actions that already enter `PaneRuntimeEvent.terminal`.
- `TerminalActivityAtom` stores high-churn context: progress, cwd, secure input,
  recent URL open requests, scrollbar state, and inferred output bursts.
- `TerminalActivityRouter` coalesces unattended scrollback growth into
  `.terminalActivity(.unseenActivitySettled(...))`.
- Inbox promotion consumes that settled activity without depending on tracing.

Not live today:

- A `PaneRuntimeEvent` carrying printed terminal text.
- A host callback for every stdout/stderr line.
- A semantic artifact atom or store.

## Ghostty Source Notes

The vendored Ghostty tree has useful ingredients, but no currently wired
Agent Studio source for arbitrary printed text:

- `vendor/ghostty/macos/Sources/Ghostty/Ghostty.Surface.swift` exposes
  `sendText(_:)`, which sends text into the terminal, not text out of it.
- `vendor/ghostty/src/input/command.zig` includes `write_screen_file`, which can
  write screen contents to a temp file through a user action, but Agent Studio
  does not currently route that as a low-volume runtime fact.
- `vendor/ghostty/src/terminal/osc/parsers/semantic_prompt.zig` and
  `context_signal.zig` parse semantic/context OSC protocols. Those are
  structured terminal signals, not a general stream of model stdout.

## First Safe Slice

This branch adds a pure `TerminalSemanticArtifactExtractor` for text that is
already available to a future source. It intentionally remains unwired:

- no new atom
- no new store
- no new runtime event case
- no notification promotion path

That keeps the parser testable while preserving the architecture boundary until
we decide which source should feed it: structured agent RPC, a Ghostty screen
snapshot action, or a future Ghostty semantic-link/text callback.

## Next Decision

Before adding `TerminalSemanticArtifactAtom` or
`.terminalActivity(.semanticArtifactsProduced(...))`, choose the source:

1. Structured agent RPC posts file references directly.
2. A user/action-triggered Ghostty screen snapshot is parsed after capture.
3. A new Ghostty/host callback carries semantic links or text ranges.

Scrollbar growth and `openURLRequested` remain insufficient substitutes for
printed file paths.
