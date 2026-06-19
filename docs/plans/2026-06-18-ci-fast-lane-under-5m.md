# CI Fast Lane Under Five Minutes Plan

Date: 2026-06-18

## Goal

Make the AgentStudio CI test fast lane comprehensive for the intended non-WebKit
SwiftPM coverage while restoring the lane to less than 5 minutes on GitHub
Actions. The plan is scoped to fixing the current branch regression where the
fast lane moved from about 5m08s to about 29m12s after class-sharding and an
uncached build directory became the default.

## Source Coverage

- User requirement in chat: CI tests must be comprehensive and less than 5
  minutes.
- Reviewer result from subagent `019eda45-da66-7352-b2f5-8eef6b9608d7`:
  class sharding should be removed from default CI; `.build-ci-fast-${{
  github.run_id }}` bypasses the existing `.build-ci` cache; sharding code is not
  justified by the proof currently in the branch.
- Current workflow evidence read:
  `.github/workflows/ci.yml` lines 163-188 show the cache path remains
  `.build-ci` while `Test fast lane` overrides `SWIFT_BUILD_DIR` to an uncached
  `.build-ci-fast-${{ github.run_id }}` path and enables
  `SWIFT_TEST_SHARD_BY_CLASS=1`.
- Current helper evidence read:
  `scripts/swift-test-helpers.sh` lines 1-270 show the class-sharding default
  path, standalone filter loop, isolated class loop, `swift test list`, and
  repeated class-shard `swift test --filter` invocations.
- Baseline evidence read from `origin/main`:
  `.github/workflows/ci.yml` lines 160-190 used one cached parallel fast-lane
  run with `SWIFT_TEST_WORKERS=4` and no sharding flags.
- Relevant changed-surface size observed:
  `6 files changed, 312 insertions(+), 14 deletions(-)` across CI/test helper
  files and script tests.

## Non-Goals

- Do not weaken CI by deleting real product test coverage.
- Do not relabel a smaller test subset as comprehensive.
- Do not introduce XCTest; this repo uses Swift Testing only.
- Do not add wall-clock sleeps or `Task.sleep`-based tests.
- Do not optimize WebKit, benchmark, release, or unrelated lanes unless they
  block the fast-lane proof and the blocker is explicitly reported.
- Do not merge or release as part of this plan.

## Requirements / Proof Matrix

| Requirement / claim | Owning task | Proof owner | Proof gate | Proof layer | Stale-proof guard | Red/green required | Sized to pass |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Default CI fast lane uses the cached SwiftPM build path `.build-ci`. | Task 1 | parent | Inspect `.github/workflows/ci.yml`; compare cache path and fast-lane env. | config | current branch diff | No | Yes |
| Default CI fast lane runs one parallel non-WebKit SwiftPM test invocation, not class-sharded serial filters. | Task 1 | parent | Inspect workflow and helper path; no default `SWIFT_TEST_SHARD_BY_CLASS=1`; `SWIFT_TEST_WORKERS=4` present. | config/unit-script | current branch diff | No | Yes |
| Intended fast-lane coverage is preserved. | Task 2 | parent | Local `mise run test-fast` passes; verify skip set remains limited to existing separate lanes: WebKit, E2E, and Zmx E2E. | integration | current local checkout | Yes: current branch is slow/regressed; corrected branch must pass | Yes |
| The branch does not keep unproven class-sharding complexity in the default path. | Task 2 | parent + reviewer | Remove sharding code/tests or make it explicitly manual-only outside default CI; run script tests/lint. | unit/config | current diff and reviewer result | No | Yes |
| GitHub Actions `Test fast lane` duration is less than 5 minutes. | Task 4 | parent | Fresh PR CI run step timestamps for `Test fast lane`; report exact start/end/duration. | CI/performance | current PR run id and commit SHA | Yes: current proof is 29m12s failure; corrected proof must be <5m | Yes |
| CI remains comprehensive at the workflow level. | Task 4 | parent | Fresh CI result includes fast lane, WebKit lane, lint, format, architecture lint/build lanes as configured by workflow. | CI | current PR run id and commit SHA | No | Yes |
| No wall-clock test anti-pattern is introduced. | Task 3 | parent | Diff-scoped review over touched Swift test files for new `Task.sleep`, `Task.sleep(for:)`, or raw wall-clock sleeps; do not use repo-wide shell `sleep` hits as blockers. | static review | current diff | No | Yes |
| Default CI invariants cannot silently regress. | Task 3 | parent | `CIFastLaneWorkflowTests.fastLaneKeepsCachedParallelDefault` reads `.github/workflows/ci.yml` and script helpers to assert default fast lane uses cached `.build-ci`, `SWIFT_TEST_WORKERS=4`, no default `SWIFT_TEST_SHARD_BY_CLASS`, and no uncached `.build-ci-fast-*` path. | unit/config | current diff | Yes: current branch would fail this guard; corrected branch must pass | Yes |

## Task Sequence

1. Restore the default fast-lane shape.
   - In `.github/workflows/ci.yml`, remove the uncached
     `SWIFT_BUILD_DIR=.build-ci-fast-${{ github.run_id }}` override.
   - Remove default class-sharding env:
     `SWIFT_TEST_SHARD_BY_CLASS`, `SWIFT_TEST_SHARD_CLASS_COUNT`,
     `SWIFT_TEST_SKIP_BUILD`, `SWIFT_TEST_FIRST_SHARD_SKIP_BUILD`,
     `SWIFT_TEST_CLASS_SHARD_RAW_OUTPUT`, `SWIFT_TEST_PARALLEL=0`, and warmup
     timeout.
   - Restore `SWIFT_TEST_WORKERS=4` and the existing 600s timeout.

2. Remove or quarantine the sharding harness.
   - Preferred correction: delete the class-sharding helper path and the
     sharding-specific tests because the current proof shows it made default CI
     slower and did not add coverage.
   - If a manual escape hatch is kept, it must be opt-in only and unreachable
     from default CI. It must have behavioral tests for emitted command shape,
     not only substring snapshots.
   - Keep unrelated helper improvements only if they do not add process fan-out,
     do not bypass the cache, and pass the proof matrix.

3. Validate locally with the smallest useful pyramid.
   - Add or update a Swift Testing script/workflow guard that fails on the
     current regressed default CI shape and passes after correction.
   - `swift test --build-path .build-ci --filter AgentStudioTests.CIFastLaneWorkflowTests/fastLaneKeepsCachedParallelDefault`
     for the script/workflow guard.
   - `swift test --build-path .build-ci --filter AgentStudioTests.SwiftTestHelperShardingTests`
     only if an opt-in sharding helper remains; if sharding is deleted, this
     test should be deleted too.
   - `SWIFT_BUILD_DIR=.build-ci mise run test-fast` to prove the local fast
     lane uses the same cached build path shape as CI. Capture the wrapper log
     line showing `[test-fast] BUILD_PATH=.build-ci`.
   - `mise run lint` to prove format, SwiftLint, and local architecture lint.

4. Validate on GitHub Actions.
   - Push the corrected branch.
   - Watch the PR CI run.
   - Capture exact `Test fast lane` step duration from logs or job timestamps.
   - Acceptance is strict: `Test fast lane` must be less than 5 minutes. If it
     is 5 minutes or more, do not claim success; inspect where time is spent and
     replan without dropping coverage.

5. Review and wrap.
   - Run implementation review focused on CI/test harness correctness and proof
     integrity.
   - Address accepted findings.
   - Update PR with the before/after duration evidence and changed-surface
     summary.

## Write Surfaces

- `.github/workflows/ci.yml`
- `scripts/run-swift-test-task.sh`
- `scripts/swift-test-helpers.sh`
- `Tests/AgentStudioTests/Scripts/SwiftTestHelperShardingTests.swift`
- Related script tests only if needed to remove stale expectations.
- PR description / comments for duration proof.

## Validation Gates

- Unit/script gate:
  focused Swift Testing tests for any retained script helper behavior.
- Integration gate:
  `mise run test-fast` from the repo root.
- Quality gate:
  `mise run lint`.
- CI/performance gate:
  fresh GitHub Actions run where the `Test fast lane` step is under 5 minutes
  and the rest of the required CI workflow remains green.

## Risks And Recovery

- Risk: simply restoring the old workflow may still land slightly above 5
  minutes because the baseline observed was about 5m08s.
  Recovery: profile the step without adding process fan-out; improve cache use,
  reduce repeated setup, or parallelize safely while preserving coverage.
- Risk: reverting the YAML fixes this run but leaves no durable protection
  against the same default-path sharding/cache bypass returning later.
  Recovery: keep a narrow Swift Testing guard for default CI invariants. The
  guard should inspect config shape only; it should not run GitHub Actions or
  invoke SwiftPM subprocesses.
- Risk: removing sharding code may expose the original reason it was added, such
  as a real hang or focus-sensitive test.
  Recovery: isolate the single problematic suite with a targeted fix or a
  separate explicit lane; do not shard the whole fast lane by default.
- Risk: local timing is not representative of GitHub macOS runners.
  Recovery: treat GitHub step timestamps as the performance proof source.

## Open Questions

- If the restored baseline remains just above 5 minutes, should the acceptance
  remain strict under 5 minutes for the `Test fast lane` step only, or should a
  small runner-variance buffer be allowed? Current plan assumes strict under 5.
- The sharding harness branch is resolved for this implementation: delete it
  entirely. If a manual-only escape hatch is ever reintroduced, it needs a
  separate plan and behavioral tests that prove opt-in reachability.

## Recommended Next Workflow

`shravan-dev-workflow:plan-review-swarm`

The plan is intentionally small but touches CI behavior and proof semantics.
It should get adversarial review before execution so we do not repeat the same
validation-layer drift.

phase_result: complete
evidence: docs/plans/2026-06-18-ci-fast-lane-under-5m.md
recommended_next_workflow: shravan-dev-workflow:plan-review-swarm
recommended_transition_reason: Plan created; review should validate that it restores speed without weakening coverage.
