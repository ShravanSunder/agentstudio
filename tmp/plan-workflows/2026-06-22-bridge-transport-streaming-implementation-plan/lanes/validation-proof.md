# Plan-Creation Lane: Validation Proof

Status: answered
Candidate evidence label: validation-proof-00-05-proof-gate-map
Agent: Hegel
Date: 2026-06-22

## Question

Map material spec requirements and accepted plan-review blockers to proof gates
for tickets 00-05.

## Evidence Inspected

- `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec.md`
- `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/review-protocol.md`
- `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/worktree-file-surface-protocol.md`
- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/plan-review-report.md`
- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-plan.md`
- `BridgeWeb/package.json`
- `.mise.toml`
- `scripts/bridge-web-sync-fixtures.sh`
- existing BridgeWeb and Swift Bridge tests

## Candidate Findings Accepted

- Ticket 00 needs real WKWebView carrier proof, not TS-only proof.
- Ticket 01 needs negative page-world privileged RPC proof, shared TS/Swift
  fixture sync, descriptor/lease/integrity proof, and comments/comms
  fail-closed tests.
- Ticket 02 must merge generic demand runtime into the Review vertical because
  descriptor refs exist only after Review frames attach descriptors.
- Ticket 02 should add scheduler/executor pressure proof and telemetry canary
  proof.
- Ticket 03 needs native Worktree/File provider tests; Vite/dev-provider proof
  is not sufficient for the native boundary.
- Ticket 04 needs explicit stale marker -> no auto-fetch -> manual refresh
  browser proof.
- Ticket 05 needs final regression, telemetry canary, fixture sync, and targeted
  benchmark reruns when pressure paths changed.

## Concrete Proof Homes Accepted

- `Tests/AgentStudioTests/Features/Bridge/BridgeIntakeCarrierWebKitTests.swift`
  if existing WebKit/transport tests become too noisy.
- `Tests/AgentStudioTests/Features/Bridge/BridgePrivilegedRPCIngressTests.swift`.
- `BridgeWeb/src/core/demand/bridge-demand-scheduler.unit.test.ts`.
- `BridgeWeb/src/core/demand/bridge-resource-executor.unit.test.ts`.
- `BridgeWeb/src/core/demand/bridge-demand-runtime.integration.test.ts`.
- `Tests/AgentStudioTests/Features/Bridge/BridgeWorktreeFileSourceProviderTests.swift`.
- `Tests/AgentStudioTests/Features/Bridge/BridgeWorktreeFileSurfaceNativeTests.swift`.
- `BridgeWeb/src/worktree-file-surface/worktree-open-file-session.integration.test.tsx`.
- `BridgeWeb/src/worktree-file-surface/test-support/worktree-file-surface.browser.integration.browser.test.tsx`.

## Parent Synthesis

Accepted into revised plan and slices:

- exact per-ticket proof commands
- `scripts/bridge-web-sync-fixtures.sh --check`
- telemetry canary ownership in ticket 02 and rerun in ticket 05
- benchmark/pressure rerun conditions
- Worktree dev-server proof as freshness guard through tickets 02-04

## Receipt

Status: answered
Confidence: medium-high
Security context: applicable
