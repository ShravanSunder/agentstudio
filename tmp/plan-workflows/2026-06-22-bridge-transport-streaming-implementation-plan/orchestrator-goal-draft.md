# Orchestrator Goal Draft

Use this as the current `/goal` contract seed after the Gate 0.a shared
BridgeViewer/FileViewer correction.

```text
goal_id: 2026-06-24-bridge-transport-review-pr-ready

Required workflow skill: shravan-dev-workflow:orchestrator-goal

Objective:
Finish the full Bridge transport/review epic to PR-ready state without merging.
Gate 0.a is the active first blocker: the exact worktree dev-server URL must
render FileViewer inside the shared BridgeViewer shell, not a second app path.
The required surface is one Bridge Viewer App with ReviewViewer and FileViewer
modes. FileViewer uses primary Pierre CodeView/File canvas on the left, Pierre
FileTree/right rail on the right, Pierre/Shiki rendering, and worker-backed
highlighting when workers are enabled.

Required reading:
- tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec.md
- tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/review-protocol.md
- tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/worktree-file-surface-protocol.md
- tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec-review-report.md
- tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/worktree-devserver-product-e2e-precursor-plan.md
- tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-plan.md
- tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/file-organization.md
- tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/plan-review-report.md

Current workflow:
implementation-execute-plan Gate 0.a shared BridgeViewer/FileViewer correction active

Next workflow:
shravan-dev-workflow:implementation-execute-plan

Terminal condition:
PR is opened or updated and proven ready, with implementation complete,
required proof gates passing or explicitly not-applicable, implementation review
findings addressed or explicitly rejected, CI/check/review-thread/readiness state
freshly reported, and no merge performed unless separately authorized.

State details:
tmp/workflow-state/2026-06-24-bridge-transport-review-pr-ready/details.md

Transition log:
tmp/workflow-state/2026-06-24-bridge-transport-review-pr-ready/events.jsonl

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
- Gate 0.a plan/spec correction is active now.
- The first implementation checkpoint must repair the live dev-server product
  surface for
  `http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree`.
- It must prove the shared BridgeViewer shell, primary code/file canvas on the
  left, Pierre FileTree/right rail on the right, Pierre CodeView/File, Shiki,
  worker path, search/regex/filter controls, stale refresh, and scroll extent
  canaries.
- It must fail against `WorktreeFileApp`, route-local custom shells, custom tree
  rendering, raw `<pre>` body rendering, mock routes, stale Vite output, and
  DOM-only content-ready markers.
- After Gate 0.a implementation proof passes, run implementation review before
  advancing to Gate 1.

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
