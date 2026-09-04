# BridgeWeb style-system audit validation

Date: 2026-09-04
Validation checkout: `bridge-review-design-2026-08-14` at `2af16e827cafcfea426200fa56432588e8536b0c` plus the concurrent working tree.
Reviewed artifact: [BridgeWeb style system audit](./2026-09-04-bridgeweb-style-system-audit.md).
Role: independent WIP validation and comparison. This is not an implementation plan or durable architecture authority.

Owner clarifications, 2026-09-04:

- Agent Studio native Swift chrome and embedded BridgeWeb support one appearance only: dark.
- The primary app/code canvas uses the Ghostty-derived grey `#282C34`. Darker neutral steps may distinguish headers, rails, and raised surfaces, but they do not replace the Ghostty-grey canvas role.
- Pierre code rendering must resolve its background to the same canvas role, while syntax colors remain a separate concern.

These settle the target appearance model; they do not change the current-source finding that `.dark` conditionally activates some styles today.

## 1. Verdict

The reviewed audit is directionally correct about the central failure:

```text
canonical tokens exist
  -> owned primitives remain inconsistent
  -> BridgeViewer class-string recipes compensate
  -> feature consumers add further overrides
  -> adjacent controls no longer share one visual grammar
```

Its primitive and consumer findings are mostly sound. Its initial program-history and Pierre/appearance conclusions contained three material errors:

1. `.dark` is applied at the live BridgeViewer root, so the `dark:` utilities are not categorically dead.
2. the design-token checker was implemented inside PR #303 and then deliberately deleted by the PR's final pre-merge commit; “never merged” hides that decision boundary.
3. Pierre tree hover already consumes Bridge's `--trees-bg-muted-override`; the Catppuccin `#313244` theme value is not the effective hover paint on the current tree.

The reviewed audit now marks and corrects all three. This validation retains the evidence because the corrections materially change implementation ordering. The remediation remains design input rather than an executable plan until the target contract and proof gates are promoted through the normal design/plan workflow.

## 2. Evidence fully loaded

The following artifacts were read end to end before this validation:

- reviewed WIP audit: 425 lines
- `2026-08-16-requirements.md`: 186 lines
- `2026-08-16-bridgeweb-design-tokens.md`: 307 lines
- `2026-08-16-program-design.md`: 500 lines
- `2026-08-16-value-token-mapping.md`: 160 lines
- current `BridgeWeb` token, primitive, BridgeViewer chrome, tree theme, and code-view option sources
- current installed `@pierre/trees` and `@pierre/diffs` CSS
- PR #303 commit list, final merge identity, and review discussion
- `origin/toggle-primary-selection` checker and allowlists

The reviewed audit was written against the same branch when HEAD was `dfe1eee0a`. Current HEAD is `2af16e827`; the intervening commit changes only the Bridge development-server supervisor/plugin and its unit test. The style findings therefore remain source-comparable, but the validation is bound to the newer HEAD.

## 3. Claim disposition

### 3.1 Accepted

| Reviewed claim | Validation | Evidence |
|---|---|---|
| The semantic token layer is structurally organized as primitives -> roles -> contexts. | Accepted, with “structurally” required. It is not sufficient to call the entire layer complete because its documented gate and scale cutover are absent. | `BridgeWeb/src/app/bridge-app.css:1-330` |
| S1b typography/radius re-anchor did not ship. | Accepted. There is no `--text-*` ramp; radius is still derived from `--radius: 0.45rem`. | `bridge-app.css:18-28,80` |
| S2-S6 are incomplete. | Accepted. File-viewer bespoke classes, compatibility aliases, raw TS theme values, and mixed annotation aliases remain. Some individual S1/S5-adjacent work did ship, so “not completed” is more accurate than “never started.” | current tree plus the 2026-08-16 slice table |
| Product primary is `#409CFF`; `#89B4FA` is retained as syntax blue. | Accepted. Native `AppStyles` records the owner choice and web CSS matches it. The 2026-08-16 spec/program/architecture text is stale. | `AppStyles.swift:11-13`; `bridge-app.css:96-97`; PR #303 commit `20b33b43a` |
| The current `pnpm run check` has zero design-token rules. | Accepted. It runs oxlint, the general architecture checker, formatting, TypeScript, and the product contract only. | `BridgeWeb/package.json`; `BridgeWeb/scripts/check-bridgeweb-architecture.ts` |
| Owned primitives disagree on typography, outline strength, focus, and disabled behavior. | Accepted. The Button/Toggle/Input/Textarea/Checkbox comparison matches current source. | `components/ui/button.tsx`, `toggle.tsx`, `input.tsx`, `textarea.tsx`, `checkbox.tsx` |
| BridgeViewer class constants form a second styling catalog. | Accepted. They override geometry, type, paint, focus, hover, and pressed state already owned by the primitives. | `bridge-viewer-chrome.ts`; `bridge-viewer-button.tsx`; `bridge-viewer-filter-menu.tsx` |
| Six copies of the active-surface paint pair exist. | Accepted by direct source inspection. | anchors in reviewed audit section B4 |
| `--bridge-*` census is 245 references, 35 referenced names, 37 definitions, 28 files, and no undefined references. | Accepted by independent `rg` reproduction. Two definitions are unused. | current working tree |
| There are zero `--palette-*` consumer leaks outside `bridge-app.css` and its TypeScript mirror. | Accepted by independent search. | current working tree |
| Pierre code and tree default to 13px when Bridge supplies no font-size override. | Accepted. Neither `--diffs-font-size` nor `--trees-font-size-override` is set by Bridge. Installed Pierre CSS defaults both to 13px. | installed `@pierre/diffs@1.2.10` and `@pierre/trees@1.0.0-beta.4` |
| The Share drawer mixes 14/11/11/12px label sizes and disabled outline paint becomes exceptionally weak. | Accepted. `Button outline` uses the 10% hairline role and the whole disabled control receives 50% opacity. | current Share source and owned Button primitive |

### 3.2 Corrected

| Reviewed claim | Disposition | Correct current model |
|---|---|---|
| “Every `dark:` utility is dead; `.dark` is never applied.” | Rejected. | `BridgeViewerAppShell` explicitly renders `className="dark ..."` and is the live `BridgeApp` root. Git blame shows that activation has existed since commit `85b1faa0a` on 2026-06-25. The 28 utility occurrences are reachable for ordinary descendants. |
| Outline and ghost dark fills never render. | Rejected as a blanket statement. | They render for controls beneath `BridgeViewerAppShell`, including the new context-panel drawer because its portal container lives under the shell. Default Base UI popover/menu/tooltip portals may escape to `body`; appearance reachability must therefore be evaluated per portal owner, not globally. |
| “The checker never merged; it only lives on `origin/toggle-primary-selection`.” | Correct outcome, wrong history. | The checker is absent now and remains on the remote toggle branch. But PR #303 included checker commit `90c6a3f68` and then deliberately deleted 506 checker/allowlist lines in final pre-merge commit `b88c6045e` (`chore(bridge-web): remove custom design token checker`). PR #303 merged as `284420c0d`. |
| S0 can simply recover the checker. | Narrowed. | The gate requirement is settled, but the deleted count-only implementation must not be restored unchanged. Planning chooses occurrence-specific exceptions in a recovered checker or implements equivalent rules in the existing architecture checker. No new owner decision is required. |
| Tree hover leaks Catppuccin `#313244` because no hover override exists. | Rejected. | Bridge sets `--trees-bg-muted-override: var(--bridge-surface-raised-bg)`. Pierre defines `--trees-bg-muted` with that override first and uses it for item hover. The completed tree inventory confirms all five non-palette chrome values are shadowed; reachable `gitDecoration.*` values remain S4 palette-mirror work. |
| `components/ui` contains 23 primitives. | Corrected terminology. | There are 22 production `.tsx` primitive files plus `tooltip.browser.test.tsx`; 23 counts the test as a primitive. The reviewed artifact's final 22 is correct; the earlier independent inventory's 23 was not. |
| 33 production files import primitives. | Corrected and clarified by the reviewed audit. | Direct current search finds 30 non-test files importing `components/ui`: 4 are internal primitive composition and 2 are bootstrap `Toaster` consumers, leaving 24 control/adjacent product consumers (26 including bootstrap). The updated audit now uses 26 product files and reserves 33 for its broader primitive/wrapper usage census. |

### 3.3 Still useful but not independently reproducible from the artifact

The following counts may be accurate, but the reviewed artifact does not include the exact census commands and its scratchpad receipts are not committed:

- 163 primitive usages
- 32 files restyling geometry/typography/paint
- 263 arbitrary Tailwind values partitioned as 167 / 72 / 24
- seven distinct disabled recipes

These counts should not be used as pass/fail gates until their command and inclusion/exclusion rules are recorded beside them. The anchored qualitative findings do not depend on these totals.

## 4. Comparison with this session's independent inventories

### 4.1 Where both audits agree

Both independent inventories and the reviewed audit found:

- production controls resolve through owned primitives rather than raw HTML;
- `Button sm` and `Toggle sm` use different typography/focus/outline recipes;
- Checkbox and Sonner still depend on transitional `--bridge-*` aliases;
- the BridgeViewer chrome constants duplicate primitive responsibilities;
- Share scope, comparison trigger, search field, filter menu, code-view collapse, and branch selector are the main override concentrations;
- primary itself is not the Share drawer defect; selecting the primary Button variant for peer destinations was the defect;
- the Share disabled state is weak because `border-border` is attenuated again by whole-control opacity.

### 4.2 What the reviewed audit adds

The reviewed audit usefully adds:

- the exact PR #303/S1 program history;
- the stale `#89B4FA` documentation diagnosis;
- Pierre font-default verification;
- the wider compatibility-alias and arbitrary-value census;
- an ordered cutover concept spanning gate, scale, primitive, chrome, File, Pierre theme, annotation context, and alias removal.

### 4.3 What this validation changes

The first reviewed revision had these incorrect models:

```text
reviewed audit
  .dark absent -> every dark branch dead

validated current source
  BridgeViewerAppShell carries .dark
    -> ordinary descendants activate dark branches
    -> context-panel drawer remains under .dark
    -> Popover, DropdownMenu, Tooltip and Combobox portal to body
    -> those four families do not inherit the shell's .dark class
    -> one primitive can render differently in-tree versus portaled
```

```text
reviewed audit
  tree theme #313244 -> hover leak

current source + Pierre CSS
  #313244 theme fallback
    -> --trees-bg-muted-override wins
    -> hover uses Bridge surface-raised value
```

The updated reviewed audit now expresses both corrected models.

### 4.4 Review-comment validation

| # | Review comment | Disposition | Evidence and consequence |
|---|---|---|---|
| 1 | Portal reachability is concrete, not merely “per owner.” | Upheld. | Base UI defaults Popover, Menu, Tooltip, and Combobox portals to `document.body`; the owned wrappers provide no container. The context-panel Drawer alone supplies a portal container beneath `BridgeViewerAppShell`. The current `.dark` activation is therefore inconsistent by surface. |
| 2 | D0 is an implementation choice, not a new owner decision. | Upheld. | R11 already requires the five enforcement rules. PR #303's recorded objection targets count-only allowlists, not the requirement for a gate. The implementation must use occurrence-specific exceptions or place equivalent rules in the existing architecture checker. |
| 3 | The tree inventory is complete and changes S4. | Upheld. | Bridge's override-first chains cover background, hover/muted background, border, foreground, muted foreground, focus, search, and selection. The five non-palette Catppuccin chrome values are shadowed. S4 should delete those dead theme keys and source reachable `gitDecoration.*` values through the palette mirror. |
| 4 | Code-view CSS still leaks transitional aliases into Pierre. | Upheld. | `bridge-code-view-options.ts` defines five `--diffs-*` values from `--bridge-added`, `--bridge-deleted`, `--bridge-accent`, `--bridge-text-primary`, and `--bridge-text-muted`. This violates the accepted role/context layering even though the frozen `--diffs-*` names remain correct. |
| 5 | This validation did not state the target contract. | Upheld. | Section 4.5 below adopts the reviewed audit's Section A where it is settled and names the remaining value decisions instead of leaving “systematic” abstract. |
| 6 | Floating frames, radii, naming, panel padding, and menu density were omitted. | Upheld as inventory. | Three floating-frame recipes, ten effective control radii, the `--bridge-text-secondary` naming trap, 16px Drawer padding, and 13px/32px menu rows are all present. Exact drawer inset and elevation convergence remain explicit design choices, not automatic deletion. |
| 7 | Two slice numbering systems exist. | Upheld. | This document now uses the reviewed audit's canonical S0/S1b/S1c/S2-S6 identifiers only. |

### 4.5 Target contract disposition

The reviewed audit's Section A is adopted as the target contract with these classifications:

| Contract area | Disposition |
|---|---|
| Appearance | Settled: Swift chrome, BridgeWeb, and Pierre are dark-only. Primitive paint is unconditional; no `.dark` ancestry or light compatibility branch. |
| Canvas | Settled: Ghostty grey `#282C34` is the app/code canvas base. Darker ramp values distinguish rails, headers, and raised surfaces. |
| Product and syntax blues | Settled: `#409CFF` is product primary; `#89B4FA` remains syntax blue. |
| Type ramp | Adopt A1: 9/11/12/13/14/16/24 with explicit line heights. Re-anchoring Tailwind names was already selected by the 2026-08-16 Program Design. |
| Radius ramp | Adopt A1: 4/6/8/14. |
| Control heights | Adopt A1: 20/24/28/32 for xs/sm/default/lg. |
| State recipes | Adopt A3: one primitive-owned rest, hover, active/open, selected, focus-visible, disabled, and invalid recipe. |
| Primitive ownership | Adopt A4/A5: `components/ui` owns control paint/type/geometry; BridgeViewer wrappers retain composition, attributes, and test IDs only. |
| Curated exceptions | Adopt A6, including frozen Pierre variable names, annotation context roles, status dots, sticky-header metric, Markdown prose, and named motion. |
| Icon scale | Open D2: 14px versus native-aligned 12px for `sm`. |
| Menu density | Open D3: current 13px/32px versus compact 11px/28px. |
| Sidebar primary | Open D4: product-primary identity versus retained syntax-blue distinction. |
| Disabled paint | Open D5: opacity-based recipe versus explicit disabled roles; `outline` starting from `border-input` is required either way. |
| Textarea minimum | Open D7: compact correction is required; exact `min-h-12` remains owner-visible. |
| Floating frames | Adopt one primitive-owned frame family. Distinct elevation variants remain allowed when geometry differs; a side drawer may retain a directional shadow without becoming a feature-local recipe. |
| Drawer inset | Inventory fact: current `p-4` is 16px, outside the stated 4/6/8 compact scale. Decide whether 16px becomes a named panel-inset token or changes visually; do not leave it as an accidental local value. |

### 4.6 Residual inconsistencies in the updated reviewed audit

The reviewed audit corrected its main narrative, but three stale lines remain:

- census section D still says “`.dark` class applied: never”; current source proves the opposite;
- A7 still calls the variant dead code without distinguishing the current active in-tree branch from the required unconditional-dark target;
- the S0 row still depends on “owner D0,” although R11 and the latest owner direction already require enforcement and leave only an implementation choice;
- A4 names `shadow-context-panel` for Drawer, then immediately says every floating surface must use `shadow-popover`. The contract should say one primitive-owned frame family with explicitly named elevation variants, or choose one identical shadow intentionally.

Portal wording also needs precision: all four wrappers portal to `document.body`, but the current visible styling divergence exists where portaled content or its descendants actually use `dark:` classes. DropdownMenu and Combobox do so directly; Popover-hosted controls can do so as descendants. Tooltip currently has no local `dark:` class, so its body portal is a structural ancestry risk rather than proof of a present tooltip paint delta.

## 5. Decision and plan classification

The reviewed audit's Section C is not ready to execute unchanged.

| Decision | Validation classification |
|---|---|
| D0 — restore or replace the deliberately removed checker | Not an owner decision. R11 already requires the gate. Planning chooses occurrence-specific allowlists in a recovered checker or equivalent rules in the existing architecture checker. Count-only allowlists are rejected. |
| D1 — re-anchor Tailwind text names | Already selected by the 2026-08-16 Program Design section 3. It becomes an owner question only if that settled decision is intentionally reopened. |
| D2 — 14px versus 12px `sm` icons | Genuine visible owner decision. |
| D3 — 11/28 versus 13/32 menu rows | Genuine visible owner decision. |
| D4 — sidebar primary identity | Genuine semantic/visual owner decision because product and syntax blues were later separated. |
| D5 — disabled paint | Genuine visible owner decision, although the first correction is independently clear: outline must not start from the hairline separator role. |
| D6 — dissolve `BridgeViewerButton` | Internal structural decision, not inherently an owner decision. The binding contract is that it become a thin adapter with no paint/type/geometry authority; whether the component remains for attributes/test IDs is implementation structure. |
| D7 — Textarea minimum height | Genuine visible/product-density decision. The old Program Design requires a compact correction but does not settle `min-h-12`. |
| D8 — single-appearance realization across in-tree and body portals | Settled requirement, not an open owner decision: BridgeWeb is dark-only. Fold the intended effective dark paint into unconditional primitive recipes, verify in-tree and body-portal surfaces, then delete `dark:` variants, the custom variant, and dependence on a `.dark` ancestor. |

## 6. Canonical remediation dependency tree

```text
Authority reconciliation  before planning
  |- update stale #89B4FA docs to product-primary #409CFF
  |- record Ghostty grey #282C34 as the app/code canvas base
  `- record unconditional dark target and current portal inconsistency

S0   enforcement gate
  |- recover the five required rules
  |- use occurrence-specific exceptions, not count-only allowlists
  `- choose checker placement during implementation planning

S1b  typography and radius re-anchor
  |- install the adopted A1 scales
  |- set explicit Pierre code/tree font sizes
  `- remove compensating literal type/radius overrides in the same slice

S1c  owned primitive harmonization
  |- one state recipe per A3
  |- one primitive-owned floating-frame family
  |- fold intended dark paint into unconditional recipes
  `- remove dark variants only after in-tree and body-portal parity proof

S3   shared chrome cutover
  |- wrappers retain attributes/composition only
  `- feature code owns layout, not paint/type/geometry

S2   File viewer cutover
  `- replace bespoke control classes with the harmonized primitives

S4   Pierre theme and CSS cutover
  |- delete shadowed tree chrome keys
  |- source reachable gitDecoration values through the palette mirror
  |- migrate five unsafeCSS --diffs-* derivations from aliases to roles
  |- bind code background to the Ghostty-grey canvas role
  `- preserve the already-working tree hover result

S5   annotation context cutover
  `- consume --comment-* roles without Bridge aliases

S6   final alias removal
  `- delete aliases only after every consumer and allowlist entry is gone
```

This is a dependency correction, not approval of a final implementation plan. Requirements/Specification/Program Design must be reconciled with the later `#409CFF` owner decision and the actual `.dark` runtime before a new plan becomes authoritative.

## 7. Reproduction ledger

Key read-only checks used:

```bash
wc -l docs/wip/2026-09-04-bridgeweb-style-system-audit.md
wc -l docs/specs/2026-08-16-bridgeweb-design-tokens/*.md
rg -o --no-filename 'var\(--bridge-[A-Za-z0-9-]+' BridgeWeb/src --glob '!*.test.*'
rg -n 'dark:' BridgeWeb/src --glob '!*.test.*'
rg -n 'className="dark' BridgeWeb/src
git blame -L 1,20 -- BridgeWeb/src/app/bridge-viewer-app-shell.tsx
gh pr view 303 --json state,mergedAt,mergeCommit,commits
git show b88c6045e -- BridgeWeb/package.json BridgeWeb/scripts
git show origin/toggle-primary-selection:BridgeWeb/scripts/check-bridgeweb-design-tokens.ts
rg -n --follow -- '--trees-bg-muted|--trees-font-size' BridgeWeb/node_modules/@pierre/trees/dist/style.js
rg -n --follow -- '--diffs-font-size' BridgeWeb/node_modules/@pierre/diffs/dist
```

No application source, configuration, tests, or infrastructure were changed by this validation.
