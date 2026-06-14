# SwiftLint + SwiftSyntax Architecture Rules Plan

Date: 2026-06-14
Status: Implemented locally; pending implementation review and PR/CI wrap-up
Goal thread: `019eb7f0-27b9-7780-abf8-5f49320f8863`

## Objective

Move AgentStudio's implicit architecture rules into the SwiftLint rule surface,
using SwiftSyntax-backed native SwiftLint rules where structure matters, and
remove bespoke shell/ripgrep architecture scripts as the long-term lint gate.

Implementation must not begin until this plan is reviewed and approved.
Approval was given in chat on 2026-06-14.

## Current Evidence

Source coverage:

- `.mise.toml`: 477 lines inspected; lint wiring lines 101-114 currently runs
  `swiftlint lint --strict`, `check-core-boundary-imports.sh`, and
  `check-atomlib-boundaries.sh`.
- `.swiftlint.yml`: 213 lines inspected; existing regex custom rules lines
  87-130 already enforce several architecture/concurrency bans.
- `.github/workflows/ci.yml`: lint job currently installs Homebrew
  `swift-format swiftlint ripgrep`, then runs `mise run lint`; test jobs run
  `mise run test-fast`, `mise run test-webkit`, and `mise run test-benchmark`.
  The final design must update CI to install or build the same pinned SwiftLint
  distribution used locally and must remove `ripgrep` as an architecture-lint
  dependency when the scripts are deleted.
- `scripts/check-core-boundary-imports.sh`: all 26 lines inspected; line 18 is
  the only boundary scan, lines 20-23 fail Core-to-Features imports.
- `scripts/check-atomlib-boundaries.sh`: all 220 lines inspected; lines 91-123
  encode DerivedValue, wrapper, equality, and dictionary-read checks; lines
  140-165 encode repo-wide dictionary allowlisting and report inventory.
- `Tests/AgentStudioTests/Scripts/AtomLibBoundaryScriptTests.swift`: all 228
  lines inspected; tests assert the shell script and fixture behavior.
- `Package.swift`: all 99 lines inspected; no SwiftSyntax or SwiftLint tooling
  target exists in the package.
- Local tool check: Swift is `6.2.4`, Homebrew SwiftLint is `0.63.3`, and
  `bazel` is not installed on this machine. Native SwiftLint custom rules cannot
  assume the current developer shell already has the upstream custom-build
  toolchain.
- `AGENTS.md`: architecture sections inspected, especially AtomRegistry,
  AtomLib, SharedComponents, and import ownership.
- `docs/architecture/directory_structure.md`: 440 lines inspected; lines 108-120
  define import direction; lines 195-217 define SharedComponents constraints.
- `docs/architecture/atom_persistence_boundaries.md`: 185 lines inspected; lines
  60-108 define AtomLib primitives, atom families, and actor placement.
- Initial implementation artifacts:
  - `tmp/plan-workflows/2026-06-14-agent-studio-performance-issues-atomlib-v2-followup-hot-reader-exceptions-swiftlint-swiftsyntax-architecture-rules/implementation-execute-plan-brief.md`
  - `tmp/spec-workflows/2026-06-14-swiftlint-swiftsyntax-architecture-rules/baseline.md`
  - `tmp/spec-workflows/2026-06-14-swiftlint-swiftsyntax-architecture-rules/architecture-rule-inventory.md`
- SwiftLint checkout under `tmp/research-workflows/.../opensource/SwiftLint`:
  README custom-rule section, package products/dependencies, regex custom-rule
  implementation, native SwiftSyntax rule protocol, registry, and extra-rule
  extension point inspected.
- swift-syntax checkout under `tmp/research-workflows/.../opensource/swift-syntax`:
  README and Package products inspected for source-accurate tree and package
  surfaces.
- Implemented custom SwiftLint rule package in `~/dev/ai-tools` on branch
  `agentstudio-swiftlint-architecture-rules-2026-06-14`, pinned here to commit
  `280eb2a1925ff3f89d6e67f2a728129f7247f723`.
- AgentStudio now runs the pinned custom SwiftLint through
  `scripts/run-agentstudio-architecture-swiftlint.sh`; old shell architecture
  scripts and their shell-script tests are removed.
- Local gates on 2026-06-14:
  - `git diff --check`: pass, exit 0.
  - `scripts/run-agentstudio-architecture-swiftlint.sh --print-tool-identity`:
    pass, shows repo URL, fetch ref, pinned commit, and subdir.
  - `AGENTSTUDIO_AI_TOOLS_ROOT=/nonexistent scripts/run-agentstudio-architecture-swiftlint.sh --verify-fixtures`:
    pass, forced a fresh cache clone of the pinned ai-tools commit, installed
    package-local Bazelisk from the checked-in npm lockfile, built SwiftLint,
    and verified native-rule fixtures.
  - pinned SwiftLint `rules --config .swiftlint.yml | grep agentstudio`: pass,
    shows 8 `agentstudio_*` rules enabled in config.
  - `PROJECT_ROOT=... SWIFT_TEST_TIMEOUT_SECONDS=300 /bin/bash scripts/run-swift-test-task.sh test-fast --filter ArchitectureSwiftLintRulesTests`:
    pass, 4 tests in 1 suite, 0 failures.
  - `mise run lint`: pass, SwiftLint 0 violations / 0 serious in 1131 Swift
    files; release script verification passed.
  - `mise run test`: pass, standard unit/integration/WebKit serialized gates;
    E2E and Zmx E2E opt-in suites skipped by repo defaults
    (`SWIFT_TEST_INCLUDE_E2E=0`, `SWIFT_TEST_INCLUDE_ZMX_E2E=0`).

## Requirements

1. Architecture policy is discoverable as SwiftLint rule identifiers, messages,
   and tests.
2. Shell/ripgrep architecture scripts are removed from the final `mise run lint`
   gate.
3. Existing behavior from both architecture scripts is preserved or deliberately
   reclassified with an explicit reason.
4. AtomLib rules become syntax-aware:
   - DerivedValue compute paths cannot read undeclared atoms.
   - wrapper helpers cannot hide undeclared/global atom inputs.
   - raw `WorktreeEnrichment` equality cannot be an atom comparator.
   - raw repo-cache dictionaries are banned from hot production reads except
     named snapshot/persistence/cold bridge allowlists.
5. Import and directory ownership rules are covered:
   - Core cannot import Features or App.
   - Features cannot import sibling Features.
   - SharedComponents cannot import Core, Features, or App and cannot subscribe
     to atoms.
   - Infrastructure/AtomLib stays generic.
6. Existing stock SwiftLint regex rules remain active.
7. CI/local validation proves the new rules and the repo's clean state.
8. The implicit architecture-rule inventory covers both existing lint scripts
   and the architecture contracts in `AGENTS.md` plus `docs/architecture/*`.
   Every rule is classified as blocking lint, report-only lint, automated test,
   or review-only guidance with a reason.

## Non-Goals

- Do not rewrite AtomLib behavior in this plan.
- Do not refactor product modules except to fix violations found by the new
  lint rules.
- Do not add a second non-SwiftLint architecture scanner as the final gate.
- Do not move observability stack ownership; this plan is lint/tooling only.

## Tool Ownership Decision

Default decision: the custom SwiftLint distribution belongs in shared tooling
under `~/dev/ai-tools`, not inside the AgentStudio app package.

Rationale:

- `~/dev/ai-tools` is the public personal tooling repo and already owns shared
  developer infrastructure such as the local observability stack.
- AgentStudio should remain an observability/lint consumer, not the conceptual
  owner of generic developer tooling.
- The architecture rules are AgentStudio-specific, but the build/distribution
  mechanism for a custom SwiftLint binary is developer tooling.
- Keeping the distribution outside the app package prevents accidental linkage
  into product targets and keeps `Package.swift` focused on app/test code.

Proposed shared-tooling shape:

```text
~/dev/ai-tools/
  swiftlint/
    agentstudio-architecture-rules/
      MODULE.bazel
      BUILD.bazel
      Sources/
        AgentStudioArchitectureRules/*.swift
      scripts/
        build-agentstudio-swiftlint.sh
        install-agentstudio-swiftlint.sh
      README.md
```

AgentStudio consumer shape:

- Pin the exact ai-tools commit or released artifact identity in a versioned
  config file, not in chat or a mutable local path.
- Add a thin `mise` task or script only to obtain/run the pinned binary. That
  bootstrap must contain no architecture-rule semantics.
- Keep `.swiftlint.yml` as the project rule-selection/config surface.
- CI must obtain the same pinned binary/source and prove the same identity in
  logs before running `mise run lint`.

Fallback if shared tooling proves infeasible:

- Re-plan before implementation continues.
- A repo-local `Tools/` implementation is allowed only after documenting why
  shared tooling cannot support the custom SwiftLint build.
- Homebrew SwiftLint may remain only for stock/regex rules; it must not be
  claimed to run native AgentStudio rules.

The implementation must not silently use the Homebrew `swiftlint` binary for
native AgentStudio rules. Homebrew SwiftLint can continue to be the fallback
only for stock/regex rules if the custom distribution spike fails and the plan
is revised.

## Security And Reliability Context

The custom lint binary becomes part of the CI trust boundary. Treat it as a
developer-tool supply-chain dependency:

- Pin exact source/artifact identity and record it in the repo.
- Prefer source builds or checksum-verified artifacts over mutable local paths.
- Ensure lint does not require network access after dependency/tool bootstrap.
- Do not export repo paths, source snippets beyond normal lint diagnostics, or
  secrets to external services.
- Keep rule allowlists in versioned config or rule fixtures, not in ad hoc shell
  grep filters.
- If the tool binary cannot be reproduced locally and in CI, stop before
  deleting the shell gates.

## Implementation Tasks

### 1. Baseline And Parity Map

- Run the current gate once:
  - `mise run lint`
  - `SWIFT_TEST_TIMEOUT_SECONDS=120 /bin/bash scripts/run-swift-test-task.sh test-fast --filter AtomLibBoundaryScriptTests`
- Capture current violations/pass state in `tmp/spec-workflows/.../baseline.md`.
- Convert every shell-script check and every relevant architecture-doc contract
  into a named inventory row with:
  - rule identifier
  - old detection source
  - new SwiftLint rule lane
  - fixtures/examples
  - allowlist source
  - expected severity
  - status: blocking lint, report-only lint, automated test, or review-only
    guidance
  - rationale for any non-blocking classification

### 2. Prove Native SwiftLint Distribution

Make this the first implementation spike. Stop and re-plan if it fails.

Preferred outcome:

- On a clean branch in `~/dev/ai-tools`, build an AgentStudio-pinned SwiftLint
  binary that registers native AgentStudio rules through SwiftLint's native rule
  registry/extra-rules path.
- The binary still runs normal SwiftLint stock rules and `.swiftlint.yml`.
- `swiftlint rules` or equivalent output shows at least one
  `agentstudio_*` native rule.
- A tiny negative fixture fails through SwiftLint's normal reporter, not through
  a sidecar script.
- CI can obtain the same binary/source using the pinned identity, without
  relying on a mutable local `~/dev/ai-tools` checkout.
- If Bazel is required, add the Bazel/Bazelisk bootstrap and version pin to
  `ai-tools`; this is likely because SwiftLint's Bzlmod `extra_rules` extension
  wires custom Swift sources into `SwiftLintExtraRules`.
- If a SwiftPM-compatible native-rule build is proven instead, document the
  exact registration mechanism and why it is equivalent to SwiftLint native
  rules.
- Do not modify AgentStudio lint wiring until this spike proves the binary can
  register a trivial `agentstudio_*` rule and run against a fixture.

Research-backed constraints:

- Stock YAML custom rules are regex rules.
- SwiftLint's documented Swift custom rules require a custom build path.
- SwiftLint's `SwiftLintExtraRules.extraRules()` is the native custom-rule
  extension point for custom builds.

If the preferred outcome is blocked, choose explicitly between:

- A maintained custom SwiftLint fork/build under shared tooling, pinned by this
  repo.
- A stock-SwiftLint regex-only fallback, accepting that some requested rules
  cannot honestly be native SwiftSyntax rules.

Do not silently substitute a repo-local SwiftSyntax executable and call it
SwiftLint.

### 3. Implement Core Native Rule Suite

In `~/dev/ai-tools` shared tooling, add native SwiftSyntax SwiftLint rules with
examples/tests:

- `agentstudio_import_direction`
- `agentstudio_shared_components_are_stateless`
- `agentstudio_atomlib_is_generic`
- `agentstudio_derived_value_declared_inputs`
- `agentstudio_repo_cache_keyed_reads`
- `agentstudio_worktree_enrichment_comparator`
- `agentstudio_state_actor_path`

Rule tests must include:

- Non-triggering examples from current allowed production patterns.
- Triggering examples copied from the current negative fixtures and synthesized
  alias/wrapper cases.
- Path-aware fixtures for Core, Features, SharedComponents, and
  Infrastructure/AtomLib.
- Allowlist tests for snapshot/persistence/cold bridge dictionary reads.

### 4. Migrate Existing Regex Rules Deliberately

- Keep existing `.swiftlint.yml` custom rules active.
- Add `default_execution_mode: swiftsyntax` for `custom_rules` if supported by
  the installed SwiftLint version used by the chosen distribution.
- Promote warnings to errors only where the existing repo is clean or fixes are
  in scope; otherwise leave warnings with follow-up tickets.
- Add or tighten regex rules only for lexical cases that do not need AST
  structure.

### 5. Replace Script Tests With Rule Tests

- In AgentStudio, replace `AtomLibBoundaryScriptTests` with tests that prove the
  pinned SwiftLint rule suite and fixtures.
- Move reusable negative fixtures out of "script behavior" language and into
  rule-specific fixture names.
- Keep a focused integration test that invokes the pinned SwiftLint binary on a
  temporary fixture and proves violations are reported through SwiftLint.
- Use the repo's real test harness for focused test proof:
  `SWIFT_TEST_TIMEOUT_SECONDS=120 /bin/bash scripts/run-swift-test-task.sh test-fast --filter <RuleOrIntegrationTestName>`.

### 6. Rewire Lint

- Update `.mise.toml` so `mise run lint` runs:
  - `swift-format lint --recursive Sources/ Tests/`
  - the AgentStudio-pinned ai-tools SwiftLint binary with `lint --strict`
  - `/bin/bash scripts/verify-release-scripts.sh`
- Remove `bash scripts/check-core-boundary-imports.sh` and
  `bash scripts/check-atomlib-boundaries.sh` from the final lint path.
- Delete the bespoke architecture scripts once native-rule parity is proven and
  no other task depends on them.
- Update `.github/workflows/ci.yml` so the lint job installs/builds the pinned
  ai-tools SwiftLint distribution instead of assuming Homebrew SwiftLint can see
  AgentStudio native rules. Remove `ripgrep` from CI lint dependencies unless
  another non-architecture task still requires it.

### 7. Fix Violations And Update Docs

- Run the new rules on the repo.
- Fix any violations in the agreed scope.
- Update:
  - `AGENTS.md` lint/tooling guidance.
  - `docs/architecture/directory_structure.md` with rule identifiers for import
    and SharedComponents boundaries.
  - `docs/architecture/atom_persistence_boundaries.md` with rule identifiers
    for AtomLib/DerivedValue/repo-cache boundaries.
  - A small architecture lint index if the rule list becomes too large for the
    existing docs.
- Add a rule inventory document, or a dedicated section in the architecture
  docs, listing each implicit architecture rule and its enforcement status.

### 8. Validate And Prepare PR

Required local gates:

- `git diff --check`
- `mise run lint`
- `swiftlint version` or pinned-tool equivalent showing the AgentStudio
  distribution identity
- `swiftlint rules` or pinned-tool equivalent showing `agentstudio_*` rules
- focused native rule tests
- focused old-parity fixture tests
- `mise run test`

Required PR gates after push:

- CI lint
- CI test
- review-thread resolution

## Proof Matrix

| Requirement | Proof |
| --- | --- |
| SwiftLint owns architecture policy | `mise run lint` output shows SwiftLint native/regex rules and no architecture shell script calls |
| Script behavior preserved | Parity fixture tests for every old shell-script rule |
| Native SwiftSyntax rules active | Rule registry or `swiftlint rules` includes `agentstudio_*`; negative fixture fails through SwiftLint |
| Custom tool is reproducible | Local and CI logs show the same pinned SwiftLint distribution identity/checksum |
| Implicit architecture inventory complete | Inventory maps existing scripts plus `AGENTS.md`/architecture docs to blocking/report-only/test/review status |
| Import boundaries enforced | Triggering/non-triggering path-aware fixtures for Core, Features, SharedComponents, Infrastructure |
| AtomLib hot-read rules enforced | DerivedValue, wrapper, repo-cache dictionary, and comparator fixtures |
| Repo clean under new rules | `mise run lint` passes |
| Product tests still pass | `mise run test` passes |
| CI agrees | GitHub required checks green before merge |

## Risks

- Custom SwiftLint distribution maintenance is real. The implementation must
  pin the tool version and document upgrade steps.
- SwiftLint and swift-syntax release alignment can break builds on upgrade.
- The developer machine currently has Homebrew SwiftLint `0.63.3` but no Bazel;
  the implementation cannot assume native custom-rule builds work without a
  pinned tool bootstrap.
- Path-aware rules can false-positive if the repo has generated or legacy
  exceptions; exceptions must be named and tested.
- Replacing scripts before parity is proven could reduce protection. Keep the
  old scripts only as temporary comparison or rollback until the new gate passes.
- Full `mise run test` can expose unrelated failures. If that happens, report
  changed-surface proof separately and stop before editing unrelated layers.

## Rollback

If the custom SwiftLint distribution cannot be made stable:

1. Restore `.mise.toml` to stock SwiftLint plus current architecture scripts.
2. Keep any safe `.swiftlint.yml` regex improvements.
3. Preserve the design/research artifact and open a follow-up decision on
   custom SwiftLint ownership.
4. Do not delete `scripts/check-core-boundary-imports.sh` or
   `scripts/check-atomlib-boundaries.sh` until a replacement gate is proven.

If native rules work but a specific rule is noisy:

1. Disable only that rule in `.swiftlint.yml` with a dated TODO and linked plan.
2. Keep clean native rules active.
3. Add a fixture proving the noisy case before re-enabling.

## Recommended Next Step

Run `implementation-review-swarm` on the implemented diff, then push PR updates
and verify GitHub CI before merge. The highest-risk review question remains the
custom SwiftLint distribution path and CI fetch/build reliability.
