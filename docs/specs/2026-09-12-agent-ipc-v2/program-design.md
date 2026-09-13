# Agent IPC v2 and Agent Package — Program Design

Date: 2026-09-13. Source baseline: `ipc-improvements@85ae48f5e`.
Requirements: [user-requirements.md](user-requirements.md).
Specification: [specification.md](specification.md).
Decisions: [decision-record.md](decision-record.md).

## Integrated design

Keep the Unix socket, typed App ports, command identities, workspace mutation
pipeline and prepared application-local SQLite database. ProgrammaticControl
owns shared method descriptors. The server registers them with handlers; the
bundled Swift `agentstudio` CLI compiles those same definitions for invocation,
validation and help. ClientCore remains the Swift transport/client library.
Sessions owns report ingestion, evidence reduction, durable messages and queries.
App composition joins these owners and drains offline notifications without a new UI.

```text
Provider hooks / installed model skill
                 |
      agentstudio CLI + retained ClientCore
        |                   |
        | notification only | shared compiled descriptors
        v                   v
 owner-only spool    Unix socket -> AppIPC admission
        |                          |             |
        +---- launch drain --------+             |
                              App typed ports    |
                              /             \    |
                    SessionsIngestion      debugTesting adapter
                         |                       |
                reducer + repository       existing command/runtime owners
                         |
                  Core prepared SQLite
                         |
                 Sessions query / explicit acknowledgment

Typed terminal facts -> Contract 7 -> named App subscriber -> SessionsIngestion
Stable/beta registry excludes debugTesting; pane authority cannot enable it.
```

Transport receipt, queued notification, durable admission and current evidence are
separate outcomes. A queued notification survives through files until database
commit; a late fact never acquires current authority merely by arriving later.

## Current foundation

| Current source | Observed behavior and consequence |
| --- | --- |
| [IPC boot](../../../Sources/AgentStudio/App/Boot/AppDelegate+IPC.swift) | Composes concrete adapters, runtime identity, service and socket. Attach Sessions and continuity ports after database preparation; preserve debug launch identity and failure isolation. |
| [Server](../../../Sources/AgentStudioAppIPC/AgentStudioAppIPCServer.swift), [routing](../../../Sources/AgentStudioAppIPC/AgentStudioAppIPCServer+AuthenticatedRouting.swift) | Peer UID, frames, authentication and typed ports already exist. Replace shape duplication and handle rewriting within this pipeline; do not add a listener. |
| [Contracts](../../../Sources/AgentStudioProgrammaticControl/IPCContracts.swift) | Schema descriptions currently name an object without its full fields. Replace placeholders with typed schemas, examples, target kinds, relationships and exposure metadata. |
| [Authentication](../../../Sources/AgentStudioAppIPC/AgentStudioIPCAuthentication.swift) | Pane authentication currently consumes an in-memory token. Use reusable pane verifiers with durable scope/generation metadata; replace single-use debug escrow with Y's reusable runtime-bound verifier credential. |
| [Terminal startup](../../../Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+ViewLifecycle.swift), [surface](../../../Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift) | Startup supplies zmx isolation, then copies environment into C strings for surface creation. Prepare pane identity asynchronously before that existing memory-only handoff. |
| [Zmx backend](../../../Sources/AgentStudio/Core/RuntimeEventSystem/Runtime/ZmxBackend.swift) | First attach starts the pane daemon; reattachment preserves an existing shell. Verified at pinned zmx 8bab1f0173b07e79835ea372d749af3dbf0d0842: src/daemonize.zig:74 executes execvpeZ(cmd.file, cmd.argv_ptr, std.c.environ). Fresh-shell inheritance needs no vendor change; reattachment cannot rewrite an existing shell's environment. |
| [IPC projection](../../../Sources/AgentStudio/App/Commands/AppCommand+IPCProjection.swift), [dispatcher](../../../Sources/AgentStudio/App/Commands/AppCommandDispatcher.swift) | Exhaustive AppCommand classification and execution remain their respective owners. Extend typed headless arguments without a second command identity catalog. |
| [Datastore actor](../../../Sources/AgentStudio/Core/State/SQLite/WorkspaceSQLiteDatastoreActor.swift) | Owns one prepared local database. Existing performLocalSaveOperation emits Inbox-labeled tracing; add a neutral prepared application-local transaction entry instead of borrowing that lane. |
| [Client core](../../../Sources/AgentStudioIPCClientCore/AgentStudioIPCClientCore.swift), [arguments](../../../Sources/AgentStudioIPCClientCore/AgentStudioIPCClientArguments.swift), [package](../../../Package.swift) | Retain framing, response-ID validation and client library/test ownership. Replace hand-mapped phase-1 verbs with descriptor-driven parsing; reuse the thin executable target for the agentstudio product. |

The old debug client required hand-mapped verbs, manually assembled JSON and
socket/token-input ceremony; incomplete schemas could not explain valid calls.
Shared typed descriptors supply executable help and correction data. Pane env supplies agent context; debug invocation automatically discovers trusted
runtime metadata and ClientCore reads the reusable credential on each call,
without token argv or manual socket/path assembly. This removes
repeated plumbing while preserving the server's channel and authority gates.

## Owners and placement

```text
Component / placement                       Responsibility and reason to change

IPCMethodDefinition + typed schema          Protocol shapes, model-call metadata,
  AgentStudioProgrammaticControl            exposure, examples; protocol evolution

IPCDebugLocationContract                    Fixed debug registry directory and entry
  AgentStudioProgrammaticControl            shape (runtime/socket/data root/credential
                                            file); App/CLI; discovery contract changes

agentstudio thin executable                 Descriptor-driven argv/stdin/help and
  existing AgentStudioIPCClient target       short model replies; invocation UX

ClientCore                                 Socket/auth/response IDs, correlation,
  AgentStudioIPCClientCore                   notification-only spool fallback; client behavior

AppIPCMethodRegistry + IPCRequestAdmission  Typed registration, target/auth gates,
  AgentStudioAppIPC                         replay and handler dispatch; admission

AgentStudioIPCPrincipalRegistry            Pane/debug verifier lookup and shared lease gate;
  AgentStudioAppIPC                         authority and connection revocation

PaneIPCIdentityOwner actor                  Environment preparation, verifier life,
  App/PaneAgents                            pane retirement; pane authority lifecycle

IPCContinuityRepository                     Pane/debug verifiers and control operation journal;
  App/PaneAgents                            continuity SQL, not domain evidence

PaneReportSpool actor                       Claim/drain/acknowledge notifications;
  App/PaneAgents                            offline admission lifecycle

LockedRequestSpool                         Lock, append, durable file replacement;
  AgentStudioIPCTransport                   generic local-file mechanics only

SessionsIngestion actor                    Ordered binding/report/ack/source-end;
  Features/Sessions/Runtime                 domain admission and queue policy

SessionsEvidenceReducer                    Pure matching, precedence and transitions;
  Features/Sessions/Models                  evidence semantics

SessionsRepository                         Domain transactions and snapshot queries;
  Features/Sessions/State/SQLite            durable Sessions data

ProviderAdapterRegistry                    Built-in exact-version event profiles;
  Features/Sessions/Providers               native dialect and qualification

SessionsSQLiteAccess / IPC adapters         Translate ports and domain types;
  App/IPCComposition/Sessions               cross-target composition

SessionsTerminalFactSubscriber             Existing admitted facts to Sessions port;
  App/IPCComposition/Sessions               subscription lifetime and translation

AgentPackage                               Native install/config ownership, hooks,
  AgentPackage/                             shared model skill; provider installation
```

Add production target AgentStudioSessions and paired AgentStudioSessionsTests.
Sessions depends on Core, Infrastructure and GRDB; App depends on Sessions.
Sessions imports no sibling Feature, AppIPC or ProgrammaticControl. App-only
adapters translate protocol types into domain types. ProgrammaticControl stays
Foundation-only and cannot import Core's AppCommand. App explicitly depends on
Transport for spool primitives and GRDB for database adapters where required.
ClientCore and its tests remain; the existing executable target can be renamed
without adding another executable layer. Transport contains no Sessions schema,
provider, authority or retention policy.

App boot owns one identity actor, spool actor, ingestion actor and named terminal
subscriber, including shutdown. There are no per-conversation actors/timers,
new atoms, snapshot Store wrappers, event families or generic coordinator.
WorkspaceSurfaceCoordinator receives only a prepared mount-attempt environment
and a semantic-close retirement handoff; it gains no evidence or spool policy.
Repositories use the same Core-prepared database and never open another pool.

### Interfaces and concurrency

Proposed names describe contracts rather than existing APIs:

- `IPCMethodDefinition<Params, Result>` contains typed schema, name, examples,
  exposure, privilege/data scope, allowed target kinds, command relationship,
  mutation flag, offline-eligibility classification and optional model-call projection. Server composition attaches
  a typed handler separately; schema decoding returns field correction data.
- `IPCRequestAdmission.admit` accepts immutable request and authenticated context,
  checks channel/schema/correlation/target/authority, then replays or invokes one
  handler. Domain ports are async Sendable ports; they are not blanket MainActor.
- `PaneIPCIdentityOwner.prepareEnvironment` validates canonical pane membership,
  commits verifier metadata and returns memory-only env for a mount attempt.
  It sets AGENTSTUDIO_CLI to its owning bundle's absolute executable path and
  prepends that directory to the inherited PATH together with pane identity;
  stable/beta/debug credentials and CLI location therefore share an issuer.
  `retire` closes leases before joining admitted work and ordering source end;
  it never deletes spool or quarantine files.
- `SessionsIngestion.submit` accepts a normalized report plus server-issued
  scope/origin/freshness. One non-reentrant FIFO consumer serializes bind,
  report, acknowledgment and source-end across awaited database work.
- `SessionsRepository.apply` reads prior context and runs an ingestion-supplied
  pure reduction closure inside one transaction, committing domain mutations,
  correlation deduplication and source cursor together. Failure advances none.
- `SessionsSQLiteAccess` injects synchronous Database transaction closures with
  Sendable results through Core's neutral prepared-local operation. Database
  handles never escape; Core never imports Sessions types.
- `PaneReportSpool.drain` claims a file generation under the shared lock, submits
  each eligible notification through normal admission with an offline context, and removes
  only committed/duplicate lines. No lock spans an awaited database operation.

The principal registry's existing lock owns a shared generation/lease gate.
Canonical-pane snapshots come through a narrow App-injected MainActor read
port; effects revalidate pane lifetime at the native owner immediately before
application. MainActor applies compact validated state/native operations.
Blocking files use explicit off-main helpers (`@concurrent nonisolated` where
needed under Swift 6.2); admission, reduction and deadlines stay off-main.

## Descriptor, CLI and authority composition

The schema algebra covers objects, arrays, scalars, nullability and typed
alternatives. Field descriptors bind decoding, requiredness, defaults, bounds,
examples and JSON Schema projection so documentation cannot invent absent fields.
Product limits live in AppPolicies and enter composed metadata as values.
Open strings at the wire boundary preserve unknown-method/command errors.

Shared method descriptors and typed command-argument variants compile into both
CLI and server dependencies. App's exhaustive ipcSpec remains the sole mapping
from AppCommand identity to exposure, argument variant and target/privilege.
For command.execute, the CLI uses the shared method/variant decoders and the
live command.list/system.capabilities projection to validate an open commandId.
It does not duplicate Core identities or import App. Runtime capability data
is distinct from a JSON build input. There is no JSON export generation step,
CLI parity gate or second hand-written method/argument map.

The live registry returns protocol/catalog compatibility identity, complete
available schemas, examples, privileges, target kinds, command relationship
and qualified provider profiles. Metadata projects to later MCP tools without
an MCP server or SDK now. Curated methods declare reused AppCommand identity
or noInteractiveIdentity. App's exhaustive ipcSpec switch provides a typed debug
argument variant for every AppCommand, including interactive cases; debug
composition merges every variant, while stable/beta merge only admitted headless
variants. The CLI derives plain-argument invocation from this same projection.
No default branch or missing-argument placeholder can stand in for a command.

Picker-backed execution names selections explicitly: repo/worktree IDs for
openWorktree/openWorktreeInPane, destination tab ID for movePaneToTab, names for
rename actions, and explicit pane/window context where focus previously selected
an owner. Selection commands validate those IDs through the existing owner;
they do not open a picker and assume selection. Presentation-only variants
include showCommandBarEverything/QuickOpen/Commands/Panes/Repos, filterSidebar,
and openPaneLocationInEditorMenu; their typed context selects the presenting
window/pane and their result is presented, never completion of the later user
action. Authentication presentation reports initiation, not sign-in completion.
Every identity reaches its existing dispatcher/owner; dormant feature commands
return typed unavailable without reviving Inbox or adding file.open internals.
The command catalog's interactive presence is never execution authority.

The CLI offers descriptor-derived catalog method invocation with --json/stdin
and structured results. Shared modelCall metadata additionally projects the
small scalar vocabulary in Specification C3. This is one semantic descriptor
set with two input/output presentations. The CLI supplies self and correlation;
the app derives bound conversation/source/turn context. `needs-you` upserts one
current deliberate assertion; `needs-you --clear` resolves that assertion in
its generation; `done` coalesces the current episode's AGENT REPORTED result.
The model vocabulary is message, needs-you, needs-you --clear and done;
message is the sole message-text verb, with no separate message kind for a note.
Needs-you explanation is private durable content associated with attention;
it is never interpolated into logs. Missing context yields a short binding
failure, not a request for model-authored IDs. Default reply rendering emits
one controlled line such as saved/queued/rejected, with explicit detail mode
for full tooling output. It never implicitly discovers and prints a catalog.

Production pane principals have self baseline only. Target parsing shares
self/UUID/pane:N spellings but dispatch uses each method's declared kind and
canonical data ownership. A message, conversation or request ID is not authority.
Cross-pane/workspace requests return missingGrant; there is no grant issuance.

Debug composition contributes every AppCommand's typed debug variant plus the
curated layout, terminal, bridge.*, ui.*, snapshot and session.message.ack
methods. The acknowledgment port accepts only the in-process App entry reserved
for future Sessions UI or the debug testing principal; pane principals remain
denied. Stable/beta omit/refuse debug-only variants, retaining their admitted
headless command variants. Server channel decides composition, never a CLI flag.

Debug startup replaces single-use escrow with one reusable random credential.
IPCContinuityRepository persists its SHA-256 verifier, runtime ID, credential
generation and status; the principal registry verifies it without consuming it.
A 0600 owner-only file holds the raw debug credential for ClientCore to read on
every invocation. This Y-authorized debug-only file is distinct from pane-token
policy: pane bearers still never persist. Publish runtime metadata only after
verifier/file setup succeeds. A failed setup reports debug auth unavailable;
it never enables unsafe auth. Each CLI call can connect, authenticate, execute
and disconnect without changing the file or generation.

Shutdown first revokes the generation/active connections, then deletes the
runtime-owned credential file. Replacement invalidates the old generation and
removes only its owned file before publishing the new runtime/credential;
stale cleanup must not delete a replacement's file. Crash leftovers authenticate
against no current runtime: next startup invalidates stale runtime verifiers and
replaces its owned file before publishing readiness. Stable/beta never create
this file. Unsafe-no-auth remains a separately explicit opt-in only.

For debug verbs, IPCDebugLocationContract in ProgrammaticControl owns the shared
Foundation-only registry location and entry shape. Use a fixed per-user,
channel-scoped directory `~/.agentstudio-debug-runtime-registry/`, independent
of AGENTSTUDIO_DATA_DIR and every per-run root. Directory mode is 0700; each
`<runtimeID>.json` entry is 0600 and names runtime ID, debug channel, socket path,
data root and credential-file location. These are locations, never the raw
credential. App boot / IPC server composition publishes its own entry atomically
only after socket and credential readiness; shutdown/replacement removes only
that runtime's entry. The repo launcher need not know this registry: its app
registers itself even when the launcher relocates data/socket roots, as
[scripts/run-debug-observability.sh](../../../scripts/run-debug-observability.sh)
does for per-worktree and traced runs.

The CLI enumerates this shared registry from an unrelated shell, validates
owner/channel and probes socket liveness/runtime identity before reading the
credential. One matching live entry is selected automatically; multiple live
entries produce a short list and require explicit runtime selection. A dead
entry is pruned only after a dead probe, and only if its identity/content still
matches the inspected entry; a live mismatched runtime is not deleted or guessed.
No live entries returns a concise start instruction. App/CLI share the location
contract without importing AppIPC into the CLI. AppIPC owns server-side registry
publication/removal; ClientCore owns enumeration/probe/selection. Stable/beta
neither publish nor use this debug registry as pane authority. Unsafe auth
remains explicit opt-in. Ordinary report/message calls use pane env authority;
debug intent selects this separate discovery path.

Descriptor projections provide plain debug arguments (for example split with a
pane handle, terminal send with text, command.execute with command ID and typed
scalars). Defaults select the discovered runtime, not a guessed target. Replies
are one-line applied/presented/unavailable or concise requested snapshot readback;
explicit detail returns structured tooling output. Repoint existing terminal and
sidebar/grouping proof consumers at this CLI. The installed skill must suffice
for the Haiku/Luna-class start/discover/split/send/command/snapshot proof.

### Credential lifetime

Generate 256-bit random pane credentials; persist only a SHA-256 verifier,
canonical pane/workspace, durable IPC generation and status. Raw credentials
travel only in memory and shell env. Preparing a mount commits before exposing
env; a cancelled mount retires its unused candidate. Restored shells keep their
existing credential, so reattachment alone must not rotate it. Explicitly
replacing a credential marks the old verifier superseded. Unknown tokens and
forged pane scope are rejected, not classified as superseded.

```text
CREDENTIAL / SOURCE LIFETIMES (separate identities)
Prepared candidate -> active pane credential -> superseded -> report-only late
                                |                  |
                         semantic pane close ------+-> revoked

active credential + admitted session.bind -> current reporting generation
app/source loss -> generation ended/stale; new binding -> fresh generation
restored credential continuity does not revive old reporting authority
```

Superseded verification yields a lateReportOnly context for eligible reports
under the original same-UID pane scope. Controls and current-authority reads
require re-identification. Pane close stops leases, invalidates connections,
joins admitted reports and orders source end. Canonical membership checks
prevent a crash between close and verifier cleanup from resurrecting authority.
Undo/recreate uses a fresh IPC generation. Filesystem spool admission is a
separate same-UID trust boundary, not an unauthenticated network endpoint.
Neither env bearer nor owner-only files identify a benevolent same-user process.

## Sessions state and persistence

Sessions binds provider-native conversation identity to the authenticated pane,
not a pane claimed in the payload. Profiles qualify exact provider/version/event
semantics and emit only bounded normalized fields; raw hook bodies and
transcripts are not stored. Server-assigned origin is REPORTED for qualified
native facts, AGENT REPORTED for deliberate calls and ESTIMATED for qualified
revocable inference. A missing profile remains unknown.

### Binding admission

SessionsIngestion's FIFO is the sole bind transition owner; arrival order alone
never authorizes replacement. The transaction reads current binding and ended
source generations, applies the rules below, and commits binding/source changes
and sessions_operation outcome atomically. A native transition requires qualified
provider session-start evidence identifying a new occurrence/generation; an
explicit model bind can establish/replace with visibly AGENT REPORTED authority.
Neither implicit model reports nor a bare competing conversation ID is a bind.

| Prior context / input | Admission and generation result |
| --- | --- |
| Absent + valid bind | Establish current binding and issue a new generation with the admitted origin. |
| Current B + repeated B in its current generation | Idempotent current binding; no new generation, even with a new correlation. |
| Current A + new B with qualified session-start or explicit model bind | End A's generation and establish B's new generation atomically; model authority is AGENT REPORTED, not provider evidence. |
| Ended/older A generation arriving after B | Historical-only outcome; never replace B, including delayed A reports. |
| Competing identity without qualified transition | bindingConflict; preserve current binding and return correction data. |
| Same correlation replay | Return recorded original outcome after authority check; do not re-run transition. |
| Matching source end | End that generation; no invented completion or automatic resurrection. |
| App restart | Restore associations/history but end their generations; first qualified bind creates a fresh generation, subsequent same-current bind repeats idempotently. |

The older-generation check precedes replacement permission. A new session-start
occurrence (or an explicit fresh model bind) must be distinguishable from replay
of an ended generation; a profile unable to establish that ordering cannot
assert provider replacement and returns bindingConflict. Delayed same-correlation
A returns its old outcome but never changes current B. Identifier-free reports
read the resulting admitted current context; source-qualified delayed reports
remain historical. This preserves the existing descendant/precedence limits.

The Agent Sessions Specification, 2026-08-03, branch sessions-in-sidebar,
Agent State Contract supplies matching and precedence semantics retained in
Specification C5. For a current capability/turn, REPORTED outranks AGENT
REPORTED, which outranks ESTIMATED. One completion result per matching turn
can be upgraded without resetting seen. Provider-identified tool/child completion is not root done. Identifier-free
deliberate descendant calls share the pane's one assertion/episode. The reducer
applies origin precedence before state selection: AGENT REPORTED child done
cannot displace a REPORTED running root turn; the developer sees RUNNING. Child
needs-you displaces nothing stronger than AGENT REPORTED. Without provider facts,
a child done may yield DONE labeled AGENT REPORTED. The shipped skill instructs
subagents not to call done/needs-you; no new identity mechanism is introduced.

```text
BOUND SOURCE -> normalized evidence -> pure reducer -> durable projections

first filter by matching context and origin precedence
current actionable condition? -> NEEDS YOU
else matching completion?     -> DONE
else current activity?        -> RUNNING
else                         -> UNKNOWN

matching clear -> remove only that condition -> recompute from remaining facts
abort          -> end matching activity; no completion result
source loss    -> native unresolved attention stale; deliberate help not current
old turn / ended generation / offline late -> history only, never current clear
query / focus / input -> no acknowledgment and no attention resolution
explicit user acknowledgment(message occurrence) -> that message seen only
```

Provider request identity and model deliberate assertion identity are separate.
The app creates an assertion ID for a bound conversation/generation and retains
it while that assertion is current; clear resolves it atomically. A native
identifierless prompt needs a qualified matching/revalidation rule before its
resolution can be claimed. App-minted IDs alone supply no such evidence.
Offline notifications retain original binding/source metadata when available.
When a drained notification's pane/binding no longer resolves, ingestion stores
it durably as an unattributed message: original pane UUID retained, conversation
unknown, disposition unattributed, original text/report content preserved.
Missing attribution is a successful durable outcome, never a rejection or drop;
a database failure still leaves the line pending for retry. It creates no live
attention/completion and never borrows a replacement conversation. Queries expose
unattributed messages to the authorized App/debug reader; an unresolvable pane
cannot invent new authority. Domain outcome and correlation commit atomically.

| Table | Durable responsibility |
| --- | --- |
| local_ipc_credential | Typed pane or diagnostic scope: pane/workspace + IPC generation, or debug runtime + credential generation; SHA-256 verifier and status only, never raw bearer. |
| local_ipc_operation | Control correlation, stable caller scope, optional canonical target, semantic fingerprint and reserved/started/final outcome. |
| sessions_conversation | Native/provider identity and durable conversation attribution. |
| sessions_pane_binding | Pane/conversation association and binding revisions/generations. |
| sessions_source | Qualified source context, cursor, liveness and ended generation. |
| sessions_evidence | Compact normalized evidence needed for reduction, not a general raw event log. |
| sessions_message | One agent-message kind, exact text/report content, occurrence, retained pane UUID, nullable conversation, attributed/unattributed disposition, optional attention association and explicit seen disposition. |
| sessions_attention | Request identity, private explanation association, source/turn/generation and current/resolved/stale disposition. |
| sessions_result | One matching completion result per turn with origin and durable seen disposition. |
| sessions_operation | Atomic report/ack correlation deduplication and domain outcome. |
| sessions_loss | Live-ingress state-overload counts/disposition and disclosed health only; no offline role. |

Core's WorkspaceLocalMigrations owns additive schema migrations and its existing
prepared writer/pool. SessionsRepository owns Sessions SQL; IPCContinuityRepository
owns IPC SQL. No Inbox transformation, save lane or startup wiring is reused.
Messages, seen and attention survive rebuilding derived state. Query pages read
one committed snapshot and carry revision/cursor; stale cursors request refresh.
Unknown or unauthorized message acknowledgment fails without mutation. Sender
receipt and result upgrades never reset the explicit user disposition.

## Offline spool and live admission

App obtains its data root from
[AppDataPaths.rootDirectory(...)](../../../Sources/AgentStudio/Infrastructure/AppDataPaths.swift).
The existing [AgentStudioIPCPathResolver](../../../Sources/AgentStudioAppIPC/AgentStudioIPCPaths.swift)
alone derives `<root>/ipc/spool/v2/`; its composed path is delivered as
AGENTSTUDIO_IPC_SPOOL_DIR. The CLI consumes that env value without a second
root-derivation implementation. Each canonical pane has one owner-only
`<paneUUID>.notifications.ndjson` and `<paneUUID>.lock`. Shared descriptors
classify offline eligibility: only messages and deliberate needs-you/done
reports are eligible. needs-you --clear is an offline-ineligible command: ClientCore returns
“Can't clear while Agent Studio is offline.” and appends nothing.
Controls, queries, auth, needs-you --clear and hook lifecycle facts are ineligible. ClientCore
applies spool fallback only to eligible notification descriptors; admission
rechecks that classification before drain dispatch so an injected command line
cannot execute. Classification follows the report variant when a method has
multiple variants, not merely the outer method name.

Notifications here mean “what happened,” not JSON-RPC's no-response envelope.
Files contain the exact JSON-RPC request lines, including correlation and
reportedAt/source context in params. No bearer or auth frame goes on disk.
App unreachability permits queuing: a missing socket path, refused connection,
or dead/stale endpoint. The existing AgentStudioIPCSocketProbeOutcome.dead
in [IPC paths](../../../Sources/AgentStudioAppIPC/AgentStudioIPCPaths.swift)
is the server-side check; ClientCore applies the same shared probe semantics
through its transport dependency without importing AppIPC. An authenticated or
protocol-level rejection proves reachability and never queues. An ambiguous
disconnect after submission remains uncertain, not an offline resubmission. Hook lifecycle facts are dropped at the source while the app is down;
provider history remains their record. No offline state-fact collection or
loss-disclosure machinery exists in round 1.

LockedRequestSpool performs locked append and durable flush before queued success.
A partial append failure rolls back that incomplete tail and returns failure.
Crash after flush but before response is safe through correlation replay.
Notifications have no eviction cap: append or durable-accept failure is explicit,
and no notification is dropped. The existing frame acceptance limit still
applies; oversized input fails explicitly rather than truncating content.

```text
CLI notification -> live socket available -> common admission -> durable/rejected
          |
          + app unreachable -> lock -> append/flush -> queued
                                         |
App launch -> validate owner/path -> claim notification generation under lock
           -> check eligibility -> common scope/domain admission, forced late
           -> commit domain + correlation
           -> remove committed/duplicate line; retain uncommitted notification

controls / queries / auth / clear -> unreachable app: failure, never spool
hook lifecycle facts      -> unreachable app: source drop, provider continues
crash before commit -> retry claimed notification
crash after commit before line removal -> deduplicate, then remove
concurrent writer -> new active generation, untouched by old-file acknowledgment
```

Claim uses rename under the per-pane lock, allowing a fresh active file while
SQL runs. Completion uses file-generation/line identity, never a blind truncate
of a writer's current file. Recovery resumes claimed files. Malformed/ineligible
lines move durably to an owner-only per-pane quarantine before removal from
the claimed file; they are neither dispatched nor silently discarded.
PaneReportSpool owns this disposition and source-health disclosure. Quarantine
retains entries until an explicit later cleanup decision; AppPolicies bounds
quarantine admission to 128 entries per pane, never eviction. When full, the
drainer retains the offending and subsequent lines in the claimed spool and
reports quarantineFull source health. The round-1 operator route is documented
manual deletion of that pane's owner-only quarantine file while the app/drainer
is stopped; it explicitly discards quarantined malformed/ineligible entries,
not the retained notification spool. On next launch the drainer resumes, can
quarantine remaining offending lines and admits retained valid notifications. This bounds quarantine count without dropping notification content.
Only the drainer removes a pane's spool data files, after every line is durably
admitted or quarantined. Pane retirement never deletes them. At final drain,
after pane producers and drainer lock holders have quiesced, the drainer removes
the pane's spool data and .lock together; if writers/holders remain, final
teardown is deferred until they stop, avoiding replacement-lock inode races.
Quarantine survives that teardown until the documented operator cleanup. Admitted lines are removed
rather than retained as a permanent telemetry log. No lock spans awaited SQL.

Ingestion has bounded live queues: 256 per pane and 1024 globally. Messages and
deliberate reports are never eviction candidates: full queue/write failure
returns explicit rejection without claiming acceptance. For live lifecycle
state drops, persist sessions_loss before dropping and return a throttled/rejected
outcome for that request. sessions_loss is retained exclusively for this live
role. If persistence itself fails, reject admission and disclose unavailable
source health; never claim a durable loss receipt that was not committed. The
reducer consumes late deliberate reports only as history and preserves newer
live projections. Provider wrappers remain fail-open; durable failure is visible
without blocking provider control.

## Agent package

```text
AgentPackage/
  manifest.json                  package version and supported profiles
  skills/agentstudio/SKILL.md     env guard, scalar calls, one-line expectations
  providers/claude/              native plugin + hooks
  providers/codex/               hooks.json + plugin
  providers/cursor/              .cursor/hooks.json integration
  hooks/                        bounded provider projection -> agentstudio CLI
  installer/                    ownership-aware native config merge/remove
```

Hooks call the bundled CLI full JSON surface. The model skill teaches only C3's
small scalar calls and guard, without IDs, sequencing or catalog boilerplate;
it instructs subagents not to call done or needs-you.
Hooks and skill use AGENTSTUDIO_CLI from the identity owner's prepared env;
the package never hardcodes a bundle path or persists pane credentials in native
configuration. Bare agentstudio resolves through the same prepared PATH; a
missing/invalid AGENTSTUDIO_CLI fails the guard rather than selecting another
installed channel's executable. Installation manifests record exact owned additions, structural
keys and last installed values, not tokens or message text. Install/upgrade
preserves unrelated settings, avoids duplicate entries and reports conflicts.
Uninstall removes only still-owned additions; user-modified values remain with
an explicit conflict report. Missing executables/config access and inactive
native trust are per-provider outcomes, not global success. Native trust cannot
be bypassed by installation. pi/OpenCode are outside this package's first round.

## Call-path deltas

`+` added, `~` changed, `-` retired, `=` preserved. Typed outcomes return along
the initiating chain unless queued/durable distinction is shown explicitly.

```text
D1 PANE IDENTITY — R-01–R-03
Current: pane -> startup zmx env -> Ghostty -> shell without IPC identity
Target: = canonical allocation and geometry gate
        + identity actor -> verifier commit -> CLI absolute path/PATH + pane env
        = Ghostty C env copy -> zmx first shell inheritance
        - fd-bootstrap delivery
        + close -> lease retirement -> joined source end
Outcome: valid shell context or explicit unavailable integration; usable terminal.

D2 DESCRIPTOR / WIRE / CLI — R-04–R-10, R-23
Current: hand-mapped CLI -> auth/handle rewrite -> string routing -> typed port
Target: + same compiled descriptors -> Swift CLI parsing/help -> ClientCore
        = Unix framing, peer UID and response-ID checks
        ~ schema/channel/target/auth -> replay admission -> typed handler
        = App adapter -> existing owner -> typed result
        + stable correction data, correlation, complete discovery/MCP metadata
        - phase-1 verb mappings and executable product name
Outcome: declared accepted/applied/partial/uncertain boundary, not guessed effect.

D3 REPORTS / QUERIES — R-11, R-12, R-15–R-19, R-21, R-22
Current: no Sessions domain port
Target: + hook JSON or scalar CLI -> admission -> App translation
        + bind establish/repeat/replace/history/conflict -> atomic generation change
        + FIFO ingestion -> qualified normalization -> reducer/SQL transaction
        + message/query/explicit acknowledgment -> committed Sessions snapshot
        = Core database preparation, no Inbox save lane
Outcome: durable occurrence, honest state or explicit rejection/unknown capability.

D4 TERMINAL FACTS — R-15, R-16, R-21
Current: copied callback -> Contract 7 -> runtime apply -> semantic bus fact
Target: = source contraction and thin MainActor apply
        + named App subscriber -> off-main qualified projection -> D3
Lane: often (potentially >=10 events/minute); no new MainActor hop.
      Projection and Sessions admission run off-main after the existing hop.
Proof: S6/S8 marker-scoped queue depth, admitted/dropped counts and duration.
Outcome: qualified evidence or ignored/unverified disposition; no raw screen path.

D5 SPOOL / RESTART — R-03, R-09, R-18–R-20
Current: missing/refused/dead endpoint cannot deliver notification
Target: + descriptor eligibility -> CLI locked append/flush -> queued receipt
        + launch claim -> common late admission -> atomic SQL dedup/domain commit
        + unattributed durable fallback -> committed-line removal; retained quarantine
        + no command/clear or hook lifecycle buffering
Outcome: notification survives until accepted, or explicit append/admission failure.

D6 DEBUG CONTROL — R-02, R-05, R-13
Current: diagnostic auth + phase-1 client -> existing control ports
Target: = debug channel boundary and native execution owners
        ~ reusable runtime verifier/file -> per-call automatic CLI discovery/auth
        + every AppCommand debug variant -> same plain-argument CLI -> typed ports
        ~ existing smoke/verifier scripts use new CLI/context/help
        + stable/beta omission/refusal and pane-role negatives
Outcome: test readback proves the actual effect; input receipt alone does not.

D7 PACKAGE — R-14, R-22
Current: separate native integration setup
Target: + native install table -> exact ownership manifest -> per-provider outcome
        + hooks invoke bundled CLI; skill invokes scalar projections
        + idempotent upgrade/uninstall preserves unrelated or conflicting edits
        = provider trust and lifecycle; report failure is fail-open
Outcome: installed/active/qualified are separately observable.
```

Environment preparation precedes synchronous surface creation. App boot prepares
restored credential availability before restore; fresh pane action boundaries
await preparation using the existing placeholder/mount-attempt lifecycle.
No SQL enters Ghostty callbacks or synchronous terminal startup.

## Failure containment and replay

Control correlation uses a discriminated caller namespace, never a connection
ID: pane callers use pane UUID + durable IPC generation; diagnostic callers use
debug runtime ID + debug credential generation. The correlation ID completes
either key. Reconnect retains the diagnostic namespace; runtime replacement ends
it. Targetless presentation/workspace commands use that diagnostic key with no
invented pane target. Explicit unsafe diagnostic composition uses its runtime's
server-issued diagnostic generation, never a client-selected namespace. Store canonical target and semantic fingerprint immutably. Look
up correlation before resolving an ordinal anew; an identical ordinal retry
uses the recorded target. A different spelling must resolve to that identity
to be equivalent. Recheck current runtime/generation authority before exposing stored private
outcomes; replacement credentials cannot read/replay an old runtime namespace.
Equal concurrent calls join one server-owned task; conflicts fail before effects.

```text
CONTROL JOURNAL
absent -> reserved (durable) -> started (durable) -> native effect -> final outcome
                                  |
                        crash -> uncertain; never automatic redispatch
reserved after restart -> only explicit caller retry can resume
completed retry -> recorded outcome after current authority check
caller disconnect -> started work continues; receipt loss is not cancellation

TRUST / FAILURE CONTAINMENT
bytes -> peer UID/frame -> schema/channel -> principal/target -> admitted context
  reject at any gate: typed reason/correction, no effect
  reports -> bounded FIFO -> reduction + domain/dedup commit -> durable receipt
  controls -> started marker -> live lease + native owner -> final/partial/uncertain
  private text -> explicit SQLite/spool only -X-> JSONL/OTLP/logger
```

SQLite cannot atomically commit arbitrary terminal/native effects. Started to
uncertain avoids repeated non-idempotent execution, at the cost of an effect
possibly never having run. No boot worker replays controls. Reports and seen
acknowledgments commit their dedup row and domain change in one transaction and
therefore avoid that gap. No general transaction coordinator is introduced.

Close stops leases before source-end ordering; an old queued generation cannot
clear replacement attention. Queries see committed snapshots. Shutdown stops
new admission, ends read waits, joins started domain transactions and rejects
unaccepted memory work before closing listener/subscribers. Spool files retain
uncommitted work. No correctness rule depends on arbitrary sleep: use protocol
barriers, injected clocks and bounded state waits at proof seams.

## Cutover, reserved seam and protected boundaries

Ship one v2 catalog and the signed/notarized bundle CLI. Retire the phase-1
agentstudio-ipc verb executable and agentstudio-pane-agent fd helper. Retain
ClientCore, its client tests and reusable transport behavior; update them for
v2. Repoint proof consumers at agentstudio. No legacy parser or dual protocol
path remains. Package/catalog version mismatch fails before mutation. Rollback
is explicit compatible binary/package selection, not concurrent schema writers.
Feature migration failure makes integration unavailable without a false durable
receipt; existing Core database preparation/recovery remains authoritative.

The sole future file.open seam is an App/IPCComposition typed contribution to
the shared registry, declaring the reserved Specification C7 relationship when
later authorized. It has no registered descriptor, handler, CLI verb or current
realization here. This design selects no file-opening internals or functional
proof for that reserved contract.

Retain existing IPC programmatic-control/port/composition/import/atom-access
and surface-sanitization architecture rules. Extend their existing owning tool
for Sessions placement, complete schemas and forbidden payload logging rather
than add shell scanners. Constructor/schema tests establish descriptor validity;
no separate CLI export parity mechanism is needed. No IPC direct atom access,
renderer transport, zmx public methods, command facts bus or Inbox startup/write.

Content-safe probes use existing allowlisted tags: controlled provider/event
kinds, outcome/drop counts, queue depth and durations. Never raw identifiers,
paths, tokens, payload/error strings or message/explanation text. Marker-scoped
proof joins private query readback with scrubbed performance metrics. Changed
often/heavy lanes retain existing admission/hop/performance obligations; this
slice adds no UI observer or collector. Steering, Sessions UI, ACP, agent-to-agent,
banners, screen manifests, transcripts, answer-through, daemon/Rust core,
SDK/Rust CLI, remote transport and grant issuance remain outside the design.

## Requirement-to-owner and proof views

| Seam | Real driver, boundary and observation |
| --- | --- |
| S1 | Real pane shell/Ghostty/zmx env to authenticated socket: identity, scope, close and restart continuity. |
| S2 | In-process ClientCore and shell CLI to actual registry/ports: schema, errors, diagnostic targetless duplicate/conflict/reconnect/replacement replay, results and bundle identity. |
| S3 | Installed skill/scalar calls in bound agent context with AGENTSTUDIO_CLI/PATH and concurrent channel installs: no model-typed IDs/JSON, short replies, coalescing, ID-free clear and A→B/delayed-A/repeated-B/source-end/restart binding cases. |
| S4 | Haiku/Luna-class agent with only installed skill to real debug app: repo-launcher start, unrelated-shell registry discovery, two-runtime selection, split/send/command/snapshot; every typed AppCommand debug dispatch and honest presentation outcome; two sequential authenticated calls/disconnect, credential shutdown/replacement disposition, targetless replay/conflict and channel negatives. |
| S5 | Installer to isolated native config/provider entry points: exact ownership, activation and fail-open outcomes. |
| S6 | Exact-version native fixtures/Contract 7 to reducer: matching evidence, binding A→B then delayed A, repeated B/source end/restart, descendant precedence, generation loss and unknown capabilities; D4 often-lane marker-scoped queue depth, admitted/dropped counts and duration. |
| S7 | App-down CLI and restart to spool plus real SQLite: removed-socket and stale-socket-file unreachability, exact messages/deliberate reports, seen/attention, late ordering and crash boundaries; offline-ineligible clear/command negatives, unattributed fallback, quarantineFull → manual quarantine-file deletion → next-launch retained admission, final lock cleanup, debug-only acknowledgment and pane denial. Separately exercise live-overload disclosure. |
| S8 | Distinctive private input to real sinks/storage and architecture checks: no forbidden content or ownership crossings; D4 probes verify off-main admission with no added MainActor hop. |
| S9 | Boot/catalog/package inspection: explicit negative space remains absent; reserved contract stays unregistered. |

| Requirement | Owner | Specification contract; proof |
| --- | --- | --- |
| R-01 | PaneIPCIdentityOwner, CLI guard | C1; S1/V1 |
| R-02 | Principal registry, admission, debug composition | C1/C4; S1/S4/V1/V4 |
| R-03 | Identity owner, continuity repository, ingestion | C1/C6; S1/S7/V1/V7 |
| R-04 | Shared descriptors, registry, ClientCore | C2; S2/V2 |
| R-05 | ipcSpec, dispatcher, typed registered ports | C2/C4; S2/S4/V2/V4 |
| R-06 | Descriptors and discovery composition | C2; S2/V2 |
| R-07 | Schema/error projection and open wire identifiers | C2/C8; S2/V2 |
| R-08 | Typed target resolver and domain ownership lookup | C1/C2; S1/S2/V1/V2 |
| R-09 | CLI, admission, both operation repositories | C2/C3/C6; S2/S3/S7/V2/V3/V7 |
| R-10 | Shared descriptors, CLI, ClientCore, bundle packaging | C2; S2/V2 |
| R-11 | Model-call projection, ingestion context derivation | C3; S3/V3 |
| R-12 | CLI short reply renderer and installed skill | C3; S3/V3 |
| R-13 | Debug composition, registry exposure, CLI | C4; S4/V4 |
| R-14 | Native installer and ownership manifest | C5; S5/V5 |
| R-15 | Provider profiles and SessionsIngestion | C5; S6/V6 |
| R-16 | Reducer, profiles, Contract 7 subscriber | C5; S6/V6 |
| R-17 | Reducer, attention rows, model context projection | C3/C5; S3/S6/V3/V6 |
| R-18 | SessionsRepository, CLI/spool | C6; S7/V7 |
| R-19 | Repository, App/debug-only acknowledgment port | C6; S7/S8/V7/V8 |
| R-20 | Descriptor eligibility, ClientCore, spool actor, ingestion, live-only loss rows | C6/C8; S7/V7 |
| R-21 | Payload owners and sink allowlists | C3/C6/C8; S8/V8 |
| R-22 | Hooks, provider profiles, admission containment | C5/C8; S5/S6/V5/V6 |
| R-23 | Descriptor JSON/MCP metadata projection | C2; S2/V2 |
| R-24 | Boot, registry and package scope boundaries | C7; S9/V9 |

Pure parsing/reducer/normalization tests prove local decisions. Real IPC,
SQLite, provider events and native effect readback prove their connections;
a fake provider cannot qualify REPORTED evidence. Crash checks straddle append,
commit and line removal. Suspended report SQL plus pane close proves generation
retirement. Model token economy is reviewed beside schema DX, not inferred from
schema completeness. Required implementation gates remain future proof work.

## Approval inventory

| Category | Realization inventory |
| --- | --- |
| Targets/dependencies | AgentStudioSessions and paired tests; App depends on Sessions/Transport/GRDB; retained ClientCore/tests and reused thin Swift CLI target. |
| Contracts/composition | Shared typed/model-call/offline-eligibility descriptors, exhaustive ipcSpec, ProviderAdapterRegistry with exact-version qualification, IPCDebugLocationContract in ProgrammaticControl, Y reusable runtime-bound debug credential/automatic discovery, every AppCommand typed debug variant under Z, debug-only session.message.ack and reserved in-process App acknowledgment entry; existing IPC path resolver owns spool root. |
| Logic/derivation | SessionsEvidenceReducer owns pure matching, origin precedence and state/attention/result derivation. |
| Persistence owners | SessionsRepository and IPCContinuityRepository over one Core-prepared database; neutral transaction entry and eleven table families including diagnostic verifier/journal namespaces; sessions_loss is live-only; unattributed messages use sessions_message. |
| Actors/subscription | PaneIPCIdentityOwner, SessionsIngestion, PaneReportSpool; principal lease gate; named SessionsTerminalFactSubscriber, off-main often lane. |
| Coordinator responsibilities | Existing coordinator receives prepared environment/mount-attempt and semantic-close handoffs only. |
| Atoms/stores | None added; no new event family or coordinator class. |
| Files/package | LockedRequestSpool primitive, one notification file plus lock per pane with quiescent final-drain cleanup, drainer-owned quarantine/manual operator cleanup; fixed debug registry published by App server composition; native installers/ownership manifest and signed bundled CLI. |
| Retired items | Phase-1 agentstudio-ipc executable/verb mapping and fd-bootstrap helper and single-use debug escrow; ClientCore remains. |
| Policy values | Live admission queues 256/pane and 1024/global; quarantine admission 128 entries/pane, retained until documented manual operator deletion, full means retained spool plus source-health disclosure and next-launch recovery; no notification eviction or offline state cap. |

## Structural choices and limits

| Choice | Benefit and cost | Alternative and revisit signal |
| --- | --- | --- |
| Shared compiled descriptors, retained ClientCore | One protocol definition for Swift consumers; App still supplies runtime command identity/exposure because Core cannot enter the shared target. | A JSON-generated Swift client adds a build boundary and is excluded by T; reconsider only under a changed language/distribution contract. |
| Feature-owned Sessions with two repository responsibilities | Provider/domain policy stays out of IPC/Core; adds one Feature target and App translation ports, not another database. | Core ownership reduces one target but misplaces provider policy; revisit if a real shared-domain consumer needs these models. |
| Persist verifiers, not bearer credentials | Existing shells survive restart without disk bearer material; revocation and generation cleanup must be durable and canonical-membership checked. | Per-boot rotation breaks continuing-shell env; a different credential mechanism requires preserving that continuity without disk bearer material. |
| One notification spool per pane | Preserves messages and deliberate reports; requires locked generations and deduplication, with explicit storage failure instead of eviction. Hook lifecycle history while offline stays with the provider. | A daemon changes the accepted deployment boundary; revisit only when a later always-on collector is authorized. |
| Conservative control journal | Prevents speculative repeated effects; crash ambiguity can require caller reconciliation. | Automatic retry risks duplicated native effects; revisit only with an effect owner supplying durable idempotent application. |

Provider qualification remains incomplete: the recorded Cursor headless
2026.09.02-c22c1a3 runs establish sessionStart/sessionEnd only; interactive TUI
and unexercised hooks remain unverified, and absent events are not inferred.
Complete Claude/Codex exact-version matrices also remain evidence inputs.
Unknown capabilities remain explicit until those exact event and operating-mode
fixtures establish their semantics.
