# Requirements: BridgeWeb Design-Token Harmonization

Owner: Shravan Sunder (sole product owner and decision authority).
Decisions referenced below (D1–D3, accent, visual invariant) were made and
confirmed by the owner in the 2026-08-16 design session.

## Who is affected

| Class | Relationship |
|-------|--------------|
| Implementing agents (Sol at low effort, future agents) | Write BridgeWeb UI code; today they must guess between competing vocabularies |
| Owner | Reviews visual changes; today cannot tell which values are load-bearing |
| End user (the owner, daily driver) | Sees the rendered Bridge file/review surfaces |
| Pierre (`@pierre/diffs`, `@pierre/trees`) | Vendored code-presentation system consuming `--diffs-*` variables and TS theme objects |
| Comment-system lane (active Sol worktree) | Needs a designed inline-comment styling context to build against |
| Native Swift app | Shares the product's visual identity; accent currently floats with macOS settings |

## Needs

### U1 — One canonical styling vocabulary `authorized`

Agents repeatedly produce visually wrong UI (random control sizes, wrong
colors) in BridgeWeb because two color vocabularies coexist with
overlapping names and conflicting meanings, plus ad hoc raw values.

Evidence (verified 2026-08-16 at branch head):
- `--accent` = `#343842` (gray hover wash) vs `--bridge-accent` = `#89b4fa`
  (blue brand): same word, different colors.
- `--muted` is a background; `--bridge-text-muted` is a foreground.
- 35 files reference `var(--bridge-*)` (~290 refs); 13 files use shadcn
  utilities; both active, neither authoritative.
- `#343842` appears under 6 different token names; `#1d2026` under 3.
- `git log` on `BridgeWeb/src/app/bridge-app.css`: the `--bridge-*`
  namespace accreted through ~15 "match/polish/align chrome" patch commits
  (2026-06), not deliberate design.

Owner decision **D1**: shadcn-convention semantic roles become the single
canonical vocabulary (extended with app-specific roles); `--bridge-*`
color tokens are removed by hard cutover; `--diffs-*` survives as
Pierre's derived contract; the `accent` collision resolves in shadcn's
favor (blue = `primary`). Priority: highest (assigner: owner).

### U2 — Preserve the approved look of file/review views `authorized`

The current Bridge file-viewer and review-viewer appearance is
owner-approved ("looks good"), but it was achieved through hand-tuned
one-off CSS. The refactor must preserve the rendered appearance; only
individually named normalization deltas may be visible.

Owner statement 2026-08-16: "before this comments stuff bridge
file/review view in the app looks good, but … made in a way that's not
maintainable." Priority: highest — this is the safety constraint on all
migration work (assigner: owner).

### U3 — Styling context for the inline-comment system `authorized`

The comment/annotation lane (separate active Sol worktree) is building on
improvised tokens (`--bridge-annotation-*`, invented in PR #259 era) that
belong to neither shadcn nor Pierre. It needs a designed inline-comment
styling context derived from the canonical system, harmonized with
Pierre's code canvas. Priority: high — the active lane consumes this
early (assigner: owner).

### U4 — Native accent pinned to product blue `authorized`

The native Swift app uses `Color.accentColor` / `.controlAccentColor`
(~20 sites), which follow the user's macOS System Settings accent, while
the web side pins `#89b4fa`. The two sides match only by coincidence.
Owner decision 2026-08-16: pin the native accent to the product blue,
deliberately overriding the macOS accent preference (consistent with the
already-pinned dark theme). Priority: medium (assigner: owner).

### U5 — Compact density harmonized to AppStyles by hand `authorized`

The app is a compact, dense terminal product. Web styling must mirror the
native scale system in `Sources/AgentStudio/Infrastructure/AppStyles.swift`
(`General`: type ramp 9/11/12/13/14/16/24, fill washes .04–.15, strokes
.10–.25, radius 4/6/8/14, spacing 4/6/8, motion 120/200ms) so both sides
of the bridge feel like one app. Owner decision **D2**: relative sizes
preserved, everything brought down to compact as the *default*;
harmonization is by hand (no Swift→web generation). Colors come from the
PR #294 gray palette (Ghostty-derived neutrals + Catppuccin accent hues)
formalized as primitives. Priority: high (assigner: owner).

### U6 — Drift must be mechanically preventable `authorized`

Today nothing stops an agent from adding a raw hex, a one-off px size, or
a new ad hoc token. The owner requires enforcement so violations fail the
PR gate rather than reaching review. Evidence: the accretion history
(U1) and the discovered tree-theme drift (U8). Priority: highest, paired
with U1 (assigner: owner).

### U7 — Owner reviews visual change via draft PRs `authorized`

Process constraint from the standing SOP: UI-affecting work lands as
draft PRs with before/after screenshots; the owner reviews before merge.
This constrains delivery, not product behavior.

### U8 — TS-side theme objects must not drift from the palette `authorized`

Discovered 2026-08-16 (observational evidence, authorized for inclusion
by owner decision **D3** full-BridgeWeb scope; evidence corrected by
independent review): `bridge-viewer-tree-theme.ts` carries pre-#294
Catppuccin Mocha hexes in its theme object, but 14 `--trees-*-override`
variables (lines 50–71) already point the major surfaces at chrome
tokens, so most of those hexes are not on screen. The live residual
drift is confined to non-overridden keys (`descriptionForeground`
#6C7086, section-header foreground #BAC2DE, git-decoration colors).
`bridge-code-view-theme.ts` spreads `catppuccin-mocha` with two
overrides. Both TS theme objects must source from the canonical
palette so the compensating-override pattern (hexes shadowed by a
second layer) cannot recur. Priority: high — the pattern, not just the
residual pixels, is the class of bug this work eliminates.

### U9 — The app is dark-only, enforced `authorized`

Owner directive 2026-08-16 (with screenshot evidence of light-mode
leakage): the app must render dark regardless of the macOS appearance
setting. Verified current state: native has no app-level appearance pin
(only `TerminalSurfaceScrollView.swift:338` sets per-surface appearance
— an intentional terminal-content exception); the web root carries no
`.dark` class, so `dark:` variants in owned components never apply.
Light appearance must not be able to leak into chrome on either side.
Priority: high (assigner: owner).

### U10 — Rules live in agent docs and in the code itself `authorized`

Owner directive 2026-08-16: the token system's rules must be explained
in agent instructions (AGENTS.md scope) and a permanent architecture
document, and guiding comments must live *in* the source-of-truth files
(`AppStyles.swift`, `bridge-app.css`) so an agent editing either file
meets the contract at the point of edit, not only in external docs.
The two sources of truth (`AppStyles.swift` native, `bridge-app.css`
web) are correlated by convention; the correlation map is part of this
documentation. Priority: high, paired with U6 (assigner: owner).

## Goal boundary (owner-confirmed)

- **Goal**: one canonical, shadcn-conventional design-token system for
  BridgeWeb, hand-harmonized with native AppStyles scales and the #294
  palette, with the existing approved look preserved and drift blocked at
  the PR gate.
- **May change**: `BridgeWeb/src/**` (token CSS, `components/ui/`, app
  chrome CSS/TSX, annotation styling, TS theme objects, lint/test
  config); `Sources/AgentStudio/**` only for the bounded native slice
  (AppStyles color role + `.tint` application + replacing direct
  accent reads + app-level dark appearance pin); BridgeWeb build/lint
  tooling for the enforcement gate; AGENTS.md scope files and
  `docs/architecture/` for the U10 documentation.
- **Protected**: Pierre package internals (no fork, no patches); the
  `--diffs-*` variable names (Pierre's consuming contract); Ghostty
  vendor; the Swift bridge protocol and transport; comment-system
  *product behavior* (separate lane and spec — this work supplies only
  its styling context).
- **Execution constraint**: all edits are executed by Sol (gpt-5.6-sol,
  low effort) from briefs; artifacts must be prescriptive enough that
  execution is lookup, not judgment. One worktree/branch/PR per
  independent slice.

## Non-goals

- No light theme; `color-scheme: dark` stays pinned.
- No redesign of the approved file/review appearance; this is plumbing.
- No new palette design: neutrals are the #294 grays; accent hues remain
  the current Catppuccin set. Formalization, not invention.
- No automated Swift↔web token generation or sync tooling.
- No support for following the macOS accent preference (deliberately
  overridden).
- No shadcn upstream version migration as part of this work.
- No comment-system product behavior (threading, drafts, persistence,
  interaction design) — separate spec and lane.
- No Pierre fork or app-side scroll/selection mechanisms (standing
  constraint from prior Pierre work).

## Unresolved

- **D4 (CLOSED — owner kept Catppuccin Mocha accents, 2026-08-16): palette-family coherence.** The current
  approved rendering mixes three palette families (One-Dark-family
  neutrals, Tomorrow-Night ANSI/text values, Catppuccin Mocha accents
  and syntax). This work formalizes the current values unchanged
  (visual invariant). Whether to later unify accents/syntax to one
  family is an owner decision, cheap to explore after tokenization
  (a primitives-block edit + screenshot A/B).
- Exact neutral-ramp hex assignments and role names are design-time
  choices delegated to the Specification/Program Design and reviewed
  by the owner via draft PR screenshots.
