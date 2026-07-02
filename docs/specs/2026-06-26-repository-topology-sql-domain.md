# Repository Topology SQL Domain

Status: revised after spec review; ready for vertical-slice planning
Date: 2026-06-26
Worktree: `/Users/shravansunder/Documents/dev/project-dev/agent-studio.repository-sql-domain`
Branch: `feature/repository-sql-domain`

## Product Intent

Repository topology should be a first-class workspace-scoped domain instead of a slice of the broad `WorkspaceStore` snapshot. Repos, worktrees, watched paths, unavailable repos, repo tags, and worktree tags describe the repository topology for one explicit workspace id. Pane graph and tab graph may reference that topology, but they do not own it.

Moving topology out of `WorkspaceStore` is an ownership split, not a removal of workspace scoping. `workspace_id` remains part of repo/worktree SQL and every topology restore, mutation, flush, and legacy-import path must be scoped by the workspace identity supplied during workspace boot.

This spec also hardens the color and tag model:

- Pane tags are removed.
- Repo tags and worktree tags are added.
- Manual repo/worktree checkout color persistence is removed.
- Automatic fork/repo/worktree palette colors remain derived presentation.
- Tab color is added as the only new persisted color, owned by tab state.

## Current-State Evidence

- Core SQLite already owns topology tables: `watched_path`, `repo`, `worktree`, and `unavailable_repo` in `WorkspaceCoreMigrations.swift`.
- `WorkspaceStore` currently observes `repositoryTopologyAtom.repos`, `watchedPaths`, and `unavailableRepoIds`, then sends topology through `WorkspaceSQLiteSnapshot`.
- `WorkspaceSQLiteSnapshot` currently mixes topology with panes, tabs, window memory, and watched paths.
- `pane_tag` exists in core SQL and pane graph mutation writes `metadata.durableFacets.tags` into that table.
- Checkout colors currently live as settings/sidebar state and legacy import payloads.
- Automatic repo/worktree/fork colors already exist in `RepoPresentationGrouping`.
- `tab_shell` exists without any persisted color column.

This spec supersedes older SQLite docs and plans that still treat `pane_tag` and `settings.sidebar.checkoutColors` as desired durable contracts.

## Requirements

R1. SQL migration first.
The core SQLite contract must define the new topology/tag/tab-color schema before app code depends on repo tags, worktree tags, or tab colors.

R2. Topology store separation.
`RepositoryTopologyStore` owns topology restore, observation, dirty state, and flush participation for one explicit workspace id. `WorkspaceStore` must stop observing topology fields and must stop building topology into its own persistence snapshot.

R3. Atom rename and ownership.
`WorkspaceRepositoryTopologyAtom` becomes `RepositoryTopologyAtom`. The atom owns live repos, worktrees, watched paths, unavailable repo ids, repo tags, worktree tags, and topology lookup/index behavior. This is a mechanical name and ownership cutover, not an `AppBench` abstraction.

R4. WorkspaceStore narrowing.
`WorkspaceStore` may coordinate workspace boot/restore ordering, but it does not own topology persistence. It remains responsible for identity/window/pane/tab workspace state that is not repository topology.

R5. Existing topology invariants are preserved.
The new store must preserve current core repository mutation invariants: unavailable repo rows are cleared and restored around replacement, watched paths are replaced deterministically, repo/worktree rows reconcile by stable key, repo/worktree tag replacement happens inside the same topology transaction, and cross-workspace worktree or tag ownership is rejected.

R6. Pane tags are removed.
Durable pane tags, `pane_tag`, pane-facet tag state, and pane-tag legacy hydration are removed. Existing pane tags are intentionally discarded/ignored rather than migrated to repo/worktree tags because pane tags do not carry a reliable repo/worktree owner.

R7. Repo and worktree tags are topology state.
Repo tags and worktree tags are stored in core SQLite, hydrated into `RepositoryTopologyAtom`, and exposed in the first slice as command/sidebar search metadata for repo/worktree rows. Visible chips, tag colors, tag ordering, grouping, taxonomy, global vocabulary, and IPC exposure are out of scope.

R8. Manual repo/worktree color persistence is removed.
No repo color, worktree color, checkout color, or manual palette override is stored in SQL, settings JSON, sidebar cache, or legacy import output.

R9. Automatic colors remain.
Automatic fork/repo/worktree palette colors remain derived from stable topology/grouping inputs. Removing manual color override state must not remove sidebar, pane display, launcher, inbox, or command-bar automatic accent behavior.

R10. Tab color is durable tab state.
Tab color is persisted with durable tab shell/graph state, restored on boot, and rendered by tab presentation. It is not repository topology and not settings/sidebar checkout color state. The persisted scalar is nullable strict `#RRGGBB`; input may be case-insensitive, but storage must be canonical uppercase hex.

R11. Reader compatibility is part of the contract.
Command bar, repo explorer/sidebar, pane display, tab display, launcher, inbox source presentation, filesystem projection, boot replay, and IPC/programmatic snapshots must continue to resolve repo and worktree identity after topology leaves `WorkspaceStore`.

R12. IPC does not grow accidental data exposure.
Existing pane IPC/programmatic snapshots keep their current repoId/worktreeId compatibility. Repo/worktree tags and tab colors are not added to pane IPC snapshots unless a later API contract explicitly chooses that exposure.

R13. Active workspace selection is not part of this slice.
`ActiveWorkspaceSelectionAtom` remains as-is. This spec does not redesign active workspace selection or make it the topology persistence owner. Topology writes must not derive their workspace id from active selection.

R14. Performance proof is required.
The later implementation must compare before/after evidence for topology-sensitive surfaces: command bar, sidebar/repo projection, tab bar/display, topology lookup, filesystem projection, and write coordination. Victoria-backed metrics/log proof is preferred when the shared local stack is available; JSONL is a debug aid, not the default proof. Performance gates require evidence and regression triage, not a hard threshold, unless the plan identifies a measurable regression attributable to this change.

## Spec Boundary / Separability Map

```text
core.sqlite topology tables
  owns: watched_path, repo, worktree, unavailable_repo,
        repo_tag, worktree_tag
  exposed by: RepositoryTopologyStore

RepositoryTopologyStore
  owns: restore/observe/dirty/flush for repository topology scoped
        to an explicit workspace id
  uses: WorkspaceCoreRepository topology APIs and migration schema
  must preserve: replacement ordering, stable-key reconciliation,
                 unavailable repo semantics, recovery participation
  must not use: ActiveWorkspaceSelectionAtom as write scope

RepositoryTopologyAtom
  owns: live repos/worktrees, watched paths, availability,
        repo tags, worktree tags, lookup/performance index
  exposes: topology read/mutation contract to readers and coordinators

WorkspaceStore
  owns: workspace identity, window memory, pane graph, tab graph/cursors,
        arrangement cursors, pane presentation
  may coordinate: boot/restore sequencing across stores
  must not own: topology observation, topology dirty state, topology snapshot

Pane graph
  owns: pane identity, content, residency, durable pane metadata
  may reference: repoId, worktreeId, cwd
  must not own: pane tags, repo tags, worktree tags

Tab shell / tab graph
  owns: tab identity, order, membership, arrangement, active cursors
  owns: persisted tab color
  must not own: repo/worktree colors or topology tags

RepoPresentationGrouping
  owns: automatic derived palette assignment
  must not persist: manual repo/worktree/checkout colors
```

## SQL Contract

The next core migration must update both the fresh schema and migration path. Names may follow the final migration numbering, but the semantic DDL must match this contract.

```sql
-- Remove pane-scoped durable tags. Existing rows are discarded.
DROP TABLE IF EXISTS pane_tag;

-- Repo tags belong to repository topology.
CREATE TABLE repo_tag (
    workspace_id TEXT NOT NULL,
    repo_id TEXT NOT NULL,
    tag TEXT NOT NULL CHECK(tag = trim(tag) AND length(tag) BETWEEN 1 AND 64),
    PRIMARY KEY(workspace_id, repo_id, tag),
    FOREIGN KEY(repo_id, workspace_id)
        REFERENCES repo(id, workspace_id)
        ON DELETE CASCADE
);

CREATE INDEX idx_repo_tag_workspace_tag
    ON repo_tag(workspace_id, tag);

-- Worktree tags belong to repository topology.
-- The unique index lets the foreign key prove the worktree, workspace, and repo
-- relationship instead of accepting a tag attached to the wrong workspace.
CREATE UNIQUE INDEX idx_worktree_id_workspace_repo
    ON worktree(id, workspace_id, repo_id);

CREATE TABLE worktree_tag (
    workspace_id TEXT NOT NULL,
    repo_id TEXT NOT NULL,
    worktree_id TEXT NOT NULL,
    tag TEXT NOT NULL CHECK(tag = trim(tag) AND length(tag) BETWEEN 1 AND 64),
    PRIMARY KEY(workspace_id, worktree_id, tag),
    FOREIGN KEY(worktree_id, workspace_id, repo_id)
        REFERENCES worktree(id, workspace_id, repo_id)
        ON DELETE CASCADE
);

CREATE INDEX idx_worktree_tag_workspace_tag
    ON worktree_tag(workspace_id, tag);

CREATE INDEX idx_worktree_tag_repo_id
    ON worktree_tag(repo_id);

-- Tab color belongs to tab shell state.
ALTER TABLE tab_shell
    ADD COLUMN color_hex TEXT
    CHECK(color_hex IS NULL OR color_hex GLOB '#[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]');
```

Repo/worktree tag values are untrusted local user text. SQL provides the last-line shape guard for empty, whitespace-padded, and overlong values; model validation must also reject control characters, newlines, ANSI escape sequences, and bidi control characters before values reach search, display, logs, or telemetry.

Tab color accepts nullable strict `#RRGGBB`. Model code may accept lowercase input, but it must normalize to uppercase before persistence. Valid example: `#58C4FF`. Invalid examples: `#zzzzzz`, `#12345g`, empty string, and overlong strings.

Forbidden SQL:

```sql
-- Do not add any of these or equivalents.
ALTER TABLE repo ADD COLUMN color_hex TEXT;
ALTER TABLE worktree ADD COLUMN color_hex TEXT;
CREATE TABLE repo_color (...);
CREATE TABLE worktree_color (...);
CREATE TABLE checkout_color (...);
CREATE TABLE pane_tag (...);
```

Settings JSON must also stop encoding and hydrating `sidebar.checkoutColors`. Legacy settings/sidebar cache data may decode old keys for forward tolerance, but the decoded values must be ignored and must not be re-encoded.

## RepositoryTopologyAtom Contract

`RepositoryTopologyAtom` owns:

- repos and worktrees as canonical topology entities;
- watched paths;
- unavailable repo ids;
- repo tags keyed by repo id;
- worktree tags keyed by worktree id;
- topology lookup/index generation and performance tracing.

It does not own:

- repo enrichment, PR counts, unread counts, recent targets, or cache rebuild metadata;
- pane graph residency or pane content;
- tab color, tab membership, or tab arrangement;
- active workspace selection;
- manual color overrides.

Repo/worktree tag values are local display/search labels, not trusted protocol data. The atom may expose them as keyed maps or fields on runtime values, but all runtime shapes must preserve explicit workspace scoping and must not allow repo/worktree tags from one workspace to attach to entities from another workspace.

Topology lookup must preserve current longest-containing-path precedence for overlapping or nested worktrees unless a later reviewed spec explicitly replaces it.

The first slice does not define tag colors, tag ordering, tag taxonomy, cross-workspace tag vocabulary, grouping semantics, IPC exposure, or access-control semantics.

## RepositoryTopologyStore Contract

`RepositoryTopologyStore` is the persistence wrapper for `RepositoryTopologyAtom`.

It must:

- hydrate topology from core SQLite into the atom;
- be constructed/restored for an explicit workspace id supplied by workspace boot/identity ownership;
- observe topology mutations outside `WorkspaceStore`;
- debounce or participate in flush according to the repository's existing persistence patterns;
- persist repos, worktrees, watched paths, unavailable repo ids, repo tags, and worktree tags through core repository APIs;
- preserve current topology replacement ordering and validation;
- validate and replace repo/worktree tags inside the same core repository topology mutation transaction as owner reconciliation;
- write tags after repo/worktree owner rows are reconciled and before the topology flush is marked complete;
- participate in the existing staged/completed workspace save model for this slice. A narrower topology-specific status marker is a future design, not part of this cutover.

It must not:

- persist pane graph, tab graph, window memory, settings, repo enrichment cache, recent targets, inbox state, or editor preferences;
- use settings JSON as a topology source of truth;
- duplicate topology tables in local SQLite;
- derive write scope from `ActiveWorkspaceSelectionAtom`;
- allow UI, settings, repo-enrichment, or sidebar-cache paths to write `repo_tag` or `worktree_tag` directly.

## WorkspaceStore Narrowing

After this cutover, `WorkspaceStore` may still be a composition participant for boot or flush coordination, but it must not be the topology write owner.

Restore call graph:

```text
workspace boot / identity owner
  -> provides explicit workspace id
  -> RepositoryTopologyStore.restore(workspaceID:)
       -> reads core SQLite topology rows
       -> hydrates RepositoryTopologyAtom
  -> WorkspaceStore.restore(workspaceID:)
       -> restores identity/window/pane/tab/presentation state only
       -> may await topology restore before consumer-facing projection
```

`WorkspaceStore` and `WorkspacePersistenceTransformer` must not hydrate repos, worktrees, watched paths, unavailable repo ids, repo tags, or worktree tags after the cutover.

Disallowed after the cutover:

- `WorkspaceStore.observePersistedState()` registering topology fields;
- `WorkspaceStore.persistNow()` building topology into a broad workspace snapshot;
- `WorkspaceSQLiteSnapshot` carrying topology-owned fields as the write boundary, including repos, worktrees, watched paths, unavailable repo ids, repo tags, or worktree tags;
- topology changes being saved only because `WorkspaceStore` observed them.

Allowed:

- coordinated boot order where topology hydrates before pane/display/filesystem consumers need repo/worktree ids;
- explicit cross-domain mutation coordinators that update topology and pane references together;
- temporary internal restore composition if it has one clear owner and cannot overwrite newer topology writes.

## Reader And Surface Contract

Tag exposure first slice:

| Surface | Repo/worktree tag behavior |
| --- | --- |
| Command bar | Tags are searchable metadata for repo/worktree rows. Rows keep their current counts, labels, targeting, and open/open-in-pane behavior. Pane tags are not a command-bar keyword source. |
| Sidebar filter / repo explorer search | Tags are searchable metadata for repo/worktree filtering. |
| Visible chips / labels | Out of scope. Do not add visible tag chips or labels in this slice. |
| Grouping / ordering | Out of scope. Do not group, sort, or prioritize by tag in this slice. |
| IPC / programmatic snapshots | Out of scope. Do not expose repo/worktree tags through pane IPC snapshots. |

Sidebar and repo explorer:

- repo grouping and worktree rows remain topology-driven;
- unavailable repo visibility and action semantics preserve current behavior unless a later UX spec changes it;
- manual "set icon color" UI and persisted color state are removed;
- automatic palette colors remain stable for equivalent topology/grouping inputs.

Pane, tab, launcher, and inbox presentation:

- repo/worktree identity continues to resolve for titles, labels, collapsed bars, launcher recent cards, and source icons;
- display readers stop depending on checkout color override maps;
- tab color is displayed from tab state, not topology.

Filesystem projection and boot replay:

- topology generation ordering, unavailable repo filtering, registration/unregistration, active worktree writes, and fallback cwd behavior remain deterministic;
- topology restore must happen before consumers make decisions that assume repo/worktree identity is ready.

IPC/programmatic control:

- existing pane query output preserves repoId/worktreeId compatibility;
- tags/colors/raw paths do not leak through pane IPC snapshots by accidental shared-model projection.

## Migration And Legacy Contract

- Existing `pane_tag` rows are discarded on migration.
- Legacy pane metadata/facet tags are ignored and are not re-encoded.
- Existing settings/sidebar checkout colors are ignored on restore/import and are not re-encoded.
- Legacy JSON topology import remains allowed only as a bootstrap path into core SQLite, not as a second live topology owner.
- Corrupt core/local database recovery and sidecar quarantine behavior remain in force.
- Topology remains committed under the same staged/completed workspace save status as the rest of the workspace SQLite snapshot for this slice.
- Recovery proof must cover staged/completed save state so splitting topology ownership does not create "valid topology, invalid workspace" split-brain.
- Crash/restart scenario: if topology writes are staged, local/pane/tab writes fail before completion, and the app restarts, restore must not expose a mixed generation where pane references point at topology rows from an uncompleted save.

## Performance And Monitoring Expectations

The implementation plan must include a before/after performance evidence artifact for topology-sensitive paths. Metrics should include counts and latency summaries such as p95/max where the existing workload already provides them. OTLP/Victoria telemetry must use hashes, counts, and latencies, not raw filesystem paths. Repo-local `tmp/` proof artifacts may contain raw fixture paths only when the proof explicitly scopes them to local debug evidence.

Surface proof signal mapping:

| Surface | Required proof signal |
| --- | --- |
| Command-bar repo/worktree rows | Focused row-construction timing or existing command-bar metric if present. |
| Sidebar/repo explorer projection | Existing projection workload metric if present; otherwise focused projection timing with row counts. |
| Tab bar/display topology identity reads | Focused refresh/read assertion; full perf metric is not required unless the implementation adds a hot loop. |
| `repoAndWorktree(containing:)` lookup | Focused lookup timing plus overlapping/nested path precedence proof. |
| Filesystem projection sync | Existing generation/unavailable-filtering proof plus timing/count signal when available. |
| Persistence/write coordination | Save/flush count and latency signal around topology replacement and staged/completed status. |

## Non-Goals

- No `AppBenchStore` or `AppBenchAtom`.
- No active workspace selection redesign.
- No repo enrichment, recent target, PR count, or inbox persistence migration into topology.
- No tag taxonomy, colors, ordering, hierarchy, or global vocabulary.
- No repo/worktree manual color persistence.
- No IPC privilege redesign.
- No new auth, secrets, network, sandbox, or encryption-at-rest requirement.
- No claim that local SQLite hides filesystem paths from the local user.
- No raw filesystem paths in OTLP/Victoria topology proof.

## Proof Expectations

Schema proof:

- migration creates `repo_tag`, `worktree_tag`, tab color storage, and no repo/worktree color storage;
- fresh schema no longer creates `pane_tag`;
- migrated schema drops or retires `pane_tag`;
- constraints reject empty/overlong tags and cross-workspace tag attachment;
- model validation rejects unsafe tag strings with control characters, newlines, ANSI escape sequences, or bidi control characters before display/search/log use;
- tab color storage accepts `NULL` and canonical `#RRGGBB`, normalizes lowercase input before persistence, and rejects `#zzzzzz`, `#12345g`, empty strings, and overlong strings.

Repository/store proof:

- repo/worktree topology round-trips through core SQLite;
- repo tags and worktree tags round-trip and cascade on owner deletion;
- unavailable repo replacement ordering is preserved;
- repo/worktree tag replacement happens inside topology replacement transaction semantics after owner reconciliation;
- nested/overlapping path lookup preserves longest-containing-path precedence;
- `WorkspaceStore` no longer observes or saves topology;
- `WorkspaceSQLiteSnapshot` carries no topology-owned fields, including repo tags and worktree tags;
- `RepositoryTopologyStore` saves topology mutations through explicit workspace scope and the shared staged/completed save status.

Legacy/recovery proof:

- old checkout colors are decoded/ignored and not re-encoded;
- old pane tags are ignored/discarded and not re-encoded;
- staged/completed save recovery still works with topology split;
- crash/restart after staged topology write and failed local/pane/tab write does not restore mixed topology/workspace generations;
- corrupt core/local quarantine behavior remains intact.

Reader proof:

- command-bar repo/worktree rows and actions still work;
- command-bar and sidebar/repo explorer search include repo/worktree tag metadata without adding visible chips, grouping, ordering, or IPC exposure;
- sidebar/repo explorer automatic colors remain stable without override state;
- command bar, sidebar/repo explorer, pane display, launcher, and inbox automatic colors remain stable for equivalent topology/grouping inputs;
- manual checkout color mutation APIs/call sites, settings/sidebar cache encoding, and "set icon color" UI/action are absent after the cutover;
- pane/tab/launcher/inbox labels and accents still resolve, with tab color tested separately from automatic repo/worktree colors;
- IPC pane snapshots preserve current repoId/worktreeId compatibility and do not expose new tag/color fields accidentally;
- filesystem projection keeps unavailable filtering and generation ordering.

Performance proof:

- before/after metrics are captured for topology-sensitive reader and persistence surfaces;
- each topology-sensitive surface records the proof signal named in this spec;
- OTLP/Victoria proof uses hashes, counts, and latencies rather than raw filesystem paths;
- regressions are triaged against the changed code path before unrelated infrastructure is changed.

Guardrail proof:

- durable pane tags are impossible to create through fresh schema, migration schema, pane graph persistence, or legacy import;
- persisted color storage exists only for tab state, not repo/worktree/checkout state;
- `WorkspaceStore` does not observe topology and `WorkspaceSQLiteSnapshot` does not carry topology-owned fields;
- pane IPC snapshot/list JSON field allowlists exclude repo/worktree tags, tab color, and raw paths.

## Open Decisions For Planning

- Final model shape for tags in runtime values: fields on repo/worktree value types or keyed maps in `RepositoryTopologyAtom`.
- Final tab color owner name: `TabShell.colorHex`, a tab presentation owner, or a tab shell companion record. The boundary is fixed: durable tab state owns it.
- Exact metric names for newly required focused performance assertions, where no existing Victoria metric already covers the surface.
