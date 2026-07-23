# Primary-Worktree Vendor Reuse Implementation Plan

Date: 2026-07-23
Status: reviewed and ready for execution
Source: [AgentStudio Primary-Worktree Vendor Reuse](../2026-07-22-terminal-runtime-distribution.md)

## Goal

Make `mise run setup` the only local bootstrap entry point:

- primary checkout: build the existing pinned Ghostty/zmx inputs locally;
- ordinary linked worktree: reuse compatible primary outputs through two
  symlinks and two regular resource copies;
- explicitly authorized vendor-development worktree:
  `mise run setup --use-local-vendors` hydrates and builds vendors locally.

All supported build, test, app-bundle, debug, performance, and observability
paths must verify the selected vendor inputs before consuming them. Existing
zmx bundling, signing, debug isolation, `AGENTSTUDIO_ZMX_PATH`, CI, benchmark,
and release behavior remain otherwise unchanged.

## Source Coverage

- Accepted specification: 567 lines read completely.
- Current implementation HEAD:
  `756b87d0f18aadd859ad052e2b49328f1c3b099d`.
- Current branch/worktree: `better-worktree`, registered under the primary
  AgentStudio Git common directory.
- Planning lanes: codebase boundary, validation/proof, and
  security/reliability; all read-only with high reasoning because filesystem,
  subprocess, observability, and live-app proof are load-bearing.

## Non-Goals

- A vendor repository, SwiftPM distribution package/plugin, receipt, artifact
  store, multi-version cache, lock service, daemon, or garbage collector.
- Automatic fallback from shared setup to local vendor hydration.
- A return-to-shared cleanup command for local-vendor worktrees.
- CI, benchmark, or release workflow redesign.
- zmx runtime, signing, session/socket, app identity, or observability redesign.
- Destructive disk cleanup to make the real local-vendor proof fit.

## Current Constraints

- The worktree currently has uninitialized submodules and none of the four
  projected/prepared paths, so shared acceptance can start from a clean state.
- Primary and linked gitlinks and primary submodule HEADs currently match.
- The primary has all required prepared outputs.
- Real local-vendor proof is intentionally sticky; shared proof must run first.
- Approximately 17 GiB was free during planning. Before local hydration/build,
  recheck available space and expected target sizes. If insufficient, stop
  without deleting user data.
- `scripts/run-debug-observability.sh`,
  `scripts/verify-global-preferences-startup-performance.sh`, and
  `scripts/verify-bridge-headless-manifest.sh` invoke direct Swift or packaging
  paths and therefore require an internal verifier call.
- GitHub Actions is an independent producer. Local-sharing verification must
  recognize `GITHUB_ACTIONS=true` and must not impose the four local projection
  requirements on existing workflow setup.
- `refresh-vendors` currently deletes the complete `terminfo` tree. The change
  must narrow deletion to generated paths so tracked `terminfo/78` survives.

## Boundary and Helper Contract

Add one repository-owned `scripts/vendor-worktree.sh` authority with no
arbitrary source/destination arguments:

```text
role
  primary | shared | local | partial

setup
  primary -> run current producers
  linked complete local -> preserve/run local producers
  linked otherwise -> prepare shared projections

setup-local
  explicit flag only -> validate/remove exact shared links, hydrate locally,
                        run current producers

verify
  primary/local -> validate gitlinks, local submodule HEADs, real output types
  shared        -> validate six revisions, exact links, and byte-equal regular
                   resource copies without nested symlinks
  GitHub Actions -> retain workflow-owned producer checks

require-producer
  allow primary or explicit/current complete local state
  reject shared/partial state before mutation
```

The helper parses `git worktree list --porcelain -z`, canonicalizes roots, uses
committed `HEAD` gitlinks, quotes all paths, and never uses sibling naming or
`eval`.

The closed setup-owned paths are:

- symlink: `Frameworks/GhosttyKit.xcframework`;
- symlink: `vendor/zmx/zig-out`;
- regular replaceable copy: `Sources/AgentStudio/Resources/ghostty`;
- regular replaceable copy:
  `Sources/AgentStudio/Resources/terminfo/67/ghostty`.

Tracked `terminfo/78` and every path outside this allowlist are preserved.
Large-output regular collisions and foreign symlinks fail without mutation.

## Requirements and Proof Matrix

| Contract | Owning task | Proof | Layer | Freshness / red-green |
| --- | --- | --- | --- | --- |
| VR-01, VR-03, VR-04 topology, pins, and source types | Task 1 | Real temporary Git repositories, local dummy submodules, registered worktrees, paths with spaces, six mismatch cases | integration | New UUID fixture each test; failing tests before helper |
| VR-05, VR-06, VR-19 exact projection/copy ownership | Task 2 | Exact two links/two copies, recursive copy equality, stale-copy rejection/repair, idempotence, collision preservation, tracked resource hashes, clean status | integration | Snapshot before mutation; red/green required |
| VR-02, VR-08 producer authority and no fallback | Task 3 | Shared setup and direct producer/refresh invocations fail before Git/Zig/filesystem mutation | integration/source | Spy command markers and primary hashes; red/green required |
| VR-15, VR-16 local-vendor conversion and preservation | Task 3 | Dummy local submodules plus synthetic producer outputs; exact link removal; real local types; primary unchanged; later plain setup preserves | integration | Fresh fixtures; red/green required |
| VR-09, VR-17, VR-18 setup CLI and agent policy | Tasks 3 and 5 | Mise `usage` flag/source contract, static dependency contract, active-instruction scan | unit/source | Expected failure against current config/docs |
| VR-07, VR-20 all supported consumers | Task 4 | Closed source-contract inventory plus preflight-order fixture for each direct consumer seam | unit/integration | Fails against current bypasses; no stale state |
| VR-11, VR-12 copied/signed zmx and debug isolation | Tasks 4, 6, 7 | Existing debug launcher suites plus real bundle and live debug marker/PID/path inspection | integration/smoke/e2e | Fresh app, PID, state marker, Victoria query |
| VR-10 refresh scope/exclusion | Task 3 | Shared refresh rejection; primary/local generated-path refresh; tracked terminfo hashes unchanged | integration | Fresh fixture; operational overlap remains accepted debt |
| VR-13 unchanged independent workflows | Task 5 | Source guard for recursive checkout/producer steps and absence of local helper dependency | source/PR | Current workflow files; no workflow edits |
| VR-14 no extra infrastructure | Final review | Diff inventory and forbidden-surface scan | review | Exact final diff |
| Real shared mode | Task 6 | Plain setup, link/copy/type/pin inspection, build, focused tests, bundle/signature inspection, live debug launch, and marker-scoped Victoria verification | integration/smoke/e2e | Must run before local conversion; fresh bundle, marker, and PID |
| Real local mode | Task 7 | Flagged setup, real local submodule/output types, primary snapshot unchanged, later plain setup preservation, build/tests | integration | One expensive current-worktree execution |
| Observability and runnable product | Tasks 6 and 7 | Shared stack health, debug launch, verifier, LaunchServices smoke when accepted, bundle/signature/zmx/resource inspection in both modes | smoke/e2e | Fresh trace marker and live PID per mode |
| PR readiness | Task 8 | Lint, full tests, release-script gate, diff check, implementation review, CI/check/comment/thread/mergeability state | PR | Exact pushed HEAD |

## Task 0 — Re-anchor and Disk Preflight

Read/verify:

- exact spec and plan hashes/line coverage;
- branch, dirty files, existing user-owned sidecar files;
- primary/current common-directory identity and vendor pins;
- current/primary submodule and output types;
- free disk and expected local materialization sizes;
- active debug process identity before live proof.

Do not delete or modify the untracked editor sidecar
`.2026-07-22-terminal-runtime-distribution.md.mindle.json`.

Checkpoint: current state is safe for shared setup; enough disk exists for the
later local proof or execution stops before hydration.

## Task 1 — Bootstrap the Testable Shared Boundary, Then TDD Verification

The current package cannot compile any Swift test while
`Frameworks/GhosttyKit.xcframework` is absent. Treat the first shared
projection as a prerequisite bootstrap slice, not as product proof:

1. Add the helper skeleton, read-only topology/pin discovery, and only the
   shared projection operation.
2. Before using the Swift suite, exercise that slice with bounded shell
   assertions against a temporary Git repository/worktree fixture and record
   the expected pre-helper failure followed by success.
3. Run plain `mise run setup` in this worktree.
4. Assert all four inputs have the intended types and sources, current
   submodules remain uninitialized, and `swift package describe` succeeds.

Do not implement local mode, producer guards, consumer wiring, or broader
verification in this bootstrap slice.

Write `VendorWorktreeScriptTests` first:

- standalone primary and registered linked worktree classification;
- canonical common-dir validation and paths containing spaces;
- missing/prunable/foreign primary failures;
- current/primary gitlink and primary submodule-HEAD mismatch matrix;
- missing, symlinked, non-directory, and non-executable source outputs;
- primary output identity/content remains unchanged on every failure.

Run the focused suite and record expected failures for the not-yet-implemented
verification and producer-authority behavior. Then implement only `role`,
read-only topology/pin helpers, `verify`, and `require-producer` in
`scripts/vendor-worktree.sh`.

Checkpoint: focused topology/verification suite green; `bash -n` passes.

## Task 2 — TDD Shared Setup Projection

Add failing fixture coverage for:

- exactly two absolute canonical symlinks;
- two regular byte-equal resource copies with no nested symlink escape;
- shared verification recursively compares both copies to the primary source;
- mutating either primary resource source makes verification fail before
  consumption, and rerunning setup repairs the stale copy;
- stale setup-owned resource copies replaced;
- regular/foreign-link collision preservation at the large destinations;
- symlinked ancestor rejection;
- tracked `terminfo/78` unchanged;
- idempotent repeated setup and clean worktree status;
- partial/interrupted setup rejected then repaired by rerunning plain setup.

Implement `setup-shared` with full preflight before mutation and temporary
sibling resource-copy publication. Add the exact superproject ignore for
`vendor/zmx/zig-out`.

Checkpoint: shared fixture suite green and no arbitrary path input exists.

## Task 3 — TDD Setup Dispatch, Local Mode, and Producer Guards

Add failing tests for:

- `.mise.toml` declares boolean `--use-local-vendors`;
- vendor producers are absent from static `setup.depends`;
- BridgeWeb installation and hook setup remain both-mode dependencies;
- plain linked setup never calls Git hydration or Zig;
- shared direct producer/refresh tasks fail before mutation;
- flagged conversion removes only verified primary-target links, especially
  zmx `zig-out`, before hydration/build;
- dummy submodules hydrate recursively and synthetic local outputs are real;
- primary outputs and submodule state remain unchanged;
- complete local state survives later plain setup;
- partial local conversion requires rerunning the flag;
- dirty local vendor source is preserved and allowed for intentional vendor
  development.

Implement:

- setup flag dispatch;
- primary/shared/local/partial state handling;
- local hydration inside the explicit setup-local helper path;
- producer guards in each producer task and `build-ghostty-local.sh`;
- refresh ownership with deletion narrowed to generated paths only;
- explicit missing-zmx bundle failures after verification.

Do not add a production skip-build/test-only flag. Fixture producers are
injected through test PATH/process boundaries, not product configuration.

Checkpoint: local/shared/producer test slices green; tracked terminfo hashes
unchanged.

## Task 4 — TDD Every Consumer and Observability Seam

Add failing `VendorConsumerWiringScriptTests` with a closed inventory of
supported entry points.

Wire the shared verifier before compilation or packaging in:

- mise `build`, `build-release`, `test`, `test-fast`, `test-large`,
  `test-prebuild`, `test-webkit`, `test-coverage`, `test-e2e`, and
  `test-zmx-e2e`; `test-benchmark` inherits through `build`;
- `scripts/run-swift-test-task.sh`;
- `scripts/run-debug-observability.sh` after `--print-identity` and
  `--preflight-idle` exits, before direct build or `--skip-build` packaging;
- `scripts/verify-global-preferences-startup-performance.sh` before its direct
  build;
- `scripts/verify-bridge-headless-manifest.sh` before its direct build/test.

Keep `Package.swift`, zmx/resource copy/sign code, debug identity, isolated
runtime copy, and `AGENTSTUDIO_ZMX_PATH` unchanged.

Extend existing debug script tests to prove verification failure precedes
BridgeWeb build, Swift build, bundle copying, signing, and launch. Retain the
existing regular app-zmx and isolated-zmx assertions.

Checkpoint: focused consumer and observability script suites green.

## Task 5 — Diagnostics and Active Instructions

Make `doctor-mac.sh` role-aware:

- primary/local: submodules, Zig, Xcode/SDK/Metal, and compiler environment;
- shared: primary/pins/outputs/links/copies without requiring Zig/submodules;
- every recovery message uses plain `mise run setup` or the explicitly
  authorized flag, never direct Git/low-level tasks.

Update only active instructions named by the spec. Remove direct recursive
submodule setup from README and doctor output. Make plain setup the agent
default; allow the flag only for user-authorized or accepted Ghostty/zmx change
work. Keep historical plans/WIP unchanged.

Add source tests proving:

- active local instructions do not advertise `git submodule update`,
  `git clone --recurse-submodules`, or `mise run init-submodules`;
- GitHub workflows retain recursive checkout and independent producer steps;
- no workflow references the local-sharing helper or developer primary.

Checkpoint: instruction/diagnostic tests green; workflow files unchanged.

## Task 6 — Real Shared-Mode Acceptance in This Worktree

This gate must precede Task 7:

1. Snapshot primary pins and output identities/hashes.
2. Run plain `mise run setup`.
3. Prove current submodules remain uninitialized.
4. Prove the two exact links point to primary.
5. Prove both resource paths are regular local copies and tracked
   `terminfo/78` remains clean.
6. Prove primary snapshot unchanged.
7. Run the focused vendor/consumer/debug script suites.
8. Run `mise run build` and representative default test work.
9. Run `mise run create-app-bundle`; inspect zmx/resources as regular,
   self-contained bundle content and verify the signature.
10. Start/check the shared observability stack, ensure the worktree debug app is
    idle, launch with `mise run run-debug-observability -- --detach`, and run
    `mise run verify-debug-observability`.
11. Inspect the fresh marker, live PID, bundle identity, app zmx, isolated
    runtime zmx, data/zmx roots, signature, and `AGENTSTUDIO_ZMX_PATH`.
12. Quit the debug app through its normal termination path.
13. Separately exercise identity/preflight modes to prove they remain
    non-consuming; do not count them as vendor-consumption proof.

Record commands, exit codes, pins, path types, targets, and hashes.

## Task 7 — Real Local Mode, Bundles, and Debug Observability

Recheck disk without cleanup. Snapshot primary assets and submodule HEADs.

1. Run `mise run setup --use-local-vendors`.
2. Prove both current submodules are hydrated at current gitlinks.
3. Prove XCFramework and `vendor/zmx/zig-out` are real local directories.
4. Prove primary snapshot unchanged.
5. Run plain `mise run setup` again and prove local state is preserved.
6. Run focused tests, `mise run build`, and `mise run create-app-bundle`.
7. Inspect app zmx/resource content as regular self-contained files and verify
   the app signature.
8. Use the shared observability stack skill to start/check the stack.
9. Ensure this worktree's debug app is idle, launch through
   `mise run run-debug-observability -- --detach`, and run
   `mise run verify-debug-observability`.
10. Inspect the fresh state marker, live PID, bundle identity, app zmx,
    isolated debug-root zmx, data/zmx roots, signature, and
    `AGENTSTUDIO_ZMX_PATH`.
11. Run the real LaunchServices debug smoke if the environment accepts the
    generated debug app; report a direct-executable fallback separately rather
    than calling it GUI proof.
12. Run `mise run verify-bridge-headless-manifest` in both shared and local
    modes. Run the full global-preferences startup performance verifier once
    after local mode when its documented prerequisites are available.
    Permanent source/order tests cover inherited debug-runner wrappers; do not
    count identity/preflight-only modes as vendor-consumption proof.

Quit the launched debug app/process through its normal termination path after
proof. Do not delete shared observability data or app artifacts.

## Task 8 — Full Gates, Review, and PR

Run:

- focused script suites;
- `mise run test`;
- `mise run test-large`;
- `mise run test-e2e`;
- `mise run test-zmx-e2e`;
- `mise run test-webkit` unless its complete lane is already demonstrably
  included by an earlier authoritative gate;
- `mise run lint`;
- `bash scripts/verify-release-scripts.sh`;
- `git diff --check`;
- implementation review swarm over the exact diff.

Fix only scoped findings and rerun affected gates. Inspect the final diff for
secrets, machine paths, user metadata, generated vendor outputs, editor
sidecars, and unrelated files.

Commit intentionally, push `better-worktree`, open a draft PR with requirements
and proof, then verify:

- local HEAD equals PR head;
- checks complete successfully;
- actionable comments and review threads are resolved;
- mergeability is known;
- the PR is left unmerged unless separately authorized.

## Execution DAG

```text
gate 0: source/state/disk re-anchor
  |
task 1: topology + verifier RED -> GREEN
  |
task 2: shared projection RED -> GREEN
  |
task 3: setup dispatch + local mode + producer guards RED -> GREEN
  |
task 4: consumer/observability wiring RED -> GREEN
  |
task 5: diagnostics/instructions + source proof
  |
task 6: real shared setup/build/test
  |
task 7: real local setup/build/bundle/debug observability
  |
task 8: broad gates -> implementation review -> commit/push/PR gates
```

Execution is intentionally serial. Tasks 1-4 share the helper, `.mise.toml`,
and test fixtures; parallel edits would create authority and ordering races.
Read-only review/monitoring may run in parallel after the integrated diff
exists.

## Recovery and Split/Replan Triggers

- Shared projection failure: rerun plain setup; only setup-owned allowlist
  entries may be repaired.
- Unexpected collision: preserve it and stop with the exact path/type.
- Interrupted local conversion: rerun the flagged setup; plain setup preserves
  and rejects partial local state.
- Missing/mismatched primary: prepare the registered primary or use the
  explicitly authorized local flag; never auto-hydrate.
- Failed refresh: quiesce workers, rerun owner setup, then reverify consumers.
- Stop and request authority before any disk cleanup.
- Replan if a receipt is required to distinguish resource ownership, refresh
  must overlap workers, staged/uncommitted gitlinks must be supported, a direct
  consumer cannot accept the verifier, or multiple shared tuples are required.

## Open Questions

None block implementation. GitHub Actions is explicitly classified as an
independent producer so its existing workflows remain unchanged.
