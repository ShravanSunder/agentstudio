# Specification: BridgeWeb Design-Token Harmonization

Requirements: [2026-08-16-requirements.md](./2026-08-16-requirements.md)
(U1–U10 and the owner-confirmed goal boundary govern this contract).

## The problem and outcome in one view

```
TODAY                                    TARGET
─────────────────────────────────        ─────────────────────────────────
shadcn roles ─┐  both active,            primitives (defined ONCE)
--bridge-*  ──┤  same hexes,               gray ramp · accent hues ·
raw hex     ──┤  colliding names,          alpha washes · scales
bespoke CSS ──┘  no authority                      │
                                          semantic roles (shadcn conv.,
agents guess → random UI                  extended; only vocabulary)
tree theme ≠ chrome palette                        │
                                        ┌──────────┴──────────┐
                                     --diffs-*           inline-comment
                                     (Pierre)            context
                                        │
                                   PR gate blocks raw hex, --bridge-*,
                                   off-system geometry
```

## Context: consumers of the styling system

```
                    ┌──────────────────────────────┐
  Implementing ───► │                              │ ◄─── Owner
  agents (Sol)      │   BridgeWeb styling system   │      (draft-PR
  write against     │        (opaque here)         │      screenshot
  roles/utilities   │                              │      review)
                    └──┬────────┬────────┬─────────┘
                       │        │        │
              --diffs-* vars  TS theme  rendered UI
                       │      objects      │
                       ▼        ▼          ▼
                    Pierre   Pierre     End user
                    diffs    trees      (file + review views,
                                        comments, future modes)

  Native Swift app: shares palette identity by hand-harmonization
  (accent #89B4FA, scales); no runtime coupling. NOT a consumer of
  the web tokens.
```

## Normative requirements

Statements use MUST for pass/fail obligations. "Primitive homes" means
the designated definition sites for color values (established by Program
Design; the obligation here is that they are enumerated and few).

### R1 — Single semantic vocabulary (U1)

The styling system MUST define exactly one semantic color vocabulary,
following shadcn conventions (role name + paired `-foreground`,
registered so each role has a working Tailwind utility). Extended roles
(at minimum: canvas, surface, surface-raised, header, selection states,
added/deleted/warning status) MUST follow the same convention.
**Fail**: a color meaning reachable only through a second vocabulary or
a raw value.

### R2 — Colors defined once, in primitives (U1, U8)

Every color value in BridgeWeb MUST resolve from a primitives layer
(neutral gray ramp, accent hues, alpha washes) defined once. Semantic
roles MUST reference primitives; contexts MUST reference roles or
primitives. A raw color literal MUST NOT appear outside the enumerated
primitive homes (test fixtures exempt).
Pinned identity values (owner-confirmed): canvas/background neutral
`#282C34`; primary accent `#89B4FA`. Other neutral hexes are tunable at
owner review without spec change.

### R3 — `--bridge-*` retired by hard cutover (U1)

When migration completes, `BridgeWeb/src` MUST contain zero references
to `--bridge-*` custom properties, and the definitions MUST be deleted.
Non-color system tokens currently in that namespace (motion, shadows,
scrollbar metrics) MUST be re-homed as properly named tokens in the
canonical system, not dropped.
**Fail**: any surviving reference or definition (mechanically checkable
by search).

### R4 — Visual invariant for existing chrome (U2, U7)

For every migration change to an existing surface (file viewer, review
viewer, shared chrome): before/after screenshots of the same app state
MUST show no visible difference except deltas individually enumerated in
that PR's description. If an unenumerated difference is visible, the
change is defective — the mapping must be corrected, not the delta list
grown after the fact.
Known planned deltas (enumerate in the owning PR): tree-sidebar neutrals
moving from Catppuccin to the #294 grays (R6); near-scale values
snapping to scale stops (e.g. stroke .18 → .20).

### R5 — Compact scales harmonized to AppStyles (U5)

The token system MUST define typography, spacing, radius, state-fill,
stroke, and motion scales whose values mirror `AppStyles.General`
(type 9/11/12/13/14/16/24 px; fills .04/.06/.08/.10/.12/.15; strokes
.10/.15/.20/.25; radius 4/6/8/14; spacing 4/6/8; motion 120/200 ms).
Owned components in `components/ui/` MUST render at the compact scale
by default — an agent using a primitive with no size props gets a
control correct for this app's density.
**Fail**: a default-rendered owned control visibly larger than the
existing compact chrome, or a scale value with no AppStyles
correspondence and no recorded reason.

### R6 — TS theme objects derive from the palette (U8)

The Pierre trees theme and the Shiki/code-view theme registration MUST
source their color values from the canonical palette (same definition
chain as R2 — no independent hex copies). The file tree MUST render with
the #294 chrome neutrals (this is a named R4 delta, not an exception).
Syntax token colors (the Catppuccin accent set) remain part of the
canonical palette; their rendered appearance in code does not change.

### R7 — `--diffs-*` contract preserved (U1, U2)

Every `--diffs-*` variable name consumed by Pierre today MUST remain
defined, with values derived from roles/primitives. The rendered code
canvas (syntax colors, diff colors, gutter, selection) MUST be visually
unchanged (R4 applies).

### R8 — Inline-comment styling context (U3)

The system MUST provide a named styling context for inline comments,
derived from semantic roles, covering at minimum: comment surface on the
code canvas, active-range-linked state, metadata/muted text at
code-compatible contrast, transparent composer treatment, focus that
does not compete with Pierre's range selection, and destructive
feedback via the product destructive role. The improvised
`--bridge-annotation-*` tokens MUST be replaced by this context
(R3 cutover applies).
The comment lane consumes these tokens; comment product behavior is out
of scope here.

### R9 — Control geometry owned by `components/ui` (U1, U5)

Interactive-control geometry (heights, control padding, control font
size, control radius) MUST come from owned components or tokens.
Route-local bespoke control styling — including the current
`.bridge-worktree-file-*` toolbar/search/button classes — MUST be
migrated to owned primitives (R4 visual invariant applies).
Compositional layout (grids, panes, scroll regions) remains free.

### R10 — Native accent pinned (U4)

With any macOS System Settings accent color, native accent-colored
surfaces MUST render the product blue `#89B4FA`. Direct
`Color.accentColor` / `.controlAccentColor` reads in app code MUST be
replaced by the AppStyles-owned role so the pin is total.
**Fail**: any app surface following the system accent (verify with a
non-blue system accent).

### R11 — Enforcement at the PR gate (U6)

The standard PR gate (`mise run test`) MUST fail, with file/line
identification, when a change introduces: (a) a raw color literal
outside primitive homes, (b) a `--bridge-*` reference, (c) new
route-local interactive-control geometry outside owned components.
The gate MUST pass on the fully migrated tree (no permanent baseline of
exceptions; temporary allowlists during migration must burn down to
empty).

### R12 — Vocabulary and its rules are documented where agents work (U1, U6, U10)

Each role, context, and scale MUST carry a one-line meaning at its
definition site. The rules MUST exist in three reinforcing homes:

- **In-code guidance**: `AppStyles.swift` and `bridge-app.css` MUST
  each open with a contract comment stating: it is the source of truth
  for its platform, the two are correlated by convention (pointer to
  the correlation map), the layer rules, and how to add a token
  correctly.
- **Agent instructions**: the AGENTS.md scope covering BridgeWeb MUST
  state the layer rules (primitives → roles → contexts), how to choose
  a role, what the gate rejects, and how to add a shadcn component
  under the single-appearance rule (R13).
- **Architecture document**: a permanent `docs/architecture/` document
  MUST own the full explanation, including the tri-system correlation
  map (AppStyles ↔ web tokens ↔ Pierre `--diffs-*`/TS themes): what
  corresponds to what and which correlations are exact versus
  approximate.

A capable agent MUST be able to select the correct token for a new
surface without reading this spec.

### R13 — Dark-only, enforced on both sides (U9)

With macOS set to light appearance: native app chrome MUST render dark
(app-level appearance pin), and BridgeWeb MUST render identically to
macOS dark appearance. The web styling system MUST NOT carry a
reachable light-mode branch: owned components carry exactly one
styling branch (no `dark:` variant dual path), and the gate MUST
reject reintroduced appearance-conditional styling in `src/`.
Named exception: terminal surfaces may set per-surface appearance to
match terminal content background (existing
`TerminalSurfaceScrollView` behavior is preserved).
**Fail**: any chrome surface that changes with the macOS appearance
toggle.

## Observable contracts

### Token definition surface

Consumers: all BridgeWeb code, Pierre (via `--diffs-*`), TS theme
objects. Owner: this spec; changes to role *names* or *meanings* require
owner sign-off; changes to neutral *values* are owner-reviewed via draft
PR (R2). Invariants: one definition per color meaning; roles never
reference other roles' resolved hexes, only primitives. Undefined /
free: file organization, number of CSS/TS files, generation mechanics —
Program Design decides.

### `components/ui` surface

Consumers: feature code and agents. Postcondition: default render is
compact-correct (R5); size variants preserve relative scale. Compat:
existing call sites keep working or are migrated in the same change —
no dual APIs (hard-cutover rule).

### Enforcement gate

Consumers: agents and CI. Output on violation: failing check naming
file, line, and violated rule. Partial success: none — any violation
fails. Timeout/absence of the checker is a gate failure, not a silent
pass.

### Native accent

Consumer: end user. Contract: R10. Compat: no API change; purely visual.

## Failure expectations

- If the gate's checker cannot run, the PR gate MUST fail loudly
  (no fail-open).
- If a migration mapping is ambiguous (an old value plausibly maps to
  two tokens), execution MUST stop and return the ambiguity to the
  design owner — Sol does not choose (STOP-AND-RECORD).
- If Pierre's rendering changes visibly after a `--diffs-*` value
  re-derivation, that slice is defective regardless of test greenness.

## Cross-cutting obligations

- **Accessibility**: text contrast MUST NOT regress versus the current
  rendering for body, secondary, and muted text on their standard
  surfaces. Existing `prefers-reduced-motion` handling MUST be
  preserved. (No new contrast targets are introduced — parity, not
  WCAG re-certification.)
- **Compatibility**: tokens MUST render identically in the Vite dev
  server and the packaged WKWebView build (the packaged BridgeWeb build
  is already part of the PR gate; screenshots for R4 may come from the
  dev loop, final verification per repo rules on the real app).
- **Performance, privacy, security, data lifecycle**: not applicable —
  static styling only; no data, no network, no persistence changes.

## Proof obligations

| Obligation | Evidence class |
|-----------|----------------|
| R1 roles + utilities exist | automated build/unit (utility classes compile and resolve) |
| R2/R3 no raw hex, no `--bridge-*` | automated scan (same checker as R11), zero findings on migrated tree |
| R4 visual invariant | owner live review of the running surfaces (dev loop and/or debug app) per PR; unenumerated delta the owner spots = fail. (Owner decision 2026-08-16: aesthetic invariants are judged by look; automated screenshot pairs were dropped after both baseline-capture paths proved broken at the base commit.) |
| R5 compact defaults | visual evidence of default-rendered owned components beside existing chrome |
| R6 tree matches chrome | screenshot (this is a named delta PR) |
| R7 Pierre unchanged | owner live review of a running diff view incl. a syntax-heavy file; unenumerated delta the owner spots = fail. (Owner decision 2026-08-16: aesthetic invariants are judged by look; automated screenshot pairs were dropped after both baseline-capture paths proved broken at the base commit.) |
| R8 comment context | this program proves: context tokens exist and derive from roles (automated scan). The comment lane owes the render-with-them proof in its own PR — not a gate of this program |
| R9 no bespoke geometry | automated scan + absence of `.bridge-worktree-file-*` control classes |
| R10 accent pinned | manual/visual: non-blue macOS accent, app surfaces stay `#89B4FA` |
| R11 gate blocks violations | red-first: a deliberate violation fails the gate with file/line, then is removed |
| R12 docs | inspection: contract comments present in both source-of-truth files; AGENTS.md rules present; architecture doc with correlation map exists |
| R13 dark-only | manual/visual: toggle macOS appearance, chrome unchanged; automated scan: zero `dark:` variants in src |

Existing BridgeWeb unit/browser/E2E suites MUST stay green throughout
(regression floor; they are not proof of the visual invariant).
Clarification: four existing test files assert the literal text of
`bridge-app.css`; re-pointing those assertions at the primitives block
with every threshold preserved (in particular the two contrast-ratio
gates) is required migration work, not gate weakening. Deleting or
loosening any threshold remains forbidden.

## Requirement coverage

| U | Requirement(s) | Contract | Proof |
|---|----------------|----------|-------|
| U1 | R1 R2 R3 R9 R12 | token surface, components/ui | build, scan, docs inspection |
| U2 | R4 R7 | token surface | owner live review of the running surfaces; screenshot pairs dropped by owner decision 2026-08-16 |
| U3 | R8 | token surface | scan + comment-lane render |
| U4 | R10 | native accent | manual/visual |
| U5 | R5 R9 | components/ui | visual + scan |
| U6 | R11 R12 | enforcement gate | red-first gate proof |
| U7 | R4 (delta enumeration), draft-PR delivery | — | owner review flow |
| U8 | R6 | token surface | screenshot (named delta) |
| U9 | R13 | native accent + token surface | appearance-toggle visual + scan |
| U10 | R12 | token surface docs | inspection |

## Negative space (what implementers must not build)

- No second vocabulary, alias layer, or compatibility shim keeping
  `--bridge-*` alive "for transition" beyond the migration PRs.
- No light theme scaffolding.
- No Swift↔web codegen/sync tooling.
- No new palette hues beyond the formalized set.
- No Pierre patches or forks; no app-side scroll/selection helpers.
- No comment-system product behavior.
- No permanent violation allowlists in the gate.
