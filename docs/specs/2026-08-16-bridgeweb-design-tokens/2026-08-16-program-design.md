# Program Design: BridgeWeb Design-Token Harmonization

Requirements: [2026-08-16-requirements.md](./2026-08-16-requirements.md) (U1–U10)
Specification: [2026-08-16-bridgeweb-design-tokens.md](./2026-08-16-bridgeweb-design-tokens.md) (R1–R13)

This document is the structural realization. Migration executors (Sol)
work from the tables here plus per-slice briefs; every mapping decision
is made in this document or its mapping appendix, never at edit time.

## 1. Integrated overview

**Two sources of truth, one per platform, correlated by convention
(owner decision 2026-08-16):** `AppStyles.swift` owns the native design
system; `bridge-app.css` owns the web design system. Their
correlation is hand-maintained and documented in the tri-system map
(§4.0); no cross-platform tooling enforces it.

```
NATIVE SOURCE OF TRUTH          WEB SOURCE OF TRUTH
AppStyles.swift                 bridge-app.css
  scales, washes, strokes,        ── primitives block (authoritative
  radius, motion, accent             web values: neutrals, text, hues,
  (SN adds first color role)         ANSI, washes, strokes)
        ▲                          ── semantic roles block (shadcn +
        │ correlated BY              extended, §4.2) in @theme inline
        │ CONVENTION (§4.0        │
        │ map; hand-harmonized)   ├──► Tailwind utilities (Tailwind v4)
        ▼                         ├──► --diffs-* block (Pierre, §5)
  native UI                       ├──► comment context block (§6)
                                  └──► system tokens (§4.4)

bridge-design-palette.ts        DERIVED mirror of the CSS primitives
  (new, src/design-tokens/)      block, for TS consumers (tree + Shiki
        │                        themes import it). Gate rule enforces
        ▼                        exact equality with the CSS block —
  TS theme objects               CSS stays canonical.

components/ui/*                 ALL interactive-control geometry
check-bridgeweb-design-tokens.ts enforcement (5 rules + burn-down)
  (in pnpm run check → mise run test)
```

Forbidden edges (checker-enforced or review-enforced):
- No file except the palette module and the CSS primitives block may
  contain a color literal (checker rule 1).
- Roles reference primitives only; contexts reference roles or
  primitives; feature code references roles/contexts only (via
  utilities or `var()`).
- TS theme objects import the palette module; they never restate hexes.
- Feature code never defines interactive-control geometry (rule 3).

## 2. Current system (evidence-anchored)

Four independent styling channels exist today; all verified at branch
head 2026-08-16:

| Channel | Evidence | Disposition |
|---------|----------|-------------|
| shadcn roles, raw hexes in `:root` | `bridge-app.css:54–87` | values become primitive refs; vocabulary becomes canonical |
| `--bridge-*` (~40 tokens, ~290 refs, 35 files) | `bridge-app.css:88–133`, `rg var(--bridge-` | retired via alias-then-delete cutover (§7) |
| bespoke control CSS | `.bridge-worktree-file-*` at `bridge-app.css:291–420` | replaced by owned components (§8 S2) |
| TS theme objects w/ stale Catppuccin hexes | `bridge-viewer-tree-theme.ts:4–25`, `bridge-code-view-theme.ts:7–17` | re-sourced from palette; tree recolor is a named delta |

Also load-bearing current facts:
- Owned Button is already compact: default `h-7` + `text-xs`
  (`components/ui/button.tsx:24–35`) — it already matches the 28px
  bespoke toolbar controls; migration is substitution, not redesign.
- Textarea default `min-h-16` + `text-sm` (`components/ui/textarea.tsx:10`)
  is the one oversized owned default (the "box in a box" in comments).
- `pnpm run check` already runs `scripts/check-bridgeweb-architecture.ts`
  (TS-AST rules, .ts/.tsx only) inside `test:bridge-web:check` →
  `mise run test`. Token enforcement gets a sibling script, same wiring.
- `pnpm run proof:visual:dev-server`
  (`scripts/capture-bridge-viewer-dev-visual-proof.ts`) is the existing
  screenshot seam for R4 evidence.
- Native accent is unpinned: ~20 `Color.accentColor` /
  `.controlAccentColor` sites (rg inventory in §9).

Constraint degree: compatibility-bound (Pierre's `--diffs-*` names and
the approved rendering are fixed); otherwise legacy-ownership-bound.

## 3. Crux and selected direction

**Crux: how do TS theme objects (tree/Shiki) consume the palette when
the owner has fixed `bridge-app.css` as the web source of truth and
ruled out codegen?**

Owner decision (2026-08-16): sources of truth are `AppStyles.swift`
(native) and `bridge-app.css` (web), correlated by convention. That
removes any "TS module canonical" option; the remaining choice is how
TS consumers get values:

| Alternative | Shape | Verdict |
|-------------|-------|---------|
| A. TS reads `getComputedStyle` at runtime | one physical source | Rejected: Shiki/tree themes need static values at registration (worker + registration timing); runtime reads add lifecycle fragility for zero product gain |
| B. Derived TS mirror module (`bridge-design-palette.ts`) hand-copied from the CSS primitives block; gate enforces exact equality, CSS canonical | one authority, two physical homes | **Selected**: static values for TS consumers, no build machinery; drift is impossible because the checker compares CSS block → module every PR |
| C. Generate the TS module from CSS at build (Vite plugin) | one physical source | Rejected: build tooling the owner didn't authorize ("by hand"); debugging generated tokens costs more than the mirror check |

Debt accepted for B: a palette change touches two files. Payer: the
editing agent; the gate converts forgetting into a red check, not a
visual bug. Falsifier: if palette changes become frequent enough that
the two-file edit is a real tax, revisit C.

**Second crux: do Tailwind utility names keep stock sizes or re-anchor
to the AppStyles ramp?** Selected: re-anchor (`--text-xs` = 11px,
`--text-sm` = 12px, `--text-base` = 13px, `--text-lg` = 14px,
`--text-xl` = 16px, `--text-2xl` = 24px) — one mental model,
`text-sm` means the same thing as native `textSm`. But the honest
blast radius is larger than font-size alone, because Tailwind v4's
paired `--text-*--line-height` tokens are unitless ratios that scale
with the override:

| Utility | Sites | Font-size | Line-height if ratio kept |
|---------|-------|-----------|---------------------------|
| `text-xs` | 56 | 12px → 11px (−1) | 16px → 14.67px (−1.33) |
| `text-sm` | 13 | 14px → 12px (−2) | 20px → 17.14px (−2.86) |

Therefore the re-anchor ships as its OWN slice (S1b, §8), never inside
S1: S1 stays visually silent; S1b pins both `--text-*` and
`--text-*--line-height` to explicit values (leading from a designed
table, not inherited ratios), ships the delta table above in its PR,
and gets its own screenshot review. Falsifier: if owner review rejects
S1b, keep stock sizes and map each surface explicitly; the role
architecture is unaffected either way.

## 4. Canonical token system

### 4.0 Tri-system correlation map (how native ↔ web ↔ Pierre relate)

The harmonization contract, maintained by convention. `exact` means
the same values under corresponding names on both sides; `convention`
means a documented correspondence an editor must consciously preserve;
`approximate` means the two sides express the same intent through
different mechanisms and only the intent is promised. This table is
the normative home of the correlation (R12 architecture doc mirrors it).

| Concern | AppStyles.swift (native SoT) | bridge-app.css (web SoT) | Pierre / TS consumers | Class |
|---------|------------------------------|--------------------------|------------------------|-------|
| type ramp | `Typography.textXxs..text2xl` 9/11/12/13/14/16/24 | `--text-2xs..--text-2xl`, same values | code view font-size = textSm (12) | exact |
| state fills | `Fill` .04/.06/.08/.10/.12/.15 | `--palette-wash-*`, same alphas | row hover/selected via roles | approximate — native composes washes over material; web's EXISTING hover/selected keep their pinned hexes (accent n4, selection n5; white@8% over n1 renders #393d44 ≠ #343842, so the mechanisms are not interchangeable). Wash primitives are reserved for NEW surfaces without a legacy hex; switching an existing surface to a wash is a visible delta requiring enumeration |
| strokes | `Stroke` .10/.15/.20/.25 | `--palette-stroke-*`, same alphas | `--diffs-border-*` via border/input roles | exact |
| radius | `CornerRadius` 4/6/8/14 | `--radius-*` rebased to the same effective set | — | exact |
| spacing | `Spacing` 4/6/8 | Tailwind 4px grid, blessed steps 1/1.5/2 | — | convention |
| motion | `Animation` 120/200ms | `--motion-fast/-standard` | — | exact |
| accent | `accentPrimary` #89B4FA (added by SN) | `--primary` | `--diffs-token-link`, `--diffs-token-function` | exact |
| status hues | (none today; adopt on demand) | success/warning/destructive | `--diffs-token-inserted/-deleted/-changed`, git decoration colors in tree theme | convention |
| neutrals | system materials + alpha washes (no hex ramp) | ramp n0–n5 fixed hexes | `--diffs-background`, tree bg via palette mirror | approximate — native composes washes over materials; web pins hexes chosen to land on the same rendered grays |
| text tiers | `Foreground` opacities .5/.6/.7 over material | text-primary/secondary/muted/faint fixed hexes | `--diffs-foreground`, tree fg | approximate — same 4-tier intent, different mechanism |
| appearance | app-level dark pin (SN) | `color-scheme: dark` + single styling branch (§6.5) | Pierre themes registered `type: 'dark'` only | exact |

Reading the map: an agent changing a row on one side must check the
correlated cell on the other side; `exact` rows are expected to stay
value-identical, and the R12 contract comments in both files point
here.

### 4.1 Primitives (web values, CSS-canonical)

Home: the `bridge-app.css` primitives block (authoritative for web),
hand-mirrored into `BridgeWeb/src/design-tokens/bridge-design-palette.ts`
(derived, for TS consumers; gate-enforced equality per §10). Values
below are the current rendered values (visual invariant); names are
the design.

```
NEUTRAL RAMP (darkest → lightest)          TEXT TIERS
n0  #1d2026  chrome/surface level           text-primary   #ffffff
n1  #282c34  canvas/app background          text-secondary #eaeaea
n2  #30343d  sidebar hover accent           text-muted     #c5c8c6
n3  #323641  card / popover                 text-faint     #9ba1ad
n4  #343842  raised / wash-equivalent
n5  #464b57  selected / strong border

ACCENT HUES (Catppuccin set, unchanged)
blue #89b4fa (PRIMARY, pinned)   green #a6e3a1   yellow #f9e2af
red #f38ba8   mauve #cba6f7      peach #fab387   teal #94e2d5
lavender #b4befe (ring)          subtext #bac2de

WASHES (white-alpha, mirrors AppStyles.General.Fill)
wash-subtle .04   wash-muted .06   wash-hover .08
wash-pressed .10  wash-active .12  wash-selected .15

STROKES (white-alpha, mirrors AppStyles.General.Stroke)
stroke-subtle .10  stroke-muted .15  stroke-hover .20  stroke-visible .25

ANSI TERMINAL PALETTE: the 16 --diffs-ansi-* values move here verbatim.

COMPOSITION BASES
white → reuse text-primary (#ffffff)     black #000000 (shadow base)
```

Composition rule: color literals exist ONLY in the primitives block.
Every translucent value elsewhere (system tokens, contexts, aliases) is
a `color-mix(in srgb, var(<primitive-or-role>) N%, transparent)`
composition preserving the exact current alpha. This is why `black` is
a primitive: shadows compose from it.

Normalization deltas built into primitives (each enumerated in its
owning PR): `--input` alpha .18 → stroke-hover .20 (S1); tree-theme
residual keys → ramp/text equivalents (S4 — see below).

S4 tree-theme reality: `bridge-viewer-tree-theme.ts:50–71` already sets
14 `--trees-*-override` variables pointing at chrome tokens, which
Pierre honors — so most theme-object Catppuccin hexes are NOT on
screen. The override block STAYS; its `var(--bridge-*)` right-hand
sides migrate to role vars in S4. Only theme-object keys with no
override change appearance (residual drift: `descriptionForeground`
#6C7086, `sideBarSectionHeader.foreground` #BAC2DE, git-decoration
colors) — those are S4's enumerated deltas. Deleting the override
block would recolor the tree substantially and is forbidden.

### 4.2 Semantic roles (canonical vocabulary)

All registered in `@theme inline` → each role has Tailwind utilities.
Stock shadcn roles keep their names; values become primitive refs:

| Role | Primitive | Meaning (one line, lives at definition) |
|------|-----------|------------------------------------------|
| background | n1 | app + code canvas base |
| foreground | text-primary | primary text |
| card / popover | n3 | floating & raised panels |
| primary | blue | brand accent; actions, active identity |
| secondary | n4 | filled secondary controls |
| muted | n4 | de-emphasized fills |
| muted-foreground | text-muted | secondary text |
| accent | n4 | hover/active wash on rows & controls |
| destructive | red | errors, deletions, destructive actions |
| border | stroke-subtle | hairline separators |
| input | stroke-hover | control outlines |
| ring | lavender | focus |
| sidebar + sidebar-* | n0 family (existing) | file-tree / rail chrome |

Extended roles (new, same convention, registered identically):

| Role | Primitive | Replaces |
|------|-----------|----------|
| surface / surface-foreground | n0 / text-primary | --bridge-surface-bg, --bridge-header-bg, --bridge-header-control-bg |
| selection | n5 | --bridge-list-selected-bg |
| success | green | --bridge-added |
| warning | yellow | --bridge-warning |
| faint-foreground | text-faint | --bridge-text-muted |

Deliberately NOT minted (deletion test): `canvas` (identical to
background today; `--diffs-background` maps to background; mint only if
they ever diverge), `header` (= surface), `raised` (= `muted` — value
n4, NOT card), `hover` (= accent). The `accent` collision resolves
here: blue is `primary`; `--bridge-accent` refs migrate to primary.

### 4.2.1 Mapping disambiguations (authoritative lookup for cutover)

Where one primitive backs several roles, the ALIAS TARGET is chosen by
the token's semantics, and exact current alphas are always preserved
via `color-mix` composition (never nearest-utility rounding):

| Current token | Target (exact) |
|---------------|----------------|
| `--bridge-code-view-file-separator` | `var(--input)` (it is `var(--bridge-border-opaque)` today; border-opaque = input) |
| `--bridge-header-control-active-bg` | `var(--accent)` (active-control wash semantics) |
| `--bridge-surface-raised-bg` | `var(--muted)` (value n4; `card` is n3 and would be a visible delta) |
| `--bridge-list-hover-bg` | `var(--accent)` |
| `--bridge-accent-soft` | `color-mix(in srgb, var(--primary) 16%, transparent)` — 16% preserved; NOT `primary/15` |
| `--bridge-focus-ring` | system token `--focus-ring: color-mix(in srgb, var(--ring) 30%, transparent)` |
| `--bridge-menu-border` | system token `--menu-border: color-mix(in srgb, var(--ring) 28%, transparent)` |
| `--bridge-menu-ring` | system token `--menu-ring: color-mix(in srgb, var(--foreground) 16%, transparent)` |
| `--bridge-focus-border` | `var(--ring)` |
| `--bridge-worktree-file-layout-proof` | non-color sentinel read by NOTHING (verified: only the definition exists) — rule-2 allowlist entry in S1; deleted in S2 |

### 4.3 Scale tokens (mirrors AppStyles.General, compact by default)

| Concern | @theme tokens | Values (native source) |
|---------|---------------|------------------------|
| type | --text-2xs..--text-2xl + paired --text-*--line-height pinned explicit | 9/11/12/13/14/16/24 (Typography) — ships in S1b, not S1 (§3 crux 2) |
| radius | literal table: --radius-sm 4px, --radius-md 6px, --radius-lg 8px, --radius-xl 14px; --radius-2xl/3xl/4xl keep the existing multiplier chain (no current chrome usage; no AppStyles correspondence — recorded reason) | 4/6/8/14 (CornerRadius) — ships in S1b; the one `rounded-xl` site (annotation frame, 10.08→14px) is an enumerated S1b delta |
| spacing | Tailwind default 4px grid already fits 4/6/8 (Spacing) — no override; document the blessed steps |
| motion | --motion-fast 120ms, --motion-standard 200ms | Animation |

Component density: Button already compact (no change). Textarea default
drops `min-h-16` → compact min-height on the control scale and
`text-xs/relaxed`; the comment composer's transparent look is a comment-
context composition, not a Textarea fork. Other owned controls audited
against the h-5/6/7/8 scale in S2.

### 4.4 System tokens (re-homed, not retired)

`--bridge-motion-fast` → `--motion-fast`; `--bridge-*-shadow` →
`--shadow-{floating-panel,menu,divider,tree-sticky,focus-dot}`;
`--bridge-scrollbar-*` → `--scrollbar-*`; focus/menu translucents per
§4.2.1 (`--focus-ring`, `--menu-border`, `--menu-ring`). Same rendered
values; new homes in a marker-delimited system block; refs migrate in
the slice that touches each file.

System-token right-hand sides follow the §4.1 composition rule — e.g.
shadows compose the black primitive at the exact current alphas
(divider: white/text-primary 6%; floating-panel: black 45%; menu:
black 86%; tree-sticky: black 90%), scrollbar thumbs compose
text-primary at 24% / 36%. No raw color literal appears in the system
block, so checker rule 1 needs no extra exemption.

## 5. Pierre `--diffs-*` derivation (names frozen)

Every existing `--diffs-*` name keeps its definition; right-hand sides
become role/primitive refs (`--diffs-background: var(--color-background)`,
`--diffs-ansi-*: var(--palette-ansi-*)`, token colors → hue primitives).
Rendered output must be pixel-identical (R7). The Shiki theme
(`bridge-code-view-theme.ts`) keeps spreading catppuccin-mocha for
syntax scopes (that IS the syntax palette, already in the hue set) but
its color overrides import the palette module instead of restating
`#282C34`/`#FFFFFF`.

## 6. Comment context (consumed by the comment lane)

Namespace `--comment-*`, defined beside `--diffs-*`, derived from
roles. Unlike `--diffs-*` (raw variables consumed by Pierre), the
comment tokens ARE product-facing: each color token is also registered
in `@theme inline`, so React consumes them as Tailwind utilities
(`bg-comment-surface`, `text-comment-muted`, `border-comment-border`,
…) — the same contract as every role. Frozen S1 API (9 tokens):
surface, foreground, muted, border, divider, hover, active,
composer-bg, destructive.

```
--comment-surface        color-mix(muted 42%, background)  ← current
                         annotation surface value, preserved
--comment-foreground     foreground        --comment-muted  faint-foreground
--comment-border         input @ 70%       --comment-divider border @ 72%
--comment-hover          color-mix(in srgb, var(--accent) 64%,
                         transparent) — exact current alpha preserved
--comment-active         comment-lane-owned: the lane defines its
                         value when it designs the range-active state
                         (pairs with Pierre selection, must not
                         duplicate ring); S1 ships it as
                         var(--primary) placeholder documented as
                         lane-owned
--comment-composer-bg    transparent       (composer inherits surface)
--comment-destructive    destructive
```

`--bridge-annotation-*` definitions and refs are replaced by these in
S5. Interaction/component anatomy for comments belongs to the comment
lane's own design; this design only owns the vocabulary above.

Markdown bodies in comments use an owned typeset-style CSS file
(shadcn's typeset pattern: one owned CSS file; `--typeset-size/-leading/
-flow` rhythm variables; zero-specificity `:where()` selectors) with a
compact preset tuned to the comment context, inheriting fonts/colors
from the roles. This replaces ad hoc markdown styling; the comment lane
consumes the preset class. Ownership: the typeset file + compact preset
are an S5 deliverable of THIS program; until S5 lands, the comment lane
composes markdown styling from existing typography utilities and adds
no tokens.

Visual-state ownership (one owner per state — binding for the lane):

| State | Owner / expression |
|-------|--------------------|
| source-range paint in the code canvas | Pierre (its selection system; never re-drawn by comment components) |
| thread linked to the ACTIVE range | `--comment-active` — that is its single meaning; applied by the comment components (e.g. rail/border tint on the thread surface) |
| composer / keyboard focus | standard `ring` via `focus-visible:` — never a second custom focus treatment |
| pointer hover on thread rows | `--comment-hover` |

### 6.5 Dark-only realization (R13)

- **Web**: the app has exactly one styling branch. All `dark:` variant
  classes in `src/` are removed during migration — this is
  behavior-preserving by construction: no `.dark` class exists on the
  root today, so those branches have never applied; the approved
  rendering IS the unconditional branch. The `@custom-variant dark`
  declaration is deleted in S6. Checker rule 5 (§10) blocks
  reintroduction. When adding a new shadcn component, the agent folds
  any upstream `dark:` styling into the single branch deliberately
  (guide rule, R12).
- **Native**: app-level appearance pinned dark at launch (AppDelegate,
  SN slice), so chrome ignores the macOS appearance toggle.
  `TerminalSurfaceScrollView.swift:338` keeps its per-surface override
  (terminal content may legitimately have a light background); it is
  the one named exception and is documented in the architecture doc.

## 7. Cutover model (alias-then-delete, one authority throughout)

| Phase | Authority | `--bridge-*` state | Gate posture |
|-------|-----------|--------------------|--------------|
| P0 today | none (4 channels) | raw values | no token rules |
| P1 after S1 | roles + palette | definitions become one-line aliases to roles (values identical ⇒ zero visual change) | rules on; existing refs in burn-down allowlist; NEW refs and raw hexes blocked |
| P2 during S2–S5 | roles + palette | refs migrate slice by slice; allowlist shrinks monotonically (checker fails if it grows) | per-slice screenshot proof |
| P3 after S6 | roles + palette | definitions deleted; allowlist empty and removed | strict; R3/R11 fully observable |

Rollback per slice: each slice is one PR in one worktree; revert = git
revert of that PR (aliases in P1 guarantee value equivalence, so a
reverted slice regresses plumbing, never pixels).

## 8. Slice decomposition (each = worktree + branch + draft PR)

| Slice | Scope (files owned) | Visible deltas allowed | Depends on |
|-------|---------------------|------------------------|------------|
| S1 foundation | palette module; bridge-app.css primitive/role/system blocks + `--bridge-*` aliasing + contract header comment; the `--comment-*` block (§6 — pure addition here so the comment lane always has legal tokens; S5 shrinks to ref-migration + `--bridge-annotation-*` deletion); checker script + allowlists; AGENTS.md rules + `docs/architecture/` token doc (incl. §4.0 map); mapping appendix; RE-POINT the four bridge-app.css text-matching test files at the primitives block — `review-viewer/code-view/bridge-code-view-theme.unit.test.ts:62–104` (update the `--input` .18 assertion to .20; the two contrast-ratio gates KEEP their thresholds and read the palette primitives n1/n0/n3), `app/bridge-viewer-shared-boundaries.unit.test.ts:159–169`, `file-viewer/bridge-file-viewer-source-structure.unit.test.ts:290`, `review-viewer/shell/review-viewer-shell.integration.test.tsx` (2 refs). Assertion re-pointing preserves every threshold — no gate is deleted or weakened | NONE (alias equivalence; ramp/radius re-anchor moved to S1b) | — |
| S1b type/radius re-anchor | `--text-*` + paired `--text-*--line-height` pinned explicit per §3 crux 2; radius literal table per §4.3 | the §3 delta table (56× text-xs −1/−1.33; 13× text-sm −2/−2.86 incl. review-viewer routes; 1× rounded-xl 10.08→14) + off-ramp literal decisions (24× `text-[10px]`, 12× `text-[11px]`, 4× `text-[13px]`, button `xs` 0.625rem) — owner decides snap-vs-bless per class from screenshots | S1 |
| S2 file-viewer chrome | `.bridge-worktree-file-*` CSS → owned components/utilities; sidebar/search/toolbar TSX | enumerated ±1px text/stroke snaps | S1 |
| S3 review-viewer + shared chrome | remaining `var(--bridge-*)` refs in review-viewer/, app/ | same class | S1 (parallel-safe with S2 only if file sets are disjoint — they share bridge-app.css: run sequentially) |
| S4 TS themes | tree theme + Shiki theme import palette | tree neutrals → ramp (the drift fix; screenshots mandatory) | S1 |
| S5 comment context | `--comment-*` block; worktree-annotations styling refs | comment surfaces only | S1; coordinates with comment lane |
| S6 cutover | delete aliases; empty+remove allowlist; strict gate | NONE | S2–S5 |
| SN native | AppStyles color role + contract header comment; `.tint` at window roots; replace accentColor reads; app-level dark appearance pin in AppDelegate | accent-colored native surfaces with non-blue system accent; chrome under macOS light mode (now stays dark) | independent |

One Sol per worktree; S2/S3 sequential (shared bridge-app.css); SN runs
any time. Slice briefs cite this document + the mapping appendix; a Sol
that meets a value not in the mapping table STOPS and records
(spec Failure expectations).

## 9. Native accent slice (SN) realization

- `AppStyles` gains its first color constants (presentation constants
  are AppStyles-owned): product accent `#89B4FA` exposed as SwiftUI
  `Color` and `NSColor`.
- `.tint(AppStyles...)` applied once per SwiftUI root the app hosts
  (window content hosts). Note: `.tint` pins implicit control tinting
  and `.foregroundStyle(.tint)` ONLY — it does NOT change
  `Color.accentColor` resolution on macOS, and nothing overrides
  `NSColor.controlAccentColor` app-wide. Total R10 coverage therefore
  comes from the read replacement below; `.tint` is belt-and-braces
  for implicit control styling.
- Direct reads migrate: `rg 'Color\.accentColor|controlAccentColor'`
  inventory — 42 non-test sites across 24 files (run the rg and
  migrate ALL of them; e.g. `MainWindowController.swift:566`,
  `PaneDropTargetOverlay.swift:19`, `EditorChooserMenuContent.swift:150`,
  `AppEntityIcon.swift:77`, fallbacks in `AppStyles.swift:205`) → the
  AppStyles role. Fallback sites (`?? .controlAccentColor`) change to
  the pinned color so no path follows the system accent.
- No settings surface; the pin is unconditional (owner decision, U4).
- **Dark appearance pin (U9/R13)**: `NSApp.appearance =
  NSAppearance(named: .darkAqua)` set once at launch in AppDelegate,
  before window creation. The terminal scroll-view per-surface
  override is preserved (§6.5 exception). AppStyles gains the R12
  contract header comment in this slice.

## 10. Enforcement design (R11)

New sibling script `BridgeWeb/scripts/check-bridgeweb-design-tokens.ts`,
invoked from `pnpm run check` (same chain as the architecture checker →
`mise run test`). Fail-closed: script crash = check failure.

| Rule | Detects | Scope | Exemptions |
|------|---------|-------|------------|
| no-raw-color-literal | hex / rgb() / hsl() / oklch() literals | src/**/*.{css,ts,tsx} | palette module; CSS primitives block (delimited by markers); *.test.*; test-support files |
| no-bridge-token | `--bridge-` occurrences | same | burn-down allowlist (S1-generated, path+count; any growth fails; removed in S6) |
| no-bespoke-control-geometry | (a) `font-size`/`height` px declarations in feature CSS and in CSS-in-TS template-literal stylesheets; (b) in `.tsx` outside components/ui: arbitrary-value size utilities (`text-[Npx]`, `h-[Npx]`, `size-[Npx]`, `min-h-[Npx]`) and bare `h-N`/`text-N` utilities applied to `button`/`input`/`textarea` elements | src/**/*.{css,ts,tsx} outside components/ui | burn-down allowlist seeded from the ~64 current sites (24× text-[10px], 12× text-[11px], 23× h-N, etc.); removed as S2/S3/S1b land |
| palette-mirror | palette module values ≠ CSS primitives block values | both homes | none — exact equality (CSS canonical) |
| no-appearance-branch | `dark:` variant classes; `prefers-color-scheme` queries | src/**/*.{css,ts,tsx} | burn-down allowlist of current `dark:` sites (removed as slices land; empty by S6) |

The mirror rule imports the TS module and parses the CSS block
delimited by the literal markers `/* @design-primitives:start */` and
`/* @design-primitives:end */`. Normalization before comparison:
lowercase both sides, expand 3-digit hex to 6, express
alpha-composed values as hex-with-alpha strings, and compare numeric
alphas via `Number()` (so `.04` == `0.04`). A wrong normalization
makes the rule always-red or always-green — implement exactly this. Red-first proof
obligation (spec): each rule demonstrated failing on a deliberate
violation before the allowlists are trusted.

## 11. Cross-cutting realization

- **Accessibility (parity)**: contrast is preserved structurally —
  primitives carry the exact current values; the only contrast-touching
  deltas (tree recolor, ±1px snaps) surface in screenshot review.
  `prefers-reduced-motion` block is untouched (S1 no-op zone).
- **Compatibility (dev server vs packaged WKWebView)**: tokens are
  static CSS/TS — identical in both by construction; the packaged
  BridgeWeb build already in the PR gate proves the bundle compiles;
  final visual verification on the real app per repo rules.
- Performance/privacy/security/data lifecycle: not applicable — static
  styling; no data, network, trust, or persistence surface changes.
  Concurrency: none at runtime; the only overlap risk is agent-level
  (two Sols editing bridge-app.css) and is prevented by the slice
  ownership table (§8).

## 12. How each requirement is realized and proven

| R | Realization (owner) | Proof seam |
|---|---------------------|-----------|
| R1 | roles block §4.2 (@theme inline) | utility compilation in existing unit/browser suites; checker presence |
| R2 | palette module + mirror rule §10 | no-raw-color-literal + palette-mirror, red-first |
| R3 | alias-then-delete cutover §7 | no-bridge-token rule at P3 (empty allowlist) |
| R4 | mapping appendix + per-slice delta enumeration §8 | `proof:visual:dev-server` screenshot pairs, owner draft-PR review |
| R5 | scale tokens §4.3 (S1b) + Textarea density fix (S2) | S1b screenshots + delta table; ramp values inspectable in @theme |
| R6 | TS themes import palette §4.1/§5 | S4 screenshots (named delta) + no-raw-color-literal covering .ts |
| R7 | --diffs-* derivation §5 | diff-view screenshot pair incl. syntax-heavy file |
| R8 | comment context §6 | checker (derivation), comment-lane render |
| R9 | S2/S3 migration + rule 3 §10 | rule 3 + absence of bespoke control classes |
| R10 | SN §9 | manual: non-blue macOS accent screenshot |
| R11 | checker §10 in pnpm check | red-first violation demo, then green gate |
| R12 | contract comments in AppStyles.swift + bridge-app.css; AGENTS.md rules; permanent `docs/architecture/` doc owning the §4.0 correlation map; one-line meanings at definition sites | inspection at review |
| R13 | single styling branch + `dark:` removal (§6.5); AppDelegate appearance pin (§9); rule 5 (§10) | appearance-toggle screenshots; rule-5 scan |

## 13. Mapping appendix (S1 deliverable, owner-reviewed)

The complete value→token table (every current `--bridge-*` token, raw
hex, and bespoke class → target token/utility, with delta class
`none | enumerated`) is committed as
`2026-08-16-value-token-mapping.md` in this spec folder during S1,
generated from the §4 tables plus a full-tree grep, and reviewed with
the S1 PR. Sol slices execute that table as lookup; the STOP rule
covers anything the table misses.
