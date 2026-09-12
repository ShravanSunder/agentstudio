# BridgeWeb component language — Requirements

Owner: Shravan Sunder.
[Specification](2026-09-07-specification.md) → [Program Design](2026-09-07-program-design.md).

## People and problem

Daily File/Review users need to distinguish actions, selected choices, field
values and supporting information without relearning each pane. Feature authors
need complete shared recipes and the freedom to build meaningful feature
components. Reviewers need actual consumer coverage and rendered evidence.

Importing a shadcn-style root does not guarantee either outcome: shared recipes
can disagree, and their compositions can independently style nested content.

## Authorized needs

These stable identities retain this cycle's needs. Each row is authorized by
the owner's September 7 discussion. U1/U2 are the owner's major invariants;
U3–U6 are required outcomes, without an invented relative ranking.

| ID | Need and why | Owner evidence |
| --- | --- | --- |
| U1 | One visual language through tokens, owned shadcn primitives, our composed components and feature screens. Feature-specific components are legitimate; competing recipes are not. | “feature composition should use shared components”; “we compose shadcn and then we make our own components on top of that for feature composition”; “do not use custom colors … use tokens.” |
| U2 | Preserve settled major surfaces, text roles and native-correlated core scales. | Owner's explicit settled surface table, reproduced below. |
| U3 | Coherent inner input, track, selected, hover, focus and disabled treatments; avoid available controls that appear unavailable. | Owner identified fading, 50% opacity, inconsistent font sizes and confusing foreground/background contrast. |
| U4 | Readable descriptive choices with distinct name, metadata, current/default facts and selection. | Owner's branch-list feedback and request for source inventory instead of trusting the spec. |
| U5 | Preserve domain and interaction behavior while normalizing presentation. | Earlier U2/U3/U8; explicit protection of the concurrent transport lane. |
| U6 | Inventory consumers, enforce composition and prove complete browser/native flows with independent review. | “full inventory”; “not just unit tests … whole flow”; “actual app”; independent rubric-based review requested. |
| U7 | See the comments selected for sharing before producing output, without navigating away from the code or introducing another editor; resolved comments must not appear or be sent as Pending. | “for now lets keep share”; “share should list all the comments … that would be copied”; the owner's earlier explicit instruction not to show or send Pending for resolved comments. The navigation Comments drawer was explicitly deferred to another PR. |
| U8 | Use a consistent floating drawer for comparison controls, with only one peer panel open at a time. | “lets make … this not a popover, but a drawer”; “peer drawers … opening one should close the other”; “set it to full for now.” |

## Fixed visual foundation

| Surface | Background | Main text | Supporting text |
| --- | --- | --- | --- |
| App header / toolbar | #272727 | #EAEAEA | #B8BCC4 |
| Floating panel / raised card | #303238 | #EAEAEA | #B8BCC4 |
| File tree | #27282B | #EAEAEA | #B8BCC4 |
| Individual file header / code-view scrollbar track | #27282B | Existing header text roles | Existing header text roles |
| Code canvas | #282C34 | Existing renderer palette | Existing renderer palette |

Product identity remains #409CFF; syntax colors remain separate. Existing
annotation surface choices and the compact native-correlated scales are preserved.

The owner selected the cool floating-surface trial after comparing #292929 and
#303030, then requested moving on with the two panel changes. File-header and
code-view scrollbar backgrounds match the tree without changing the app toolbar
or reading canvas. The header's bottom divider is removed, its height preserved,
and Open in Files uses an outlined control. Expanded ghost buttons use the
existing #363636 muted fill when idle; hover and other variants remain unchanged.

## Earlier requirements and scope

The [earlier Requirements](../2026-08-16-bridgeweb-design-tokens/2026-08-16-requirements.md)
remain governing rather than being silently replaced:

| Earlier identity | Disposition |
| --- | --- |
| U1, U2 | Preserved; current U1 explicitly includes legitimate feature components. |
| U3 | Annotation context preserved; shared controls participate, domain transitions do not change. |
| U4, U5 | Preserve product/syntax distinction and compact scales. |
| U6, U7 | Preserve mechanical enforcement and equivalent running-product evidence. |
| U8 | Preserve renderer contracts; only tree/code background equality is superseded by the owner's #27282B choice. |
| U9, U10 | Preserve unconditional dark appearance and guidance at working source/architecture homes. |

Permitted later implementation: BridgeWeb tokens, owned primitives, shared
patterns, feature compositions, presentation metrics, enforcement, tests and
scoped guidance, plus the targeted native Pending-selection correction below.
This design task itself does not authorize product edits.

Protected: transport/tab ownership, native/SDK integration, persistence, DTOs,
comparison semantics, annotation focus/resolution authority and output lifecycle, Pierre
internals, Ghostty and dependency upgrades. AppStyles is a convention reference,
not a write target. No new state store, coordinator, event bus, theme runtime,
generated synchronization or second component library.

The Share work also corrects the recorded resolved-thread Pending rule in
[ANP-U5](../2026-08-24-worktree-annotation-new-pending/2026-08-24-requirements.md#anp-u5--identify-pending-human-work-before-handoff).
That targeted correction does not authorize changing All membership, immutable
History Repeat, handled/viewed storage, snapshot/revision checks, command
execution, or comparison meaning. Native output selection remains native-owned
and must agree with the UI; a UI-only exclusion is not sufficient.
A navigation Comments drawer, editing/replying
inside a drawer, stacked/nested panel navigation, arbitrary resizing and new
height controls are outside this change. Share keeps its current presentation
and scope controls; Compare uses full viewer height. Existing output-in-progress
dismissal protection remains applicable when switching peer panels.

## Inner-control decision basis

The owner explicitly confirmed the September 7 proposal: neutral input fill,
transparent outlined tracks, main-text selected labels over 15% product tint,
descriptive rows with ordinary rows remaining 28px, and contrast targets
of 4.5:1 for enabled text and 3:1 for meaningful indicators. This is a deliberate
exception to the earlier single-line 28px row convention for two-line content,
not a change to the 20/24/28/32px action-control ladder.

The owner's subsequent typography direction requires aligning semantic roles,
not merely using corresponding scales: list title uses textBase/text-base,
metadata and search use textSm/text-sm, compact actions use textXs/text-xs.
This supersedes the trial's 11/9px descriptive typography and derived 36px height.
The source-backed native list mapping is 13px-equivalent primary and 12px supporting;
the same web roles use those values. Existing code typography remains separate.

The Specification owns the exact observable treatment. Real browser/native proof
is still required; confirmation of a trial is not evidence that it renders well.
