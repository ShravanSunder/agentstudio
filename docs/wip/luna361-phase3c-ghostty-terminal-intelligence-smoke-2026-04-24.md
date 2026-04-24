# LUNA-361 Phase 3c — Ghostty Terminal Intelligence Audit

**Date:** 2026-04-24

## Inbox-routed terminal signals

| Ghostty signal | Agent Studio event | Inbox routing |
| --- | --- | --- |
| OSC 9 / OSC 777 desktop notification | `GhosttyEvent.desktopNotificationRequested` | yes, existing `.agentDesktopNotification` |
| BEL / ring bell | `GhosttyEvent.bellRang` | yes, gated by `InboxNotificationPrefsAtom.bellEnabled` |
| OSC 133 command finished | `GhosttyEvent.commandFinished` | yes, gated by unattended pane and minimum duration |
| OSC 9;4 progress error | `GhosttyEvent.progressReportUpdated(.error)` | yes, edge-triggered per pane as `.terminalProgressError` |
| Renderer unhealthy | `GhosttyEvent.rendererHealthChanged(false)` | yes, unhealthy edge-triggered per pane as `.terminalRendererUnhealthy` |
| Secure input requested | `GhosttyEvent.secureInputChanged(true)` | yes, edge-triggered per pane as `.terminalSecureInputRequested` when unattended |

## Runtime-state-only signals

These are intentionally not inbox notifications because they are high-churn context, not user-actionable alerts:

| Ghostty signal | Agent Studio event | Reason |
| --- | --- | --- |
| OSC 9;4 progress set / paused / indeterminate / remove | `progressReportUpdated` | captured in `TerminalActivityAtom`; only error edge notifies |
| OSC 7 current working directory | `cwdChanged` | captured in `TerminalActivityAtom` and pane context; useful for labels/filesystem projection |
| title / tab title | `titleChanged`, `tabTitleChanged` | display context |
| scrollbar / scrollback totals | `scrollbarChanged` | captured in `TerminalActivityAtom` as row-total/output-burst activity, not output text |
| URL open requests | `openURLRequested` | captured in `TerminalActivityAtom` as recent host-open requests, not every printed URL |
| secure input cleared | `secureInputChanged(false)` | captured in `TerminalActivityAtom`; only the true edge notifies |
| read-only / mouse shape / mouse link | typed `GhosttyEvent` cases | terminal interaction state |

## Verification hooks added

- `InboxNotificationRouterTests` now covers progress-error, renderer-unhealthy, and secure-input edge routing.
- `TerminalActivityAtomTests` and `TerminalActivityRouterTests` cover progress state, CWD, recent URL requests, secure-input state, and scrollbar-derived output bursts.
- `GhosttyActionRouterTests` now covers observed terminal-intelligence payloads through the action-router path:
  desktop notification, progress report, renderer health, scrollbar, and pwd/CWD.
- Existing `GhosttyAdapterTests` cover the action tag to typed `GhosttyEvent` translation table.
- Existing `TerminalRuntimeTests` cover replayable runtime state for progress and renderer health.

## Smoke note

The live OSC visual smoke is still the native-app verification step: launch the debug app, emit real OSC/BEL sequences from a terminal pane, and visually confirm inbox rows plus toolbar/drawer/worktree indicators. The code path is now covered headlessly; the live UI smoke remains a manual/native verification artifact unless run with Peekaboo in this branch.
