# Implementation Execute Plan Brief

Date: 2026-06-22
Branch: luna-338-pierreshikitrees-review-viewer-2
Plan: `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-plan.md`
Current ticket: `slices/00-carrier-proof.md`

## Controller Commitments

- Execute ticket 00 before any protocol migration.
- Use TDD for behavior changes: RED, GREEN, refactor, then climb proof gates.
- Keep tests event/state bounded. Do not add arbitrary wall-clock sleeps.
- Use subagents only for bounded read-only research or disjoint write scopes.
- Use Victoria/observability proof where the Swift/WebKit path exposes a real runtime surface.
- Stop and replan if the push/event carrier cannot prove ordered, bounded, stale-safe delivery in real WKWebView.

## Active Read-Only Lanes

- Swift/WebKit/Victoria proof surface research.
- Existing BridgeWeb push receiver compatibility and test-pattern research.

## Ticket 00 First Slice

The first RED test defines the generic intake receiver state-machine contract:
ordered frames are accepted, sequence gaps move the receiver to `resetRequired`,
and later frames fail closed until a reset path is implemented.
