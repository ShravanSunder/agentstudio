# AgentStudio Local SwiftPM Architecture Lint Plan

Date: 2026-06-15
Status: Draft plan, not executed
Supersedes: `docs/plans/2026-06-14-swiftlint-swiftsyntax-architecture-rules.md`

## Goal

Remove the AgentStudio architecture-lint dependency on `ai-tools`, Bazel,
Bazelisk, and Java. This is only about the AgentStudio architecture-lint path.
Keep normal SwiftLint for stock and regex rules, but move AgentStudio-specific
structural architecture checks into an AgentStudio-owned SwiftPM/SwiftSyntax
tool that is isolated from product targets.

This plan is intentionally scoped to AgentStudio. The user will delete the
temporary ai-tools SwiftLint/Bazel branch separately. Do not modify
`~/dev/ai-tools` as part of this implementation.

The earlier draft had three material defects:

1. It treated the old ai-tools branch mostly as rejected tooling instead of
   mandatory source material. That was wrong because the branch contains rule
   semantics and fixtures that must be translated, even though its build system
   must be discarded.
2. It listed only the original seven architecture rule ids. That would have
   silently dropped the IPC/programmatic-control rules from the later commits.
3. It used the phrase "observability references are out of scope" without
   saying exactly what that meant. The correct meaning is: keep the separately
   approved `~/dev/ai-tools/observability` references untouched; remove
   `ai-tools` only from AgentStudio architecture lint.

## Source Coverage

Chat requirement, 2026-06-15:

- AgentStudio must not use `ai-tools` for AgentStudio architecture lint rules.
- AgentStudio must not use Bazel, Bazelisk, or Java for this lint path.
- The structural lint rules should be implemented with Swift and SwiftPM.
- The replacement should live in AgentStudio, but must not pollute product app
  targets.
- ai-tools cleanup is a final external/user-owned step unless explicitly
  reauthorized.
- The listed ai-tools commits are source coverage: translate their AgentStudio
  architecture rule behavior and fixtures into the AgentStudio-local SwiftPM
  tool, then delete the AgentStudio dependency on the ai-tools implementation.

Current repo evidence inspected on current `main` at
`f8857db9330cb3e96f3e805ad2011b5144933497`:

- `.mise.toml`: 474 lines counted; lint task lines 101-114 run
  `scripts/run-agentstudio-architecture-swiftlint.sh lint --strict`.
- `.github/workflows/ci.yml`: 265 lines counted; lint dependency line 36
  installs `swift-format bazelisk`.
- `.swiftlint.yml`: 213 lines counted; stock SwiftLint configuration plus regex
  `custom_rules` remain useful and should stay.
- `scripts/run-agentstudio-architecture-swiftlint.sh`: 120 lines counted;
  currently resolves and builds a pinned tool from `ai-tools`.
- `scripts/agentstudio-architecture-swiftlint.env`: 4 lines counted; currently
  pins `https://github.com/ShravanSunder/ai-tools.git` commit
  `280eb2a1925ff3f89d6e67f2a728129f7247f723`.
- `Tests/AgentStudioTests/Scripts/ArchitectureSwiftLintRulesTests.swift`: 117
  lines counted; currently asserts the ai-tools pin and `bazelisk` CI install.
- `docs/architecture/architecture_lint_inventory.md`: 48 lines counted;
  currently says ai-tools verifier builds the custom SwiftLint binary.
- `docs/architecture/directory_structure.md`: 448 lines counted; import
  direction and SharedComponents rules inspected.
- `docs/architecture/atom_persistence_boundaries.md`: 205 lines counted;
  AtomLib, DerivedValue, AtomEntityMap, and hot dictionary-read rules inspected.
- `AGENTS.md`: 713 lines counted; architecture lint guidance currently says
  the custom rule source lives in `~/dev/ai-tools/...`.
- `Package.swift`: 101 lines counted; app package currently has no tool target
  or SwiftSyntax dependency.

Upstream SwiftLint evidence:

- SwiftLint supports Swift Package plugins for running normal SwiftLint.
- SwiftLint's documented Swift custom rules are SwiftSyntax-capable, but using
  them requires building SwiftLint with Bazel.
- Therefore this plan does not call the replacement a "native SwiftLint custom
  rule" unless SwiftLint upstream gains a non-Bazel injection path. The honest
  design is stock SwiftLint plus a separate SwiftPM/SwiftSyntax architecture
  linter.

Rejected-tooling source material to port, read-only:

- `9f2121b01c1134911b42402a4f57b6ff4b5b1d0f`: initial AgentStudio architecture
  rule implementation and good/bad fixtures.
- `d730bf6b4b3f0e955e5111401e46ef6cfb0e7a19`: tightened
  `agentstudio_shared_components_are_stateless` behavior and fixtures.
- `b2a5ba02362d5a0488b209b065e4572e85378683`: bootstrap hardening plus
  DerivedValue fixture/readme changes that must be reviewed for rule semantics.
- `280eb2a1925ff3f89d6e67f2a728129f7247f723`: locked npm/custom-SwiftLint
  bootstrap evidence; port no Bazel/npm/bootstrap mechanics, but use it to
  identify AgentStudio references that must be removed.
- `1bc0e474c48cf01c815f83e16abd65be6d27f51b`: IPC/programmatic-control
  architecture rules and fixtures.
- `6d8ef2947fc5e7512f2974a701a9205629a0a346`: Bazel output ignore evidence;
  port no behavior except the negative requirement that AgentStudio should not
  create Bazel outputs.

Required final rule inventory:

- `agentstudio_import_direction`
- `agentstudio_shared_components_are_stateless`
- `agentstudio_atomlib_is_generic`
- `agentstudio_derived_value_declared_inputs`
- `agentstudio_repo_cache_keyed_reads`
- `agentstudio_worktree_enrichment_comparator`
- `agentstudio_state_actor_path`
- `agentstudio_ipc_programmatic_control_boundary`
- `agentstudio_appipc_port_boundary`
- `agentstudio_ipc_composition_location`
- `agentstudio_ipc_public_surface_sanitization`
- `agentstudio_ipc_no_direct_atom_access`
- `agentstudio_no_forbidden_architecture_marker`

## Non-Goals

- Do not modify, delete, branch-delete, or clean `~/dev/ai-tools`.
- Do not remove observability references to `~/dev/ai-tools/observability`.
  Those references belong to the separately approved shared local observability
  stack. They are not the architecture-lint problem. Searches for old
  architecture-lint references must distinguish them from observability
  references.
- Do not reintroduce shell or `rg` architecture scanners as the long-term gate.
- Do not add SwiftSyntax dependencies to the AgentStudio app/test package unless
  the implementation explicitly proves product targets do not resolve or build
  them.
- Do not claim the SwiftPM tool is SwiftLint-native. It is an AgentStudio
  architecture linter run alongside SwiftLint.

## Design Decision

Create a separate SwiftPM package under AgentStudio:

```text
Tools/
  AgentStudioArchitectureLint/
    Package.swift
    Sources/
      AgentStudioArchitectureLint/
        main.swift
        ArchitectureLintCommand.swift
        Rule.swift
        RuleContext.swift
        Rules/
          ImportDirectionRule.swift
          SharedComponentsStatelessRule.swift
          AtomLibGenericRule.swift
          DerivedValueDeclaredInputsRule.swift
          RepoCacheKeyedReadsRule.swift
          WorktreeEnrichmentComparatorRule.swift
          StateActorPathRule.swift
          IPCProgrammaticControlBoundaryRule.swift
          AppIPCPortBoundaryRule.swift
          IPCCompositionLocationRule.swift
          IPCPublicSurfaceSanitizationRule.swift
          IPCNoDirectAtomAccessRule.swift
          ForbiddenArchitectureMarkerRule.swift
    Tests/
      AgentStudioArchitectureLintTests/
        ArchitectureLintCommandTests.swift
        RuleParityTests.swift
        Fixtures/
          Good/
            Sources/
              AgentStudio/
              AgentStudioAppIPC/
              AgentStudioProgrammaticControl/
          Bad/
            Sources/
              AgentStudio/
              AgentStudioAppIPC/
              AgentStudioProgrammaticControl/
```

This package is repo-local and AgentStudio-owned, but product-isolated. The app
root `Package.swift` should not gain SwiftSyntax dependencies. The tool package
owns its own `Package.swift`, dependencies, tests, and fixtures.

The tool package manifest must make these contracts explicit:

- executable product name: `agentstudio-architecture-lint`
- executable target/module name: `AgentStudioArchitectureLint`
- exact `swift-syntax` dependency tag: `602.0.0`, matching the current Swift
  6.2 toolchain family. Upgrade this tag only with a toolchain upgrade.
- no `swift-argument-parser` in v1 unless the implementation updates this plan
  with a concrete reason.
- commit `Tools/AgentStudioArchitectureLint/Package.resolved` so clean clones
  do not re-resolve the architecture-lint tool differently from reviewed code.
- the test target excludes the fixture tree from compilation, for example
  `exclude: ["Fixtures"]`, and loads fixtures as files/resources at runtime.

`mise run lint` should become:

```text
swift-format lint --recursive Sources/ Tests/ Tools/AgentStudioArchitectureLint/Sources Tools/AgentStudioArchitectureLint/Tests
swiftlint lint --strict
swift run --package-path Tools/AgentStudioArchitectureLint agentstudio-architecture-lint Sources Tests
/bin/bash scripts/verify-release-scripts.sh
```

Stock SwiftLint and swift-format must cover the tool implementation. If fixtures
cannot safely run through the repo-wide format/lint config, exclude only
`Tools/AgentStudioArchitectureLint/Tests/AgentStudioArchitectureLintTests/Fixtures`
and document why; do not exclude the tool sources or non-fixture tests.

The architecture linter should emit diagnostics in a simple stable format first:

```text
path:line:column: error: [agentstudio_import_direction] Core must not import Features.
```

If GitHub Actions annotation formatting is needed, add it after the baseline
tool is proven. Do not make reporter polish block removal of Bazel/ai-tools.

## Requirements And Proof Matrix

| Requirement | Owning task | Proof owner | Proof gate | Layer | Stale-proof guard | Red/green required | Sized to pass |
| --- | --- | --- | --- | --- | --- | --- | --- |
| AgentStudio architecture lint no longer depends on `ai-tools`. | Rewire lint | Executor | `rg -n "agentstudio-architecture-rules|AGENTSTUDIO_ARCH_SWIFTLINT|run-agentstudio-architecture-swiftlint|https://github.com/ShravanSunder/ai-tools.git" .mise.toml .github scripts Tests docs/architecture docs/guides AGENTS.md Package.swift Tools` shows no architecture-lint hits. Historical `docs/plans/**` references are excluded from this no-hit gate and must instead be explicitly marked superseded/rejected. Separately approved observability hits are allowed only when they point to `~/dev/ai-tools/observability` or observability scripts/docs. | Static | Search includes active executable, tests, architecture docs, guide docs, CI surfaces, and the new tool package. Observability and historical-plan hits must be manually classified and listed in the proof note. | No; removal proof is direct. | Yes |
| Bazel/Bazelisk/Java are not in the AgentStudio lint path. | Rewire CI and scripts | Executor | `rg -n "\b(Bazel|Bazelisk|bazel|bazelisk|JAVA_HOME|java_home|openjdk)\b" .github .mise.toml scripts Tests docs/architecture docs/guides AGENTS.md Package.swift Tools` has no architecture-lint hits. Historical `docs/plans/**` references are excluded from this no-hit gate and must be marked superseded/rejected. | Static | Search includes CI and new tool package without matching unrelated words such as JavaScript. | No | Yes |
| Normal SwiftLint still runs stock and regex rules. | Rewire lint | Executor | `mise run lint` plus focused fixture test for `no_combine_import`. | Unit/integration | Test invokes real `swiftlint lint --strict --config .swiftlint.yml` against temp fixture. | Yes: bad fixture fails, good fixture passes. | Yes |
| Structural architecture rules are SwiftPM/SwiftSyntax-owned in AgentStudio. | Build local tool | Executor | `swift test --package-path Tools/AgentStudioArchitectureLint` and `swift run --package-path Tools/AgentStudioArchitectureLint agentstudio-architecture-lint --print-rules` show all 13 required `agentstudio_*` rule ids plus severities. | Unit/integration | Rules are discovered from the built local package, then compared against this plan's required inventory. `agentstudio_state_actor_path` remains warning; the other 12 rules remain errors unless this plan is updated and reviewed. | Yes: bad fixtures fail, good fixtures pass. | Yes |
| Product package stays free of lint-tool dependencies. | Package isolation | Executor | `Package.swift` root app package has no SwiftSyntax / ArgumentParser / lint-tool dependencies; `swift build` still builds app package. `Tools/AgentStudioArchitectureLint/Package.swift` owns `swift-syntax` exactly at `602.0.0`, and its committed `Package.resolved` is the only resolver artifact for the tool package. | Build/static | Compare root package and tool package separately. Fresh `swift package resolve --package-path Tools/AgentStudioArchitectureLint` leaves no unreviewed resolver churn. | No | Yes |
| Existing architecture coverage from the six listed ai-tools commits is preserved or explicitly reclassified. | Rule parity | Executor | Architecture inventory maps every listed commit's rule and fixture contribution to a local SwiftPM rule, a local fixture, or a written non-port rationale. A checked-in parity table records source commit, source fixture path, changed hunk/semantic case, local fixture/test path, and non-port rationale when applicable. | Docs/test | Read-only comparison against the listed commit SHAs, especially `AgentStudioExtraRules.swift`, verifier expectations, and Good/Bad fixture contents/changed hunks. Name-only fixture parity is not enough. | Yes for all migrated rule rows. | Yes |
| IPC/programmatic-control architecture rules from the later commit are not lost. | IPC rule port | Executor | `--print-rules` includes the five IPC rule ids plus `agentstudio_no_forbidden_architecture_marker`; tests include translated Good/Bad IPC fixtures that preserve upstream relative path topology under `Fixtures/{Good,Bad}/Sources/...`. | Unit/integration | Compare against `1bc0e474c48cf01c815f83e16abd65be6d27f51b` rule registration and fixture contents. `architecture_lint_inventory.md` must map each IPC rule to a repo-local architecture contract, not only to branch-era fixtures. | Yes | Yes |
| Observability's approved ai-tools stack references remain untouched. | Scope guard | Executor | Diff review shows no edits to observability docs/scripts/env names except if explicitly approved in a separate task. Static search classifies remaining `~/dev/ai-tools/observability` references as observability-only. | Static/docs | Search terms include `ai-tools`, `observability`, `run-debug-observability`, and `AI_TOOLS_OBSERVABILITY`. | No | Yes |
| CI proves the same gates without Bazel/Bazelisk. | CI update | Executor | GitHub CI lint/test success after PR push; lint install step no longer installs `bazelisk`; CI runs both `mise run lint` and `swift test --package-path Tools/AgentStudioArchitectureLint` on the PR head. | CI | Fresh PR head SHA check, not older run. | No | Yes |
| Docs stop blessing ai-tools for AgentStudio architecture lint. | Docs update | Executor | `AGENTS.md`, architecture inventory, agent resources, and superseded-plan note point to `Tools/AgentStudioArchitectureLint`. | Docs/static | Active-doc search for old lint ownership terms excludes historical `docs/plans/**` but includes `AGENTS.md`, `docs/architecture/**`, and `docs/guides/**`. | No | Yes |

## Task Sequence

### 1. Branch And Preflight From Current Main

- Start from current `main`.
- Create a new AgentStudio worktree/branch for the fix.
- Confirm clean status before edits.
- Record preflight evidence:
  - `git status --short --branch`
  - `rg -n "agentstudio-architecture-rules|AGENTSTUDIO_ARCH_SWIFTLINT|run-agentstudio-architecture-swiftlint|https://github.com/ShravanSunder/ai-tools.git" .mise.toml .github scripts Tests docs/architecture docs/guides AGENTS.md Package.swift Tools || true`
  - `rg -n "\b(Bazel|Bazelisk|bazel|bazelisk|JAVA_HOME|java_home|openjdk)\b" .github .mise.toml scripts Tests docs/architecture docs/guides AGENTS.md Package.swift Tools || true`
  - `command -v swift swiftlint swift-format`
  - `command -v java javac bazel bazelisk || true` as informational cleanup
    context only; these tools being absent is valid after this migration.
  - `brew list --versions bazel bazelisk openjdk swiftlint swift-format || true`
    as informational cleanup context only.

### 2. Add AgentStudio-Local Tool Package

- Create `Tools/AgentStudioArchitectureLint/Package.swift`.
- Use SwiftPM only.
- Dependencies:
  - `apple/swift-syntax` pinned exactly to `602.0.0`.
  - `apple/swift-argument-parser` only if the command-line surface earns it;
    otherwise parse a minimal argument list manually to keep dependency surface
    smaller.
- Expose an explicit executable product named
  `agentstudio-architecture-lint`; keep the executable target/module name
  `AgentStudioArchitectureLint`.
- Commit `Tools/AgentStudioArchitectureLint/Package.resolved`.
- Implement a small rule protocol:
  - rule id
  - severity
  - diagnostic message
  - `validate(file:source:syntaxTree:context:) -> [Diagnostic]`
- Implement path-aware file discovery:
  - include `Sources/` and `Tests/` by default
  - skip `vendor/`, `.build/`, `Frameworks/`, `Tools/AgentStudioArchitectureLint/.build/`
  - accept explicit paths from `mise run lint`
- Output deterministic diagnostics sorted by path, line, column, rule id.
- Keep fixtures under `Tests/AgentStudioArchitectureLintTests/Fixtures`, exclude
  them from test-source compilation, and load them as fixture files/resources.

### 3. Port Rule Semantics To SwiftSyntax

Port the current rule ids without changing their names or severities. The local
tool is allowed to have different internal type names, but `--print-rules`,
diagnostics, tests, and docs must preserve these externally visible contracts.

- `agentstudio_import_direction`
- `agentstudio_shared_components_are_stateless`
- `agentstudio_atomlib_is_generic`
- `agentstudio_derived_value_declared_inputs`
- `agentstudio_repo_cache_keyed_reads`
- `agentstudio_worktree_enrichment_comparator`
- `agentstudio_state_actor_path`
- `agentstudio_ipc_programmatic_control_boundary`
- `agentstudio_appipc_port_boundary`
- `agentstudio_ipc_composition_location`
- `agentstudio_ipc_public_surface_sanitization`
- `agentstudio_ipc_no_direct_atom_access`
- `agentstudio_no_forbidden_architecture_marker`

Severity inventory:

- warning:
  - `agentstudio_state_actor_path`
- error:
  - all other listed rule ids.

Implementation notes:

- Import direction is path-aware plus import-declaration aware.
- SharedComponents statelessness checks path plus attributes and wrappers.
- AtomLib generic checks path plus imports and product symbol references.
- DerivedValue checks compute closures for direct atom reads and same-file helper
  wrappers that hide atom reads.
- Repo-cache keyed reads checks member accesses and identifier reads in hot
  production paths, with allowlists for persistence, snapshots, tests, and cold
  bridge surfaces.
- Worktree comparator checks raw `WorktreeEnrichment` equality in atom
  comparator contexts.
- State actor path checks new state files and should include an explicit
  grandfathered-exception list for existing legacy paths.
- IPC programmatic-control boundary checks that programmatic-control code stays
  behind the approved IPC/AppIPC contracts instead of leaking into app state
  surfaces.
- AppIPC port boundary checks that `AgentStudioAppIPC` owns contract/port
  vocabulary and product code does not reach around that boundary.
- IPC composition location checks that composition/root wiring happens in the
  approved app/composition surface, not scattered through feature or core files.
- IPC public-surface sanitization checks that exported/public IPC values are
  scrubbed contract types, not raw atom, prompt, path, or product-internal
  state.
- IPC no-direct-atom-access checks that IPC layers do not read or mutate atoms
  directly; they must go through the approved programmatic-control service
  surface.
- Forbidden architecture marker catches intentionally bad fixture markers and
  prevents test-only architecture escapes from landing in production paths.

Before implementing each rule, read the corresponding old rule source, fixture
contents, and commit hunks from the listed commits. Create a local translated
fixture or a written non-port rationale for each semantic case. Do not count
same-named fixtures as parity unless their behavior and path topology are
preserved. Do not mechanically copy Bazel, npm, package-lock, or SwiftLint build
logic.

### 4. Add Tool Fixtures And Tests

- Move or copy the relevant good/bad fixture semantics into the tool package.
  Do not depend on the old ai-tools checkout at test time.
- Preserve upstream fixture path topology under
  `Fixtures/{Good,Bad}/Sources/...` because several rules are path-aware. If a
  fixture cannot preserve topology, the test must inject a virtual source path
  matching the old semantic path.
- Add rule-level tests:
  - each rule has at least one good fixture and one bad fixture, or a written
    non-port rationale approved in this plan.
  - bad fixtures assert rule id and line/column where practical.
  - allowlist fixtures prove cold dictionary reads remain allowed.
- Add a command integration test:
  - run the built tool against `Fixtures/Good`: exit 0.
  - run it against `Fixtures/Bad`: non-zero with expected rule ids.
- Add a rule inventory test:
  - `--print-rules` returns exactly the required 13 ids and severities unless
    the plan is updated and reviewed.
  - fixture coverage includes translated equivalents for IPC fixtures from
    `1bc0e474c48cf01c815f83e16abd65be6d27f51b`.
- Add aggregate bad-corpus verification:
  - all 12 non-marker rule ids appear in bad fixture diagnostics.
  - `agentstudio_no_forbidden_architecture_marker` has a dedicated fixture/test
    using `AGENTSTUDIO_FORBIDDEN_ARCHITECTURE_MARKER`.

### 5. Rewire AgentStudio Lint

- Replace `.mise.toml` lint task:
  - keep `swift-format lint`, expanded to cover `Sources/`, `Tests/`,
    `Tools/AgentStudioArchitectureLint/Sources`, and
    `Tools/AgentStudioArchitectureLint/Tests`.
  - run stock `swiftlint lint --strict`
  - run `swift run --package-path Tools/AgentStudioArchitectureLint agentstudio-architecture-lint Sources Tests`
  - keep release script verification
- Update `.swiftlint.yml` so stock SwiftLint covers the tool implementation
  sources/tests. Exclude only fixture directories if needed and document the
  exclusion.
- Delete:
  - `scripts/run-agentstudio-architecture-swiftlint.sh`
  - `scripts/agentstudio-architecture-swiftlint.env`
- Update CI:
  - remove `bazelisk` from `brew install`.
  - install only `swift-format` plus whatever is already required for stock
    `swiftlint`.
  - If stock SwiftLint remains Homebrew-managed, install `swiftlint` explicitly
    and do not build custom SwiftLint.
  - run `swift test --package-path Tools/AgentStudioArchitectureLint` as an
    explicit CI step, not only through repo test discovery.

### 6. Replace AgentStudio Script Tests

- Replace `ArchitectureSwiftLintRulesTests` expectations that mention ai-tools,
  Bazelisk, pinned commits, or custom SwiftLint binaries.
- Keep the suite name `ArchitectureSwiftLintRulesTests` for this migration, or
  update every validation command in this plan in the same patch that renames
  it.
- Add AgentStudio-side tests that prove:
  - `.mise.toml` invokes stock SwiftLint and local architecture linter.
  - CI does not install Bazelisk.
  - deleted runner/env files are not referenced.
  - `Tools/AgentStudioArchitectureLint/Package.resolved` exists.
  - the `no_combine_import` regex custom rule still works through stock
    SwiftLint.
  - the local architecture tool can run a small temp fixture or exposes
    `--print-rules`.

### 7. Update Docs

- Update `AGENTS.md` architecture lint section:
  - source lives in AgentStudio `Tools/AgentStudioArchitectureLint`.
  - ai-tools is not an AgentStudio architecture-lint owner.
  - no Bazel/Bazelisk/Java in lint path.
- Update `docs/architecture/architecture_lint_inventory.md`:
  - replace ai-tools verifier with local SwiftPM tool tests.
  - retain same rule ids and severities.
  - map every rule id to a repo-local architecture contract. IPC rules must map
    to a repo-local IPC/programmatic-control architecture document, not only to
    branch-era fixtures.
- Update `docs/guides/agent_resources.md`:
  - remove Bazelisk as a prerequisite.
  - describe stock SwiftLint plus local SwiftPM architecture tool.
- Update the high-level build/test and architecture sections in `AGENTS.md`; the
  top summary and the architecture section must agree about stock SwiftLint plus
  the local SwiftPM tool.
- Update the superseded 2026-06-14 plan:
  - mark it superseded by this plan.
  - leave the historical evidence but clearly state the ai-tools/Bazel direction
    is rejected.

### 8. Validate Locally

Run in order:

```bash
git diff --check
swift package resolve --package-path Tools/AgentStudioArchitectureLint
swift test --package-path Tools/AgentStudioArchitectureLint
swift run --package-path Tools/AgentStudioArchitectureLint agentstudio-architecture-lint --print-rules
swift run --package-path Tools/AgentStudioArchitectureLint agentstudio-architecture-lint Sources Tests
swiftlint lint --strict
SWIFT_TEST_TIMEOUT_SECONDS=120 /bin/bash scripts/run-swift-test-task.sh test-fast --filter ArchitectureSwiftLintRulesTests
mise run lint
mise run test
```

If `mise run test` exposes unrelated failures, stop and report changed-surface
proof separately before editing unrelated layers.

### 9. PR, CI, And Review

- Push branch and open/update PR.
- Required PR gates:
  - CI lint/test success on the PR head.
  - CI logs show no Bazel/Bazelisk install.
  - CI logs show the tool package tests ran with
    `swift test --package-path Tools/AgentStudioArchitectureLint`.
  - review comments addressed and threads resolved.
- Do not merge while any ai-tools/Bazel lint reference remains in AgentStudio
  executable/test/active-doc surfaces, except observability references that are
  explicitly classified as the approved `~/dev/ai-tools/observability` stack and
  historical `docs/plans/**` references marked superseded/rejected.

### 10. Post-Merge Cleanup Handoff

After AgentStudio main no longer depends on ai-tools for architecture lint:

- User deletes the ai-tools branch
  `agentstudio-swiftlint-architecture-rules-2026-06-14`.
- Optional machine cleanup after explicit approval:
  - remove `/private/var/tmp/_bazel_shravansunder`
  - remove local generated Bazel symlinks and `node_modules` under the temporary
    ai-tools branch checkout
- Verify no active Bazel/Java processes before deleting cache directories.

## Write Surfaces

Expected AgentStudio writes:

- `Tools/AgentStudioArchitectureLint/**`
- `Tools/AgentStudioArchitectureLint/Package.resolved`
- `.mise.toml`
- `.github/workflows/ci.yml`
- `Tests/AgentStudioTests/Scripts/ArchitectureSwiftLintRulesTests.swift`
- `docs/architecture/architecture_lint_inventory.md`
- `docs/architecture/agentstudio_ipc_architecture.md` or the agreed repo-local
  IPC/programmatic-control architecture document that owns IPC rule contracts.
- `docs/architecture/directory_structure.md`
- `docs/architecture/atom_persistence_boundaries.md`
- `docs/guides/agent_resources.md`
- `AGENTS.md`
- `docs/plans/2026-06-14-swiftlint-swiftsyntax-architecture-rules.md`

Expected AgentStudio deletes:

- `scripts/run-agentstudio-architecture-swiftlint.sh`
- `scripts/agentstudio-architecture-swiftlint.env`

Explicitly not touched:

- `~/dev/ai-tools/**`
- `/private/var/tmp/_bazel_shravansunder`
- Homebrew packages or system Java/Bazel state

## Security And Supply-Chain Notes

- Removing ai-tools from this lint path removes a cross-repo supply-chain edge.
- Removing Bazel/Bazelisk removes network-heavy tool bootstrap from lint.
- Stock SwiftLint remains a developer dependency; keep version expectation in
  docs/CI. If stricter reproducibility is needed later, plan a SwiftLint binary
  pin separately.
- The local SwiftPM tool should not read secrets, execute subprocesses, or make
  network calls.
- The local tool must not shell out to `rg`, `grep`, Bazel, npm, or ai-tools.

## Risks

- SwiftSyntax API versioning must match the active Swift toolchain. Pin the
  dependency and expect occasional maintenance during Swift upgrades.
- The local tool is not SwiftLint-native, so IDE SwiftLint integrations will not
  show these structural diagnostics automatically unless wired separately.
- Re-implementing the old native-rule behavior may reveal false positives; keep
  fixtures and allowlists explicit.
- `swift run` may be slower on a cold cache than shell checks. Use SwiftPM build
  caching and keep the package isolated so the app package stays clean.

## Rollback

If the local SwiftPM architecture tool cannot be made stable inside this scope:

1. Stop before merging.
2. Leave the current ai-tools-backed path untouched on `main` or on the
   pre-migration branch until a smaller local-tool slice is proven.
3. Do not restore shell/`rg` architecture scanners and do not restore
   ai-tools/Bazel after a removal has merged.
4. Split the replacement into smaller rule groups and prove them incrementally.

## Open Questions

1. Should the local architecture linter use `swift-argument-parser`, or should
   v1 keep hand-written argument parsing to minimize dependency surface?
2. Should CI install Homebrew `swiftlint`, or should a separate follow-up pin
   stock SwiftLint through the SwiftLintPlugins binary package?
3. Should the linter output GitHub Actions annotations in v1, or is
   `path:line:column: error: [rule] message` sufficient for this correction PR?

## Recommended Next Workflow

Run `plan-review-swarm` on this plan before implementation. The highest-risk
review question is whether the repo-local SwiftPM tool can preserve enough
architecture-rule parity without drifting into a second bespoke scanner that is
hard to maintain.
