# Sidebar Organization Requirements

## Purpose

Help a person managing many repositories and terminal panes find work through clear navigation, independent pinning, and truthful terminal activity. The user directing this design owns the product decisions. Current source and native evidence establish implementation reality.

This is the Requirements identity. The separate [Specification](2026-09-07-sidebar-organization-specification.md) owns observable obligations; the separate [Program Design](2026-09-07-sidebar-organization-program-design.md) owns internal realization.

## Accepted sidebar model

```text
Row 1   [ Repos | Panes ] │ Filter…
Row 2   Pin │ ↑/↓  Name/Activity │ Repo → Activity
```

Row two uses compact command-backed controls: pinned-section visibility, the existing animated direction arrow, a Name/Activity sort picker, and one grouping summary. The grouping summary opens one two-column Group/Subgroup popover.

Repos is repository navigation and has no subgroup:

```text
Group: Repo                         Group: Activity
├── Pinned Repos                    ├── Pinned Repos
│   └── ▾ agent-studio              ├── Active
│       ├── agent-studio            ├── Just Now
│       └── agent-studio.sidebar    ├── Last Hour
├── Open Repos                      ├── Today
│   └── ▾ agent-vm                  ├── Last 7 Days
└── Available Repos                 ├── Older
    └── ▾ devfiles                  └── No Activity
```

Pinned Repos is first and exclusive when shown. Repo grouping partitions unpinned repositories into Open Repos and Available Repos. Activity replaces those two sections with fixed, noncollapsible activity buckets. Each repository remains expandable to its checkouts. Activity aggregates the newest eligible output timestamp across the remote identity. Section membership is per registered repository; remote-identity grouping then occurs within each section.

Panes keeps independent Pinned Panes and Other Panes sections. It groups by Repo, Tab, or Activity. Repo and Tab may subgroup by None or Activity; Activity has no redundant subgroup. Activity subgroup headings appear only when a parent contains more than one nonempty bucket.

Section headings use their entity icon and blue title treatment. Expandable repository/tab headers contain a chevron and title without an entity icon. Section and subgroup labels capitalize the first letter of every word and render the remaining lowercase letters as small capitals. Subgroups use secondary color and a trailing divider. Shared spacing gives noninitial sections and subgroups more room above without shifting leaf columns.

## Authorized needs

Stable identifiers remain owned here. Priority and decision authority belong to the user.

| ID | Need and outcome | Delivery |
| --- | --- | --- |
| U1 | Exactly two toolbar rows: Repos/Panes plus Filter, then organization controls. | Current branch |
| U2 | Direct, compact organization controls using existing command icons and tooltips. | Current branch |
| U3 | Repos offers Repo and Activity only; Repo uses Pinned/Open/Available and Activity replaces Open/Available with buckets. | Current branch |
| U4 | Panes offers Repo, Tab, and terminal Activity; activity never falls back to focus or click recency. | Current branch, accepted source limits |
| U5 | Repository and pane pins are independent; hiding a pinned section merges its items back without clearing or duplicating them. | Current branch |
| U6 | Buckets are Active, Just Now, Last Hour, Today, Last 7 Days, Older, and No Activity. | Current branch |
| U7 | State-changing sidebar choices use surface-specific command specs, preflight and the existing dispatcher. Selector open/dismiss remains local presentation state with LocalActionSpec metadata. Exact chords remain deferred. | Current branch |
| U8 | Search, membership, grouping, activity classification, sorting, and row derivation remain off MainActor; MainActor captures keyed facts and renders prepared results. | Current branch |
| U9 | Persist qualifying terminal activity across restart and establish Active from fresh evidence. | Deferred terminal-source scope |
| U10 | Preserve repository pins through the Favorite-to-Pinned cutover and persist pane pins independently. | Existing branch migration |
| U11 | Name/Activity sorting and direction are independent from grouping and from each other. | Current branch |
| U12 | Show unseen-activity dots for stopped, unseen pane activity. | Deferred; excluded here |
| U13 | Give actively producing terminals low-overhead motion. | Deferred; excluded here |
| U14 | Complete future activity coverage through zmx without a separate Ghostty-provider workstream. | Deferred; excluded here |
| U15 | Use zmx IPC for future source-owned activity metadata. | Deferred; excluded here |
| U16 | Deliver three dependent scopes: PR1 sidebar organization using existing activity; PR2 zmx update; PR3 zmx IPC and terminal history/indicator enhancements. Later work does not block PR1 implementation. | Staged boundary |
| U17 | Restore saved sidebar choices before defaults. Without saved values, Panes defaults to Repo grouping with Activity subgroup; both screens default to Name ascending. Saved None remains None. | Current branch |
| U18 | Use entity icons on sections, no entity icon on expandables, and quiet divided subgroups without extra leaf indentation. | Current branch |

## Choice model

```text
Repos                         Panes
├── Group: Repo               ├── Group: Repo
└── Group: Activity           │   ├── Subgroup: None
    └── No Subgroups          │   └── Subgroup: Activity
                              ├── Group: Tab
Sort                          │   ├── Subgroup: None
├── Direction: ↑ / ↓         │   └── Subgroup: Activity
└── Type: Name / Activity     └── Group: Activity
                                  └── No Subgroups
```

The popover keeps equally wide Group and Subgroup columns. Valid None stays selectable. Unavailable subgrouping retains the Subgroup header/icon and shows lighter noninteractive “No Subgroups”; invalid choices never dispatch.

Show Pinned defaults on independently on both surfaces. Selected is blue without persistent fill; unselected is neutral. The grouping summary reads `Main → Subgroup` when applicable. The sort picker changes type only; the animated arrow changes direction only.

## Truth, persistence, and scope boundaries

The current branch uses the existing settled-output timestamp. It can miss output outside current admission, suppresses identical settled lines, and is runtime-only. Missing evidence becomes No Activity. Focus, click, creation time, and old recency chips are never fallbacks.

Existing recency/focus chips and terminal indicators remain. Removing them was discussed but not authorized. Blue dots, running animations, zmx IPC, and vendor/toolchain updates are outside this branch.

Reuse existing grouping and per-surface organization persistence. Legacy `repoSubgroupMode` remains for compatibility but has no Repos effect. This latest correction adds no schema. The branch's existing pin migration remains.

No new atom, store, event, coordinator responsibility, source detector, focus fallback, or terminal protocol is authorized. Completion still requires automated gates, the real native panel/keyboard/sort/pin/settings path, and marker-scoped performance proof. This artifact claims no pass, review verdict, or PR readiness.
