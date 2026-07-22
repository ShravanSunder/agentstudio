# AgentStudio Terminal Runtime Distribution

Date: 2026-07-22
Status: ready for review
Scope: dependency production and distribution; no implementation sequencing

Related contracts:

- [Swift build-slot containment](../2026-07-22-swift-build-slot-containment/2026-07-22-swift-build-slot-containment.md)
- [Debug app artifact containment](../2026-07-22-debug-app-artifact-retention/2026-07-22-debug-app-artifact-retention.md)

## Decision

Create one versioned repository, `ShravanSunder/agentstudio-vendors`,
that owns the source revisions, build recipe, toolchain, compatibility testing,
and release artifacts for GhosttyKit and zmx.

Each terminal-runtime release binds four independently packaged outputs into one
tested version:

1. `GhosttyKit.xcframework.zip`, consumed as a SwiftPM binary library;
2. `zmx.artifactbundle.zip`, exposed to AgentStudio packaging through a SwiftPM
   command plugin that returns the resolved executable path;
3. `ghostty-resources.tar.zst`, synchronized into AgentStudio only during an
   explicit runtime-version bump;
4. `RuntimeMetadata.json`, recording compatibility and provenance.

AgentStudio remains the owner of app construction and runtime operation. It
continues to embed zmx at `Contents/MacOS/zmx`, sign zmx before signing the app,
copy the bundled debug zmx into the worktree-isolated runtime location, and
operate zmx with the existing data, socket, session, and observability model.
Only the source of the inputs changes.

## Product Intent

An ordinary AgentStudio checkout or worktree must not clone, compile, or cache
the Ghostty or zmx source trees. Those dependencies change infrequently but
currently impose gigabytes of source, generated output, and Zig caches on every
prepared worktree.

The terminal runtime is one compatibility unit because the linked GhosttyKit,
Ghostty-generated resources, and embedded zmx executable are shipped and tested
together. They are not one packaging unit: GhosttyKit is a build-time library,
zmx is an embedded runtime executable, and Ghostty resources are runtime data.

## Current-State Evidence

At `5cf627ee`, the prepared checkout contained approximately:

| Input | Observed size |
| --- | ---: |
| `vendor/ghostty` | 6.8 GB |
| `vendor/zmx` | 72 MB |
| `Frameworks/GhosttyKit.xcframework` | 571 MB |
| checked/generated Ghostty resources | under 100 KB |

The current ownership is visible in:

- `.gitmodules`, which pins both vendor source repositories;
- `.mise.toml`, where `setup` hydrates submodules, builds both vendors, copies
  the XCFramework, and generates resources;
- `Package.swift`, which links a local
  `Frameworks/GhosttyKit.xcframework` binary target;
- `scripts/build-ghostty-local.sh`, which temporarily changes Ghostty's
  `LibtoolStep.zig` behavior as part of the AgentStudio product recipe;
- local, CI, debug, and release bundle scripts, which copy zmx from
  `vendor/zmx/zig-out/bin/zmx`;
- `SessionConfiguration.findZmx`, which can fall through from the bundled
  executable to vendor, Homebrew, and `PATH` candidates.

The local Ghostty recipe and CI/release recipes are not currently identical.
The external runtime producer must replace those variants with one declared
recipe rather than publishing an unspecified build.

## Measurable Success

The contract succeeds when all of the following are true:

- a fresh ordinary AgentStudio worktree contains no Ghostty or zmx source
  checkout and requires no Zig toolchain;
- normal AgentStudio build and default test lanes link the released
  GhosttyKit without compiling either vendor;
- ordinary build and test do not require the zmx artifact unless a bundling or
  real zmx lifecycle surface asks for it;
- every stable, beta, and supported debug app embeds zmx from the exact selected
  terminal-runtime release;
- the shipped GhosttyKit, Ghostty resources, and pre-sign zmx bytes all identify
  the same terminal-runtime release;
- resource synchronization is an explicit reviewed runtime-bump operation, not
  worker setup;
- no normal AgentStudio setup, CI, or release path contains a vendor-source
  fallback.

## Boundary and Separability Map

```text
agentstudio-vendors
  owns:
    vendor/ghostty and vendor/zmx source revisions
    Zig/Xcode/SDK build environment
    AgentStudio Ghostty build adaptation
    GhosttyKit construction
    zmx construction
    Ghostty-generated resource extraction
    compatibility tests and release provenance

  publishes one exact version
       |
       +--> GhosttyKit.xcframework.zip -- SwiftPM link --> AgentStudio
       |
       +--> zmx.artifactbundle.zip -- locator plugin --> app bundlers
       |
       +--> ghostty-resources.tar.zst -- explicit sync --> tracked resources
       |
       `--> RuntimeMetadata.json -- compatibility/provenance verification

AgentStudio
  owns:
    exact runtime dependency selection
    Ghostty host API usage
    tracked custom xterm-256color entry
    app bundle construction and resource placement
    zmx embedding, signing, isolation, and process lifecycle
    stable/beta/debug identity, notarization, and runtime tests
```

The three related AgentStudio specs remain separable. The terminal-runtime
release changes input provenance. It does not own Swift build-slot cardinality
or debug app-generation retention.

## Runtime Repository Contract

### Repository ownership

The runtime repository owns:

- Ghostty and zmx as pinned source submodules;
- the Zig version and any other build-tool versions;
- the AgentStudio-specific Ghostty libtool adaptation;
- production of all published artifacts;
- extraction of upstream Ghostty shell integration and terminfo;
- smoke and compatibility tests across the published tuple;
- release metadata and checksums.

The runtime repository does not own:

- AgentStudio source or its Ghostty host adapter;
- AgentStudio bundle identifiers, channels, signing identities, or notarization;
- zmx session names, socket roots, restore policy, or health checks;
- AgentStudio debug data-root and worktree isolation;
- AgentStudio's custom `xterm-256color` source/compiled resource.

### One release identity

Every release has one immutable semantic version. AgentStudio consumes that
version exactly, never through a range or a moving `latest` reference.

`RuntimeMetadata.json` must record at least:

- metadata schema version and terminal-runtime version;
- exact Ghostty and zmx revisions;
- Zig version, Xcode build, SDK, and minimum deployment target;
- supported architecture/triple inventory;
- build flags and digest of the complete build-recipe inputs;
- GhosttyKit header/module/archive identity;
- each release asset's byte length and SHA-256 digest;
- resource inventory and digests;
- the compatibility test receipt identity.

The supported architecture set must be explicit before publication. The
migration must not silently drop an architecture currently promised by an
AgentStudio release.

### Artifact immutability

Release asset URLs are versioned and immutable. The repository tag's
`Package.swift` contains the checksums SwiftPM uses for remote binary targets.
`RuntimeMetadata.json` must agree with those values. A checksum downloaded only
beside the asset is not the trust root.

A failed download, checksum mismatch, unsupported metadata schema, wrong
architecture, or incomplete artifact inventory must fail before AgentStudio
links, copies, executes, or signs the candidate bytes.

## GhosttyKit Contract

The runtime package exports a `GhosttyKit` library backed by a downloadable
SwiftPM binary target. AgentStudio depends on the package at one exact version
and links the exported product instead of declaring a local framework path.

The published XCFramework is already in its final consumer form. AgentStudio
does not strip, repack, patch, or otherwise mutate it after checksum
verification. Headers, module layout, archive members, deployment target, and
architecture slices are part of the release contract.

SwiftPM's per-scratch extraction of the XCFramework is accepted. Avoiding that
copy is not a requirement of this spec; bounding active scratch directories is
owned by the build-slot spec.

## zmx Contract

### Distribution

zmx is published as a macOS executable artifact bundle with its own checksum
and architecture metadata. It is not embedded inside the GhosttyKit archive and
is not linked into AgentStudio.

The runtime package exports one command plugin whose only product-facing job is
to ask SwiftPM for the resolved `ZmxTool` path and return a stable,
machine-readable result containing:

- canonical executable path;
- terminal-runtime version;
- expected pre-sign SHA-256 digest;
- supported architecture identity.

AgentStudio code and scripts must not know SwiftPM's internal artifact-cache or
extraction layout. One shared AgentStudio resolver consumes the plugin output,
validates it, and supplies all bundlers and real zmx tests.

### Resolution policy

Normal build, lint, architecture, and non-zmx test lanes do not invoke the zmx
locator. zmx is resolved only for surfaces that need an actual app/helper pair
or a real zmx lifecycle proof.

Packaged stable and beta apps use the bundled zmx or fail closed. They must not
fall through to a vendor tree, Homebrew, `PATH`, or `which zmx`. An explicitly
authorized debug/test override can remain, but it cannot become a production
fallback.

### AgentStudio bundle ownership

For stable, beta, and debug bundles, AgentStudio continues to:

1. receive the verified pre-sign zmx path;
2. copy it to `Contents/MacOS/zmx`;
3. verify that the copied pre-sign digest matches the selected runtime;
4. sign the nested helper according to AgentStudio's signing policy;
5. sign the outer app and perform the existing signature/notarization proof.

For supported debug launches, AgentStudio continues to require zmx inside the
generated app, copy that bundled executable to the stable per-worktree debug
runtime path, and pass `AGENTSTUDIO_ZMX_PATH`. The data root, zmx socket root,
session identity, and worktree isolation behavior do not change.

This spec does not redesign zmx entitlements. A separate security review may
reduce helper entitlements, but that is not part of the disk/provenance
cutover.

## Ghostty Resource Contract

The runtime release includes Ghostty-generated shell integration and the
`ghostty` and `xterm-ghostty` terminfo entries that correspond to the released
GhosttyKit.

During a deliberate runtime-version bump, an exported synchronization command
updates the small tracked copies in AgentStudio and writes a tracked provenance
record containing the terminal-runtime version, Ghostty revision, resource
inventory, and aggregate digest.

The synchronization operation must:

- verify the exact runtime release and resource archive before changing tracked
  files;
- update Ghostty-owned resource files as one atomic reviewed set;
- preserve AgentStudio's custom `xterm-256color` entry and its source;
- reject unexpected paths, links, special files, or incomplete inventories;
- leave the prior tracked set unchanged on failure.

Ordinary workers receive these resources from Git. They never regenerate them.
Moving the resources into a dependency resource bundle is explicitly deferred.

## AgentStudio Hard-Cut Boundary

After the distribution contract is adopted, AgentStudio has one producer
authority: the exact terminal-runtime release. The ordinary consumer repo must
not retain a second source-build path.

The following responsibilities therefore no longer belong in AgentStudio:

- the Ghostty and zmx submodules;
- Zig version management for those vendors;
- GhosttyKit construction and the Ghostty libtool adaptation;
- zmx compilation;
- Ghostty-generated resource extraction;
- vendor caches in AgentStudio CI and release workflows.

The hard cut does not remove AgentStudio's bundling, signing, debug isolation,
or zmx E2E responsibilities.

## Requirements

| ID | Requirement |
| --- | --- |
| TR-01 | One exact terminal-runtime version binds GhosttyKit, zmx, generated Ghostty resources, and provenance. |
| TR-02 | The runtime repository is the only source-build owner for Ghostty and zmx. |
| TR-03 | AgentStudio ordinary setup/build/test never hydrates the vendor submodules or invokes Zig for them. |
| TR-04 | GhosttyKit is consumed as a checksum-verified SwiftPM binary library product. |
| TR-05 | zmx is a separately checksummed executable artifact bundle located through one exported SwiftPM plugin and one AgentStudio resolver. |
| TR-06 | Ordinary non-zmx work does not require the zmx locator or real zmx executable. |
| TR-07 | AgentStudio continues to embed and sign zmx inside every supported app bundle. |
| TR-08 | Supported debug launch continues to project bundled zmx into the existing isolated per-worktree runtime path. |
| TR-09 | Stable and beta runtime selection cannot fall back to ambient or vendor zmx. |
| TR-10 | Ghostty-generated resources are tracked in AgentStudio and synchronized only during an exact runtime bump. |
| TR-11 | AgentStudio's custom `xterm-256color` remains AgentStudio-owned. |
| TR-12 | All artifacts declare and prove platform, architecture, deployment, recipe, and source-revision identity. |
| TR-13 | Download, metadata, architecture, inventory, or checksum failure is fail-closed before consumption or signing. |
| TR-14 | AgentStudio remains the owner of app identity, signing, notarization, zmx lifecycle, and runtime isolation. |

## Security and Failure Semantics

- Network and release assets are untrusted until verified against the exact
  package/metadata pin.
- Artifact extraction rejects path traversal, absolute paths, unexpected links,
  special files, duplicate paths, and undeclared executable content.
- Caches are accelerators, not proof; cached artifacts are revalidated against
  the selected release identity.
- A cold cache with unavailable release storage fails clearly. AgentStudio does
  not fall back to rebuilding vendors.
- A runtime bump is reversible by restoring the prior exact package version and
  its matching tracked resource/provenance change.
- Release metadata and logs must not contain signing credentials or secrets.

## Alternatives and Tradeoffs

### Separate GhosttyKit and zmx repositories

Rejected. It permits independent versions where the product needs one tested
tuple and duplicates release/provenance infrastructure.

### One monolithic archive copied into legacy paths

Rejected. It obscures the different consumption mechanisms and gives up
SwiftPM's native binary-library and executable-tool resolution.

### Continue source builds with shared caches

Rejected. It reduces some repeated compilation but leaves every worktree and CI
lane responsible for source hydration, toolchain compatibility, and product
recipe ownership.

### Put resources in a dependency bundle immediately

Deferred. It is architecturally clean but expands the first cut into runtime
resource lookup and app resource-bundle discovery. The resources are tiny; a
tracked synchronized copy removes worker generation cost with less migration
risk.

### General-purpose artifact hydrator

Rejected for the first cut. SwiftPM owns binary artifact resolution. The only
custom surfaces are the narrow zmx locator and deliberate resource synchronizer.

## Explicit Non-Goals

- Changing zmx session, socket, restore, health, or debug-isolation semantics.
- Moving zmx outside `Contents/MacOS` in an AgentStudio app.
- Letting the runtime repository sign or notarize AgentStudio.
- Eliminating SwiftPM's per-scratch XCFramework extraction.
- Solving Swift build-slot cardinality or debug app retention.
- Redesigning TCC, repository placement, bookmarks, or Documents access.
- Supporting independent GhosttyKit/zmx version negotiation.
- Creating a vendor-editing workflow inside ordinary AgentStudio worktrees.

## Proof Expectations

The implementation plan must operationalize these proof modalities:

- schema and negative fixtures for release metadata, checksums, inventory, and
  extraction safety;
- producer proof for XCFramework slices, headers/modules, archive symbols, zmx
  architecture/version, resource inventory, and build-recipe provenance;
- clean AgentStudio compile/link proof using only the exact remote GhosttyKit;
- static boundary proof that normal AgentStudio setup, CI, and release contain
  no vendor build or Zig path;
- ordinary build/test proof that zmx is not required;
- debug and release bundle inspection proving the exact zmx is embedded and
  nested signing remains AgentStudio-owned;
- real zmx attach/list/wait/kill/restore and worktree-isolation proof using the
  released executable;
- resource lookup and checksum proof tying the checked-in Ghostty resources to
  the exact linked GhosttyKit release;
- final app signature, notarization, and runtime-release receipt proof for
  publishable channels.

## Open Decisions

The supported architecture/toolchain matrix must be declared before the first
runtime release. No other product decision blocks an implementation plan.
