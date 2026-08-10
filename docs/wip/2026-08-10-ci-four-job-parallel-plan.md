# CI Four-Job Parallelization Implementation Plan

> **For agentic workers:** Execute this plan inline with focused verification after each workflow contract slice.

**Goal:** Move the Swift-backed BridgeWeb integration and E2E proof into a fourth independent CI job while retaining cache correctness and only parallelizing preparation steps with independent ownership.

**Architecture:** Keep `code-quality`, `bridge-web-validation`, and `swift-test-suite` independent, then add `bridge-web-swift-backend` with its own runner and workspace. The backend job restores the existing Swift cache as a read-only build seed, builds the backend once, and runs prepared BridgeWeb suites; only `swift-test-suite` prebuilds and saves the Swift test cache. Within jobs, overlap dependency/cache restores, vendor builds, and resource copies; keep Swift test execution and backend suites serial until separate runtime isolation is proven.

**Tech Stack:** GitHub Actions, `actions/cache`, Xcode 26.3, mise, SwiftPM, pnpm, Vitest.

## Global Constraints

- Preserve all current BridgeWeb and Swift proof lanes.
- Do not introduce a `needs:` edge between the four required jobs.
- Do not let the backend job save under the Swift test cache key.
- Keep `.build-ci` private to each job workspace.
- Use explicit prepared BridgeWeb scripts so CI does not rebuild the backend per suite.
- Do not parallelize Swift fast/WebKit execution or backend integration/E2E in this first slice.

---

### Task 1: Add prepared BridgeWeb test commands

**Files:**
- Modify: `BridgeWeb/package.json:19-29`

**Interfaces:**
- Produces `test:integration:node:prepared` and `test:e2e:prepared`, each running its existing Vitest configuration without invoking Swift compilation.

- [x] Add the two prepared scripts beside the existing local scripts, preserving the existing build-prefixed commands for local callers.
- [x] Verify the JSON remains valid and the existing `test` aggregate still uses the build-prefixed commands.

### Task 2: Split the Swift-backed proof into a fourth job

**Files:**
- Modify: `.github/workflows/ci.yml:100-284`

**Interfaces:**
- Adds `bridge-web-swift-backend` with descriptive job name `BridgeWeb Swift backend`.
- Removes the backend test step from `swift-test-suite`.
- Backend job restores `swift-test-v2` into private `.build-ci` but has no cache-save step.

- [x] Add the backend job with checkout, Xcode 26.3, mise, recursive submodules, pnpm/Node, and the existing vendor cache keys.
- [x] Put BridgeWeb install and vendor cache restores in one `parallel` group.
- [x] Put Ghostty and zmx compilation in a second `parallel` group, conditional on cache misses.
- [x] Put XCFramework copy and resource setup in a third `parallel` group.
- [x] Compute the existing Swift fingerprint and restore the existing Swift cache before compiling the backend.
- [x] Build the backend once, then run prepared Node integration and E2E steps serially.
- [x] Remove the old backend step from the Swift job and keep Swift fingerprint, restore, prebuild/save, fast, and WebKit ordering intact.
- [x] Do not add `needs:` edges or a backend cache save.

### Task 3: Update workflow contract tests

**Files:**
- Modify: `Tests/AgentStudioTests/Scripts/CIFastLaneWorkflowTests.swift:45-190`

**Interfaces:**
- Contract tests recognize the fourth job, its checkout credential policy, prepared scripts, resource ordering, and cache ownership.

- [x] Add the new job to descriptive-name and checkout-credential assertions.
- [x] Replace the old assertion that backend lanes live in `swift-test-suite` with assertions that they live in `bridge-web-swift-backend` after vendor/resource preparation.
- [x] Assert the Swift job no longer contains the backend lane.
- [x] Assert the backend job uses prepared scripts and does not save the Swift test cache.
- [x] Assert the existing Swift preparation parallel groups remain ordered and add coverage for the resource-copy parallel group.

### Task 4: Verify the implementation

**Files:**
- No additional files.

- [x] Run the focused Swift workflow-contract test: 12 tests passed.
- [x] Run workflow syntax validation with the repository-supported validator; `actionlint 1.7.12` still rejects the six existing/new `parallel` groups because its schema predates the GitHub Actions step-parallel feature.
- [x] Run BridgeWeb package script validation/typecheck: `pnpm --dir BridgeWeb run check` passed.
- [x] Inspect the final diff and confirm no unrelated files changed; only the workflow, package manifest, contract tests, and this WIP plan are changed.

Local backend runtime note: the prepared backend command was attempted from this linked worktree, but the shared vendor setup exposes `Frameworks/GhosttyKit.xcframework` as a symlink and `vendor-worktree.sh verify` intentionally requires a real CI checkout directory. The CI job uses recursive checkout and therefore has the required real vendor paths; no local vendor hydration was performed.
