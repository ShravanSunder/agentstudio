# Inbox Retirement — Requirements

## Authority And Evidence

- The product owner explicitly retires both the global Inbox sidebar and pane-local Inbox presentation. The owner requires the implementation and existing persisted rows to remain intact for a later data-safe removal, while all presentation, command access, and new notification collection are disabled now.
- The owner selected this boundary after the real-size demand-admission workload attributed 418 scheduled CPU samples to `InboxNotificationSidebarView.repoPresentationByRepoId`, 322 to `RepoPresentationGrouping.buildGroups`, and 304 to `InboxNotificationSidebarView.body` on MainActor.
- Current source is observational evidence: App composition mounts the global Inbox beside Repo Explorer, starts `InboxNotificationStore` and `InboxNotificationRouter`, exposes global and pane-local commands through command bar, toolbars, shortcuts, and IPC, and supplies Inbox counts/actions to Repo Explorer and pane chrome.

## Affected Classes

- **U1 — Interactive Agent Studio users:** need the repository sidebar and terminal workspace to remain responsive without an unused Inbox surface performing work.
- **U2 — Existing workspace owners:** need previously persisted Inbox rows left untouched until a later explicit removal decision.
- **U3 — Maintainers:** need the retirement boundary to be unmistakable so dormant Inbox code is not accidentally reconnected.

## Authorized Needs

### U-INBOX-1 — Retire Inbox presentation

**Priority:** P0, assigned by the product owner.

U1 must have no global or pane-local Inbox UI, badges, notification counts, or interactive entry points. Repo Explorer is the only application sidebar surface.

### U-INBOX-2 — Stop unused Inbox work

**Priority:** P0, assigned by the product owner.

U1 must not pay for global or pane-local Inbox projection, routing, promotion, persistence observation, or new notification writes while Inbox is retired.

### U-INBOX-3 — Preserve dormant implementation and data

**Priority:** P0, assigned by the product owner.

U2 requires existing Inbox source, schema, and persisted rows to remain present and unmodified. This retirement must not delete, clear, migrate, or rewrite notification history.

### U-INBOX-4 — Make the boundary explicit

**Priority:** P1, assigned by the product owner.

U3 needs surviving Inbox composition and persistence boundaries to state that presentation and ingestion are intentionally retired, retained only for later data-safe removal, and must not be reconnected without a new owner decision.

## Boundaries

- In scope: App composition, global and pane-local Inbox presentation, command catalog/presentation/dispatch, shortcuts, toolbar actions, IPC exposure, startup routing/store activation, Repo Explorer notification entry points/counts, persisted sidebar-surface normalization, architecture documentation, and proof.
- Preserve Repo Explorer grouping/activity/Git/PR behavior and the demand-admission repairs checkpointed at `f275a07e2`.
- Preserve all Inbox source files, atom types, persistence schema, and existing database rows.
- Do not add a rollout feature flag, alternate Inbox implementation, data migration, placeholder notification UI, or compatibility presentation path.
- Full source/schema deletion and data disposition are deferred to a separate owner-authorized change.
