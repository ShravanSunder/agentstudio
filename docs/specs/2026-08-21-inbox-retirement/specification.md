# Inbox Retirement — Specification

Requirements: [requirements.md](requirements.md)

## Observable Contract

**R1 — Repo Explorer is the sole application sidebar.** The application MUST mount and display Repo Explorer as the only sidebar content. A restored or requested Inbox sidebar selection MUST converge to Repo Explorer; it MUST NOT produce an empty, hidden-but-mounted, or alternate Inbox surface. [U-INBOX-1]

**R2 — No Inbox presentation or query is reachable.** Global and pane-local Inbox commands MUST NOT appear in the command bar, application toolbar, pane toolbar, terminal-zoom toolbar, menus, or inline controls. Inbox shortcuts MUST NOT open presentation. Inbox commands received through IPC or internal dispatch MUST be rejected as unavailable and MUST NOT mutate presentation state. Non-command IPC discovery and sidebar-query contracts MUST NOT advertise or accept Inbox as a surface; a stale Inbox-valued request MUST return the existing invalid/unavailable error without reading Inbox state. Repo-only sidebar queries remain available. [U-INBOX-1]

**R3 — Repo and pane chrome contain no Inbox affordance.** Repo Explorer and pane presentation MUST NOT render Inbox notification badges/counts or actions that target the retired global or pane-local Inbox. Removing those affordances MUST NOT change repository, worktree, pane, Git, PR, focus, or activity behavior. [U-INBOX-1]

**R4 — Retired Inbox runtime work does not start.** Application boot MUST NOT load Inbox history or preferences into live atoms, start Inbox history or preference persistence observation, start `InboxNotificationRouter`/promotion, or create new Inbox notifications. Active workspace-settings persistence MUST neither read nor write Inbox preferences. Runtime terminal activity and the demand-admission pane-status path MUST continue under non-Inbox ownership. Persistence-recovery handling MUST neither create/buffer Inbox notifications nor accumulate an unconsumed Inbox queue. [U-INBOX-2]

**R5 — Existing Inbox data remains untouched.** Startup, unrelated workspace/editor preference saves, autosave, ordinary operation, shutdown, and proof runs MUST perform no Inbox history or preference row deletion, clearing, migration, rewrite, replacement, or timestamp update. Existing schema and rows remain readable by the dormant implementation but are not loaded or presented by the application. [U-INBOX-3]

**R6 — Retirement is source-visible and enforced.** The surviving dormant Inbox boot/persistence/presentation boundaries and every authoritative architecture contract that currently describes Inbox presentation, commands, IPC, hosting/keyboard surfaces, workspace-data reads, or persistence MUST identify the retirement, the preserved-data constraint, and the prohibition on reconnecting Inbox without a new product decision. Automated architecture/source proof MUST fail if Inbox presentation, command/query exposure, router startup, store/settings loading or writes, or notification-count reads are reintroduced into App composition. [U-INBOX-4]

## Failure And Compatibility

- Legacy persisted `.inbox` sidebar selection is accepted only as stored input and normalizes to Repo Explorer without presenting Inbox or failing workspace restore.
- An Inbox command from a stale shortcut, IPC client, or internal caller fails closed as unavailable; it never silently clears data or opens another surface.
- Inbox retirement does not weaken terminal activity settlement, Repo Explorer activity rows, Git/PR refresh, or observability fail-open behavior.
- Binary rollback may read the preserved existing rows through the preceding implementation. No forward data migration is introduced.

## Proof Obligations

- Automated presentation/command coverage proves every global and pane-local Inbox surface is absent and dispatch is unavailable through interactive and IPC paths.
- Source/architecture coverage proves App does not mount Inbox, pass pane Inbox presentation, start Inbox store/router work, or read Inbox notification counts for Repo/pane chrome.
- Persistence inspection snapshots Inbox tables before and after boot/workload proof and proves identical schema and rows.
- Native debug proof shows Repo Explorer as the sole sidebar, no Inbox toolbar/pane controls, and no Inbox command-bar results.
- Marker-scoped performance proof retains the 150-repository, 180-worktree, 12-tab, 36-pane, one-active-PTY fixture; every existing 100-count admission/readback floor that remains meaningful; the `<30%` interval process-CPU threshold; Repo stage ratios; keyed-wake isolation; and zero trace/runtime/collector-drop gates. Only Inbox-specific commands, mutations, metrics, and surface-switch identities are owner-authorized supersessions. A replacement Repo-only command/readback sequence MUST preserve the workload duration and load class, and its new workload identity MUST reject stale Inbox-era baselines.

## Negative Space

- The dormant Inbox feature module is not deleted or redesigned.
- Historical notification data is not exposed through a replacement UI or export.
- The change does not promise indefinite compatibility for dormant source or schema; later removal requires a new owner decision.
