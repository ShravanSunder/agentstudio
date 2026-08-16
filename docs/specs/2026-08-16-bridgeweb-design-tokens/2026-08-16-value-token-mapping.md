# BridgeWeb S1 Value-to-Token Mapping

This appendix is the lookup contract for the S1 foundation cutover. It inventories the
current `BridgeWeb/src` tree at `929f74773d0d550af361a263ad36d13f6289bdf2` and applies
Program Design sections 4.1, 4.2, 4.2.1, 4.4, 6, and 10. S1 changes one rendered value:
the input stroke normalizes from white at 18% to `--palette-stroke-hover` at 20%.

## Legacy Bridge token aliases

| Current token | S1 target | Delta |
|---|---|---|
| `--bridge-app-bg` | `var(--background)` | none |
| `--bridge-canvas-bg` | `var(--background)` | none |
| `--bridge-header-bg` | `var(--surface)` | none |
| `--bridge-header-control-bg` | `var(--surface)` | none |
| `--bridge-header-control-active-bg` | `var(--accent)` | none |
| `--bridge-surface-bg` | `var(--surface)` | none |
| `--bridge-surface-raised-bg` | `var(--muted)` | none |
| `--bridge-menu-bg` | `var(--popover)` | none |
| `--bridge-surface-muted-bg` | `var(--muted)` | none |
| `--bridge-border-subtle` | `var(--border)` | none |
| `--bridge-border-opaque` | `var(--input)` | `enumerated: input stroke alpha 0.18 to 0.20` |
| `--bridge-text-primary` | `var(--foreground)` | none |
| `--bridge-text-secondary` | `var(--muted-foreground)` | none |
| `--bridge-text-muted` | `var(--faint-foreground)` | none |
| `--bridge-accent` | `var(--primary)` | none |
| `--bridge-accent-soft` | `color-mix(in srgb, var(--primary) 16%, transparent)` | none |
| `--bridge-focus-border` | `var(--ring)` | none |
| `--bridge-focus-ring` | `var(--focus-ring)` | none |
| `--bridge-focus-dot-shadow` | `var(--shadow-focus-dot)` | none |
| `--bridge-menu-border` | `var(--menu-border)` | none |
| `--bridge-menu-ring` | `var(--menu-ring)` | none |
| `--bridge-divider-shadow` | `var(--shadow-divider)` | none |
| `--bridge-floating-panel-shadow` | `var(--shadow-floating-panel)` | none |
| `--bridge-menu-shadow` | `var(--shadow-menu)` | none |
| `--bridge-tree-sticky-shadow` | `var(--shadow-tree-sticky)` | none |
| `--bridge-scrollbar-size` | `var(--scrollbar-size)` | none |
| `--bridge-scrollbar-thumb` | `var(--scrollbar-thumb)` | none |
| `--bridge-scrollbar-thumb-hover` | `var(--scrollbar-thumb-hover)` | none |
| `--bridge-scrollbar-track` | `var(--scrollbar-track)` | none |
| `--bridge-motion-fast` | `var(--motion-fast)` | none |
| `--bridge-list-hover-bg` | `var(--accent)` | none |
| `--bridge-list-selected-bg` | `var(--selection)` | none |
| `--bridge-added` | `var(--success)` | none |
| `--bridge-deleted` | `var(--destructive)` | none |
| `--bridge-warning` | `var(--warning)` | none |
| `--bridge-code-view-file-separator` | `var(--input)` | `enumerated: inherited input stroke alpha 0.18 to 0.20` |
| `--bridge-worktree-file-layout-proof` | S1 count-bounded legacy-token allowlist; delete in S2 | none |

## Pierre contract derivation

| Pierre token group | S1 target | Delta |
|---|---|---|
| `--diffs-focus-border` | `var(--ring)` | none |
| `--diffs-focus-ring` | `var(--focus-ring)` | none |
| `--diffs-border-subtle` | `var(--border)` | none |
| `--diffs-border-opaque` | `var(--input)` | `enumerated: input stroke alpha 0.18 to 0.20` |
| `--diffs-foreground` | `var(--foreground)` | none |
| `--diffs-background` | `var(--background)` | none |
| `--diffs-ansi-*` | matching `var(--palette-ansi-*)` primitive | none |
| `--diffs-token-link`, `--diffs-token-function` | `var(--palette-blue)` | none |
| `--diffs-token-string`, `--diffs-token-inserted` | `var(--palette-green)` | none |
| `--diffs-token-comment` | `var(--palette-text-faint)` | none |
| `--diffs-token-constant` | `var(--palette-peach)` | none |
| `--diffs-token-keyword` | `var(--palette-mauve)` | none |
| `--diffs-token-parameter`, `--diffs-token-changed` | `var(--palette-yellow)` | none |
| `--diffs-token-string-expression` | `var(--palette-teal)` | none |
| `--diffs-token-punctuation` | `var(--palette-subtext)` | none |
| `--diffs-token-deleted` | `var(--palette-red)` | none |

## Raw color literal inventory

### `bridge-app.css`

| Current literal | Primitive or composition target | Delta |
|---|---|---|
| `#1d2026` | `--palette-neutral-n0` | none |
| `#282c34` | `--palette-neutral-n1` | none |
| `#30343d` | `--palette-neutral-n2` | none |
| `#323641` | `--palette-neutral-n3` | none |
| `#343842` | `--palette-neutral-n4` | none |
| `#464b57` | `--palette-neutral-n5` | none |
| `#ffffff` | `--palette-text-primary` | none |
| `#eaeaea` | `--palette-text-secondary` and the value-identical ANSI bright-white primitive | none |
| `#c5c8c6` | `--palette-text-muted` and the value-identical ANSI white primitive | none |
| `#9ba1ad` | `--palette-text-faint` | none |
| `#89b4fa` | `--palette-blue` | none |
| `#a6e3a1` | `--palette-green` | none |
| `#f9e2af` | `--palette-yellow` | none |
| `#f38ba8` | `--palette-red` | none |
| `#cba6f7` | `--palette-mauve` | none |
| `#fab387` | `--palette-peach` | none |
| `#94e2d5` | `--palette-teal` | none |
| `#b4befe` | `--palette-lavender` | none |
| `#bac2de` | `--palette-subtext` | none |
| `#000000` | `--palette-black` | none |
| `rgb(255 255 255 / 0.04/.06/.08/.10/.12/.15)` | `--palette-wash-subtle/-muted/-hover/-pressed/-active/-selected` | none |
| `rgb(255 255 255 / 0.10/.15/.20/.25)` | `--palette-stroke-subtle/-muted/-hover/-visible` | `.18 input becomes enumerated .20 stroke-hover; all other rows none` |
| `rgb(137 180 250 / 0.16)` | primary at 16% `color-mix` composition | none |
| `rgb(180 190 254 / 0.30)` | ring at 30% `color-mix` composition | none |
| `rgb(255 255 255 / 0.06)` | foreground at 6% divider-shadow composition | none |
| `rgb(0 0 0 / 0.45/.86/.90)` | black at 45%/86%/90% system-shadow compositions | none |
| `rgb(255 255 255 / 0.24/.36)` | foreground at 24%/36% scrollbar compositions | none |
| `#1d1f21`, `#cc6666`, `#b5bd68`, `#f0c674`, `#81a2be`, `#b294bb`, `#8abeb7`, `#c5c8c6`, `#666666`, `#d54e53`, `#b9ca4a`, `#e7c547`, `#7aa6da`, `#c397d8`, `#70c0b1`, `#eaeaea` | matching `--palette-ansi-*` primitive | none |

### S4-owned production theme files

These files are protected from S1 consumer edits. Their exact current raw-literal counts are
count-bounded in the transitional raw-color allowlist and must burn down in S4.

| File | Current literals | Disposition | Delta |
|---|---|---|---|
| `src/app/bridge-viewer-tree-theme.ts` | `#00000000`, `#181825`, `#282C34`, `#313244`, `#45475A`, `#6C7086`, `#89B4FA`, `#A6E3A1`, `#B4BEFE`, `#BAC2DE`, `#CDD6F4`, `#F38BA8`, `#FFFFFF` | S4 scope — do not change now | none in S1 |
| `src/review-viewer/code-view/bridge-code-view-theme.ts` | `#282C34`, `#FFFFFF` | S4 scope — do not change now | none in S1 |

### Test-only literal homes

The raw-color rule exempts `*.test.*` and `*test-support*`. Full-tree grep found raw literals
only in these test files beyond the CSS and two S4 production files:

- `src/app/bridge-review-comparison-control-ux.browser.test.tsx`
- `src/app/bridge-viewer-content-header.browser.test.tsx`
- `src/app/bridge-viewer-shared-boundaries.unit.test.ts`
- `src/review-viewer/code-view/bridge-code-view-theme.unit.test.ts`

Their disposition is `test fixture/assertion exemption`; delta class `none`. The four S1
text-matching tests named by the brief are re-pointed away from the legacy `--bridge-*`
vocabulary without deleting or loosening any threshold.

## File-viewer bespoke class inventory

Every class below remains byte-for-byte in S1 and has disposition `migrates in S2`; delta
class `none` in S1.

| Class | Disposition | Delta |
|---|---|---|
| `.bridge-worktree-file-app` | migrates in S2 | none |
| `.bridge-worktree-file-sidebar` | migrates in S2 | none |
| `.bridge-worktree-file-toolbar` | migrates in S2 | none |
| `.bridge-worktree-file-search-input` | migrates in S2 | none |
| `.bridge-worktree-file-toolbar-button` | migrates in S2 | none |
| `.bridge-worktree-file-toolbar-button[aria-pressed='true']` | migrates in S2 | none |
| `.bridge-worktree-file-filter-group` | migrates in S2 | none |
| `.bridge-worktree-file-query-status` | migrates in S2 | none |
| `.bridge-worktree-file-tree` | migrates in S2 | none |
| `.bridge-worktree-file-content` | migrates in S2 | none |
| `.bridge-worktree-file-tree-extent` | migrates in S2 | none |
| `.bridge-worktree-file-content-extent` | migrates in S2 | none |
| `.bridge-worktree-file-tree-row` | migrates in S2 | none |
| `.bridge-worktree-file-tree-row:hover` | migrates in S2 | none |
| `.bridge-worktree-file-content pre` | migrates in S2 | none |
| `.bridge-worktree-file-stale-notice` | migrates in S2 | none |

## S1 visible-delta contract

- `enumerated`: `--input`, `--bridge-border-opaque`,
  `--bridge-code-view-file-separator`, and `--diffs-border-opaque` resolve from white at 18%
  to `--palette-stroke-hover` at 20%.
- `none`: every other S1 mapping row.
- Typography and radius values remain untouched; their re-anchor belongs to S1b.
