# Plan-Creation Lane: Codebase Boundary

Status: answered
Candidate evidence label: codebase-boundary-00-05-write-surface-audit
Agent: Laplace
Date: 2026-06-22

## Question

Check whether tickets 00-05 map onto the current repo with clean ownership and
low-overlap write surfaces.

## Evidence Inspected

- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-plan.md`
- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/file-organization.md`
- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/plan-review-report.md`
- `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec.md`
- `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/review-protocol.md`
- `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/worktree-file-surface-protocol.md`
- `BridgeWeb/src/app/**`
- `BridgeWeb/src/bridge/**`
- `BridgeWeb/src/foundation/review-package/**`
- `BridgeWeb/src/foundation/review-query/**`
- `BridgeWeb/src/review-viewer/content/**`
- `Sources/AgentStudio/Features/Bridge/**`
- `Tests/AgentStudioTests/Features/Bridge/**`

## Candidate Findings Accepted

- The revised ticket order `00 -> 01 -> 02 -> 03 -> 04 -> 05` fits the repo
  better than the older slices.
- The work is sequential, not parallel/disjoint. The repo supports independent
  proof better than independent editing.
- Ticket 00 and 01 overlap on transport/bootstrap-adjacent files; ticket 00
  must stay focused on carrier proof and ticket 01 must own privileged RPC and
  resource grammar.
- Ticket 02 and 04 both touch `BridgeWeb/src/app/**`; ticket 02 should create
  the first app protocol router and ticket 04 should extend it.
- Ticket 03 must explicitly include transition edits to existing Review-shaped
  native files:
  - `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeReviewQuery.swift`
  - `Sources/AgentStudio/Features/Bridge/Runtime/ReviewFoundation/BridgeReviewPipeline.swift`
- Ticket 04 must replace Review-shaped dev worktree scaffolding:
  - `BridgeWeb/src/app/bridge-app-dev-bootstrap.tsx`
  - `BridgeWeb/src/app/bridge-app-dev-worktree.ts`

## Conflicts / Open Questions

- Current Worktree-like native behavior is Review-owned today; ticket 03 cannot
  be new-files-only.
- Current app shell is Review-only; app routing needs explicit ownership in
  ticket 02.
- Telemetry canary and comments/comms fail-closed proof need explicit owners.

## Parent Synthesis

Accepted into revised plan:

- serial execution wording
- app protocol router owned by ticket 02
- ReviewFoundation transition files named in ticket 03
- ticket 04 extends router and replaces worktree dev scaffolding
- telemetry/comments proof assigned to tickets 01, 02, 04, and 05

## Receipt

Status: answered
Confidence: medium
Security context: applicable
