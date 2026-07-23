# AgentStudio Primary-Worktree Vendor Reuse

Date: 2026-07-23
Status: ready for review
Scope: local Ghostty and zmx preparation across AgentStudio worktrees

Related contracts:

- [Swift build-slot containment](../2026-07-22-swift-build-slot-containment/2026-07-22-swift-build-slot-containment.md)
- [Debug app artifact containment](../2026-07-22-debug-app-artifact-retention/2026-07-22-debug-app-artifact-retention.md)

## Decision

Keep Ghostty and zmx in the AgentStudio repository as the existing pinned
submodules. The primary worktree for one Git common directory hydrates and
builds them once. Linked worktrees reuse the primary worktree's prepared
outputs.

One explicit escape hatch supports vendor development in an isolated linked
worktree:

```bash
mise run setup --use-local-vendors
```

That flag hydrates and builds the vendors inside the current worktree instead
of projecting primary outputs. It is an explicit mode, never an automatic
fallback for missing or incompatible primary outputs.

In local-vendor mode, `setup` runs the existing recursive submodule
initialization for the current worktree before building Ghostty, zmx, the
XCFramework, and generated resources.

`mise run setup` remains the single setup entry point in every mode. The flag
changes only where vendor source and prepared outputs come from; BridgeWeb,
hooks, build/test/bundle paths, resources, signing, and runtime behavior keep
the same setup and consumption contracts.

Repository instructions and diagnostics must never direct a developer or agent
to run `git submodule update`, `mise run init-submodules`, or another vendor
hydration command directly. Submodule initialization is an internal operation
owned by `mise run setup`. GitHub Actions recursive checkout remains an
independent workflow implementation detail, not a local setup instruction.

Agent instructions default to plain `mise run setup`. An agent may add
`--use-local-vendors` only when the user explicitly requests local vendor work
or the accepted task requires changing Ghostty or zmx. A missing primary,
revision mismatch, absent output, or ordinary setup/build failure does not
authorize the escape hatch.

The local sharing contract has only four projected assets:

| Linked-worktree path | Local representation | Source in primary worktree |
| --- | --- | --- |
| `Frameworks/GhosttyKit.xcframework` | symlink | same path |
| `vendor/zmx/zig-out` | symlink | same path |
| `Sources/AgentStudio/Resources/ghostty` | regular local copy | same path |
| `Sources/AgentStudio/Resources/terminfo/67/ghostty` | regular local copy | same path |

The two large build outputs are symlinked. The tiny resources are copied so a
built SwiftPM resource bundle and packaged app remain self-contained instead
of retaining a filesystem dependency on the primary worktree.

There is no separate vendor repository, remote artifact distribution, SwiftPM
package or plugin, artifact store, version directory, receipt, daemon, lock
service, or garbage collector.

GitHub CI, benchmarks, and release remain independent producers. Their
recursive checkout, vendor build, caching, app bundling, signing, notarization,
and publication behavior do not depend on a developer's primary worktree.

## Product Intent

AgentStudio developers and workers create many linked worktrees while Ghostty
and zmx revisions change rarely. A linked worktree must not spend gigabytes of
disk or setup time hydrating and rebuilding the same vendors when its pinned
vendor revisions match the prepared primary worktree.

Success means:

- the primary worktree remains the default shared place that hydrates and
  builds Ghostty and zmx;
- a compatible linked worktree can run `mise run setup` without hydrating
  either submodule or invoking Zig;
- a vendor-development worktree can explicitly run
  `mise run setup --use-local-vendors` to hydrate, edit, and build its own
  vendor checkouts without mutating primary outputs;
- switching to a linked branch with different vendor pins fails clearly before
  a supported build, test, or bundle task consumes the old projections;
- existing SwiftPM paths, app resource paths, zmx packaging, signing, runtime
  isolation, and `AGENTSTUDIO_ZMX_PATH` behavior remain unchanged;
- CI and release remain reproducible without local shared state.

## Current-State Evidence

At AgentStudio commit `756b87d0f18aadd859ad052e2b49328f1c3b099d`:

- the primary and current linked worktree use the same Git common directory;
- both superprojects pin Ghostty at
  `332b2aefc6e72d363aa93ab6ecfc86eeeeb5ed28`;
- both superprojects pin zmx at
  `0d787cfc113b13eac9be313cf5b75917806e5f18`;
- the primary's checked-out submodule HEADs match those pins;
- the primary has a prepared 571 MB `GhosttyKit.xcframework`;
- the primary has a prepared 1.8 MB `vendor/zmx/zig-out`;
- the generated Ghostty resources are under 100 KB;
- this linked worktree has uninitialized vendor submodules and none of the
  required prepared outputs.

Current ownership is split across:

- `.gitmodules`, which pins both vendor source repositories;
- `.mise.toml`, which hydrates, builds, copies, tests, bundles, and refreshes
  vendor-derived inputs;
- `scripts/build-ghostty-local.sh`, which owns AgentStudio's local Ghostty
  build adaptation;
- `Package.swift`, which expects the XCFramework at the stable local path;
- app and debug bundlers, which copy zmx and resources from the current stable
  local paths;
- `SessionConfiguration` and `ZmxTestHarness`, which use the current zmx path
  contracts.

The repository tracks
`Sources/AgentStudio/Resources/terminfo/78/xterm-256color` and
`Sources/AgentStudio/Resources/terminfo/78/xterm-ghostty`. Those files remain
branch-owned. The complete `terminfo` directory must never be projected from
the primary worktree.

## Roles and Ownership

```text
one AgentStudio Git common directory

  primary worktree
    owns:
      hydrated vendor source checkouts
      Ghostty and zmx producer tasks
      prepared XCFramework, zmx output, and Ghostty resources
      vendor refresh authority

          two large symlinks + two tiny resource copies
                              |
                              v

  linked worktrees
    own:
      branch-specific AgentStudio source and vendor gitlinks
      ignored projection paths
      tracked terminfo/78 resources
      Swift build/test outputs and app/debug runtime state

  linked vendor-development worktree
    selected only by: mise run setup --use-local-vendors
    owns:
      its own hydrated vendor source checkouts
      real local prepared outputs instead of shared symlinks
      its own vendor refresh and build activity

GitHub standalone checkout
  owns its own hydration, build, caches, bundle, signing, and release proof
```

The primary worktree is derived from Git's registered worktree topology for the
current Git common directory. It is not found by sibling-directory naming and
is not selected through a committed machine-specific path.

A standalone clone is its own primary. A registered linked worktree sharing
that clone's common directory is a shared consumer by default.

The `--use-local-vendors` flag turns the current linked worktree into an
explicit vendor-development worktree. No committed setting or external state
store records this mode. Later verification distinguishes it through hydrated
submodules whose HEADs match the current worktree's gitlinks and real local
prepared outputs where shared consumers have symlinks.

Only preparation inputs are shared. The following always remain local to the
app or linked worktree:

- Swift build directories;
- app bundles and signatures;
- zmx data roots, sockets, sessions, and processes;
- debug and beta app identity and data roots;
- logs, traces, test fixtures, and runtime state.

## Compatibility Contract

Before a shared linked worktree creates or consumes projections, all six
revisions must agree:

```text
linked Ghostty gitlink  = primary Ghostty gitlink = primary Ghostty HEAD
linked zmx gitlink      = primary zmx gitlink     = primary zmx HEAD
```

The primary outputs must also exist with the expected types:

- `Frameworks/GhosttyKit.xcframework` is a real directory in the primary;
- `vendor/zmx/zig-out/bin/zmx` is a real executable file in the primary;
- `Sources/AgentStudio/Resources/ghostty` is a real directory in the primary;
- `Sources/AgentStudio/Resources/terminfo/67/ghostty` is a real file in the
  primary.

Linked setup and supported local vendor-consuming tasks fail closed when the
primary is unavailable, any revision differs, an output is missing, or a
projection has the wrong type. They do not initialize submodules, invoke Zig,
search another worktree, use an ambient zmx binary, or mutate the primary to
recover.

The recovery message identifies the mismatch and tells the operator to prepare
the required vendor pins in the primary worktree, then rerun linked setup.
It may also mention `--use-local-vendors` as the deliberate vendor-development
alternative, but it never selects that mode automatically.

A vendor-development worktree instead requires:

```text
local Ghostty gitlink = local hydrated Ghostty HEAD
local zmx gitlink     = local hydrated zmx HEAD
```

Its XCFramework and `vendor/zmx/zig-out` must be real local directories, not
symlinks. Its supported build, test, and bundle tasks consume those local
outputs through the same stable paths.

### Deliberately accepted freshness limit

Revision and type checks do not cryptographically prove that ignored output
bytes were produced from the checked-out revisions. In the first cut,
successful primary `mise run setup` is the trusted local preparation act.
After either vendor pin changes, the primary must run setup again before linked
consumers are supported.

No receipt, digest manifest, or provenance database is added. This is
intentional: the trust boundary is one user's local Git checkout, vendor
updates are rare, and the requested benefit is avoiding repeated worktree
hydration. Add stronger preparation state only if stale output is observed in
practice or the trust boundary expands.

## Projection Contract

One repository-owned helper is the sole local role, validation, and projection
authority. It exposes four narrow operations:

- identify primary, shared-consumer, or local-vendor state;
- authorize a producer task only for the primary or an explicitly entered
  local-vendor setup;
- prepare or verify the linked projection set;
- prepare or verify real local vendor outputs.

The exact helper name and shell interface belong to the implementation plan;
the contract does not require multiple scripts or a service.

Linked preparation:

- preflights Git topology, all six revisions, all source output types, and all
  four destination paths before changing a destination;
- creates exactly the two declared symlinks;
- copies exactly the two declared resource inputs as regular local files;
- is idempotent when projections and copies are already correct;
- treats the two exact ignored resource destinations as setup-owned and may
  replace their stale regular copies after full preflight;
- preserves and fails on an unexpected regular file or directory collision;
- never projects `vendor/ghostty`, `vendor/zmx`, the whole `terminfo`
  directory, or another arbitrary path;
- leaves tracked `terminfo/78` files untouched;
- verifies the complete set after preparation.

Local-vendor preparation:

- is entered only through `mise run setup --use-local-vendors`;
- removes only the two known shared-output symlinks before any local vendor
  build, so zmx cannot build through a symlink into the primary;
- refuses unexpected regular-file or directory collisions before conversion;
- initializes the current worktree's pinned submodules recursively;
- runs the existing Ghostty, zmx, XCFramework, and resource producer recipes
  against the current worktree;
- leaves real local outputs at the same stable consumer paths;
- never mutates, refreshes, or consumes the primary outputs.

After local-vendor preparation succeeds, ordinary supported build/test/bundle
verification recognizes and preserves that local state. A later unflagged
`mise run setup` must not silently delete hydrated vendor source or replace
real local outputs with shared symlinks. Returning such a worktree to shared
mode is outside the first-cut automated contract; the safe default is to keep
the worktree local until its vendor work is finished or the worktree is
discarded.

The helper canonicalizes the primary and linked roots and rejects topology or
paths that escape those roots. A linked worktree treats the primary outputs as
read-only.

Setup ownership does not extend beyond the two declared resource-copy
destinations. A regular file or directory at either large symlink destination,
or any collision outside the closed four-path allowlist, is user-owned and
fails without mutation.

An interrupted preparation may leave an incomplete disposable projection set.
Verification must reject that set, and rerunning setup repairs it. This design
does not add transactional publication machinery.

## Refresh and Concurrency

The primary may hydrate, build, copy, or refresh the shared outputs. A linked
vendor-development worktree may hydrate, build, copy, or refresh only its own
local outputs after explicit local-vendor setup. A shared linked consumer
cannot invoke producer or refresh tasks and fails before mutation.

Primary setup or refresh must not overlap a linked build, test, app-bundle, or
debug-bundle operation that consumes projected outputs. Without locking or
immutable generations, a command that overlaps refresh is invalid and must be
rerun after preparation and compatibility verification complete.

This operational exclusion is accepted because vendor changes are rare. The
design must be revisited if refresh needs to run while workers remain active or
if two active branches need different shared vendor tuples concurrently without
using explicit local-vendor preparation.

## Complete Affected-Surface Inventory

This inventory is normative for the later implementation plan. It classifies
every current instruction, setup producer, and direct consumer found in the
repository. Historical plans, research notes, and archived WIP are not
authoritative setup instructions and are not bulk-rewritten.

### Instructions that change

| Surface | Required change |
| --- | --- |
| `AGENTS.md` build/setup section | Make plain `mise run setup` the agent default. Explain primary producer, shared linked consumer, and explicit `--use-local-vendors` setup. Permit the flag only after a user request or accepted task requiring Ghostty/zmx changes. Make the Zig/Xcode vendor-build hazard apply only to worktrees that actually build vendors. |
| `AGENTS.md` project tree | Keep both submodules documented, while noting that linked worktrees normally leave them uninitialized. |
| `README.md` build and clone sections | Separate first-clone/primary preparation, default linked reuse, and explicit local-vendor setup. A fresh clone proceeds to `mise run setup`; do not give a separate recursive-submodule command. |
| `README.md` project tree and zmx acknowledgment | Stop implying every linked worktree contains hydrated vendor sources; keep vendor ownership accurate. |
| `docs/guides/agent_resources.md` setup section | Replace the claim that fresh clones and linked worktrees bootstrap identically with the three-role model, failure cases, recovery, and explicit local-vendor escape hatch. `mise run setup` is the only documented hydration entry point. |
| `docs/guides/agent_resources.md` generated-artifact table | Distinguish primary-produced outputs from linked projections/copies and correct the current false claim that `mise run build` generates them. |
| `docs/guides/agent_resources.md` Zig guidance | State that vendor build investigation and the Xcode/Zig workaround apply to the primary, standalone CI, and explicit local-vendor worktrees, not shared linked consumers. |
| `docs/architecture/session_lifecycle.md` actionable vendor-source note | Direct source verification to the primary worktree when the current checkout is linked and unhydrated. |
| `docs/debugging/zmx-environment-isolation.md` actionable local zmx commands | Describe the stable linked projection path and primary preparation prerequisite. Historical investigation evidence remains unchanged. |
| `Sources/AgentStudio/Resources/terminfo-src/xterm-256color.src` comments | Replace stale build-script wording with primary-generated versus tracked-resource ownership. |

### Setup and script surfaces that change

| Surface | Required change |
| --- | --- |
| new repository-owned vendor helper | Own three-role discovery, producer authorization, revision/output validation, two symlinks, two resource copies, local-vendor preparation, and clear recovery errors. |
| `.mise.toml` `init-submodules` | Internal setup implementation only, not a documented user/agent command. Producer-authorized only: primary or explicit local-vendor setup. Fail before Git mutation in a shared linked consumer. |
| `.mise.toml` `build-ghostty` | Producer-authorized only; retain the current recipe. |
| `.mise.toml` `build-zmx` | Producer-authorized only; retain the current recipe and optimization mode. |
| `.mise.toml` `copy-xcframework` | Producer-authorized only; retain the current copy and archive-strip behavior. |
| `.mise.toml` `setup-dev-resources` | Producer-authorized only; retain production of the Ghostty resource directory and Ghostty terminfo while preserving tracked `terminfo/78`. |
| `.mise.toml` `setup` | Declare a boolean `usage` flag named `--use-local-vendors`. Without it, primary builds and linked worktrees project. With it, the current worktree hydrates/builds local vendors. Remove vendor producers from static `depends` because dependencies run before flag dispatch; keep BridgeWeb installation and Git-hook setup as per-worktree dependencies. |
| `.mise.toml` `refresh-vendors` | Refresh the current worktree's owned outputs only: shared outputs in the primary or local outputs in a vendor-development worktree. Fail in a shared consumer. |
| `.mise.toml` supported Swift build/test tasks | Run the lightweight vendor verification before Swift compilation. This covers `build`, `build-release`, `test`, `test-fast`, `test-large`, `test-prebuild`, `test-webkit`, `test-coverage`, `test-e2e`, `test-zmx-e2e`, and `test-benchmark` through the smallest shared task/script seam. |
| `.mise.toml` local app/debug bundle entry points | Verify before `create-app-bundle`, `create-beta-app-bundle`, `run-debug-observability`, and the debug/preference/packaged-product tasks that build or bundle AgentStudio. Reuse shared entry points rather than duplicating validation in every script. |
| `scripts/run-debug-observability.sh` | Add the shared vendor preflight after non-consuming identity/idle modes and before either direct Swift build or `--skip-build` packaging. Preserve all bundle, signing, launch, identity, and runtime-isolation behavior. |
| `scripts/verify-global-preferences-startup-performance.sh` | Run the shared vendor preflight before its direct Swift build. |
| `scripts/verify-bridge-headless-manifest.sh` | Run the shared vendor preflight before its direct Swift build/test path. |
| `scripts/doctor-mac.sh` | Become role-aware: primary/local-vendor producers check submodules, Zig, Xcode/SDK/Metal, and compiler environment; shared consumers check primary discovery, revision agreement, outputs, projections, and resource copies without requiring Zig or hydrated submodules. Every recovery message routes through `mise run setup` or its `--use-local-vendors` flag, never direct Git submodule commands. |
| `scripts/build-ghostty-local.sh` | Require producer authorization before temporarily modifying or building the current worktree's Ghostty source; preserve the existing build adaptation and cleanup. |
| `.gitignore` | Add an exact superproject ignore for `vendor/zmx/zig-out`, which is otherwise unignored when the zmx submodule is uninitialized. Keep existing framework and resource ignores. |

Direct raw `swift build`, `swift test`, or internal script invocation that
bypasses the supported mise entry points is not made projection-safe in the
first cut. Repository instructions must use the supported commands.

### Surfaces explicitly unchanged

| Surface | Reason it stays unchanged |
| --- | --- |
| `.gitmodules` and both gitlinks | AgentStudio remains the vendor source and pin owner. |
| `.mise.toml` Zig pin | The primary and standalone CI still build vendors. |
| `Package.swift` | The existing local binary-target path is the reuse seam. |
| `scripts/run-debug-observability.sh` packaging/launch semantics | Apart from the new preflight, it still copies projected or local zmx/resources into a self-contained debug app and isolated runtime root. |
| `scripts/create-local-beta-bundle.sh` internals | Local beta packaging continues to consume the same stable paths. |
| `.mise.toml` app copy/sign logic | zmx is still copied into `Contents/MacOS/zmx` as a regular file and signed there. |
| `SessionConfiguration` | Runtime lookup and `AGENTSTUDIO_ZMX_PATH` semantics do not change. |
| `ZmxTestHarness` | The legacy `vendor/zmx/zig-out/bin/zmx` path remains valid through the projection. |
| `.github/workflows/ci.yml` | CI remains a recursive-checkout producer with its own caches and build. |
| `.github/workflows/benchmarks.yml` | Benchmarks remain an independent producer. |
| `.github/workflows/release.yml` | Release remains an independent producer and retains signing, notarization, and publication behavior. |
| zmx runtime state and debug roots | Sharing a build input must not share runtime state or lifecycle. |
| historical specs, plans, and WIP | They record the context at their time and are not active bootstrap instructions. |

## Requirements

| ID | Requirement |
| --- | --- |
| VR-01 | Git's registered common-directory topology determines primary versus linked role without a committed machine-specific path. |
| VR-02 | Vendor hydration and producer tasks run only in the primary or through explicit `mise run setup --use-local-vendors`; shared consumers fail before mutation. |
| VR-03 | Linked compatibility requires equality among both linked gitlinks, both primary gitlinks, and both primary checked-out submodule HEADs. |
| VR-04 | Linked setup requires all four primary outputs with the declared types before changing linked destinations. |
| VR-05 | Linked setup creates exactly two symlinks and two regular resource copies at the declared stable paths. |
| VR-06 | Projection never replaces an unexpected regular file/directory, escapes either worktree root, or changes tracked `terminfo/78` resources. |
| VR-07 | Supported local build, test, and bundle entry points revalidate compatibility before consumption. |
| VR-08 | A missing, moved, incomplete, or incompatible primary fails closed without automatic local hydration, Zig execution, ambient fallback, or primary mutation. |
| VR-09 | `mise run setup` retains per-worktree BridgeWeb and Git-hook setup while dispatching vendor preparation by role and declared flag. |
| VR-10 | Primary vendor refresh is operationally exclusive with linked vendor consumption; overlapping results are invalid. |
| VR-11 | zmx is copied into app bundles and debug runtime roots as a regular file before the existing signing and execution steps. |
| VR-12 | zmx runtime state, sockets, sessions, app identity, data roots, and `AGENTSTUDIO_ZMX_PATH` remain isolated per existing contracts. |
| VR-13 | CI, benchmark, and release checkouts remain independent vendor producers with no developer-primary dependency. |
| VR-14 | The first cut adds no receipt, remote distribution, multi-version store, daemon, lock, or cleanup lifecycle. |
| VR-15 | `mise run setup --use-local-vendors` replaces only known shared symlinks, hydrates/builds current-worktree vendors, produces real local outputs, and never mutates primary state. |
| VR-16 | Later unflagged setup and supported consumption preserve detected local-vendor state rather than silently deleting vendor source or reverting to shared projections. |
| VR-17 | `mise run setup` is the sole documented local bootstrap and submodule-hydration entry point; agent instructions, README/guides, and diagnostics do not advertise direct Git or low-level mise hydration commands. |
| VR-18 | Agents default to plain `mise run setup` and use `--use-local-vendors` only for an explicit user request or accepted task that requires changing Ghostty/zmx; setup failures and primary incompatibility do not grant that authority. |
| VR-19 | The two exact ignored resource-copy destinations are setup-owned and replaceable; all other regular-file/directory collisions are preserved and fail closed. |
| VR-20 | Every supported direct Swift build/test or app/debug packaging path reaches the shared vendor verifier before consumption, including direct observability callers. |

## Security and Failure Semantics

The trusted authority is the same user's Git-registered primary worktree after
canonical topology, revision, and output checks. Path naming and arbitrary path
overrides are not authority.

The helper validates a closed four-path allowlist. It must reject root escape,
unexpected source types, unexpected destination collisions, and a primary from
another Git common directory. It must not delete or overwrite an unexpected
user-owned destination.

Local-vendor conversion may remove only verified shared-output symlinks whose
canonical targets are the validated primary paths. It must not delete real
local output directories or hydrated vendor source to force a mode transition.

The design does not defend against a malicious same-user actor modifying both
the primary outputs and Git checkout. It introduces no network, credential,
secret, signing-key, or remote artifact trust boundary.

A broken or deleted primary makes linked consumers unavailable. Recovery is to
restore/prepare that primary and rerun linked setup; there is no automatic
fallback.

GitHub Actions checkouts are standalone vendor producers, not participants in
local worktree sharing. The local-sharing verifier recognizes the GitHub
Actions environment and leaves the workflows' existing recursive checkout,
producer, cache, and proof responsibilities unchanged.

## Tradeoffs and Revisit Triggers

What this design gains:

- one hydrated and built vendor tuple instead of one per linked worktree;
- no new repository, package, artifact publication, or CI dependency;
- unchanged build, bundle, runtime, and release paths after projection;
- simple recovery through primary setup and linked setup.

What it pays:

- one mutable vendor tuple per Git common directory;
- linked worktrees depend on the primary path remaining available;
- branches with different vendor pins cannot both consume the primary tuple,
  but an explicitly local-vendor worktree can build its divergent tuple;
- primary refresh cannot safely overlap linked consumption;
- pin/type validation cannot prove prepared-byte provenance;
- a local-vendor worktree pays the full vendor source/build disk cost by
  explicit choice;
- SwiftPM may still copy the XCFramework into each Swift build scratch.

Revisit this boundary only when at least one of these becomes real:

- two active worktrees require different shared vendor pin tuples without
  paying for explicit local-vendor preparation;
- vendor refresh must run while linked workers remain active;
- stale or altered prepared bytes pass the pin/type checks;
- primary relocation or deletion becomes a routine workflow;
- SwiftPM stops accepting the external XCFramework symlink;
- vendor sharing crosses user or machine trust boundaries;
- vendor updates become frequent enough to justify an immutable local store.

## Alternatives

### Separate vendor repository or remote artifacts

Rejected for this need. It moves build ownership and adds publication,
provenance, download, cache, and release maintenance when the actual problem is
local duplication across related worktrees.

### SwiftPM binary target or executable plugin

Rejected. SwiftPM already consumes the XCFramework through a stable local path,
and zmx is an app-packaging input rather than a linked package product. A
package/plugin adds indirection without reducing the local work beyond the two
symlinks.

### Symlink both complete vendor source trees

Rejected. Linked worktrees must not expose mutable producer source as if it
were branch-local state, and they do not need vendor sources to build
AgentStudio from prepared outputs.

### Symlink all four prepared assets

Rejected. A SwiftPM fixture showed that a copied resource-directory symlink can
remain a symlink inside the built resource bundle. Regular local resource
copies keep SwiftPM and app bundles self-contained for negligible disk cost.

### Receipt, checksums, and immutable versions

Deferred. They improve freshness and concurrent-version guarantees but add
state publication, invalidation, and retention contracts. The accepted
first-cut model trusts primary setup and supports one quiescent tuple.

## Explicit Non-Goals

- Changing vendor pins or vendor source ownership.
- Automatically hydrating Ghostty or zmx after shared-primary validation fails.
- Documenting direct `git submodule update` or low-level vendor-producer tasks
  as alternative local setup paths.
- Treating `--use-local-vendors` as a generic recovery switch for missing
  shared outputs, mismatched pins, or unrelated build failures.
- Sharing Zig caches as a new managed service.
- Supporting simultaneous incompatible vendor tuples.
- Making refresh concurrent-safe.
- Making raw commands outside supported mise entry points safe.
- Redesigning zmx discovery, bundling, signing, entitlements, lifecycle, or
  isolation.
- Changing app identity, signing, notarization, or release publication.
- Solving Swift build-slot size or debug-app retention.
- Rewriting historical research, plans, or debugging evidence.

## Proof Expectations

The implementation plan must operationalize:

- Git topology fixtures for standalone primary, registered linked worktree,
  explicit local-vendor worktree, missing primary, foreign common directory,
  and paths containing spaces;
- compatibility fixtures for each gitlink or submodule-HEAD mismatch;
- negative output fixtures for every missing or wrong-type primary asset;
- projection fixtures proving exactly two symlinks, two regular copies,
  idempotent reruns, preserved collisions, and untouched tracked
  `terminfo/78`;
- replacement fixtures proving stale copies at the two exact setup-owned
  resource destinations are replaceable while all other collisions survive
  unchanged;
- a clean linked-worktree status after setup, including the explicit
  `vendor/zmx/zig-out` ignore;
- negative proof that linked setup and direct producer/refresh task invocation
  do not initialize submodules, invoke Zig, or mutate the primary;
- local-vendor proof that the declared setup flag removes only verified shared
  symlinks, hydrates the current worktree, creates real local outputs, and
  leaves primary output identities and bytes unchanged;
- preservation proof that later unflagged setup does not destroy or silently
  replace detected local-vendor state;
- representative linked Swift compile/test proof through the projected
  XCFramework;
- resource-bundle and packaged-app inspection proving copied resources are
  regular self-contained content;
- app/debug bundle inspection proving projected zmx becomes a regular copied
  and signed helper and the debug runtime still uses its isolated copy;
- static workflow proof that CI, benchmarks, and release remain independent
  recursive-checkout producers;
- direct-consumer wiring proof that debug observability, global-preferences
  startup performance, and Bridge headless-manifest builds verify vendor inputs
  before direct Swift or packaging consumption;
- instruction coverage proving every active bootstrap command explains the
  primary/shared/local-vendor distinction and routes all local hydration and
  recovery through `mise run setup`;
- repository-wide instruction proof that no active agent guide, README,
  developer guide, or diagnostic output advertises direct Git submodule
  initialization or `mise run init-submodules`;
- agent-instruction proof that plain `mise run setup` is the default and the
  local-vendor flag is limited to explicitly authorized Ghostty/zmx work.

## Open Decisions

No product decision blocks adversarial spec review. The setup flag is
`--use-local-vendors`; exact helper naming and the smallest shared mise
validation seam belong to implementation planning.
