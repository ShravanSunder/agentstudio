# Agent Studio Performance Program Coordinator Plan

Status: coordinator plan; Spec B implemented/review-fixed, Spec A planned
Date: 2026-06-11
Repo: `/Users/shravansunder/Documents/dev/project-dev/agent-studio.performance-issues`
Branch/worktree: `performance-issues`

## Goal

Drive the two-spec Agent Studio performance program from reviewed specs to
PR-ready implementation evidence without merging, releasing, publishing, or
touching the user's live AgentStudio instance.

The program has two implementation lanes:

- **Spec B — Git enrichment refresh and main-thread performance:** urgent
  idle-CPU/cmd-P/typing relief. Existing plan exists but must be amended.
- **Spec A — AtomLib v2 state primitives:** structural push-on-change,
  per-key observation, and revision-memoized derivation. No implementation
  plan existed before this coordinator pass.

## Source Coverage

Read and verified in this coordinator pass:

- `tmp/spec-workflows/2026-06-11-agent-studio-performance-issues-atomlib-v2-state-primitives/spec-handoff.md` — 204 lines.
- `tmp/spec-workflows/2026-06-11-agent-studio-performance-issues-atomlib-v2-state-primitives/copy-paste-prompt.md` — 64 lines.
- `docs/superpowers/specs/2026-06-11-atomlib-v2-state-primitives.md` — 572 lines after compile-time enforcement edits.
- `docs/superpowers/specs/2026-06-11-git-enrichment-refresh-redesign.md` — 298 lines.
- `docs/plans/2026-06-11-agent-studio-idle-git-render-performance.md` — 709 lines, all checkboxes unchecked at verification time.
- `tmp/debug-workflows/2026-06-11-agent-studio-performance-issues-cmdp-slowdown/debug-investigation.md` — 145 lines.

Coordinator subagent lanes used:

- Spec B amendment lane — found the existing plan still encoded older
  3-tier/scheduler-extraction language and lacked several Spec B amendment
  tasks and workload gates.
- Goal-contract lane — mapped the program to PR-ready evidence and surfaced
  artifact drift.
- Spec A plan skeleton lane — mapped primitive/enforcement/row-1/row-2 write
  surfaces and proof gates.

## Current State And Drift

- `origin/main` is at `52c5e677` (PR #164, OTLP/Victoria observability) and
  this worktree has been re-anchored to that commit. The stack was used for
  marker-scoped JSONL/OTLP proof.
- Spec B has been implemented, reviewed, and fixed for accepted in-scope review
  findings. Its closeout proof lives in
  `docs/plans/2026-06-11-git-enrichment-refresh-plan-amendment.md`.
- Spec A has a reviewed implementation plan but its primitives/adoptions are
  not implemented in this Spec B relief slice. Keep it as the next structural
  lane rather than silently claiming its proof matrix.
- The two specs and plans remain working-tree artifacts until the PR is staged;
  re-run `git status` before handoff or commit.
- The user's live AgentStudio must not be killed, relaunched, or manipulated.
  Any live experiment uses a debug build or AgentStudio Beta only.
- Workload proof must not mutate user repos, user worktrees, or user git
  config. Busy-agent and commit-interference smokes use disposable fixture
  repos/worktrees under `tmp/debug-workflows/`.
- Tooling changes are security-reviewable. If implementation touches
  `.swiftlint.yml`, `.mise.toml`, hook scripts, lint scripts, or workload
  drivers, the parent coordinator reviews that diff synchronously before
  further `.swift` edits; those changes are not delegated as an unsupervised
  subagent side quest.

## Program Order

### Cycle -1 — Completed Spec Review And Normalization Gate

Completed before plan-review and implementation. Existing draft plans were
provisional inputs to this gate, not accepted execution plans:

- `shravan-dev-workflow:spec-review-swarm` ran over the two specs plus the
  handoff packet.
- The accepted normalization points are now plan requirements:
   - Spec A compile-time enforcement language.
   - Spec B final 2-bucket + focus-boost model.
   - Cross-spec hard-cutover rule: Spec A row-1 deletes-and-absorbs Spec B's
     interim cache gate.
- Security remains split: product-state changes are correctness/performance
  risk; tooling/script/workload-driver/subprocess surfaces are
  security-reviewable.
- Preserve open questions as open; do not silently resolve them:
   - Spec A box type: per-domain recommended.
   - Spec A store-observation scope: `RepoCacheStore` only recommended.
   - Spec B cadence: 15s active self-heal and 240s striped background after
     idle proof showed the earlier 2s active tick remained load-bearing and
     180s background striping left only marginal <=2/s idle headroom.

Output: short review report or checked-in note under `tmp/spec-workflows/`.

### Cycle 0 — Planning

Create or amend plans without product code edits:

1. Amend the existing Spec B plan or write a delta plan. This pass writes the
   delta plan:
   `docs/plans/2026-06-11-git-enrichment-refresh-plan-amendment.md`.
2. Create Spec A implementation plan:
   `docs/plans/2026-06-11-atomlib-v2-state-primitives-implementation-plan.md`.
3. Run `shravan-dev-workflow:plan-review-swarm` on each plan before execution.
   Spec B plan-review must review the base plan and the amendment together;
   the delta alone is not a standalone execution source.
4. Include Claude and Gemini/agy review lanes in plan or implementation review
   when explicitly requested by the user; if tooling is unavailable, produce
   copy-paste prompts instead of pretending external review ran.

### Cycle 1 — Execute Spec B For Fast Relief

Use `shravan-dev-workflow:implementation-execute-plan` after Spec B plan review
passes.

Implementation ownership can split into bounded subagents:

- Git provider/process lane: `GIT_OPTIONAL_LOCKS=0`, provider tests.
- Projector scheduler lane: policy, budget, stripes, requeue, input filter,
  focus boost.
- Topology repair lane: topology-owned lifecycle reassertion with
  epoch/generation guard; no direct projector lifecycle authority.
- MainActor discipline lane: PaneCoordinator envelope guard/context memo,
  normalized path index, command-bar presence batching, direct pane count,
  SurfaceManager no-op writes.
- Topology/render/cmd-P lane: normalized path index, projection reuse,
  command-bar item construction/rebuild timing, and tab-bar row proof.
- Verification lane: AgentStudio trace records/signposts, JSONL/Victoria marker
  proof, samples, and workload proof artifacts.

Fixture rule: all busy-agent and commit-interference work happens in
disposable repos/worktrees created for the proof run. If disposable fixtures
cannot be created, the proof gate is blocked, not waived.

Stop after Spec B Phase 1 only after mandatory MainActor discipline and all
three B8 workload gates pass. Conditional Phase 2 is reserved for residual
scheduler extraction or deeper state-layer work justified by current samples.

### Cycle 2 — Execute Spec A Structural State Layer

Use `shravan-dev-workflow:implementation-execute-plan` after Spec A plan review
passes.

Implementation order:

1. Primitive foundation and enforcement.
2. Row-1 `RepoEnrichmentCacheAtom` adoption with Z1 guards first and
   privatization last.
3. `RepoCacheStore` revision observation.
4. Per-row surface restructuring for repo explorer, tab bar, and cmd-P.
5. Row-2 derived migration.
6. Rows 3+ only with measurement or co-located work evidence.

### Cycle 3 — Implementation Review

Run `shravan-dev-workflow:implementation-review-swarm` after each executed
lane and before PR readiness.

Required review lanes:

- Correctness and stale-UI risks.
- Architecture boundaries and ownership.
- Test/proof completeness.
- Performance regression risks.
- Security context check when subprocess, lint tooling, or scripts changed.

External review:

- Claude: use Claude Code CLI harness or copy-paste prompt when explicitly
  requested.
- Gemini/agy: use available harness when explicitly requested; otherwise record
  that it was requested but unavailable.
- Parent coordinator verifies all external findings before accepting them.

### Cycle 4 — PR-Ready Closeout

PR-ready means:

- Plans are updated and checked off only for completed tasks.
- Review findings are resolved, rejected with evidence, or tracked as open.
- `mise run test` passes.
- `mise run lint` passes.
- Spec B workload gates are re-measured against debug baselines:
  - idle sample
  - busy-agent sample from disposable fixture repos/worktrees
  - cmd-P keystroke/filter timing
- Spec B proof artifacts include isolated `AGENTSTUDIO_DATA_DIR`, launched PID,
  `AGENTSTUDIO_TRACE_NAME`, JSONL trace file path, and Victoria verification
  output when OTLP is enabled.
- Spec A proof matrix rows pass for every implemented primitive/adoption.
- Debug/proof artifacts include commands, exit codes, counts, and sample paths.
- No merge, release, publish, or live-user app manipulation.

## Requirements And Proof Matrix

| Requirement | Owning Cycle | Proof Gate | Layer | Red/Green |
|---|---:|---|---|---|
| Spec review happens before plan-review/execution | -1 | spec-review report with accepted/contested/open findings and applied normalization edits | review | no |
| Spec B plan matches final 2-bucket + focus-boost design | 0 | plan-review-swarm accepts the amended/delta plan | review | no |
| Spec B has process-budget and MainActor-discipline tasks | 0-1 | unit/integration tests plus idle/busy/cmd-P proof gates | unit/integration/smoke | yes |
| Spec A has compile-time/lint enforcement tasks, not doc-only rules | 0-2 | V/T/E/D/A/S/R/Z proof rows and lint/boundary checks | unit/lint/integration | yes |
| Cross-spec hard cutover is preserved | 0-2 | no dual `hasSameCacheContent` gate once Spec A row-1 lands | review/test | yes |
| Subagent execution stays bounded | all | task packets name disjoint write surfaces and parent verifies outputs | process | no |
| External reviews are real or explicitly marked unavailable | 3 | review artifacts or copy-paste prompts captured | review | no |
| Tooling/script changes are reviewed before Swift edits proceed | 0-3 | parent-owned diff check for lint/mise/hook/script/workload-driver surfaces | security/process | no |
| PR readiness is evidence-backed | 4 | `mise run test`, `mise run lint`, workload proof, implementation review | full | no waiver |

## Risks And Replan Triggers

- If Spec B plan-review finds stale 3-tier/scheduler language remains, stop
  before implementation and revise the plan.
- If Spec A plan cannot make input/equality safety compile- or lint-enforced,
  stop before implementation and reconverge on the primitive API.
- If any proof gate requires wall-clock sleeps or production `#if DEBUG` hooks,
  split/replan the task.
- If debug/Beta smoke cannot be run without touching the live app, record the
  blocker and do not substitute the live instance.
- If concurrent agents edit the same untracked artifact, stop writes to that
  artifact until ownership is clarified or a baseline is created.

## Next Workflow

1. Do not claim PR readiness yet. Spec B's accepted implementation-review
   fixes are applied, but the final full `mise run test` and post-review
   `mise run lint` reruns still need current-state proof under normal machine
   load.
2. Preserve the Spec B proof packet:
   `tmp/review-workflows/2026-06-12-agent-studio-performance-implementation-review/implementation-review-report.md`
   plus the `/tmp/asperf/idle-postcadence240-023014` and
   `/tmp/asperf/perf-postcadence240-023536` workload artifacts.
3. When CPU pressure is acceptable, rerun the default repo gates without
   broadening proof conditions:
   `mise run test`
   `mise run lint`
4. Then continue with Spec A through
   `shravan-dev-workflow:implementation-execute-plan` from
   `docs/plans/2026-06-11-atomlib-v2-state-primitives-implementation-plan.md`.
   Spec A is not implemented in the current worktree.
