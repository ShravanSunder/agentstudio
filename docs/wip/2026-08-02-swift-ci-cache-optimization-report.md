# Swift CI test-cache optimization report

## Scope and status

- Repository: `ShravanSunder/agentstudio`
- Worktree: `/Users/shravansunder/Documents/dev/project-dev/agent-studio.ci-swift-test-cache`
- Branch: `ci/swift-test-cache`
- Pull request: [#237](https://github.com/ShravanSunder/agentstudio/pull/237)
- Implementation head under test: `1a608c5a0e016c9faa3ce073dbf114040aac545a`
- Base: `origin/main` at `f1bfedc28918a9fba64049937e035cbb8169af1e`
- Merge: intentionally not performed. The PR remains open for the user’s merge decision.

This report covers the cache investigation, the final implementation currently pushed to the PR, local proof, and the completed CI cache-miss/exact-hit experiment.

## Problem

The Swift CI job restored `.build-ci`, then unconditionally ran `swift build --build-tests`. A cache archive hit therefore did not remove the dominant prebuild cost. The old cache key also mixed a broad `hashFiles()` expression with vendor SHAs and did not make the actual post-setup SwiftPM input boundary explicit.

The job sequence is:

```text
checkout + Xcode 26.3
  -> BridgeWeb packaged build
  -> Ghostty/zmx artifacts and generated resources
  -> restore .build-ci
  -> swift build --build-tests (the expensive barrier)
  -> fast and WebKit tests with --skip-build
```

The optimization target is only the restore/prebuild decision. Test execution, test selection, vendor builds, and the test proof floor remain unchanged.

## Baseline evidence

Successful baseline run [30776439689](https://github.com/ShravanSunder/agentstudio/actions/runs/30776439689):

| Segment | Observed duration |
| --- | ---: |
| Whole Swift job | 15m43s |
| `.build-ci` restore (1.38 GB) | 41s |
| Swift test-bundle prebuild | 6m29s |
| Cache save | 47s |
| Fast tests | 2m59s |
| WebKit tests | 3m10s |

Earlier runs showed the same shape: exact archive restoration was roughly 34–50s, but Swift prebuild still consumed roughly 5m41s–9m56s when the workflow always executed it. The old PR-ref cache key also prevented cache roll-forward between commits.

The dominant possible saving is therefore the prebuild plus save path, not parallelizing test workers further.

## Research conclusions

1. `actions/cache/restore` reports an exact hit only when the requested primary key matches. A restore-key match is a partial hit and must still rebuild and save under the new primary key.
2. `hashFiles()` is byte-oriented and does not provide a path/mode/directory contract. A rename or mode-only change can collide, and an empty directory is invisible if only files are enumerated.
3. SwiftPM’s scratch/build directory is not guaranteed to be portable across fresh workspaces. Cache correctness must be conservative: cache keys must include all build inputs and toolchain identity, and the workflow must rebuild on a partial/missing hit.
4. The SwiftPM target copies directory resources (`Resources/terminfo`, `Resources/ghostty`, and `Resources/BridgeWeb`). Directory identity therefore matters even when a directory contains no files.

## Final design

### Input fingerprint

[`scripts/swift-build-input-fingerprint.sh`](/Users/shravansunder/Documents/dev/project-dev/agent-studio.ci-swift-test-cache/scripts/swift-build-input-fingerprint.sh:1) runs after BridgeWeb and vendor-derived resources are prepared. It fingerprints:

- `Package.swift`, `Package.resolved`, and `.mise.toml`;
- the actual post-setup `Sources/` and `Tests/` trees, including generated resources;
- `Frameworks/GhosttyKit.xcframework`;
- `scripts/swift-build-slot.sh`, `scripts/swift-test-helpers.sh`, `scripts/run-swift-test-task.sh`, and the fingerprint script itself.

Each sorted record includes entry type, POSIX mode, repository-relative path, and either file content SHA-256 or symlink target. Directories are recorded as well as files, so empty and mode-only directory changes invalidate the digest.

The workflow separately hashes:

```text
xcodebuild -version
swift --version
xcrun --sdk macosx --show-sdk-version
```

The local sample was Xcode 26.3 build 17C529, Swift 6.2.4, macOS SDK 26.2.

### Cache flow

```text
post-setup inputs
  ├─ path-aware source/resource digest
  └─ toolchain digest
          │
          ▼
restore .build-ci with exact key
          │
          ├─ exact hit ─────► skip prebuild and skip save
          │                    run tests with --skip-build
          │
          └─ miss/partial ──► prebuild test bundles
                               save under cache-primary-key
                               run tests with --skip-build
```

The primary key is:

```text
swift-test-v2-${runner.os}-${runner.arch}
  -xcode-${toolchainDigest}-debug-${swiftInputDigest}
```

The restore prefix is `swift-test-v2-${runner.os}-${runner.arch}-xcode-`, and both prebuild and save are gated on:

```text
steps.swift-build-cache-restore.outputs.cache-hit != 'true'
```

No PR number, branch name, commit SHA, or `hashFiles()` expression participates in the primary key.

## Implementation

- `1a608c5`: capture Xcode/Swift/SDK diagnostics in the key (current pushed head).
- `8f6d340`: include toolchain and directory inputs after independent review found both gaps.
- `d88271b`: require fingerprint computation after BridgeWeb and generated-resource setup.
- `f8e2b19`: introduce the path-aware fingerprint and exact-hit gating.
- `dda424b`: prior intermediate content-key experiment.
- `6796f83`: prior commit-qualified cache experiment.

Changed implementation files:

- [`.github/workflows/ci.yml`](/Users/shravansunder/Documents/dev/project-dev/agent-studio.ci-swift-test-cache/.github/workflows/ci.yml:226)
- [`scripts/swift-build-input-fingerprint.sh`](/Users/shravansunder/Documents/dev/project-dev/agent-studio.ci-swift-test-cache/scripts/swift-build-input-fingerprint.sh:1)
- [`CIFastLaneWorkflowTests.swift`](/Users/shravansunder/Documents/dev/project-dev/agent-studio.ci-swift-test-cache/Tests/AgentStudioTests/Scripts/CIFastLaneWorkflowTests.swift:70)
- [`SwiftBuildInputFingerprintScriptTests.swift`](/Users/shravansunder/Documents/dev/project-dev/agent-studio.ci-swift-test-cache/Tests/AgentStudioTests/Scripts/SwiftBuildInputFingerprintScriptTests.swift:1)

## Local proof

| Command | Result |
| --- | --- |
| `swift test --disable-sandbox --build-path .build-agent-1 --filter CIFastLaneWorkflowTests` | 9/9 passed |
| `swift test --disable-sandbox --build-path .build-agent-1 --filter SwiftBuildInputFingerprintScriptTests` | 7/7 passed |
| `bash -n scripts/swift-build-input-fingerprint.sh` | passed |
| `actionlint .github/workflows/ci.yml` | passed |
| `git diff --check` | passed |
| `mise run lint` with an in-process `commit.gpgsign=false` override for disposable release-test commits | passed; SwiftLint 0 violations, architecture lint and release verification passed |

The fingerprint script took 26.1s on the full local tree and under 2s per fixture suite. The normal unoverridden `mise run lint` wrapper was also run; its release fixture attempted temporary Git commits using the repository’s 1Password signing configuration and failed before release assertions. No source lint failure was observed. The in-process override changed no repository or global configuration.

The fingerprint fixture tests cover:

- identical trees remain stable;
- file content changes;
- file renames;
- file mode changes;
- symlink-target changes;
- empty-directory creation;
- generated BridgeWeb resource changes;
- Ghostty framework changes.

## CI proof

The first final-head run [30778383691](https://github.com/ShravanSunder/agentstudio/actions/runs/30778383691) for `1a608c5` completed with Swift success and BridgeWeb failure. Its Swift timing evidence is:

| Segment | Run 30778383691 |
| --- | ---: |
| Swift job | 21m26s |
| Fingerprint computation | 50s |
| Swift cache restore | miss |
| Swift test-bundle prebuild | 12m49s |
| Swift cache save | 57s |
| Fast + WebKit lanes | passed |

The BridgeWeb failure was in `Run BridgeWeb lanes`: 142 tests passed, 1 failed, and the browser failure guard tripped on repeated React `act(...)` console warnings. This is outside the Swift cache diff and must be independently rechecked, not silently treated as a Swift failure.

The same run was rerun at the same SHA. That rerun is the exact-cache experiment:

1. First run: fingerprint miss, prebuild runs, and cache saves under the new exact key. This is now evidenced above.
2. Same-SHA rerun: exact fingerprint hit, prebuild and save steps were skipped, and both test lanes passed.
3. Compare the two runs to the 15m43s baseline. The exact-hit Swift job completed in 7m16s, a reduction of 8m27s versus that baseline.

Same-SHA exact-hit rerun [30778383691, attempt 2](https://github.com/ShravanSunder/agentstudio/actions/runs/30778383691) at `1a608c5`:

| Segment | Rerun attempt 2 |
| --- | ---: |
| Swift job | 7m16s |
| Fingerprint computation | 36s |
| Swift cache restore | 23s (exact hit) |
| Swift test-bundle prebuild | skipped |
| Swift cache save | skipped |
| Fast tests | 2m28s |
| WebKit tests | 2m35s |

All three jobs passed on the rerun:

- Swift test suite: [job 91580940862](https://github.com/ShravanSunder/agentstudio/actions/runs/30778383691/job/91580940862), 7m16s.
- Code quality: [job 91580940870](https://github.com/ShravanSunder/agentstudio/actions/runs/30778383691/job/91580940870), 2m58s.
- BridgeWeb validation: [job 91580940890](https://github.com/ShravanSunder/agentstudio/actions/runs/30778383691/job/91580940890), 3m24s.

The first final-head attempt in the same run had a Swift cache miss and recorded the expected expensive path (50s fingerprint, 12m49s prebuild, 57s save), while BridgeWeb independently hit a flaky React `act(...)` warning guard. The exact-hit rerun passed BridgeWeb, so that first failure did not reproduce and is not attributed to this Swift cache change.

The exact-hit rerun did not rebuild inside either test lane. This validates the intended workflow gate: a complete exact cache skips the prebuild barrier while preserving `--skip-build` test execution. A future cache-portability investigation is only needed if a later exact-hit run unexpectedly rebuilds.

## Risks and tradeoffs

- The path-aware digest costs about 26–30s locally and may be somewhat different on GitHub-hosted runners. That is a bounded cost against a multi-minute prebuild.
- A new SwiftPM input or toolchain input must be added to the fingerprint contract; the focused fixture and workflow tests make accidental narrowing visible, but they cannot prove future dependencies that are not named.
- Partial restores intentionally rebuild. This preserves correctness at the cost of a slower first run after an input change.
- The branch contains no merge or release action. The CI proof is complete; any merge decision remains separate from this report.

## Current handoff

PR #237 is evidence-ready and intentionally remains open and unmerged. The implementation under test is pushed at `1a608c5`; this report is the only follow-up commit. Local proof and the CI miss/exact-hit experiment are recorded above. The exact-hit rerun passed all required jobs and reduced the Swift job from the 15m43s baseline to 7m16s. Any merge or follow-up cache-portability work is a separate user decision.
