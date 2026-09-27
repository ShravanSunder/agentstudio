# Find: search service program design

Requirements: [requirements](2026-09-26-find-search-service-requirements.md) (U1–U13) · Specification: [specification](2026-09-26-find-search-service-specification.md) (E1–E7, R1–R15, C1–C3, F1–F5).

## How it fits together

```mermaid
flowchart LR
  subgraph CB["AgentStudioCommandBar (MainActor)"]
    direction TB
    TF["CommandBarTextField<br/>rawInput"] --> CTRL["CommandBarPanelController<br/>owns: query sequence, submit"]
    CTRL --> ST["CommandBarState<br/>owns: shown results, selection,<br/>retained root query (E6)"]
    LIVE["Live sources<br/>panes · tabs · commands"]
  end
  subgraph CORE["AgentStudioCore (off main)"]
    direction TB
    KIND["SearchKind declarations<br/>(Swift only)"] -.declares.-> SVC["SearchService (actor)<br/>owns: matching, ranking, grouping,<br/>live documents, memory mirror"]
    SVC --> IDX["SearchIndexStore (private)"] --> LOC[("search-index.sqlite<br/>own file, rebuildable")]
    DS["WorkspaceSQLiteDatastoreActor<br/>(unchanged saves)"] -- "committed repo/worktree facts" --> SVC
  end
  CTRL <== "await search(query, seq) → result set(seq)" ==> SVC
  LIVE -- "replaceLiveDocuments" --> SVC
```

**The change in ordinary words:**
- **Matching leaves the main thread.** Today the command bar ranks every item synchronously inside SwiftUI's `body`. After this change it sends the query to a `SearchService` actor and shows the answer when it arrives, and only if it is still the newest query.
- **Repos and worktrees become indexed entries.** They live in the service's own SQLite file (`search-index.sqlite`, one entry table plus an FTS5 trigram index). The existing persistence actor hands the service the repo and worktree facts it has just committed, so the index is always a derived copy, never a new source of truth. The file is never migrated: when its layout changes it is deleted and rebuilt from core.sqlite and local.sqlite.
- **Panes, tabs and commands stay in memory.** They are live UI state, so the command bar hands them to the service as *live documents* whenever they change.
- **Every kind is declared the same way:** fields, group, and indexed or live. That is how new kinds plug in later.
- **What stays the same:**
  - the empty-query view;
  - navigation levels and ↵ behaviour;
  - the matcher's scoring (moved, not rewritten);
  - the existing persistence stores and debounce.
- **Why this is enough:** every fact already reaches the datastore actor. The index rides on saves that happen anyway, so nothing new has to watch the filesystem, git or the atoms.
- **Cost:**
  - one new Core slice (`Core/Search/`);
  - one new rebuildable file (`search-index.sqlite`); core.sqlite and local.sqlite get no migration;
  - the command bar's results become asynchronous (one frame of the previous results can remain until the answer lands, ≤16 ms by R10).
- **Who pays:** command-bar code (the synchronous snapshot path is replaced) and the datastore save path (one hand-off of committed facts after each topology and cache save; the index write itself runs on the search actor).

## Components and ownership

| Component | Owns (single source) | Consumers | Changes when |
|---|---|---|---|
| **`SearchService`** (actor, `Core/Search/`) | query answering: candidate retrieval, fuzzy re-rank, grouping (R6, R7), short-query rule (R5); the live-document set; the memory-resident mirror of small indexed kinds | CommandBar now; IPC and remote consumers later (C2) | matching or ranking policy changes |
| **`SearchKind`** declarations (`Core/Search/`) | per-kind fields (E3), result group, storage class (`indexed` or `live`), memory-resident flag, recency boost | `SearchService`, index writer, sources | a kind or field is added (R14) |
| **Fuzzy ranker** (private to `SearchService`) | today's `CommandBarSearch` scoring, moved; reachable only from inside the actor (R13) | `SearchService` only | scoring rules change |
| **`SearchIndexStore`** (private to `SearchService`, `Core/Search/`) | `search-index.sqlite`: the entry rows and their FTS5 index. Sole writer; derived and rebuildable, never migrated (R15) | `SearchService` only | index layout changes (bump `index_version`, rebuild) |
| **Indexed-kind contributors** (repo, worktree) | mapping committed topology and cache facts to entries: name, folder name (last path component only, R3), tags, branch; no worktree names on repo entries (R2) | `SearchIndexStore` | a kind's persisted fields change |
| **`WorkspaceSQLiteDatastoreActor`** (existing) | unchanged saves; after a committed topology or cache save it hands the changed repo and worktree facts to the injected `SearchIndexFeed` | `SearchService` | never for search reasons beyond this one hand-off |
| **CommandBar live sources** | mapping the existing cached pane, tab and command items to documents | `SearchService` | command-bar item shapes change |
| **`CommandBarPanelController`** | query sequence numbers, submission, cancellation of the superseded task, applying only the current sequence's result (R9) | CommandBar views | bar lifecycle changes |
| **`CommandBarState`** | the displayed result set, selection, retained root query (E6, R12) | CommandBar views | UI state changes |

**Forbidden edges:**
- CommandBar → the fuzzy ranker (**unrepresentable**: a private type in another module);
- anyone → `SearchIndexStore` except `SearchService` (a private type);
- the datastore actor → search internals (it sees only the narrow `SearchIndexFeed` protocol);
- `SearchService` → atoms (it receives documents; it never reads MainActor state);
- search-index.sqlite → read by anything as a source of truth (it is a cache; core.sqlite and local.sqlite stay authoritative).

## Interfaces

**`SearchService` (actor), consumed by the command bar (C2)**
- `search(SearchQuery) async -> SearchResultSet`
  - **Query:** scope (E7), text, session id, sequence.
  - **Result:** the query's sequence plus grouped documents (E5). The result is always tagged with the sequence it answers, so answers may arrive out of order and the caller drops stale ones.
  - **Rules:**
    - an empty text is never sent (the empty view stays on today's MainActor projection, R4);
    - 1–2 characters rank live documents plus the memory-resident mirror, recents first, without touching the index (R5);
    - 3+ characters take FTS5 trigram candidates (≤ 200) plus live and memory-resident matches, then the fuzzy re-rank, then grouping (R1, R6, R7).
  - **Errors:** none surface to callers. If the index read fails, it degrades to memory-only results and records an `index_unavailable` trace attribute (F1).
- `replaceLiveDocuments(kind:, documents:, revision:)`: last-writer-wins by revision per kind; older revisions are ignored.

**`SearchIndexFeed` (protocol, implemented by `SearchService`), called by the datastore actor**
- `indexedFactsCommitted(SearchIndexedFacts)`: after `saveRepositoryTopologySnapshot` or `saveRepoCacheState` commits. The facts are plain Sendable values: repo and worktree ids with name, folder name, tags and branch, plus removed ids. The service writes them to its index and updates its memory-resident mirror in the same actor turn (R11). A feed failure never fails the save.

**`SearchIndexStore` (private to `SearchService`)**
- `apply(facts)`: one transaction per hand-off, keyed upsert or delete per entry. No triggers: the store itself keeps the FTS5 index in step, issuing FTS5's `delete` command with the old values before changing an entry, then inserting the new values.
- `rebuildFromPersistedRows()` runs when the file is missing, its `index_version` differs, a row fails to parse, or an integrity check fails. It deletes the file, recreates it, and loads every repo and worktree through the datastore actor's existing read API (F1, F5).

**`SearchKind` declaration (C3):** `id`, `group` (Repos · Worktrees · Panes · Tabs · Commands), `fields: [SearchFieldName]`, `storage: .indexed(contributor) | .live`, `memoryResident: Bool`, `recencyBoost`. Adding a kind means one declaration plus its contributor or live source (R14). `SearchKind` is a Swift enum and exists only in code: live kinds never touch SQLite, and indexed kinds appear there only as a plain text value.

## Search index storage

**Rules (owner, 2026-09-26):**
- no triggers;
- no SQL constraints except boolean CHECKs, so `kind` is plain text with no CHECK, parsed into `SearchKind` in Swift at read time, and an unknown value fails closed (the file is treated as stale and rebuilt; the value never defaults to some other kind);
- tables split by write pattern, never one per kind: a new indexed kind is a new `kind` value and, when needed, new columns;
- no JSON blobs; typed columns;
- the store is the only writer, with keyed upserts in one transaction;
- no migrations: this file is replaced, never migrated.

| Table | Write pattern | Columns | Keys |
|---|---|---|---|
| `search_entry` | current values, last write wins per entry | `entry_rowid`, `kind`, `entity_id`, `name`, `folder_name`, `branch`, `tags` (space-joined), `parent_name` | `entry_rowid` INTEGER PRIMARY KEY; UNIQUE(`kind`, `entity_id`) for idempotent upsert |
| `search_entry_fts` | FTS5 external-content index over `search_entry`, kept in step by the store (no triggers) | `name`, `folder_name`, `branch`, `tags`; `tokenize='trigram'` | `content_rowid = entry_rowid` |
| `search_index_meta` | small bookkeeping | `key`, `value` (`index_version`) | `key` PRIMARY KEY |

**Why a separate file instead of a local.sqlite table:** the index is derived, so replacing it is always safe. A table in local.sqlite would need a local.sqlite migration now and one for every future index change. A separate file needs none. It costs one more small SQLite file, which the search actor owns and opens itself.

## What runs where

| Work | Runs on | Primitive |
|---|---|---|
| keystroke: assign `rawInput`, bump sequence, submit | MainActor | local `@Observable` state (`CommandBarState`); no atom |
| matching, ranking, grouping, short-query rule | `SearchService` actor | actor-private state; not an atom (no UI subscriber) |
| index reads and writes | `SearchService` actor | private `SearchIndexStore`: a repository-style store, not an atom |
| committed facts hand-off | datastore actor → `SearchService` | one async call after the save commits |
| live panes, tabs, commands → documents | MainActor, on the command bar's existing cache invalidation | captures values already built for today's rows; no new derivation |
| apply result, availability guard, selection reconcile | MainActor | assign only, O(shown rows), keyed reads |

No new atom, no new bus event, no new coordinator responsibility.

## Call paths: keystroke to results

**Current** (source: `Views/CommandBarTextField.swift:74-84` → `CommandBarState.swift:34-47` → `Views/CommandBarView.swift:19-60` → `CommandBarResultSession.swift:56-112` → `CommandBarItemSearch.swift:44-87`):

```mermaid
sequenceDiagram
  participant TF as TextField (Main)
  participant ST as CommandBarState (Main)
  participant V as CommandBarView.body (Main)
  participant RS as ResultSession (Main)
  TF->>ST: rawInput = text (sync)
  ST-->>V: observation re-renders body
  V->>RS: snapshot(state) (sync)
  RS->>RS: filter ALL items (sync, every keystroke)
  RS-->>V: filtered groups + selection
```

**Proposed:**

```mermaid
sequenceDiagram
  participant TF as TextField (Main)
  participant C as PanelController (Main)
  participant S as SearchService (actor)
  participant D as SearchIndexStore / search-index.sqlite
  participant ST as CommandBarState (Main)
  TF->>C: rawInput changed (sync, assign only) [changed]
  C->>C: seq += 1, cancel previous task [added]
  C->>S: await search(query, seq) [added, async]
  alt 3+ characters
    S->>D: FTS5 trigram candidates (read) [added]
    D-->>S: ≤200 documents
  end
  S->>S: + live & memory-resident matches, fuzzy re-rank, group [moved off main]
  S-->>C: SearchResultSet(seq)
  C->>C: seq == latest? else drop [added]
  C->>ST: apply result set + reconcile selection [changed]
  Note over ST: availability guard (R8) at apply: drop items<br/>whose repo/worktree is now unavailable (keyed reads)
```

**Edge changes:**

| Edge | Change |
|---|---|
| body → `snapshot` → `filter` | removed from the keystroke path |
| controller → service | added, async |
| service → its own index read | added; the index lives in the service's own file, so no datastore round trip on the keystroke path |
| apply with sequence guard | added |
| the empty-query projection | **intentionally unchanged**, on MainActor (R4) |
| selection reconcile | **intentionally unchanged** in rule; now runs on apply |

## Call paths: a worktree or branch changes

```mermaid
flowchart LR
  A["Topology or branch fact published<br/>(WorkspaceCacheCoordinator → atoms)"] --> B["RepositoryTopologyStore / RepoCacheStore<br/>observe, debounce 500 ms (unchanged)"]
  B --> C["WorkspaceSQLiteDatastoreActor<br/>saveRepositoryTopologySnapshot / saveRepoCacheState (unchanged)"]
  C -- "after commit: indexedFactsCommitted [added]" --> D["SearchService actor"]
  D --> E[("search-index.sqlite<br/>keyed upsert + FTS5, no triggers [added]")]
  D --> F["memory-resident mirror<br/>same actor turn [added]"]
```

The worst-case freshness is the 500 ms debounce plus one write, which is under R11's 1 s. Scoped topology already calls `flushAsync` on revision changes (`WorkspaceCacheCoordinator+ScopedTopology.swift:84-96`), which shortens the add and remove path.

## Query lifecycle

```mermaid
stateDiagram-v2
  [*] --> Pending: keystroke (seq n)
  Pending --> Answered: result(seq n) and n == latest
  Pending --> Superseded: keystroke (seq n+1) arrives first
  Superseded --> Dropped: result(seq n) arrives later
  Answered --> Applied: MainActor applies + availability guard
  Applied --> [*]
  Dropped --> [*]
```

**Illegal:** applying a result whose sequence isn't the latest. This is rejected at the single apply entry, the controller's guard, and enforced by an automated test.

**Retained root query (E6):** `CommandBarState` records the text on dismiss when the scope is root, no level is pushed and there is no prefix. `show(defaultScope:)` restores it and asks the field to select all. `show(prefix:)` and `switchPrefix` ignore it. It is never persisted (R12).

## Failure, recovery, concurrency

| Situation | Detection | Containment and recovery | Owner |
|---|---|---|---|
| F1: index missing, stale version, unparseable row or corrupt | `index_version` check when the service opens the file; a parse or read error during a query | the query answers from memory-resident and live documents; the service deletes the file and runs `rebuildFromPersistedRows`; a trace attribute records the degraded answer | `SearchService` (degrade and rebuild) |
| Index write fails after a save | error from `apply(facts)` on the search actor | the save already committed and is unaffected; the service marks the index stale and rebuilds it | `SearchService` |
| F2: overlapping queries | sequence numbers | the actor answers each; the controller drops stale ones; the previous task is cancelled (cooperative, a best-effort saving) | controller |
| F3: an item withdrawn while shown | availability guard on apply; the next index write removes the row | a stale row is dropped at apply; ↵ on a withdrawn entity follows today's handling | controller + contributors |
| F5: restart | the index persists in search-index.sqlite | the first query is answered from the index before any scan; the memory-resident mirror loads from the index at service start | `SearchService` |
| Reentrancy | actor awaits the datastore read | an interleaved newer query is harmless because results are tagged; the live and mirror sets are replaced atomically inside the actor | `SearchService` |
| Writer vs reader | WAL (`SQLiteDatabaseFactory`) | readers don't block the writer; the FTS query sees the last committed write | SQLite |

## Cross-cutting realization

| Obligation | Realization | Proof seam |
|---|---|---|
| R13 off main by construction | `SearchService` is an actor; the fuzzy ranker is a `private` type in `Core/Search/` (a different module from CommandBar); the command bar's only path is `await search` | static: the CommandBar module cannot reference the ranker (compile error); `Infrastructure/Search/CommandBarSearch.swift` is deleted in the same change (hard cutover, no second matcher) |
| R10 budgets | MainActor work = assign + submit + apply(O(results)); ranking off main; candidates capped at 200 | new spans `performance.search.query` (duration, kind counts, index hit or degraded) and `performance.commandbar.apply` (MainActor duration), read by a marker-scoped debug run plus a 10k-document synthetic benchmark in the existing `test:swift:benchmark` lane |
| R11 freshness | index writes ride the existing saves (≤ 500 ms + write) | span `performance.search.index_write` with its lag since the fact was published |
| Privacy | local-only; documents hold names, folder names, tags and branches already stored | not applicable beyond this |
| Accessibility | result rows keep today's labels; the restored query is the field value | manual VoiceOver spot check |

## How each requirement works and how we verify it

| Obligation | Realized by | Proof |
|---|---|---|
| R1 R2 R3 | worktree and repo contributors + FTS5 + ranker | service tests with real documents over an in-memory `DatabaseQueue` (as `WorkspaceCoreRepositoryTestSupport` does): name, folder, branch hits; no repo hit via worktree names; no full-path hit |
| R4 | unchanged MainActor empty projection | the existing `CommandBarResultSessionTests`, unchanged |
| R5 R6 R7 | `SearchService` short-query rule, ranker, grouping | service tests (`agvmoa`, 1–2 characters without index access, group order) |
| R8 | contributor availability + apply guard | a controller test where an item turns unavailable between query and apply |
| R9 | sequence guard | a controller test with out-of-order answers from a controlled service fake |
| R10 R11 | spans + benchmark | measurement (marker-scoped debug run, synthetic 10k) |
| R12 | `CommandBarState` retained query | controller tests (esc, ↵, prefix, nested, restart) |
| R13 | module and private type | compile-time (no call path exists) |
| R14 | `SearchKind` declaration | test: a test-only live kind appears, and existing kinds' results are unchanged |
| R15, F1, F5 | feed + index store + rebuild | integration test: a real datastore save → `indexedFactsCommitted` → entry rows; an unknown `kind` text or a stale `index_version` → file replaced and rebuilt, never defaulted; a reopened index answers before any topology event |

What is real and what is replaced in the proofs:
- **Real in service and integration tests:** SQLite/GRDB (in-memory or temp file) and the ranker.
- **Replaced only in controller tests:** the service, faked to control answer order.

The UI change the user sees is the Requirements visual (`assets/find-today-vs-after.png`); nothing else in the UI changes.
