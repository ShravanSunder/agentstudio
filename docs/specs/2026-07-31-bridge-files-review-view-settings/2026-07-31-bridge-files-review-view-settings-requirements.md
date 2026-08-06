# Bridge Files and Review Controls — User Requirements

Date: 2026-07-31
Target classification: general-domain
Normative home: user-visible product requirements for the Files and Review
surfaces in a Bridge pane.

Status: candidate specification for local specification/program review. This
document does not claim pair acceptance or authorize implementation.

## Purpose and consumers

This document defines what a person using Agent Studio can expect from Bridge
Files and Review controls. It owns the visible meanings of Filters, View
Settings, Search, source lifecycle states, and Web View Reload. It does not
choose React or Swift components, state owners, transport frames, call graphs,
test files, commands, or task order.

The consumers are:

- a person browsing every available file in a registered worktree;
- a person navigating a continuous review of changed files; and
- an implementer or reviewer deciding whether development and packaged Bridge
  surfaces satisfy the same observable contract.

## Authority and current observable problem

The product decisions governing this document are:

- Filters, View Settings, and Search are separate controls;
- matching Files and Review controls use one interaction and visual language;
- View Settings are a gear-button dropdown and last only for the current Bridge
  web presentation session;
- Files follows Review's filter presentation while omitting Review-only facts;
- `⌘⌥F` toggles Filters and `⌘⇧F` toggles Search;
- only a registered worktree is an authoritative Files or Review source;
- the current exclusive native file classification is retained and curated
  rather than replaced by a multi-axis taxonomy;
- Review Search is path-navigation search and does not filter continuous review
  content;
- WebKit's contextual Reload is removed, while an explicit command-bar Reload
  invokes the same page-reload behavior as a deliberate recovery escape hatch;
- when a Files Filter or Search, or a Review Filter, excludes the selected item,
  selection and selected content clear rather than moving automatically;
- Refreshing and Stale are distinct visible source states;
- losing registered-worktree authority resets Filters and Search immediately,
  and targeting a different registered worktree resets them before Loading;
- Review has no generic Show hidden filter, and Bridge exposes no default native
  context menu in this scope; and
- explicit Web View Reload keeps the existing native Bridge pane and source
  authority while restarting browser-local Files and Review state.

Repository constraints additionally require native Swift to remain the
packaged filesystem and Git authority, matching controls to share owned UI
primitives, typed shortcut presentation to remain singular, and visual/native
behavior to receive packaged proof.

Today, Files and Review controls do not always agree in presentation or
behavior. Some filter choices are not backed by complete packaged data. Search
clear, close, focus, and invalid-input behavior is inconsistent. Empty,
filtered, stale, unavailable, failed, and selected-content failures can look
the same. WebKit also exposes a contextual page Reload that looks like a Bridge
refresh even though it restarts the web presentation rather than refreshing
the authoritative source.

## Product model

```text
authoritative registered-worktree items
  -> Filters choose which items are eligible
      -> Search finds paths in the eligible navigation tree
          -> View Settings change only how visible content is rendered

explicit Reload Bridge Web View
  -> invokes the existing WebKit page Reload as an escape hatch
  -> restarts browser-local presentation state
  -> does not claim to refresh the authoritative native source
```

Files is the complete registered-worktree file browser. Review is a continuous
changed-file comparison with a navigation tree. The two products share control
mechanics, not mutable filter, search, or presentation values.

## Outcomes

O1. A person can predict what every control changes before selecting it.

O2. Every advertised filter is backed by complete native product data; a Vite
fixture cannot make an unavailable packaged capability look real.

O3. Search can be opened, cleared, closed, corrected, and left temporarily
without losing focus ownership or leaving an invisible query active.

O4. View Settings improve readability without changing source identity,
Filters, Search, selection, or the mounted Bridge product.

O5. Loading, refreshing, stale, source-empty, filter-empty, search-empty,
invalid, unavailable, failed, and selected-content-unavailable states remain
truthful and distinguishable.

O6. Files and Review remain read-only products. Ordinary interaction never
exposes browser page lifecycle as source refresh, while an explicit command-bar
escape hatch remains available for recovery.

## User requirements

### Shared controls

**UR-01 — Separate meanings.** Files and Review must present separate Filters,
View Settings, and Search controls. Filters change source eligibility. Search
finds paths within the eligible navigation tree. View Settings change rendering
only.

Pass: opening each control reveals only choices belonging to that meaning.
Negative: a rendering preference must not be presented as a file filter, and a
content-visibility choice must not be presented as a rendering preference.

**UR-02 — Shared interaction language.** Matching Files and Review controls must
use the same visual scale, spacing, focus treatment, open/close behavior, and
accessible naming. Surface-specific choices are allowed where their products
differ.

**UR-03 — Menu interaction.** View Settings must use an accessible gear-icon
button and a dropdown. Filters and View Settings must use the same owned dropdown
interaction contract in Files and Review, including keyboard dismissal and focus
return. This work does not introduce a second route-local menu lifecycle or
change the shared dropdown primitive's platform behavior merely because Search
is present.

### Filters

**UR-04 — Exclusive category vocabulary.** The retained native classifier gives
each file exactly one classification bucket. The category group exposes Source
code, Tests, Documentation, Configuration, Generated, Dependencies and build
output, Fixtures, and Other. `All` means no category restriction and therefore
also admits classification buckets governed by separate visibility controls.

These labels name exclusive classifier buckets, not inclusive facts. For
example, a large test classified as Large is not also classified as Tests. The
product must not imply otherwise. Replacing this limitation with multi-axis
classification is outside this work.

**UR-05 — Files Filters.** Files must expose one category group. Exactly one of
`All` or one visible category is selected. Files must not expose Git-status,
Binary, or Large choices. Large is only an exclusive size-precedence classifier
bucket rather than the independent visibility fact such a Files control would
imply.

**UR-06 — Review Filters.** Review must expose:

- one Git status group with exactly one of `All`, Added, Modified, Renamed,
  Deleted, or Copied selected;
- one category group with exactly one of `All` or the UR-04 categories selected;
  and
- independent visibility toggles for binary and large items.

The selected Git status and category are combined with AND. Visibility gates
are applied independently and do not bypass an active Git-status or category
selection. Consequently, enabling Binary or Large makes those exclusive
classes reachable under `All`; it does not make them match a different selected
category. Clear Filters returns both groups to `All` and turns every visibility
toggle Off.

**UR-07 — Visibility independence.** Review must not expose a generic Show
hidden control. Generated, Dependencies and build output, and Fixtures are
controlled directly by the category group and must appear when their category
is selected without requiring a second visibility gate. Binary and Large remain
independent visibility toggles, and each changes only its named gate.

**UR-08 — Truthful availability.** A filter may be shown only when the packaged
native source provides the complete fact needed to evaluate it. Development
fixtures may exercise a control but do not establish product authority. A
same-worktree replacement that omits a fact required by an already available
filter is not a complete accepted replacement for this surface: the previous
accepted product and filter value remain visible under the source-lifecycle
rules rather than silently resetting user state or leaving an invisible filter.

The existing programmatic Filter action remains supported and must express the
same per-surface groups and visibility toggles as the visible controls. It must
not install a category, status, or visibility value that the target Files or
Review surface cannot represent. An unsupported value is rejected atomically:
Filters, selection, selected content, projection, and focus remain unchanged,
and the caller receives a bounded rejection reason. This is one Filter model,
not a legacy programmatic state path beside the visible controls.

If a Files Filter or Review Filter makes the selected item ineligible, the
surface clears selection and selected content without automatically choosing a
replacement. Selection-specific content demand for that item ends, and focus
moves to the surface's eligible navigation tree. If that tree cannot accept
focus, focus moves to the active surface root. If the selected item remains
eligible, selection is unchanged.

### View Settings

**UR-09 — Files View Settings.** Files must offer Line numbers, Word wrap, and
Reset View Settings. Reset restores the surface's initial presentation values
without changing Filters, Search, source, or selection. This work does not
change the pre-existing initial rendering defaults.

**UR-10 — Review View Settings.** Review must offer:

- Line numbers;
- Word wrap;
- Change backgrounds;
- Diff layout with Split and Unified choices;
- Change indicators with Bars, Symbols, and None choices; and
- Reset View Settings.

Reset restores those values without changing Filters, Search, source, or
selection. Binary and Large are Filters and must not be duplicated in View
Settings.

**UR-11 — Session-local and surface-local values.** Files and Review retain
separate View Settings values for the current Bridge web presentation session,
including while switching between Files and Review or accepting a source
replacement. Values must not become durable application preferences or affect
another Bridge pane.

The explicit Reload Bridge Web View escape hatch is the sole exception and has
the deterministic reset contract in UR-24.

**UR-12 — Selection continuity.** Changing a View Setting must not reload,
resync, or remount the Bridge product, and the selected file must remain
selected. This work does not add an exact line-anchor or scroll-displacement
guarantee beyond the existing renderer's behavior.

### Search and focus

**UR-13 — Open and focus.** The Search trigger or `⌘⇧F` opens Search for the
active Files or Review surface, focuses its field, and selects existing query
text. Blur, file selection, and scrolling do not close Search.

**UR-14 — Clear and close.** While Search contains text, Clear empties the query
and error but leaves Search open. While Search is empty, Clear closes it. Escape,
the Search trigger, or `⌘⇧F` closes Search from any Search state. Every close
path clears query/error state and returns focus to the most recent valid focus
owner in that surface. No close path may leave an invisible active query.

Escape follows foreground-control ownership. If a Filters or View Settings menu
currently owns focus, the first Escape closes that menu and returns focus to its
trigger without clearing Search. Once Search owns the foreground interaction,
Escape applies the Search close contract above.

When the recorded focus owner is no longer valid, Search close falls back first
to the Search trigger and then to the active Files or Review surface root. It
must not focus an ineligible tree row or a retired surface.

**UR-15 — Search scope.** Files Search narrows the Files navigation tree by
path. Review Search narrows only the Review navigation tree by path; it must not
remove files from continuous Review content, change Review selection, or change
continuous-content demand. Text/regex mode remains surface-local for the web
presentation session. Next/Previous match navigation is not part of this path
filtering contract.

Both surfaces match the complete displayed relative path, not only the
basename. Leading and trailing query whitespace is ignored. Text and regex
modes preserve the existing ECMAScript `iu` matching behavior without added
Unicode normalization or locale-specific folding. Text mode treats the query
as a literal case-insensitive substring. Regex mode treats it as an ECMAScript
regular expression over the same path, and anchors retain their ordinary
regular-expression meaning. An empty trimmed query imposes no Search
restriction.

If Files Search excludes the selected item, Files applies the same clear-
selection, clear-content, and focus contract as UR-08. Review Search remains the
explicit exception because it changes navigation only.

**UR-16 — Correctable invalid input.** Invalid regex input must remain visible
with an accessible inline error. The navigation tree continues showing the last
valid query evaluated against the current accepted source generation. A
same-worktree replacement re-evaluates that last valid query against the new
generation; rows from a retired generation must not remain. A subsequent valid
edit or switching to text mode clears the error and applies the new projection.
Invalid regex is not an ordinary no-match state.

**UR-17 — Bounded input.** Search must reject oversized input safely and
accessibly through every visible and programmatic ingress. Rejection must be
atomic: the attempted value never becomes the field value, and the previous
query, validation state, projection, and focus remain. The announcement must
explain that the query is too long without exposing a worker/transport
exception. The concrete safety bound is a Program Design policy rather than a
public product promise.

**UR-18 — Shortcut discoverability.** The product must present `⌘⌥F` for Filters
and `⌘⇧F` for Search consistently in handlers, labels, tooltips, command
presentation, and keycap hints. No View Settings shortcut is required. Plain
`⌘F` and `⌘⌥⇧F` remain unclaimed by these Bridge controls.

### Source lifecycle and truthful states

**UR-19 — Registered-worktree authority.** Files and Review operate only on the
deepest registered worktree containing the pane's current working directory.
Resolution must not depend on registration order; registrations referring to
the same canonical root resolve through the registry's one canonical worktree
identity. If no registered worktree contains that directory, both surfaces must
show `Not in a watched worktree` rather than choosing a nearby repository, an
unrelated sole worktree, or development fixture data.

**UR-20 — Source replacement.** When a surface accepts a replacement with the
same registered `worktreeId`, it retains Filters, Search, and View Settings and
re-evaluates them against the replacement. When a different registered
`worktreeId` becomes that surface's authoritative target, it resets Filters and
Search immediately before the new source enters Loading and retains View
Settings. Filter or Search edits made while that new source is Loading survive
its first complete accepted product. Files and Review apply this rule to their
own source transitions; an inactive surface must not reveal stale constraints
when later activated.

For a same-worktree replacement, selection remains only when the replacement
identifies the same logical source item. If that item no longer exists,
selection and selected content clear without automatically choosing a
replacement. A rename retains selection only when the authoritative product
identifies the renamed entry as the same logical item; relative-path heuristics
must not invent continuity. A different-worktree replacement always clears the
old selection and selected content before the new source applies its ordinary
initial-selection behavior. A matching relative path in the different
worktree does not preserve the old selection.

Search reset means closed, empty, text mode, and no validation error. Filter
reset means every exclusive group returns to `All` and every visibility toggle
returns Off. If the pane's current directory moves from registered worktree A to
registered worktree B, A's accepted product stops being visible or interactive
as soon as B becomes the authoritative target. B then follows the initial-load
states below; A is never presented as Refreshing content for B.

Losing registered-worktree authority resets Filters and Search for both
surfaces once, closes their transient menus, and makes source-dependent Filters
and Search unavailable while `Not in a watched worktree` is active. View
Settings retain their pane-session values. A later transition to either the
same or a different registered worktree begins from the reset Filters/Search
state and retained View Settings.

If authority loss closes a focused Filters menu after its trigger becomes
unavailable, focus moves to the active surface root rather than a disabled or
retired trigger. View Settings continues using the shared dropdown's ordinary
focus-return behavior because that control remains available.

**UR-21 — State meanings and composition.** Source lifecycle, navigation
projection, Search validation, and selected-content availability are separate
visible lanes. A source status must not hide a correctable Search error, and a
selected-content failure must not replace a valid navigation tree.

Source lifecycle:

1. If the current directory belongs to no registered worktree, show Not in a
   watched worktree and no prior-worktree content.
2. While the first authoritative product is still constructing, show Loading.
   Any accepted non-empty progressive Files publication remains usable only as
   one self-consistent generation, and incomplete publication must not produce
   Source empty, Filter no match, or Search no match conclusions.
3. During same-worktree replacement, keep the previous complete accepted
   generation usable and label it Refreshing until one self-consistent complete
   replacement generation is accepted. Do not merge rows from old and new
   generations or replace the old generation with a partial replacement. If the
   replacement fails or is cancelled, retain the old generation; when no newer
   replacement remains active, label retained non-fresh content Stale with a
   bounded reason. Superseding replacement work keeps the old generation under
   Refreshing until a complete successor is accepted.
4. If an accepted product remains after freshness is lost and no replacement is
   active, keep it usable and label it Stale with a bounded reason.
5. Unavailable is reserved for an explicit authoritative capability outcome
   saying the registered worktree cannot provide this product when no accepted
   product exists and no construction is active. It does not replace Loading or
   hide a retained accepted product.
6. If construction terminates without any accepted product, show Failed with a
   bounded reason.

Navigation, validation, and content:

1. Only a complete accepted product with zero source items may show Source empty
   or Nothing to review.
2. If the source has items but Filters remove all, show Filter no match.
3. If eligible items exist but a valid Search finds none, show Search no match.
4. Invalid Search replaces only ordinary Search no-match presentation while the
   last valid query is re-evaluated against the current accepted generation.
5. A selected item's missing body is Content unavailable and must not replace
   the navigation tree or source lifecycle status.

**UR-22 — Failure and recovery honesty.** Unavailable, Stale, Failed, and Content
unavailable states must show bounded user-readable reasons. Raw provider errors
and fixture-only states must not be displayed as product truth. Existing
recovery and Retry behavior is not changed by this work; these controls must not
introduce a new recovery action or policy. Cancellation during replacement or
pane teardown must not appear as a terminal failure.

### Platform and read-only boundary

**UR-23 — No native browser context menu.** Bridge must replace WebKit's default
context menu with no native menu for this scope, so right-click exposes neither
page Reload nor other default browser actions. A future TypeScript-owned Bridge
context menu is separate work. Agent Studio's typed `⌘R` Management Layer
command must continue to execute once without page navigation or
web-presentation retirement.

**UR-24 — Explicit Reload escape hatch.** When the active pane is Bridge, the
`⌘P` command surface must offer `Reload Bridge Web View`. Invoking it calls the
same WebKit page Reload behavior currently exposed by the default contextual
Reload; moving the entry point must not replace the native Bridge pane,
controller, or host view.

The existing native-selected Files or Review surface and authoritative
registered-worktree source identity remain in place, and the action does not
request a native source refresh. Reload restarts the browser page, so both
Files and Review Filters, Search, and View Settings return to their initial
browser-session values, transient controls close, and browser-local selection
and viewport are discarded. The reloaded page then applies its ordinary
initial selection and viewport behavior.

The command description must disclose that browser presentation state is
discarded and distinguish the action from refreshing registered-worktree
source data. It has no direct keyboard shortcut beyond command-surface
discovery. Reload continues using the existing WebKit navigation and Bridge
page-reload bootstrap behavior; this work adds no native-host replacement,
custom Reloading or reload-failure presentation, duplicate-attempt policy, or
new recovery lifecycle.

**UR-25 — Read-only scope.** This work must not add editing, patch application,
comments, annotations, saved notes, review-state workflows, themes, durable
settings, new source identities, or TypeScript production Git/filesystem
authority.

## Cross-cutting obligations

Accessibility:

- icon-only controls require accessible names;
- active menu choices and visibility toggles expose their state;
- Search errors are announced without destroying the entered text; and
- keyboard-only interaction can open, operate, and close every control and
  recover a valid focus owner.

Reliability and security:

- strict input rejection must remain a controlled product state;
- native packaged source authority may not be replaced by Vite or TypeScript
  fixture authority; and
- page Reload must be possible only through the explicit command-surface escape
  hatch, not an ambiguous contextual action.

Performance:

- View Setting changes must update the existing presentation rather than reload
  or reconstruct source data; and
- Search and Filter changes must remain interactive while authoritative source
  preparation continues, without promising a numeric latency threshold here;
  and
- a Review visibility filter may cause newly eligible visible content to enter
  the existing content-demand path, but must not resync the authoritative source.

Privacy and persistence:

- this work adds no durable preference, query, or filter storage; and
- raw paths, queries, provider errors, or content must not be added to telemetry
  by these controls.

## Non-goals and negative space

- replacing the exclusive native classifier with multi-axis file facts;
- Files Git-status, binary-content, or large-file filters;
- content search or Next/Previous search-match navigation;
- filtering continuous Review content from the path Search field;
- redefining the existing initial View Settings values or adding an exact
  viewport-anchor guarantee;
- enabling Guided or Plans/specs Review modes;
- themes or durable settings;
- comments, annotations, notes, editing, or review workflow state;
- a contextual browser Reload or an implicit mapping from page Reload to native
  source refresh;
- a native Bridge context-menu action set or the future TypeScript-owned
  context menu;
- native Bridge pane, controller, or host replacement for explicit Web View
  Reload, or a new Reload lifecycle layered over WebKit navigation; and
- implementation choices such as component names, workers, Swift types,
  transport frames, test files, exact commands, or task ordering.

## Requirement-to-proof obligations

| Requirements | Evidence that distinguishes pass from fail |
| --- | --- |
| UR-01–UR-03 | Packaged visual and keyboard interaction plus shared-control behavior evidence |
| UR-04–UR-08 | Native-to-render contract/state inspection and packaged registered-worktree interaction, including exclusive-class counterexamples |
| UR-09–UR-12 | Presentation behavior plus selected-file continuity and absence of product reload/remount |
| UR-13–UR-18 | State-transition evidence and packaged WKWebView keyboard/focus interaction, including invalid and over-limit input |
| UR-19–UR-22 | Authoritative source replacement/failure inspection plus packaged state presentation |
| UR-23–UR-24 | AppKit/WebKit context-menu and key-routing evidence plus command-surface execution/read-back |
| UR-25 | Scope inspection proving no editing, persistence, source identity, or production-authority expansion |

Browser/component fixtures may prove control mechanics but cannot substitute for
packaged WKWebView shortcut, focus, native-source, or Reload proof.

## Traceability spine

```text
misleading or inconsistent controls
  -> predictable controls and truthful data (O1/O2)
      -> UR-01..UR-12
          -> visual, interaction, native-contract, selection, and mount evidence

presentation changes disrupting the product
  -> stable rendering-only settings (O4)
      -> UR-09..UR-12
          -> selection continuity and absence of reload/remount evidence

broken or inconsistent search lifecycle
  -> recoverable path navigation (O3)
      -> UR-13..UR-18
          -> state, focus, keyboard, invalid-input, and boundary evidence

ambiguous source, empty, and failure states
  -> truthful recovery (O5)
      -> UR-19..UR-22
          -> lifecycle transition and packaged state evidence

ambiguous browser Reload
  -> deliberate read-only recovery boundary (O6)
      -> UR-23..UR-25
          -> AppKit/WebKit, command-surface, and scope evidence
```

## Resolved tradeoffs and remaining design questions

The accepted product tradeoff is truthful but exclusive categories now instead
of a broader multi-axis taxonomy. This keeps the change bounded but means a file
cannot simultaneously appear as, for example, Tests and Large.

No unresolved product decision blocks Program Design. Exact initial View
Settings values and ordinary dropdown dismissal behavior are compatibility
inputs: this work preserves the existing rendering defaults and uses the shared
owned dropdown primitive rather than defining a new product convention. Program
Design must still prove that the supported WebKit/AppKit host can replace the
default context menu with no native menu, route the command-surface action to
the existing page Reload, bind every Search ingress to one internal safety
policy, and expose proof seams for packaged focus, source lifecycle, and command
execution. The current 4,096 UTF-16-code-unit worker bound is a compatibility
input to that policy, not a product promise. These are feasibility and
structural questions, not permission to change the requirements above.
