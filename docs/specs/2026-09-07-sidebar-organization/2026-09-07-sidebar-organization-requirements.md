# Sidebar Organization Requirements

## Purpose

Help a person managing many repositories and terminal panes find work through clear navigation, deliberate pinning, and terminal activity. The existing sidebar mixes worktree browsing and pane grouping in one control; long repository lists and repeated pane labels make scanning difficult.

The owner is the user directing the 2026-09-07 sidebar design conversation. The user-provided screenshots are observational evidence; the user's explicit corrections and selections below authorize desired changes. External application research is advisory, not governing authority.

This is the Requirements identity. A separate Specification must define observable behavior after the open decisions are settled; a separate Program Design must describe its realization. This document does not authorize implementation.

## What the sidebar will look like

These trees illustrate the agreed PR1 behavior (U1–U8, U10, U11, U17). Names and rows are examples, not current workspace data. Existing row metadata remains; it is omitted here to make the hierarchy readable. The Specification owns the exact behavior.

### The same two header rows in both screens

```text
Row 1   [ Repos | Panes ] │ Filter… fills remaining width
Row 2   Group controls │ Subgroup controls │ Sort │ ↑↓ │ Show Pinned
```

The second line names the control positions for this drawing. The actual header uses existing compact icons and selected-state treatment, without those explanatory captions, extra rows or an options menu. Each action comes from the command spec for its screen.

### Repos: repositories containing worktrees

Initial subgroup: None. Initial sort: Name ascending. Saved choices override both. Symbols below stand in for the existing entity icons; they are not new icon artwork.

```text
Repos selected │ Filter…
Repository │ None / Activity │ Name / Activity │ ↑↓ │ Show Pinned
────────────────────────────────────────────────────────────────
PINNED REPOSITORIES
▾ ▣ agent-studio
  ◇ agent-studio
  ⎇ main

  ◇ agent-studio.sidebar-useful
  ⎇ sidebar-useful

OPEN REPOSITORIES
▾ ▣ agent-vm
  ◇ agent-vm.oauth
  ⎇ oauth

OTHER REPOSITORIES
▾ ▣ devfiles
  ◇ devfiles
  ⎇ main
```

Pinned repositories appear once in their pinned section. Open Repositories contains the remaining repositories with open pane destinations; it does not mean a process is running. Other Repositories contains the rest.

Selecting Activity subgroup divides the worktrees within each repository without adding indentation to the worktree rows:

```text
PINNED REPOSITORIES
▾ ▣ agent-studio

  ACTIVE
  ◇ agent-studio.sidebar-useful

  LAST HOUR
  ◇ agent-studio

  NO ACTIVITY
  ◇ agent-studio.archived-work
```

### Panes: repository grouping with the Activity subgroup

This is the initial Panes organization. A saved None subgroup remains None.

```text
Panes selected │ Filter…
Repo / Tab / Activity │ None / Activity │ Name / Activity │ ↑↓ │ Show Pinned
─────────────────────────────────────────────────────────────────────────
PINNED PANES
▾ ▣ agent-studio

  LAST HOUR
  ◫ Pane 1 · agent-studio.review-comments

OTHER PANES
▾ ▣ agent-studio

  ACTIVE
  ◫ Pane 2 · agent-studio.sidebar-useful
  ▷ Latest terminal output…
  ⎇ sidebar-useful

  JUST NOW
  ◫ Pane 3 · agent-studio.issues-perf

▾ ▣ agent-vm

  TODAY
  ◫ Pane 1 · agent-vm.oauth

▾ ▣ No Repositories

  NO ACTIVITY
  ◫ Pane 2 · zsh
```

Only an individual pane pin puts a row in Pinned Panes. A repository pin never does. The pinned pane is not repeated below. Row labels above illustrate the existing pane-title format; this change does not introduce a new automatic naming system.

### Heading alignment and hierarchy

```text
OTHER PANES                 section: existing blue heading
▾ ▣ agent-vm                group: existing collapsible header

  ACTIVE                    subgroup starts at the icon column
  ◫ Pane 2 · agent-vm       existing icon and text columns
  ▷ Latest output…
  ⎇ main

  JUST NOW
  ◫ Pane 3 · review
```

Subgroup headings use the **same font as section headings**, including size, weight and casing treatment. Their color is existing secondary gray; top-level section headings retain the existing blue. Subgroup text starts at the row-icon column, not the disclosure-chevron column or pane-text column. Subgroups have no extra icon or independent disclosure arrow. Spacing separates them; pane and metadata rows keep their existing horizontal alignment. Collapsing the repository/tab hides its subgroups and rows.

### Panes: switch the main group without changing the screen

Group by Tab, subgroup by Activity:

```text
OTHER PANES
▾ ▣ Development

  ACTIVE
  ◫ Pane 2 · sidebar-useful

  JUST NOW
  ◫ Pane 3 · issues-perf

▾ ▣ Infrastructure

  TODAY
  ◫ Pane 1 · oauth
```

Group by Activity, with no redundant subgroup:

```text
OTHER PANES
  ACTIVE
  ◫ Pane 2 · sidebar-useful

  JUST NOW
  ◫ Pane 3 · issues-perf

  TODAY
  ◫ Pane 1 · oauth
```

Pinned Panes, when present, uses the same selected grouping above the ordinary Other Panes section. Switching back from Activity to Repository/Tab restores the saved subgroup choice. The option trees below describe logical choices, not extra visual indentation in the sidebar.

### All available combinations

```text
Repos
└── Group: Repository
    ├── Subgroup: None                     initial default
    └── Subgroup: Activity

Panes
├── Group: Repository
│   ├── Subgroup: Activity                 initial default
│   └── Subgroup: None
├── Group: Tab
│   ├── Subgroup: Activity                 unless saved otherwise
│   └── Subgroup: None
└── Group: Activity
    └── No extra subgroup

Activity buckets, in order
├── Active              evidence less than 1 minute old
├── Just Now
├── Last hour
├── Today
├── Last 7 days
├── Older
└── No activity         no usable evidence; row remains visible

Sort within each existing group/subgroup
├── Name                A–Z / Z–A
└── Activity            oldest / newest
```

Sort never moves the group headers or changes section membership. In PR1 the clock comes from the existing settled-output fact: it is not focus time, exact last-byte time, or proof that a process is running. Reliable output detection and new indicators belong to the later terminal work.

### Show Pinned changes organization, not visibility of items

```text
Repos: Show Pinned ON            Repos: Show Pinned OFF
├── Pinned Repositories          ├── Open Repositories
├── Open Repositories            │   includes pinned repos with panes
└── Other Repositories           └── Other Repositories
                                     includes other pinned repos

Panes: Show Pinned ON            Panes: Show Pinned OFF
├── Pinned Panes                 └── Other Panes
└── Other Panes                      includes pinned panes
```

Each screen remembers its own Show Pinned choice. Pin values are preserved when the section is hidden; no row disappears and no row is duplicated.

## Authorized needs

All rows below are required within the requested scope; priority assigner and decision authority are the user. Stable identifiers belong to this document.

| ID | Need and outcome | Evidence and authority |
| --- | --- | --- |
| U1 | Keep exactly two header rows. Row one contains Repos/Panes and a filter filling the remaining width. Row two contains group, subgroup, and sort controls. | Authorized: repeated explicit header corrections in the design conversation. |
| U2 | Make organization controls directly accessible and their choices understandable without a catch-all settings menu. Use concise labels and existing SF Symbols/command icon conventions. | Authorized: user rejects hidden controls and verbose text; requests existing icons. Presentation uses the existing compact icon controls; native width proof remains required. |
| U3 | Repos presents repository/worktree navigation with Pinned Repositories, Open Repositories, and Other Repositories sections. Open means repositories with open panes, not terminals currently producing activity. | Authorized: user selects exact section names and clarifies open-pane meaning. |
| U4 | Panes supports repository, tab, and terminal-activity grouping; time organization must reflect terminal activity, never focus or click recency. | Authorized: user explicitly distinguishes these grouping choices and rejects last-visited semantics. |
| U5 | Support independent repository pins in Repos and independent pane pins in Panes, with separate pinned-section visibility. Pane section names are Pinned Panes and Other Panes. Repository pins never affect pane state or membership, including when Panes is grouped by repository. Turning off Show Pinned removes the separate section and returns its items to ordinary grouping without clearing their pins or excluding them. Replace Favorite terminology with Pinned in relevant code and UI. | Authorized: user explicitly corrects mixed pin ownership and selects visibility option A. |
| U6 | Activity categories include Active, Just Now (the existing less-than-ten-minute bucket), Last hour, Today, and Last 7 days. | Authorized: user selects these times and corrects calendar week to Last 7 days. Older/missing evidence must remain visible rather than disappearing. |
| U7 | All sidebar actions use surface-specific command specs: Repos and Panes classify their own grouping, subgrouping, sort field/direction, pins and visibility. Keyboard and visible controls use the same existing dispatcher and surface context. Exact shortcut chords may be chosen later and do not block design; no view-local handlers or separate shortcut catalog. | Authorized: repeated explicit surface-specific command-spec requirement and decision to defer actual chords. |
| U8 | Preserve responsive operation by using the existing off-MainActor systems for search, filtering, grouping, subgrouping, sorting and other derivation. No sidebar work in pane views or view hot paths. | Authorized: repeated user corrections; existing projection ownership is implementation evidence, not permission for replacement machinery. |
| U9 | Retain terminal activity timestamps across application restarts; establish Active from fresh runtime evidence rather than a persisted active flag. | Authorized: user answers yes to this explicit persistence proposal. |
| U10 | Preserve repository pin selections during the Favorite-to-Pinned cutover and persist individual pane pins independently. | Authorized: user accepts the proposed repository column migration and new independent pane pin storage. |
| U11 | Offer Name and Terminal activity sorting in both screens, with separate ascending/descending direction. Sorting orders leaf rows within their existing sections/groups/subgroups; it must not change grouping, membership, or group order. Exclude Layout order because pane arrangements can change it. | Authorized: user accepts the two sort options, explicitly excludes arrangement-dependent ordering, and requests independent direction without changing grouping. New sort fields start at Name; saved direction is preserved. |
| U12 | Show a blue unseen-activity dot on the affected pane's sidebar row and its tab when activity has stopped and the user has not looked at it. | Authorized: explicit user request. Exact quiet/acknowledgement rules and restart persistence of unseen state remain open. |
| U13 | Give active terminals a small, low-overhead animation in the Panes screen using the existing visual vocabulary. | Authorized: explicit user request for an active animation. A rotating blue arc and static Reduce Motion equivalent are proposals, not owner-selected artwork. |
| U14 | Base terminal activity on the product's zmx-backed terminal path. Do not add a separate direct-Ghostty-provider workstream based merely on retained enum cases or fallback code. | Authorized: user corrects the provider-scope assumption; production creation paths explicitly select zmx. |
| U15 | Use zmx's existing IPC boundary to deliver session output-activity metadata to AgentStudio. | Authorized: user explicitly selects existing zmx IPC. This does not assert that output metadata or subscriptions already exist. |
| U16 | Deliver in three dependent scopes: first sidebar work using existing terminal activity, second a zmx update, third zmx IPC and the terminal enhancements. Do not make the first scope depend on the vendor update or new IPC signal. | Authorized: user selects this sequence and requests the design cycle for it. The three scopes preserve all needs without requiring later-source work in PR1. |
| U17 | Save the user's current sidebar selections through the existing persistence systems and restore them ahead of defaults. For Panes grouped by Repository or Tab, default the subgroup to Activity when no saved subgroup exists. | Authorized: user requires settings to be saved and proposes Activity as the Panes subgroup default. Activity as the main grouping has no redundant subgroup. |
| U18 | Align activity subgroup headings with the existing row-icon column, keep row indentation unchanged, and use the same font as top-level section headings. Subgroups use secondary gray while sections remain blue. | Authorized: user corrects alignment to the icon column, accepts the treatment, renames the bucket to Just Now, and explicitly requests the section font. |

## Three delivery scopes

The scopes divide delivery; they do not delete requirements or claim later behavior in the first change.

| Scope | Required outcome | Requirements carried |
| --- | --- | --- |
| PR 1: sidebar organization | Two screens, two-row controls, independent pins and migration, grouping/subgrouping, leaf sort/direction and keyboard changes using existing activity evidence. No zmx update or new zmx protocol. | U1–U8, U10, U11, U17; source coverage limited by current terminal machinery |
| PR 2: zmx update | Update the fork baseline with its prompt-redraw behavior retained and existing sessions preserved. Resolve build/toolchain requirements and verify attach/restore/resize and mixed-version behavior. No new activity protocol implied by the update. | U16; preserves the existing session/runtime foundation |
| PR 3: zmx IPC and terminal enhancements | Reuse internal zmx IPC design; add source-owned activity metadata and complete restart-safe terminal activity. New blue-dot/animation behavior is retained in this later terminal scope. | U9,U12–U15; U4/U6 gain improved source coverage rather than a new meaning |

PR 1 uses the existing timestamped settled-output fact for activity organization. It does not substitute focus timestamps, claim complete PTY coverage, or treat accumulating bursts as a reliably running terminal. New unseen dots and animation remain in the later terminal-enhancement scope under the three-PR split; U12/U13 are retained, not removed. PR1 preserves current indicators.

## Foundation and scope

The affected user is the person navigating parallel work. No new buyer, operator, remote API consumer or downstream-agent product journey is requested. Existing repository topology, pane identity, navigation, search, persisted favorite selections, command system, and off-main projection systems are foundations to preserve while changing the scoped behavior.

Source observations: `RepoExplorerProjection.swift` changes row kind and grouping across current repo/pane/tab modes; `RepoExplorerProjectionInputCapture.swift` uses lastInteractedAt for current pane recency; `PaneMetadata.swift` has no individual pin field; `EntityRecency.swift` defines opened/focused interactions. These establish current behavior, not authority to reuse focus timestamps for terminal activity.

Excluded: full provider session-history sidebar, Needs You/agent-completion classification, notification removal, unrelated infrastructure or vendor changes, implementation and actual PR delivery in this design cycle. PR 2 now explicitly scopes the zmx upgrade design; PR 3 scopes the zmx IPC extension design. Domain and SQLite changes necessary for the accepted sidebar behavior are design scope. The owner accepted the proposed cutover from repo.is_favorite to repo.is_pinned and addition of independent pane.is_pinned storage in core.sqlite; Program Design must verify the existing persistence paths and migration conventions. No separate pin atom/store or replacement off-main machinery is authorized by that storage decision.

Required evidence follows the repository contract: behavior through the actual sidebar and keyboard path, applicable automated gates, native visual proof for the two-row surface, and measured performance under terminal activity. Unit tests alone cannot establish native usability or performance.

## PR1 boundaries and later decisions

PR1 uses the current settled-output timestamp, not complete output detection or restart-safe terminal history. Its state owners, persistence scopes, default/migration rules, group membership and time predicates are defined in the Specification and Program Design. Existing settings always win; Panes defaults to Activity subgroup when there is no saved choice. Repos retains the existing un-subgrouped shape initially.

Exact keyboard chords are owner-deferred and do not block design. Native layout and runtime performance must be proved during implementation. PR2 update compatibility and PR3 IPC/history/acknowledgement design are later-scope work. The blue dots and active animation remain recorded requirements for that later terminal scope.

## Design navigation

- [Observable Specification](2026-09-07-sidebar-organization-specification.md)
- [Program Design](2026-09-07-sidebar-organization-program-design.md)

The companion documents define the first scope and retain the later update/IPC obligations separately. This design cycle does not authorize implementation or vendor changes.

## Current-system constraints exposed by source inspection

- Reuse Contract 7 source admission, TerminalActivityProjector, and the Repo Explorer derived-atom family/worker. Unseen-notification windows are attendance-dependent and cannot be the sidebar activity authority; accumulating output-burst state is not reset by quiet settlement and cannot be equated with current activity.
- Existing activity aggregate timestamps are monotonic uptime milliseconds. Persisted activity ages need a restart-safe wall-clock representation; do not store uptime as calendar time.
- Scrollbar aggregation includes viewport position changes. Its latest observation timestamp is not automatically the latest qualifying output timestamp. Output that redraws without increasing scrollback is also not established by positive-row-growth evidence alone.
- Current sidebar deadline selection derives per-pane dates on MainActor, and current pane capture formats recency there. The new design must not extend these computations on MainActor; use existing off-main projection ownership for time classification, deadline selection, search, filter, sorting and grouping.
- Current grouping is window-local UI state; current sort is workspace-local feature preference state. Preserve their actual owners and scopes; a shared label does not imply shared storage.
- Current surface routing and command dispatch exist, but group/sort AppShortcut bindings do not. Reuse the routing/catalog machinery rather than view-local key monitors.
- The pinned Ghostty revision is 332b2aefc6e72d363aa93ab6ecfc86eeeeb5ed28. Its renderer sends scrollbar updates only when scrollbar values change (`src/renderer/generic.zig:1380-1386,1451-1456`); the embedding action/callback API lacks a dedicated per-surface output notification. PR 1 accepts the existing evidence's in-place/alternate-screen coverage limits. PR 3 improves coverage at zmx IPC; broad render/wakeup events and a separate Ghostty extension are not substituted.
- `EagerDerivedAtom.startProjection` provides the existing detached execution guarantee. The projection adapter's By Tab preference capture currently preserves the previous sort order; this existing exemption conflicts with U11 and cannot survive the new sorting contract.
