# Orchestrator Goal Contract: BridgeViewer Shared App PR-Ready

```text
Objective:
Finish the BridgeViewer shared-app work to PR-ready state without merging. Use
the Vite dev server for quick iteration, but the final app behavior must also be
proven inside Agent Studio Bridge/WKWebView against the local worktree. The file
view, review diff view, Review-file-target view, shared navigation state,
Pierre/Shiki/worker rendering path, shared UI chrome, scroll stability,
telemetry/proof artifacts, implementation review, and PR-ready checks all have
to be dependable before the goal can complete.

Goal id:
2026-06-25-bridgeviewer-shared-app-pr-ready

Required workflow skill:
shravan-dev-workflow:orchestrator-goal

Requirement/spec source:
- chat decision from 2026-06-25
- docs/specs/bridge-viewer-transport/spec.md
- docs/specs/bridge-viewer-transport/review-protocol.md
- docs/specs/bridge-viewer-transport/worktree-file-surface-protocol.md

Required reading:
- docs/specs/bridge-viewer-transport/spec.md
- docs/specs/bridge-viewer-transport/review-protocol.md
- docs/specs/bridge-viewer-transport/worktree-file-surface-protocol.md
- tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/worktree-devserver-product-e2e-precursor-plan.md
- tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/orchestrator-goal-2026-06-25-bridgeviewer-shared-app-pr-ready.md
- tmp/workflow-state/2026-06-25-bridgeviewer-shared-app-pr-ready/details.md
- tmp/workflow-state/2026-06-25-bridgeviewer-shared-app-pr-ready/events.jsonl
- tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-plan.md
  (historical only; do not resume from its ticket order)
- tmp/workflow-state/2026-06-24-bridge-transport-review-pr-ready/details.md
  (historical stuck-lane context only)

Current workflow:
shravan-dev-workflow:implementation-execute-plan

Next workflow:
shravan-dev-workflow:implementation-review-swarm

Terminal condition:
PR is opened or updated and proven ready, with implementation complete, required
proof gates passing or explicitly not-applicable, dev-server and Agent Studio
Bridge/WKWebView behavior proven against the local worktree, implementation
review findings addressed or explicitly rejected, PR checks/review-thread/
mergeability freshly reported, and no merge performed unless separately
authorized.

State details:
tmp/workflow-state/2026-06-25-bridgeviewer-shared-app-pr-ready/details.md

Transition log:
tmp/workflow-state/2026-06-25-bridgeviewer-shared-app-pr-ready/events.jsonl

Allowed write scope:
- tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/**
- tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/**
- tmp/workflow-state/2026-06-25-bridgeviewer-shared-app-pr-ready/**
- BridgeWeb/** for implementation after spec/plan review
- Sources/AgentStudio/Features/Bridge/** and Tests/AgentStudioTests/Features/Bridge/**
  for Swift-hosted Bridge proof after plan review
- proof artifacts under tmp/** as required by plans

Non-goals / scope boundary:
- Do not merge the PR.
- Do not keep old and new app roots as parallel product paths.
- Do not treat dev-server query params as production navigation API.
- Do not move file bodies, raw diffs, streams, workers, Pierre instances, or
  resource executors into Zustand.
- Do not move content bytes through RPC, continuous event frames, intake frames,
  push/store updates, or blob-shaped whole-package metadata paths. Content bytes
  must travel through stream-capable `ContentStreamPath` resource descriptors.
- Do not replace Agent Studio Bridge/WKWebView proof with Vite-only proof.
- Do not weaken proof gates to get unstuck; replan or split instead.

Proof gates:
- spec-review-swarm over the corrected shared BridgeViewer spec/protocol changes
- plan-creation-swarm rewrite of the implementation plan around the corrected
  sequence
- plan-review-swarm before code resumes
- every checkpoint that changes visible BridgeViewer UX must have real
  browser/native proof, screenshot or video artifacts, and a second-agent
  visual/code onlook that inspects screenshots plus relevant source paths before
  the checkpoint can close
- jsdom is not accepted as UX proof unless the user explicitly requests a narrow
  lower-level state guard; replace or demote any jsdom-only shared-context
  memory proof before claiming Gate 0.a progress
- before visible chrome work resumes, compare current FileViewer, current
  ReviewViewer, and DiffsHub/Pierre source/screenshots and keep the shared
  BridgeViewer shell design target in the proof packet
- unit/component/integration proof for navigation store, query adapter, Swift
  intent adapter, no-large-body state, and protocol contracts
- dev-server Playwright proof for:
  http://127.0.0.1:5173/?fixture=worktree&viewer=file&workers=on&scenario=current-worktree
  http://127.0.0.1:5173/?fixture=worktree&viewer=review&workers=on&scenario=current-worktree
  http://127.0.0.1:5173/?fixture=worktree&viewer=review&presentation=file&path=<path>&version=<base|head|current>&workers=on&scenario=current-worktree
- visual/screenshot and JSON proof artifacts that assert visible layout,
  Pierre/Shiki/worker ownership, shared UI primitives, context toggle,
  per-context memory, search/regex/filter controls, stale refresh, and negative
  substitute guards
- Agent Studio Bridge/WKWebView proof against the local worktree, with
  marker-correlated observability evidence where available. This proof must
  cover native Files context, Review diff context, Review file-target context,
  and Files-to-Review handoff; one native smoke path is not sufficient.
- lint/typecheck/test gates from the final reviewed plan
- streaming-resource realignment gate from
  tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/worktree-devserver-product-e2e-precursor-plan.md:
  `Slice 06P.S / Streaming Resource Contract Realignment`
  - continuous event and intake paths are metadata/descriptor/projection-only
  - `ContentStreamPath` / `agentstudio://resource/...` is the only content-byte
    carrier
  - product Browser paths do not default to whole-body `response.text()` /
    `Promise<string>` / `{ body }` resource APIs
  - Swift `BridgeSchemeHandler` emits bounded chunks and enforces lease/byte
    authority during the stream
  - stale/cross-pane/revoked/tampered resource authority fails closed
  - native `oq4s` IPC/WKWebView proof is rerun after resource-stream changes
- implementation-review-swarm
- implementation-pr-wrapup

Requirements/proof matrix:
See tmp/workflow-state/2026-06-25-bridgeviewer-shared-app-pr-ready/details.md.
The next plan must preserve and refine those rows; it must not replace them with
blank proof placeholders.

Stop condition:
Stop only when the terminal condition is satisfied, or when a real blocker meets
the blocked condition below. Do not stop at spec review, plan review, subagent
completion, dev-server-only proof, jsdom proof, screenshot-only proof, or a
single green test.

Blocked condition:
The same material blocker recurs under host blocked-state rules, or a required
user/product decision cannot be inferred from the spec/code without a risky
assumption, or required proof cannot run because of an external environment
failure outside agreed write scope.

Checkpoint rhythm:
Checkpoint after accepted spec revision, accepted plan revision, each proven
implementation slice, accepted implementation-review fixes, and PR-ready wrapup.
Commit scoped files at verified checkpoints when repo policy permits. Never
stage unrelated files, and never treat a commit as proof. For visible UX slices,
the checkpoint is not verified until the browser/native proof artifacts and the
second-agent onlook report have both been inspected by the parent agent.

Orchestration rules applied:
default implementation terminal; mutable starting point; pr-ready non-merge
boundary; full proof loop; checkpoint commit rule; phase skills recommend but
orchestrator-goal writes official workflow transitions.
```
