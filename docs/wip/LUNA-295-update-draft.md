# Draft Update for LUNA-295

Issue: https://linear.app/askluna/issue/LUNA-295/notification-routing-route-agentservice-events-to-the-right-workspace

## Proposed Comment

Implemented planning work to route terminal/session lifecycle through notification-driven boundaries so workspace-specific behavior can be deterministic and testable.

### What we learned from debugging

1. Session restore order alone is not enough to eliminate flicker or width artifacts.
2. Hidden tabs are not rendered in the active SwiftUI tree, so they do not naturally satisfy window/size readiness at startup.
3. Deferred attach must be driven by explicit readiness + priority events, not implicit view timing.

### Proposed architecture for this issue

1. Add a typed notification/event pipeline for pane/session lifecycle.
2. Introduce pure `PaneAttachStateMachine` (reducer only).
3. Introduce `PaneAttachSchedulerService` (`@MainActor`) to process events and schedule work.
4. Keep side effects in a runtime boundary (`PaneAttachRuntime` protocol) to avoid coupling.
5. Compose in existing app files (`TerminalViewCoordinator`, `TerminalTabViewController`, `GhosttySurfaceView`) as thin publishers/subscribers.

### Priority behavior (must-have)

1. active pane in active tab first,
2. active pane drawer panes second,
3. other visible panes in active tab third,
4. hidden panes last.

### Acceptance criteria

1. Event routing is workspace-correct (events scoped to correct pane/workspace identifiers).
2. Attach scheduling is deterministic and test-covered.
3. Tab switch promotes destination pane/drawers immediately.
4. Background work cannot starve visible work.
5. Startup and tab-switch flicker are measurably reduced.

### Suggested test coverage

1. Unit tests for state machine transitions and priority changes.
2. Integration tests for visibility changes, drawer expansion, and tab switching.
3. Regression checks for startup width/cols correctness and attach timing.

---

Note: Linear MCP update is currently blocked in this environment due auth handshake failure (`Auth required`). Once `linear` MCP login is completed, post this update directly to LUNA-295.

