# Bridge Transport Review PR-Ready Implementation Plan

Date: 2026-06-24
Goal id: `2026-06-24-bridge-transport-review-pr-ready`
Status: draft for plan-review-swarm

## Source Of Truth

Accepted spec artifacts:

- [spec.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec.md:1)
- [review-protocol.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/review-protocol.md:1)
- [worktree-file-surface-protocol.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/worktree-file-surface-protocol.md:1)
- [reconciliation-review-2026-06-24.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/reconciliation-review-2026-06-24.md:1)

Goal state:

- [details.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/workflow-state/2026-06-24-bridge-transport-review-pr-ready/details.md:1)
- [events.jsonl](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/workflow-state/2026-06-24-bridge-transport-review-pr-ready/events.jsonl:1)

Reviewer context packet:

- [spec-review-packet-2026-06-24.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/workflow-state/2026-06-24-bridge-transport-review-pr-ready/spec-review-packet-2026-06-24.md:1)

Every future implementation/review packet must include the prior failure
context: old narrow green proof versus current product red proof, and the
question "Can this proof pass while the user-visible product is still wrong?"

## Planning Decision

Do not implement this epic as one unbroken blob. Execute it as checkpointed
vertical tickets. Each ticket must produce its own proof and checkpoint commit.

Gate 0 is the first executable blocker. Gates 1-4 remain in scope for this epic
and cannot be silently deferred from PR-ready.

## Gate Sequence

```text
Gate 0  Worktree/File product proof
   │
   ▼
Gate 1  Generic Bridge transport/core runtime
   │
   ▼
Gate 2  Worktree/File and Review app protocols
   │
   ▼
Gate 3  Pierre/Review renderer rewrite/integration
   │
   ▼
Gate 4  PR-ready non-merge wrapup
```

## Tickets

### Ticket 00: Gate 0 Worktree/File Product E2E

Path:
[00-gate0-worktree-product-e2e.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/plan-workflows/2026-06-24-bridge-transport-review-pr-ready-implementation-plan/tickets/00-gate0-worktree-product-e2e.md:1)

Deliverable:
The exact Vite dev-server URL renders and operates the intended Worktree/File
product surface and cannot pass as a mock/raw/minimal substitute.

Blocking:
No downstream implementation claim may proceed until this ticket proves the
product surface.

### Ticket 01: Gate 1 Generic Bridge Transport/Core

Path:
[01-gate1-bridge-transport-core.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/plan-workflows/2026-06-24-bridge-transport-review-pr-ready-implementation-plan/tickets/01-gate1-bridge-transport-core.md:1)

Deliverable:
Generic Bridge runtime primitives exist without Review/Worktree semantics:
RPC/event/intake/resource paths, descriptor registry, generic lane scheduler,
executor/backpressure, shared validation, telemetry hooks, and native runtime
proof seams.

### Ticket 02: Gate 2 App Protocols

Path:
[02-gate2-app-protocols.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/plan-workflows/2026-06-24-bridge-transport-review-pr-ready-implementation-plan/tickets/02-gate2-app-protocols.md:1)

Deliverable:
Worktree/File and Review app protocols own domain semantics on top of generic
Bridge: source/version/provenance, app materializers, app demand policies,
large-data-out-of-Zustand invariants, live worktree/change-set behavior, and
bounded stream/request behavior.

### Ticket 03: Gate 3 Pierre/Review Renderer Cutover

Path:
[03-gate3-pierre-review-renderer-cutover.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/plan-workflows/2026-06-24-bridge-transport-review-pr-ready-implementation-plan/tickets/03-gate3-pierre-review-renderer-cutover.md:1)

Deliverable:
Review/Pierre rendering consumes the new transport/materialization/scheduler
model with DiffsHub-like static diff, live update, change-set comparison, and
scroll-stability behavior. PR-ready requires hard cutover for every in-scope
renderer entry path and negative proof that covered routes cannot reach the
legacy renderer/remount bypass.

### Ticket 04: Gate 4 PR-Ready Wrapup

Path:
[04-gate4-pr-ready-wrapup.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/plan-workflows/2026-06-24-bridge-transport-review-pr-ready-implementation-plan/tickets/04-gate4-pr-ready-wrapup.md:1)

Deliverable:
The branch is PR-ready but not merged. Required proof pyramid passes or is
explicitly not applicable; dev-server/browser visual proof, Agent Studio
Bridge/WKWebView proof, performance/observability proof, implementation review,
lint/typecheck/tests, PR state, checks, comments, and mergeability are freshly
reported.

## Proof Matrix

| Gate | Unit | Integration | Browser/E2E | Native/Observability | Review |
| --- | --- | --- | --- | --- | --- |
| 0 | filter/regex/provenance/stale state | provider descriptors/resources | exact current-worktree URL, controls, content, stale-refresh, scroll, screenshots, negative substitutes | not final native proof; native proof is carried to Gate 4 | parent/human/reviewer artifact inspection |
| 1 | schemas, scheduler state, descriptor registry | RPC/event/intake/resource boundaries, executor/backpressure | focused smoke only if route wiring changes | Victoria-safe telemetry and marker seams | implementation review for generic/app boundary |
| 2 | app materializers and demand policies | Worktree/File and Review protocol streams/resources | live worktree/change-set protocol surfaces | source/version/provenance markers where required | app-ownership review |
| 3 | renderer adapters and update lifecycle | Pierre/CodeView/tree integration | static diff, live update, change-set comparison, scroll canary | performance/scroll telemetry | renderer hard-cutover review |
| 4 | focused regressions | package/native bridge smoke | final dev-server/browser proof | Agent Studio Bridge/WKWebView + Victoria proof | implementation review + PR wrapup |

## Proof Surface Contract

This epic has two real product proof surfaces. They are complementary, not
substitutes:

1. Vite dev-server/browser proof
   - owns the fast product loop for the exact Worktree/File and Review URLs
   - must exercise visible controls, interactions, content, scroll, stale state,
     screenshots, and negative substitute assertions
   - must fail when the route renders a mock, raw dump, minimal list, or old
     narrow verifier surface

2. Agent Studio Bridge/WKWebView proof
   - owns native host integration for the same in-scope product routes
   - must prove native route boot, page/host handshake, protocol/source/resource
     identity, event stream readiness, resource/content requests, visual product
     state, and Victoria/log marker correlation
   - must include Worktree/File, Review/Pierre, and any Gate 3 in-scope
     change-set/native comparison route before PR-ready

No gate may be closed by unit, integration, mock, route bootstrap, telemetry, or
subagent claims alone when user-visible product behavior is in scope.

## Execution Rules

- Do not proceed past a gate until its blocking proof is captured and committed.
- Carry Gate 0 forward as a standing regression gate. Tickets 01-03 must rerun
  the Gate 0 current-worktree product proof before closing if they touch shared
  BridgeWeb transport, protocol, scheduler, or renderer wiring.
- Do not use a lower proof layer as a substitute for visible product behavior.
- Do not use Vite/dev-server proof as final native Agent Studio Bridge proof.
- Do not count failed/disconnected subagent review as accepted review.
- Do not put large bodies in Zustand.
- Do not let generic Bridge own Review or Worktree semantics.
- Do not claim PR-ready while a residual renderer bypass remains in scope.

## Next Workflow

Run `shravan-dev-workflow:plan-review-swarm` on this plan and ticket set before
implementation execution.

phase_result: complete
evidence: this plan plus ticket files under `tmp/plan-workflows/2026-06-24-bridge-transport-review-pr-ready-implementation-plan/`
recommended_next_workflow: shravan-dev-workflow:plan-review-swarm
recommended_transition_reason: Spec review is accepted and a checkpointed gate plan now exists for review.
