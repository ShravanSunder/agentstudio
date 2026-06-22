# Orchestrator Goal Draft

Use this as the current `/goal` contract seed after the plan revision and
1.6.29 spec refresh.

```text
goal_id: 2026-06-22-bridge-transport-streaming

Required workflow skill: shravan-dev-workflow:orchestrator-goal

Objective:
Deliver the Bridge transport streaming architecture from accepted spec through
plan review, implementation, proof, implementation review, and PR-ready handoff
without merging.

Required reading:
- tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec.md
- tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/review-protocol.md
- tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/worktree-file-surface-protocol.md
- tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec-review-report.md
- tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-plan.md
- tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/file-organization.md
- tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/plan-review-report.md

Current workflow:
plan-review-ready

Next workflow:
shravan-dev-workflow:plan-review-swarm

Terminal condition:
PR is opened or updated and proven ready, with implementation complete,
required proof gates passing or explicitly not-applicable, implementation review
findings addressed or explicitly rejected, CI/check/review-thread/readiness state
freshly reported, and no merge performed unless separately authorized.

State details:
tmp/workflow-state/2026-06-22-bridge-transport-streaming/details.md

Transition log:
tmp/workflow-state/2026-06-22-bridge-transport-streaming/events.jsonl

Scope:
- BridgeWeb common runtime/models under BridgeWeb/src/core/**
- BridgeWeb browser host adapters under BridgeWeb/src/core/bridge-host/**
- Existing BridgeWeb/src/bridge/** treated as legacy compatibility during cutover
- BridgeWeb feature code under BridgeWeb/src/features/**
- Existing Review UI adapters under BridgeWeb/src/review-viewer/**
- Worktree/File surface under BridgeWeb/src/worktree-file-surface/**
- Swift common contracts under Models/Transport and Transport
- Swift feature contracts/runtime under Models/<Feature> and Runtime/<Feature>
- Tests, fixtures, dev-server proofs, benchmark/pressure proofs, telemetry
  canaries, and plan/review/handoff artifacts needed for the proof chain

Non-goals:
- Do not merge the PR.
- Do not add comments/comms schemas beyond fail-closed reserved behavior.
- Do not move large bodies into Zustand.
- Do not rewrite Pierre/CodeView/Tree unless a proven materializer identity issue
  requires a narrow change.
- Do not keep old and new fetch authority paths alive inside the same protocol
  after a ticket cuts over.

Required plan-review gate before implementation:
- Run `shravan-dev-workflow:plan-review-swarm` on the revised plan package.
- If accepted blocker or important findings remain, route back to
  `plan-creation-swarm` or `spec-creation-swarm` by finding owner.
- If the plan review passes or only accepted tiny plan edits remain, route to
  implementation checkpoint execution.

Execution rules:
- At each ticket, read current code first, then add/adjust failing tests before
  implementation where behavior changes.
- Do not proceed to the next ticket until that ticket's red/green proof,
  integration/boundary proof, highest applicable app/browser/dev-server/Swift
  proof, and reviewer handoff output are complete.
- If a proof gate fails outside the ticket scope, stop and report scoped
  pass/fail plus the external blocker before editing unrelated infrastructure.
- Accepted plan findings route back to plan-creation-swarm.
- Accepted implementation review findings route back to implementation-execute-plan.
- Checkpoint commit at accepted spec/plan revisions, each proven implementation
  ticket, accepted review-finding fixes, and PR-ready wrapup.

Phase result footer required from every phase skill:
phase_result: complete | blocked | needs_revision | not_applicable
evidence: <paths, commands, findings, or transcript notes>
recommended_next_workflow: <shravan-dev-workflow skill or terminal>
recommended_transition_reason: <one sentence>

Orchestration rules applied:
default implementation terminal; mutable starting point; pr-ready non-merge
boundary; full proof loop; checkpoint commit rule.
```
