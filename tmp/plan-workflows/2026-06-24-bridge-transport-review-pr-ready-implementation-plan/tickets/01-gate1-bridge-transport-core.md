# Ticket 01: Gate 1 Generic Bridge Transport/Core

Status: draft for plan-review-swarm
Depends on: Ticket 00 completion

## Deliverable

Implement generic Bridge carriers and runtime primitives without Review or
Worktree semantics:

- RPC command path
- continuous event stream path
- typed intake stream path
- finite resource/content path
- descriptor registry
- generic lane scheduler
- generic resource executor and backpressure
- shared validation
- safe telemetry hooks and Victoria proof seams

## Reviewer Reminder

Review this ticket against the prior false-green failure mode. Ask whether a
generic transport proof could pass while the user-visible product is still wrong
or while Review/Worktree semantics leak into generic Bridge core.

## Ownership Boundary

Gate 1 must not own app-specific materializers or app demand policies.
Concrete Review and Worktree/File semantics belong to Gate 2.

## Vertical Slices

1. Transport schema and Zod/TypeScript models
   - unit proof for accepted/rejected frames
   - no `any` or unvalidated casts for boundary data

2. Descriptor registry and resource URL authority
   - integration proof for registered descriptor fetch
   - stale/foreign/forged descriptors rejected

3. Continuous event stream carrier
   - integration proof for ready, heartbeat, source-status, descriptor
     availability, invalidated, gap, reset, and closed frames
   - proof that bodies do not travel on the event stream

4. Generic scheduler and backpressure
   - unit/integration proof for lane ordering, queue bounds, aborts, stale drops,
     and in-flight limits
   - no app-specific conditions in generic scheduler

5. Telemetry seams
   - source-scrubbed events
   - marker-correlated queue/resource metrics
   - Victoria proof path prepared for native runtime gates

## Proof Gates

Required:

- focused unit tests for schemas/scheduler/registry
- integration tests for transport/resource boundaries
- typecheck/lint for touched BridgeWeb paths
- no app-semantics imports into generic core
- Gate 0.a current-worktree shared FileViewer/Pierre product proof remains green
  before this ticket closes

Blocked until:

- Ticket 00/Gate 0.a shared FileViewer/Pierre route proof is green and
  committed.

## Required Commands

Standing Gate 0.a regression command consumed from Ticket 00:

```bash
pnpm --dir BridgeWeb run test:dev-server:worktree
```

```bash
pnpm --dir BridgeWeb run test -- <focused transport/core tests>
pnpm --dir BridgeWeb run check
pnpm --dir BridgeWeb run test:dev-server:worktree
mise run lint
```

phase_result: complete
evidence: Gate 1 ticket drafted with ownership boundary and proof gates.
recommended_next_workflow: shravan-dev-workflow:plan-review-swarm
recommended_transition_reason: Gate 1 has a reviewable implementation ticket.
