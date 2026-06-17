# Notification Less-Spam Roll-Up Alerts Implementation Plan

Date: 2026-06-14
Status: plan-review revisions applied
Source spec: `docs/superpowers/specs/2026-06-14-notification-less-spam-rollup-alerts.md`
Baseline: `7b1ed70f`

2026-06-15 revision:
This plan now also owns the agent-settled attention state and the IPC-backed
debug proof lane discovered after `origin/main` brought in AgentStudio app IPC.
The original roll-up rule still stands: blue activity is row-only and never a
tab dot. Tab dots are attention-only: red action, amber safety, and yellow
settled-agent attention if the settled heuristic is valid and not revoked.

## Goal

Implement notification less-spam semantics from the reviewed spec:

- red/amber/blue row dots for unread action/safety/activity rows
- read rows show no dots and contribute to no chrome
- activity remains history-only and never counts in badges, chips, or tab dots
- action/safety roll up into global, worktree, pane, and tab chrome
- read state and inbox browsing preferences survive restart
- chrome-driven entry always explains the chrome that opened it
- agent-settled yellow dots are high-precision, provisional, and revoked if
  the agent continues before the user reads the row/scope
- IPC debug proof drives real terminal input and Victoria/Peekaboo verification
  for changed notification behavior
- final proof includes focused tests, full `mise run test`, `mise run lint`,
  Victoria debug observability, and PID-targeted Peekaboo when feasible

## Non-Goals

- No new notification ingestion path.
- No bridge API change.
- No terminal-output content parsing.
- No activity roll-up count.
- No blue tab activity dot.
- No yellow settled dot for non-agent panes.
- No yellow settled dot from the existing short terminal quiet-settled activity
  fact alone.
- No durable settled notification if later output invalidates the quiet state.
- No row background tinting by lane.
- No broad BridgeWeb, Terminal, AtomLib, release, or merge work.
- No compatibility shim that keeps old unread-count names for roll-up chrome.
- No Core tab-state notification storage. App may pass primitive render tokens
  into tab chrome, but Core tab models remain notification-free.

## Source Coverage

- `docs/superpowers/specs/2026-06-14-notification-less-spam-rollup-alerts.md`
  - `wc -l`: 778
  - read by controller in chunks: `1-220`, `221-520`, `521-778`, and
    post-review patched sections `180-380`
- `docs/architecture/agentstudio_ipc_architecture.md`
  - `wc -l`: 532
  - read by controller in chunks: `1-260` and `386-476`
  - live proof on 2026-06-15: fresh debug app `Agent Studio Debug akm3`,
    IPC `identify`, `capabilities`, `pane.list`, `pane.current`,
    `terminal.status pane:7`, `pane.focus pane:7`, and
    `terminal.send pane:7` succeeded; `terminal.wait commandFinished` timed
    out, confirming input acceptance is not shell-completion proof yet
- `docs/plans/2026-06-10-inbox-notification-correctness.md`
  - `wc -l`: 163
  - read in full
- `docs/superpowers/plans/2026-05-11-notification-claim-promoter.md`
  - `wc -l`: 220
  - read in full
- `AGENTS.md`
  - `wc -l`: 713
  - read in full

## Current-State Evidence

Post-merge current-state evidence must be refreshed before implementation
continues because this worktree already contains restored in-progress changes
from the pre-`origin/main` stash.

Already landed in the current worktree and treated as verify-only unless Task 0
finds an out-of-scope path:

- `MainWindowController`, `MainSplitViewController`, and
  `SidebarSurfaceHost` now show roll-up alert behavior in the live worktree.
- `WorkspaceNotificationCountProjection` has in-progress roll-up alert
  projection changes that feed multiple shell surfaces.
- The IPC/Victoria smoke path has been verified once on 2026-06-15 against
  `Agent Studio Debug akm3`; that proof is tool-shape evidence only and must be
  rerun for final proof.

Still requiring implementation audit or code changes:

- `InboxRow` must render unread row dots by lane: red action, amber safety,
  blue activity, and no row background tint.
- `PaneInboxNotificationPopover` and sidebar controls must hard-cut to the new
  content/read-scope model and read-all clearing semantics.
- `TabBarAdapter` currently reads `atom(\.inboxNotification)` directly while
  deriving tab items. Task 5 must remove that hidden feature coupling or replace
  it with an App-injected primitive token provider.
- `TabBarItem`/`CustomTabBar` must carry and render primitive red/amber/yellow
  attention tokens; blue activity must never appear on a tab.
- `TerminalActivityRouter` currently has no injected conservative agent-pane
  classifier beyond attended-pane state. Task 2a must add an App-composed
  classifier/policy input.
- `InboxSidebarState.pendingFilter` must support temporary chrome-driven
  content/read-scope overrides without overwriting persisted preferences.
- `WorkspaceSettingsStore` and inbox preference import paths must persist the
  new preference vocabulary and leave legacy behavior import-only.
- `InboxNotificationAtom` and `InboxNotificationSQLiteRepository` both enforce
  retention independently and need one shared feature-owned retention selector.
- Approval/security text can reach notification bodies through raw event fields;
  length truncation alone is not a safe summary for paths, secret ids, commands,
  prompts, or tool output.

Pre-implementation audit:

```bash
rg -n "globalRollUpAlertCount|visiblePaneInboxRollUpAlertCount|requestTemporaryOverride|rollUpAlertCount|atom\\(\\\\.inboxNotification\\)" Sources/AgentStudio Tests/AgentStudioTests
```

## Requirements / Proof Matrix

### R1. Producer correctness is fixed before roll-up chrome

Requirement or claim:
The June 10 inbox correctness work is Phase 0. Roll-up chrome must not be built
on producer state that still confuses observed panes with attended panes or lacks
read/dismiss round-trip proof.

Owning task:
Task 1.

Proof owner:
implementation executor plus parent verifier.

Proof gate:
`mise run test -- --filter "InboxNotificationRouterObservedPane|PaneFocusTracker|InboxNotificationAtom|InboxNotificationSQLiteRepository|InboxPromoter"` and the focused tests added or updated for attended-vs-observed auto-clear,
focus-tracker restart, coalescence predicate parity, manual unread clearing
pane dismissal, stronger-event reopen, and mark-read round-trip.

Proof layer:
unit + integration.

Stale-proof guard:
Run after Task 1 changes on current worktree; tests must exercise current
`InboxNotificationRouter`, `PaneFocusTracker`, atom, and SQLite repository code.

Red/green:
Required.

### R2. Lane and roll-up projection has one feature-owned source of truth

Requirement or claim:
Roll-up summaries reuse `InboxNotificationClaimLane`; consumers do not rescan
raw rows and invent lane semantics.

Owning task:
Task 2.

Proof owner:
implementation executor plus parent verifier.

Proof gate:
`mise run test -- --filter "InboxNotificationAtom|InboxNotificationClaim|InboxNotificationListModel"`.

Proof layer:
unit.

Stale-proof guard:
Tests must assert action/safety/activity mapping from current row/claim data and
fallback mapping for rows without claim keys.

Red/green:
Required for old activity-count behavior.

### R3. Activity never contributes to badges, chips, or tab dots

Requirement or claim:
Activity is a blue row dot only. It never affects global toolbar badge,
worktree/repo chips, Pane Inbox badge, group/header counts, or tab dots.

Owning task:
Tasks 2, 4, and 5.

Proof owner:
implementation executor plus parent verifier.

Proof gate:
`mise run test -- --filter "WorkspaceNotificationCountOwnership|MainWindowControllerInboxToolbarButton|PaneInboxPresentation|TabBarAdapter|InboxNotificationSidebarView|InboxNotificationListModel"`.

Proof layer:
unit + mounted/UI.

Stale-proof guard:
Run after final chrome wiring, not after only domain helpers.

Red/green:
Required. Existing tests that count activity as unread chrome should fail first.

### R4. Read/read-all clears every dot and persists

Requirement or claim:
Read rows show no red/amber/blue row dot and no roll-up chrome. Read-all clears
all dots in its write scope. Repo/worktree scope narrows writes; content mode and
row-state filters are view-only and do not narrow writes. Toggling a
pane-dismissed row back to unread clears pane dismissal. Any transition from
read back to unread clears `isDismissedFromPaneInbox`, including manual toggles
and stronger action/safety coalescence into a read row.

Owning task:
Tasks 2, 4, and 6.

Proof owner:
implementation executor plus parent verifier.

Proof gate:
`mise run test -- --filter "InboxNotificationAtom|InboxNotificationStore|InboxNotificationSQLiteRepository|InboxPromoter|AppDelegateInboxNotificationCommands|PaneInboxNotificationPopover|InboxNotificationSidebarView|PaneTabViewControllerPaneInboxCommand"`.

Proof layer:
unit + persistence + mounted/UI.

Stale-proof guard:
Tests must reload persisted rows from the current store/repository and assert
dots/chrome from rehydrated state.

Red/green:
Required.

### R5. Content modes and row-state filters persist safely

Requirement or claim:
Global and pane inbox content mode and row-state filter are single
workspace-scoped observable preferences owned by `InboxNotificationPrefsAtom` +
`WorkspaceSettingsStore`. Missing fields decode to defaults without resetting
existing settings. `InboxNotificationStore` does not become a second active
preference owner; any retained legacy preference payload is import-only and no
new writes use it.

Owning task:
Task 3.

Proof owner:
implementation executor plus parent verifier.

Proof gate:
`mise run test -- --filter "WorkspaceSettingsStore|InboxNotificationStore|InboxNotificationPrefsAtom|PaneInboxPresentationAtom|InboxSidebarState"`.

Proof layer:
persistence + unit.

Stale-proof guard:
Include an old payload/missing-field decode case in the current settings store
test run and a two-consumer pane-mode sync case in the inbox state test run.

Red/green:
Required for missing-field decode and negative store ownership.

### R6. Chrome-driven entry explains its source badge/dot

Requirement or claim:
Toolbar badge, worktree chip, Pane Inbox badge, and tab dot entry open
`rollupAlerts` + `unreadOnly` temporarily, preserving repo/worktree scope when
the source is scoped. This does not overwrite the persisted browsing mode.
The temporary override is owned by feature runtime state, consumed by the
chrome-driven open request, discarded on close if the user made no explicit
change, and replaced by persisted preferences only after explicit user
interaction.

Owning task:
Tasks 3, 4, and 5.

Proof owner:
implementation executor plus parent verifier.

Proof gate:
`mise run test -- --filter "InboxNotificationSidebarView|PaneInboxNotificationPopover|PaneInboxNotificationPresenter|InboxSidebarState|SidebarSurfaceHost|MainWindowControllerInboxToolbarButton|TabBarAdapter"`.

Proof layer:
unit + mounted/UI.

Stale-proof guard:
Tests must start from persisted `activityOnly` or read+unread mode and then
enter through chrome. They must close without explicit changes, reopen manually,
and prove persisted preferences return.

Red/green:
Required.

Yellow-entry addendum:
Red and amber tab dots are roll-up alert entry points and open
`rollupAlerts` + `unreadOnly`. A yellow-only tab dot is not a numeric roll-up
alert, so it must open a temporary entry state that reveals the settled-agent
source without overwriting persisted browsing preferences. The first
implementation may use `allLanes` + `unreadOnly` plus source-pane/tab scoping,
or a feature-owned settled-agent attention filter if that proves cleaner during
implementation. Either way, the yellow entry state must show the row/scope that
caused the dot and must not create activity counts.

### R7. Tab dots follow live pane ownership

Requirement or claim:
Tab roll-up projection uses current pane graph ownership by pane/parent pane.
Stored tab metadata is only a history fallback after the live owner is gone.
For tab chrome, the App-owned primitive projection is a tab-attention
projection, not just a numeric roll-up projection: red/amber come from unread
action/safety roll-up alerts, and yellow comes from valid unsettled-agent
attention. Blue activity is never included.

Owning task:
Task 5.

Proof owner:
implementation executor plus parent verifier.

Proof gate:
`mise run test -- --filter "TabBarAdapter|TabDisplayDerived|InboxNotificationAtom"`.

Proof layer:
unit + mounted/UI if feasible.

Stale-proof guard:
Tests must move a pane between live tabs after notification creation and assert
the dot moves. A separate test must mark the only roll-up or yellow row read
without any pane/tab mutation and assert the tab token clears immediately.

Red/green:
Required.

### R8. Untrusted notification text is bounded before persistence/diagnostics

Requirement or claim:
Bridge, runtime, terminal, approval, tool/plugin/MCP/subagent, and security text
is either safe pass-through bounded text or fixed-vocabulary summarized text
before promotion, persistence, and diagnostics. Approval lane comes from
internal event kind, never caller text. Sensitive ingress must not persist raw
paths, secret ids, commands, prompts, tool output, or terminal output in title
or body text.

Sensitive ingress examples:

- `filesystemAccessDenied(path:operation:)` stores a fixed summary such as
  `Filesystem access denied` plus safe operation vocabulary; it does not store
  the raw path.
- `secretAccessed(secretId:consumerId:)` stores a fixed secret-access summary;
  it does not store the raw secret id or consumer id.
- `processSpawnBlocked(command:rule:)` stores a fixed blocked-process summary;
  it does not store the raw command.
- approval/tool/plugin/MCP/subagent events store fixed source/action vocabulary
  and bounded caller-visible summary only when the source contract declares that
  field safe for inbox display.

Owning task:
Task 2.

Proof owner:
implementation executor plus parent verifier.

Proof gate:
`mise run test -- --filter "InboxNotificationRouter|InboxPromoter|InboxPostHandler|InboxNotificationBridgeWebKitIntegration|InboxNotificationSQLiteRepository"`.

Proof layer:
unit + integration.

Stale-proof guard:
Oversized approval/security/tool-derived fixture strings and secret/path/command
fixtures must pass through the current router/promoter path and prove persisted
title/body do not equal raw fixture strings. Oversized bridge `inbox.post`
title/body fixtures must pass through the current bridge handler or WebKit
integration seam and prove safe pass-through text is length bounded.

Red/green:
Required.

### R9. Retention protects unread roll-up alerts from activity spam

Requirement or claim:
Retention uses one shared priority policy across atom and SQLite append, upsert,
snapshot replace, and legacy import. Eviction order is read rows, unread
activity, then unread roll-up alerts only as a last resort. Diagnostics are
aggregate and OTLP-safe.

Owning task:
Task 2.

Proof owner:
implementation executor plus parent verifier.

Proof gate:
`mise run test -- --filter "InboxNotificationAtom|InboxNotificationSQLiteRepository|InboxNotificationStore|InboxNotificationRouterObservedPane"`.

Proof layer:
unit + persistence + trace/diagnostic.

Stale-proof guard:
Tests must exercise atom append/upsert, SQLite append/upsert,
`replaceSnapshot`, `replaceLegacyImportSnapshot`, and store reload with the same
mixed-lane fixture and identical survivors.

Red/green:
Required.

### R10. Row and sort UI match the requested behavior

Requirement or claim:
Rows show lane dots only, no row tint. Accessibility/help exposes lane and read
state. Sort icon rotates 180 degrees on toggle without layout jump.

Owning task:
Task 6.

Proof owner:
implementation executor plus parent verifier.

Proof gate:
`mise run test -- --filter "InboxRow|PaneInboxNotificationPopover|InboxNotificationSidebarView"` plus PID-targeted Peekaboo visual proof.

Proof layer:
mounted/UI + visual.

Stale-proof guard:
Peekaboo must target the same PID launched through debug observability when
possible.

Red/green:
Required for row-dot/accessibility. Sort animation may use mounted state proof
plus visual proof rather than a failing pre-change animation test if the current
test harness cannot observe animation.

### R11. Final proof uses current repo, Victoria, and actual UI evidence

Requirement or claim:
Final wrapup separates changed-surface proof from unrelated blockers and includes
focused tests, full tests, lint, Victoria debug observability, and PID-targeted
Peekaboo when feasible.

Owning task:
Task 8.

Proof owner:
parent verifier.

Proof gate:
`mise run test`, `mise run lint`,
`mise run observability:up`,
`mise run run-debug-observability -- --detach`,
`mise run verify-debug-observability`,
then `peekaboo see --app "PID:$AGENTSTUDIO_OBSERVABILITY_PID" --json` after
reading `tmp/debug-observability/latest-observability.env`.

Proof layer:
full test + lint + smoke/observability + visual.

Stale-proof guard:
The verifier must query the current marker in
`tmp/debug-observability/latest-observability.env` and use the current debug app
PID from this worktree. Do not use stale logs or app-name targeting.

Red/green:
Not applicable for final smoke; evidence must be current.

### R12. Yellow settled agent attention is high precision and revocable

Requirement or claim:
Yellow settled is an attention-bucket dot for likely-finished coding-agent
work, not a generic activity dot. It is produced only for agent-classified
terminal panes after substantial work and a long quiet window. It is
provisional: any later terminal output or runtime activity before the user
reads the row/scope revokes yellow immediately and returns the pane to blue
activity/running state. The existing short terminal quiet-settled activity facts
remain blue activity history unless they also pass the strict agent-settled
heuristic.

Initial heuristic:

```text
candidate starts only after fresh agent-classified output activity in a pane
whose agent identity is explicit at candidate start
AND (
  active span >= 6 minutes
  OR rows_added_since_candidate_start >= 500
)
AND no row growth, terminal activity window, or terminal signal for 3 minutes
AND revalidate latest activity timestamp immediately before showing yellow
```

Hard exclusions:

```text
non-agent pane
historical backlog before candidate start
rows_added_since_candidate_start < 100
active span < 60 seconds unless a future explicit completion signal exists
terminal.signal without row growth
existing 750ms/short quiet-settled activity fact alone
```

Candidate lifecycle:

```text
start candidate:
  first row-growth event after the pane is classified as an agent pane

extend candidate:
  any later row growth while candidate remains active

reset candidate without yellow:
  pane loses/changes agent identity, pane closes, tab/pane runtime resets,
  user reads/read-all clears the candidate scope, or activity remains below
  hard minimums when the quiet window expires

promote yellow:
  candidate passes thresholds, survives the 3 minute quiet window, and a final
  revalidation sees no newer row growth/signal/activity

revoke yellow:
  any row growth, terminal activity window, or terminal signal after yellow
  and before user read/read-all

repromote after revoke:
  only after a new qualifying candidate starts from fresh row growth; stale
  rows from the revoked candidate cannot immediately repromote yellow
```

Owning task:
Task 2a plus Task 5 and Task 8.

Proof owner:
implementation executor plus parent verifier.

Proof gate:
`mise run test -- --filter "TerminalActivity|InboxPromoter|InboxNotificationAtom|WorkspaceNotificationCountOwnership|TabBarAdapter"` plus IPC-driven debug smoke that uses
`agentstudio-ipc terminal-send` to generate controlled output and Victoria logs
to verify activity/settled/revocation telemetry.

Proof layer:
unit + integration + smoke/observability + visual.

Stale-proof guard:
The smoke proof must launch the current worktree debug app after this branch's
code changes, read `tmp/debug-observability/latest-observability.env`, use the
current IPC metadata file from that debug data root, and target the current PID
with Peekaboo. Do not reuse the 2026-06-15 proof marker except as tool-shape
evidence.

Red/green:
Required. False positives are high-cost; tests must prefer missed yellow over
premature yellow.

Mandatory red/green cases:

- non-agent panes never produce yellow
- historical backlog plus a short new burst does not produce yellow
- fewer than 100 rows since candidate start never produces yellow
- active span under 60 seconds never produces yellow unless a future explicit
  completion signal exists
- terminal signal without row growth never produces yellow
- the existing short quiet-settled activity fact alone never produces yellow
- qualifying agent burst or long-running candidate promotes yellow after quiet
- later row growth revokes yellow
- later terminal signal revokes yellow
- read and read-all clear yellow
- revoked yellow does not repromote until a new qualifying run
- tab priority is red over amber, amber over yellow, yellow over no dot, and
  blue activity never appears as a tab dot

## Task Sequence

### Task 0. Worktree, index, and PR hygiene

Write surfaces:

- `tmp/workflow-state/2026-06-15-notification-less-spam-pr-wrapup/details.md`
- optional repo-local status artifact under `tmp/workflow-state/2026-06-15-notification-less-spam-pr-wrapup/`
- no product code

Steps:

1. Capture `git status --porcelain=v2`, `git diff --cached --stat`,
   `git diff --cached --name-only`, `git ls-files --others --exclude-standard`,
   and `git stash list --max-count=3`.
2. Classify every staged and untracked path before further code edits:
   `in-scope`, `park before implementation`, or `explicit scope expansion`.
3. Record the current safety stash ref
   `stash@{0}: pre-origin-main-merge-notification-system-less-spam-20260615T200610`
   while it exists. Do not drop it until after build/test proof or a scoped
   commit captures the recovered work.
4. Decide which planning/spec/review artifacts ship in the PR and which stay
   local workflow state. The spec and implementation plan may ship if they are
   useful review context; `tmp/workflow-state` stays local unless explicitly
   requested.
5. Require a scoped index before implementation resumes. If a staged path is
   outside the plan write surfaces, either add it to the plan with rationale or
   park it before implementation.
6. Check PR bootstrap state:
   - whether an upstream branch exists
   - whether a PR already exists for the branch
   - which commit(s) will be pushed

Validation:

```bash
git status --porcelain=v2
git diff --cached --stat
git diff --cached --name-only
git ls-files --others --exclude-standard
git rev-parse --abbrev-ref --symbolic-full-name @{u}
gh pr status
```

Split/replan trigger:
If current staged files outside the notification/terminal-observability proof
path are real required dependencies, update this plan before editing product
code. If they are not required, park them before implementation.

### Task 1. Phase 0 producer correctness

Write surfaces:

- `Sources/AgentStudio/Features/InboxNotification/Routing/InboxNotificationRouter.swift`
- `Sources/AgentStudio/Features/InboxNotification/Routing/PaneFocusTracker.swift`
- `Sources/AgentStudio/Features/InboxNotification/Models/InboxNotificationClaim.swift`
- `Sources/AgentStudio/Features/InboxNotification/State/MainActor/Atoms/InboxNotificationAtom.swift`
- `Sources/AgentStudio/Features/InboxNotification/State/MainActor/Persistence/InboxNotificationSQLiteRepository.swift`
- focused tests under `Tests/AgentStudioTests/Features/InboxNotification/`

Steps:

1. Validate the June 10 plan against current code.
2. Fix auto-clear to use attended-pane truth where the policy requires it.
3. Add bounded restart behavior for `PaneFocusTracker` on unexpected stream end.
4. Extract one coalescence predicate used by atom and SQLite paths.
5. Make any read-to-unread transition clear `isDismissedFromPaneInbox`,
   including manual toggle and stronger-lane coalescence reopen.
6. Add mark-read/dismiss/reopen save-and-reload proof.

Validation:

```bash
mise run test -- --filter "InboxNotificationRouterObservedPane|PaneFocusTracker|InboxNotificationAtom|InboxNotificationSQLiteRepository|InboxPromoter"
```

Split/replan trigger:
If call-site analysis proves an observed-pane clear is intentional for one path,
stop and split the auto-clear decision before changing behavior.

### Task 2. Domain policies: lane projection, text bounds, retention

Write surfaces:

- `Sources/AgentStudio/Features/InboxNotification/Models/`
- `Sources/AgentStudio/Features/InboxNotification/Routing/`
- `Sources/AgentStudio/Features/InboxNotification/State/MainActor/Atoms/InboxNotificationAtom.swift`
- `Sources/AgentStudio/Features/InboxNotification/State/MainActor/Persistence/InboxNotificationSQLiteRepository.swift`
- `Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController.swift`
  only for applying the feature-owned safe display text policy to existing
  `inbox.post` title/body normalization; no Bridge API shape change
- `Sources/AgentStudio/Infrastructure/AppPolicies.swift`
- `Tests/AgentStudioTests/Features/Bridge/InboxPostHandlerTests.swift`
- `Tests/AgentStudioTests/Integration/InboxNotificationBridgeWebKitIntegrationTests.swift`
- tests under inbox model/routing/state suites

Steps:

1. Add feature-owned roll-up summary/projection APIs on or adjacent to
   `InboxNotificationAtom`, reusing `InboxNotificationClaimLane`.
2. Add fallback lane mapping for legacy rows without claim keys.
3. Add one feature-owned text policy with two explicit modes:
   - safe display ingress: trim and length-bound caller-provided title/body
     using the current shared inbox max title/body constants
   - sensitive structured ingress: ignore raw sensitive fields and emit
     fixed-vocabulary title/body summaries before promotion and persistence
4. Update approval/security/tool/plugin/MCP/subagent body paths to use the
   sensitive structured mode whenever the source field may contain a path,
   secret id, command, prompt, tool output, terminal output, or attacker-
   controlled payload. Explicitly forbid storing those raw strings in
   persisted notification title/body text.
5. Add router/integration tests for `secretAccessed`,
   `filesystemAccessDenied`, `processSpawnBlocked`, and approval/tool-derived
   fixtures asserting persisted title/body do not equal raw path, secret id,
   command, prompt, or tool-output fixture strings and match the fixed summary
   shape.
6. Update bridge `inbox.post` ingress proof so oversized title/body text is
   bounded before persistence through the real handler or WebKit integration
   seam.
7. Add one shared retention-priority selector used by atom and SQLite paths,
   including append/upsert, snapshot replace, and legacy-import materialization.
8. Make retention diagnostics aggregate-only and OTLP-safe.
9. Preserve the safety coalescence contract: safety stays outside
   activity-session coalescence unless exact guarded semantics are explicitly
   added later.
10. When a stronger roll-up-eligible event coalesces into a read row, reopen the
   existing row to unread, clear pane dismissal, and do not create a sibling
   duplicate.

Validation:

```bash
mise run test -- --filter "InboxNotificationAtom|InboxNotificationSQLiteRepository|InboxNotificationRouter|InboxPromoter|InboxNotificationClaim|InboxPostHandler|InboxNotificationBridgeWebKitIntegration"
```

Split/replan trigger:
If shared retention policy placement would force a forbidden Core -> Feature
import, keep it feature-owned and adapt SQLite call sites inside the feature
repository boundary.

### Task 2a. Agent-settled candidate policy and revocation

Write surfaces:

- `Sources/AgentStudio/Features/Terminal/Routing/TerminalActivityRouter.swift`
- `Sources/AgentStudio/Features/InboxNotification/Routing/InboxPromoter.swift`
- `Sources/AgentStudio/Features/InboxNotification/Models/`
- `Sources/AgentStudio/Features/InboxNotification/State/MainActor/Atoms/InboxNotificationAtom.swift`
- `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyActionRouter+Tracing.swift`
- `Sources/AgentStudio/App/Boot/AppDelegate+InboxNotificationBoot.swift`
- OTLP projection/tag allowlists if new aggregate-safe attributes are needed
- focused tests under terminal activity, inbox promoter, and diagnostics suites

Allowed adjacent infra edits:

- `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyActionRouter+Tracing.swift`
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPTraceProjection.swift`
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioTraceTag.swift`
- `docs/architecture/observability_and_traceability.md` only for documenting
  the new aggregate-safe notification/terminal proof signals

Adjacent infra edits that require replan:

- `Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController.swift`
- BridgeWeb assets/tests unrelated to notification or IPC proof
- IPC auth/server/client behavior beyond proof command documentation
- AtomLib, release, build-system, or architecture-lint changes

Steps:

1. Add a feature/domain representation for a provisional agent-settled
   candidate that is distinct from ordinary blue activity and from action/safety
   roll-up alerts.
2. Classify agent panes conservatively from explicit pane/command/session hints.
   Unknown panes must never produce yellow.
3. Add the classifier at the App composition seam in
   `AppDelegate+InboxNotificationBoot.swift`; `TerminalActivityRouter` receives
   the classifier/policy as an injected closure or value and must not reach into
   global atoms for feature-specific agent identity.
4. Use this precedence table for the first implementation:
   - `PaneContentType.agent` at candidate start: eligible, subject to all R12
     activity/quiet thresholds and revocation rules
   - future explicit command/session agent hint: eligible only if the hint is
     typed and produced by the runtime contract, not parsed from terminal output
   - `ExecutionBackend.local`, `.docker`, `.gondolin`, or `.remote` alone:
     not an agent identity and never enough for yellow
   - ordinary terminal pane, unknown pane content type, plugin type without a
     typed agent contract, or missing hint: never yellow
   - if hints disagree, choose the safest result: not eligible
5. Implement the strict heuristic from R12 with injected/testable clocks or
   event-driven waits. Do not add wall-clock sleeps to tests.
6. Revalidate latest terminal activity immediately before promoting yellow.
7. Revoke yellow on any later row growth, terminal activity window, or terminal
   signal before read; return the row/scope to blue activity/running state.
8. Ensure read/read-all clears yellow along with red, amber, and blue dots.
9. Add aggregate-safe trace attributes for candidate start, promotion, and
   revocation only if needed for Victoria proof. Do not export command text,
   terminal output, raw paths, or prompt content.
10. Add the mandatory negative and revocation tests named in R12 before relying
   on manual or smoke evidence.

Validation:

```bash
mise run test -- --filter "TerminalActivity|InboxPromoter|InboxNotificationAtom|AgentStudioOTLPTraceProjection|AgentStudioTraceConfiguration"
```

Split/replan trigger:
If live testing finds a reliable explicit completion signal from Codex, Claude,
Gemini, or agy, add it as an additional high-confidence input. Do not weaken
the row/quiet heuristic just to make yellow appear more often.

### Task 3. Preferences and filter state hard cutover

Write surfaces:

- `Sources/AgentStudio/Features/InboxNotification/State/MainActor/Atoms/InboxNotificationPrefsAtom.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceSettingsStore.swift`
- `Sources/AgentStudio/Features/InboxNotification/State/MainActor/Atoms/PaneInboxPresentationAtom.swift`
- `Sources/AgentStudio/Features/InboxNotification/State/MainActor/Atoms/InboxSidebarState.swift`
- `Sources/AgentStudio/Features/InboxNotification/State/MainActor/Persistence/InboxNotificationStore.swift`
- `Sources/AgentStudio/Features/InboxNotification/Models/PaneInboxNotificationFilterMode.swift`
- `Sources/AgentStudio/Features/InboxNotification/Models/InboxNotificationListModel.swift`
- `Tests/AgentStudioTests/Core/Stores/WorkspaceSettingsStoreTests.swift`
- `Tests/AgentStudioTests/Features/InboxNotification/State/InboxNotificationStoreTests.swift`
- `Tests/AgentStudioTests/Features/InboxNotification/State/PaneInboxPresentationAtomTests.swift`

Steps:

1. Replace `.unread` / `.all` pane filtering with content mode plus row-state
   filter.
2. Persist global and pane content mode/row-state filter in workspace settings
   with tolerant decode defaults.
3. Replace per-parent pane presentation caches with one workspace-scoped
   observable content-mode owner and one workspace-scoped observable row-state
   owner.
4. Keep `PaneInboxPresentationAtom` as request/presentation targeting only.
5. Keep repo/worktree pending scope filter runtime-only.
6. Add feature-runtime override request state for chrome-driven entry:
   `InboxSidebarRuntimeAtom` owns global inbox override requests, and the pane
   inbox runtime owner/presenter owns pane-popover override requests. Do not put
   content-mode or row-state fields onto Core request types such as
   `PaneInboxRequest` or `PaneInboxPresentation`.
7. Consume override requests on chrome-driven open, discard them on close if the
   user made no explicit preference change, and persist only explicit user
   changes.
8. Prove `InboxNotificationStore` does not own the new preferences. Remove
   active preference writes from its payload, or keep legacy preference fields
   import-only with tests proving no current save path writes them.
9. Update the `InboxNotificationPrefsAtom` ownership comment so it names
   `WorkspaceSettingsStore`, not `InboxNotificationStore`.

Validation:

```bash
mise run test -- --filter "WorkspaceSettingsStore|InboxNotificationStore|InboxNotificationPrefsAtom|PaneInboxPresentationAtom|InboxSidebarState|InboxNotificationListModel"
```

Split/replan trigger:
If adding the new persisted enum types widens Core dependencies beyond the
existing settings-store exception, introduce a shared raw-value contract before
continuing.

### Task 4. Global and Pane Inbox surfaces

Write surfaces:

- `Sources/AgentStudio/Features/InboxNotification/Views/InboxNotificationSidebarView.swift`
- `Sources/AgentStudio/Features/InboxNotification/Views/PaneInboxNotificationPopover.swift`
- `Sources/AgentStudio/Features/InboxNotification/Components/`
- `Sources/AgentStudio/Features/InboxNotification/State/MainActor/Atoms/InboxNotificationAtom.swift`
- `Sources/AgentStudio/Features/InboxNotification/State/MainActor/Persistence/InboxNotificationSQLiteRepository.swift`
- `Sources/AgentStudio/Core/Views/Drawer/PaneInboxPresentation.swift`
- `Sources/AgentStudio/Core/Models/InboxNotificationCommands.swift`
- `Sources/AgentStudio/App/Windows/MainSplitViewController.swift`
- `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- `Sources/AgentStudio/App/Boot/AppDelegate+InboxNotificationCommands.swift`
- `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource+Inbox.swift`
- related mounted tests

Steps:

1. Add compact controls for content mode, row-state filter, activity-only, and
   all-lanes without activity counts.
2. Add one feature-owned scoped mark-read mutation API below the UI, covering
   workspace, repo, worktree, and pane scopes in both atom and SQLite
   persistence. UI/controller code must pass scope; it must not filter rows and
   call workspace-wide `markAllRead()`.
3. Cut over command seams explicitly:
   scoped global-surface read-all callback, pane read-all callback distinct from
   pane clear, and app-level workspace mark-all kept separate for command-bar
   or global shortcuts.
4. Expose both pane controls in this slice:
   `Mark Pane Read` sets `isRead = true` and does not dismiss; `Clear Pane
   Inbox` sets read + pane dismissal and remains separately labeled.
5. Make chrome-driven entry temporarily force `rollupAlerts` + `unreadOnly`
   through the Task 3 runtime override owner, including the case where the
   inbox surface is already visible.
6. Replace Core pane-inbox `unread*` naming with roll-up naming and remove
   `pruneFilterModes`-style ownership from the Core contract. `PaneTabViewController`
   must stop calling the removed hook; stale request state should be deleted or
   redirected to request-only cleanup, not per-parent filter pruning.
7. Update group/header counts so activity-only mode does not show activity
   numeric rollups.

Validation:

```bash
mise run test -- --filter "InboxNotificationSidebarView|PaneInboxNotificationPopover|PaneInboxPresentation|AppDelegateInboxNotificationCommands|PaneTabViewControllerPaneInboxCommand|PaneTabViewControllerPaneInboxDispatch|MainSplitViewControllerCompositeCommand"
```

Split/replan trigger:
If existing command infrastructure cannot express scoped read-all without broad
command architecture changes, keep scoped read-all as a local surface action and
leave app-level command as unscoped workspace mark-all. Do not implement scoped
read-all by calling the workspace-wide mutation from a filtered controller list.

### Task 5. Chrome roll-up wiring and tab dots

Write surfaces:

- `Sources/AgentStudio/App/Windows/MainWindowController.swift`
- `Sources/AgentStudio/App/Windows/SidebarSurfaceHost.swift`
- `Sources/AgentStudio/App/Windows/MainSplitViewController.swift`
- `Sources/AgentStudio/App/Panes/WorkspaceNotificationCountProjection.swift`
- `Sources/AgentStudio/App/Panes/WorkspaceLauncherProjector.swift`
- `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- `Sources/AgentStudio/App/Boot/AppDelegate+WorkspaceBoot.swift`
- `Sources/AgentStudio/App/Panes/TabBar/TabBarAdapter.swift`
- `Sources/AgentStudio/App/Panes/TabBar/CustomTabBar.swift`
- `Sources/AgentStudio/Core/Views/Drawer/PaneInboxPresentation.swift`
- app/chrome tests

Steps:

1. Verify the already-landed roll-up alert shell consumers from
   Current-State Evidence and fix only remaining stale all-unread consumers.
2. Replace any remaining global toolbar badge count with global roll-up alert
   count.
3. Replace any remaining worktree/repo notification chip counts with roll-up
   alert counts
   across in-scope app-shell consumers of `WorkspaceNotificationCountProjection`,
   including pane-management and launcher chrome, so activity-only rows do not
   light one shell surface while another stays quiet.
4. Replace Pane Inbox badge count with visible pane roll-up alert count.
5. Compose tab roll-up tokens in App by resolving inbox roll-up candidates
   against the current pane graph before `TabBarAdapter.refresh`.
6. Add the production composition in `AppDelegate+WorkspaceBoot.swift` so
   `TabBarAdapter` receives primitive tab-dot tokens or a token provider.
   `TabBarAdapter` must stop reading `atom(\.inboxNotification)` directly for
   notification dots.
7. Add App-local primitive tab notification render token to `TabBarItem`.
   `TabBarAdapter` may accept token data or expose an App-owned update hook, but
   it must not import inbox feature domain types or observe inbox state directly.
8. Add an explicit invalidation path for inbox-only changes so marking the last
   roll-up row read clears the tab dot without waiting for a pane/tab mutation.
9. Render red/amber/yellow attention tab dots in `CustomTabBar`; never render
   blue activity dot.
10. Apply dot priority consistently: red action wins over amber safety, amber
   safety wins over yellow settled, and yellow settled wins over no dot.
11. Ensure tab dot moves when the live pane owner moves between tabs.
12. Clear the yellow tab dot immediately when the settled state is revoked by
    continued output or cleared by read/read-all.

Validation:

```bash
mise run test -- --filter "WorkspaceNotificationCountOwnership|WorkspaceLauncherProjector|MainWindowControllerInboxToolbarButton|PaneInboxPresentation|SidebarSurfaceHost|MainSplitViewControllerCompositeCommand|TabBarAdapter|TabDisplayDerived|TerminalActivity"
```

Split/replan trigger:
If live pane graph ownership pressures `TabBarAdapter` toward a circular
dependency, keep composition one level up in App and pass precomputed primitive
tab-dot tokens into the adapter.

### Task 6. Row dots, accessibility, and sort animation

Write surfaces:

- `Sources/AgentStudio/Features/InboxNotification/Components/InboxRow.swift`
- `Sources/AgentStudio/Features/InboxNotification/Views/PaneInboxNotificationPopover.swift`
- `Sources/AgentStudio/Features/InboxNotification/Views/InboxNotificationSidebarView.swift`
- related AppStyles/AppPolicies constants if needed
- row/mounted UI tests

Steps:

1. Render row dots red/amber/blue by lane for unread rows only.
2. Keep rows dot-only visually: no row background tint and no replacement icon.
3. Add accessibility/help text for lane and read state.
4. Animate sort icon rotation 180 degrees on sort toggle without layout shift.
5. Add or update mounted tests for row dots, accessibility, and sort state.

Validation:

```bash
mise run test -- --filter "InboxRow|PaneInboxNotificationPopover|InboxNotificationSidebarView"
```

Split/replan trigger:
If animation cannot be asserted in mounted tests, assert state and layout
stability in tests and rely on PID-targeted Peekaboo for visual animation proof.

### Task 7. Focused integration pass

Write surfaces:

- tests only, unless focused runs expose changed-surface bugs

Steps:

1. Run the focused suite from the spec.
2. Fix only failures inside the agreed notification/chrome/settings path.
3. Separate unrelated failures from changed-surface proof.

Validation:

```bash
mise run test -- --filter "InboxNotificationRouterObservedPane|PaneFocusTracker|InboxNotificationAtom|InboxNotificationSQLiteRepository|InboxPromoter|InboxNotificationClaim"
mise run test -- --filter "InboxPostHandler|InboxNotificationBridgeWebKitIntegration|PaneInboxPresentation|DerivedTerminalActivityNotificationRegression"
mise run test -- --filter "WorkspaceNotificationCountOwnership|WorkspaceLauncherProjector|MainWindowControllerInboxToolbarButton|SidebarSurfaceHost|MainSplitViewControllerCompositeCommand|WorkspaceSettingsStore|InboxNotificationStore|InboxSidebarState|TabBarAdapter|TabDisplayDerived|PaneInboxPresentation"
```

Split/replan trigger:
If a focused failure is in unrelated BridgeWeb/Terminal/AtomLib infrastructure,
stop edits and report the scoped pass/fail status.

### Task 8. Full proof, observability, visual verification, and wrapup

Write surfaces:

- wrapup/handoff artifact if useful
- no product code unless a proof gate exposes an in-scope defect

Steps:

1. Run full tests and lint:

   ```bash
   mise run test
   mise run lint
   ```

2. Run Victoria debug observability:

   ```bash
   mise run observability:up
   AGENTSTUDIO_IPC_UNSAFE_NO_AUTH=1 AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=ipc-terminal-smoke mise run run-debug-observability -- --detach
   mise run verify-debug-observability
   ```

3. Resolve the IPC CLI from the current build slot, source current debug state,
   exercise IPC terminal input, run a marker-scoped post-send check, and run
   PID-targeted Peekaboo:

   ```bash
   . tmp/debug-observability/latest-observability.env
   IPC_CLIENT="$(find "${AGENTSTUDIO_OBSERVABILITY_BUILD_PATH:-.build}" -path '*/debug/agentstudio-ipc' -type f -perm -111 | head -1)"
   "$IPC_CLIENT" --metadata "$AGENTSTUDIO_OBSERVABILITY_DATA_DIR/ipc/runtime.json" identify
   "$IPC_CLIENT" --metadata "$AGENTSTUDIO_OBSERVABILITY_DATA_DIR/ipc/runtime.json" current-pane
   "$IPC_CLIENT" --metadata "$AGENTSTUDIO_OBSERVABILITY_DATA_DIR/ipc/runtime.json" terminal-status pane:<current-ordinal>
   "$IPC_CLIENT" --metadata "$AGENTSTUDIO_OBSERVABILITY_DATA_DIR/ipc/runtime.json" terminal-send pane:<current-ordinal> $'echo AGENTSTUDIO_IPC_NOTIFICATION_PROOF\n'
   # Query Victoria for marker-scoped post-send terminal activity before using
   # the screenshot as UI evidence. Do not use terminal.wait commandFinished.
   peekaboo see --app "PID:$AGENTSTUDIO_OBSERVABILITY_PID" --json
   ```

4. Treat the generic IPC terminal-send proof as debug-control plumbing proof,
   not positive yellow proof. Positive yellow promotion/revocation must be
   proven by deterministic tests unless a dedicated debug startup diagnostic or
   fixture creates an agent-classified pane, drives a qualifying candidate, and
   captures marker-scoped Victoria promotion/revocation logs plus same-PID
   Peekaboo before/after evidence.
5. Optional manual-agent proof lane, with the user driving real Codex/Claude/
   Gemini/agy activity if available:
   - launch a fresh debug app with explicit marker and IPC enabled
   - record debug PID, marker, pane ordinal, agent/tool invoked, and timestamp
   - user triggers the agent manually
   - parent queries Victoria logs for candidate/activity/revocation facts
   - parent captures same-PID Peekaboo evidence
   - manual evidence can supplement smoke/e2e confidence, but it cannot replace
     deterministic R12 negative/revocation tests
6. Inspect visual evidence for row dots, no blue activity tab dot, yellow
   settled behavior when a dedicated fixture/manual run is available, tab
   attention-dot behavior, read-all dot clearing, and sort rotation when
   feasible.
7. Run `implementation-review-swarm`.
8. Commit scoped work, detect/create the PR, push with upstream if needed,
   respond to review comments, wait for required checks,
   resolve valid review threads, and merge only after scoped proof and PR gates
   are green.
9. Produce wrapup with changed-surface proof, unrelated blockers, and remaining
   risks.

Split/replan trigger:
If debug launch reports `already_running`, quit the reported debug PID, relaunch
with `mise run run-debug-observability -- --detach`, and then rerun
`mise run verify-debug-observability`. If Peekaboo
cannot capture for environment reasons, record the blocker and rely on mounted
proof only after separating the UI-capture blocker from implementation
correctness.

## Write Surfaces Summary

- `Sources/AgentStudio/Features/InboxNotification/Models/`
- `Sources/AgentStudio/Features/InboxNotification/Routing/`
- `Sources/AgentStudio/Features/InboxNotification/State/MainActor/Atoms/`
- `Sources/AgentStudio/Features/InboxNotification/State/MainActor/Persistence/`
- `Sources/AgentStudio/Features/InboxNotification/Views/`
- `Sources/AgentStudio/Features/InboxNotification/Components/`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceSettingsStore.swift`
- `Sources/AgentStudio/Core/Views/Drawer/PaneInboxPresentation.swift`
- `Sources/AgentStudio/App/Windows/`
- `Sources/AgentStudio/App/Panes/TabBar/`
- `Sources/AgentStudio/App/Panes/WorkspaceNotificationCountProjection.swift`
- `Sources/AgentStudio/App/Panes/WorkspaceLauncherProjector.swift`
- `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- `Sources/AgentStudio/Core/Models/InboxNotificationCommands.swift`
- `Sources/AgentStudio/App/Boot/AppDelegate+InboxNotificationCommands.swift`
- `Sources/AgentStudio/App/Boot/AppDelegate+InboxNotificationBoot.swift`
- `Sources/AgentStudio/App/Boot/AppDelegate+WorkspaceBoot.swift`
- `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource+Inbox.swift`
- focused tests under `Tests/AgentStudioTests/`

## Validation Gates

Focused gates:

```bash
mise run test -- --filter "InboxNotificationRouterObservedPane|PaneFocusTracker|InboxNotificationAtom|InboxNotificationSQLiteRepository|InboxPromoter|InboxNotificationClaim"
mise run test -- --filter "InboxPostHandler|InboxNotificationBridgeWebKitIntegration|InboxNotificationRouter|InboxPromoter|InboxNotificationStore"
mise run test -- --filter "WorkspaceSettingsStore|InboxNotificationStore|InboxNotificationPrefsAtom|PaneInboxPresentationAtom|InboxSidebarState|InboxNotificationListModel"
mise run test -- --filter "InboxNotificationSidebarView|PaneInboxNotificationPopover|PaneInboxPresentation|AppDelegateInboxNotificationCommands|PaneTabViewControllerPaneInboxCommand|PaneTabViewControllerPaneInboxDispatch|MainSplitViewControllerCompositeCommand"
mise run test -- --filter "WorkspaceNotificationCountOwnership|WorkspaceLauncherProjector|MainWindowControllerInboxToolbarButton|SidebarSurfaceHost|MainSplitViewControllerCompositeCommand|PaneInboxPresentation|TabBarAdapter|TabDisplayDerived"
mise run test -- --filter "InboxRow|PaneInboxNotificationPopover|InboxNotificationSidebarView"
```

Full gates:

```bash
mise run test
mise run lint
```

Observability and visual gates:

```bash
mise run observability:up
AGENTSTUDIO_IPC_UNSAFE_NO_AUTH=1 AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=ipc-terminal-smoke mise run run-debug-observability -- --detach
mise run verify-debug-observability
. tmp/debug-observability/latest-observability.env
IPC_CLIENT="$(find "${AGENTSTUDIO_OBSERVABILITY_BUILD_PATH:-.build}" -path '*/debug/agentstudio-ipc' -type f -perm -111 | head -1)"
"$IPC_CLIENT" --metadata "$AGENTSTUDIO_OBSERVABILITY_DATA_DIR/ipc/runtime.json" identify
"$IPC_CLIENT" --metadata "$AGENTSTUDIO_OBSERVABILITY_DATA_DIR/ipc/runtime.json" current-pane
"$IPC_CLIENT" --metadata "$AGENTSTUDIO_OBSERVABILITY_DATA_DIR/ipc/runtime.json" terminal-send pane:<current-ordinal> $'echo AGENTSTUDIO_IPC_NOTIFICATION_PROOF\n'
peekaboo see --app "PID:$AGENTSTUDIO_OBSERVABILITY_PID" --json
```

## Risks

- Phase 0 may reveal that observed-pane auto-clear has a deliberate call path.
  If so, split that decision before changing behavior.
- Retention priority must stay identical between atom and SQLite. A partial fix
  can make reload behavior diverge.
- The settings-store Core/Feature dependency is already a sanctioned exception
  in this repo. Do not widen it outside inbox settings.
- Tab-dot live ownership can create dependency pressure in `TabBarAdapter`.
  Keep App-level primitive token composition; do not push notification state into
  Core tab models or teach the adapter to observe inbox domain objects.
- Yellow settled false positives are more frustrating than missed settled
  signals. Keep the first heuristic strict and revocable; do not promote short
  quiet activity facts to yellow just because they are available.
- Safety amber and settled yellow are separate domain meanings. If the final
  visual tokens are too close, adjust presentation constants rather than
  collapsing the semantics.
- IPC `terminal.send` proves input acceptance and visible UI output with
  Peekaboo, but `terminal.wait commandFinished` currently times out for the
  echo smoke. Do not use commandFinished as a required completion gate until the
  runtime exports that signal reliably.
- The CLI parser currently exposes `current-pane`, `terminal-status`,
  `terminal-send`, and `terminal-wait`, but not `terminal-snapshot`, even though
  the server and IPC architecture document mention `terminal.snapshot`.
  Do not use `terminal-snapshot` in the scripted proof until the CLI parser
  supports it.
- Shared worktree count helpers feed multiple shell surfaces. The implementation
  intentionally cuts over both pane-management and launcher consumers so blue
  activity rows do not light one worktree surface while another stays quiet.
- Peekaboo visual proof may be blocked by local permissions or launch state.
  Treat that as a proof blocker, not as implementation success.

## Rollback / Recovery Notes

- All roll-up counts are derived; no migration should store count state.
- New persisted filter fields must tolerate missing values and default to
  `rollupAlerts` / `unreadOnly`.
- If filter preference persistence causes decode trouble, fallback should reset
  only missing new fields, not grouping/sort/bell or unrelated settings.
- If retention policy changes behave incorrectly, reverting the shared priority
  selector returns storage to oldest-first behavior but may reintroduce activity
  spam eviction risk.

## Plan-Review Decisions Applied

1. `Pane Inbox` exposes both pure mark-read and separately labeled clear/dismiss
   controls in the first implementation slice.
2. Automated tab-token proof plus PID-targeted Peekaboo is required. Mounted
   `CustomTabBar` rendering proof is optional extra only if the harness supports
   it cheaply.
3. Text bounding reuses the current shared inbox max title/body constants for
   all newly bounded ingress paths unless a later product decision introduces
   source-specific limits.
4. `WorkspaceNotificationCountProjection` consumers in pane-management and
   launcher chrome are in scope for the roll-up cutover.

## Next Step

Plan review is complete; continue with
`shravan-dev-workflow:implementation-execute-plan`. Before merge, run
`shravan-dev-workflow:implementation-review-swarm` and
`shravan-dev-workflow:implementation-pr-wrapup`.

phase_result: complete
evidence: `docs/plans/2026-06-14-notification-less-spam-rollup-alerts-implementation.md`, `tmp/workflow-state/2026-06-15-notification-less-spam-pr-wrapup/plan-review-synthesis.md`
recommended_next_workflow: `shravan-dev-workflow:implementation-execute-plan`
recommended_transition_reason: Plan review accepted blocker and important
findings after revisions; implementation should resume with Task 0 already
completed.
