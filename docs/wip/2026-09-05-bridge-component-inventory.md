# Bridge shared-component alignment inventory

Scope: all 22 `BridgeWeb/src/components/ui/*.tsx` families, their direct production
imports, and shared Bridge adapter/style-override scans. This inventory distinguishes
source coverage from rendered proof; a valid token or class is not a visual pass.
It supplements [the UI TODO](2026-09-05-bridge-ui-consistency-todo.md), not the governing plan.

## Ownership contract

CSS defines canonical values and roles. Owned UI primitives define complete recipes.
Bridge adapters choose a supported size/variant and arrange layout. A shared fix is
applied once per primitive family; callers are checked for overrides and wrong variants.
Pierre and native Swift remain separately verified rendering paths.

## Family inventory

Direct imports are import-site counts outside `components/ui`, excluding test/browser
files; they are not total rendered controls or transitive consumers. Counts came from
`rg` on literal `components/ui/<family>` imports. Internal-only/unused exports are explicit.

| Family | Direct imports | Current source disposition / next proof |
|---|---:|---|
| button | 13 | Owned 20/24/28/32 ladder, 11px labels, explicit disabled paint. Existing state/geometry coverage; continue app-wide live-state audit. |
| toggle | 1 | Same compact ladder and state roles; used through ToggleGroup too. |
| toggle-group | 5 | Shared segmented 20px inner items within 24px frame corrected and browser/native reviewed. Ordinary outline groups retain their selected size. |
| input | 1 | Owned 24/28px sizes, 11px label, focus/invalid/disabled roles. |
| input-group | 1 | Bridge search uses default 28px outer recipe; internal Combobox also uses it. Nested icon/button sizing needs compound-state proof, not global icon resizing. |
| textarea | 2 | 48px minimum, 12px editing text, explicit state roles; multiline text is not an 11px toolbar label. |
| checkbox | 0 | Named 14px compact indicator; no direct product import found. Do not force button geometry onto it. |
| dropdown-menu | 2 | Owned 28px rows, 11px labels, 14px row icons and canonical frame. Motion recipes still have a 100ms candidate to reconcile with the pinned motion scale. |
| combobox | 1 | Owned 28px rows and canonical frame; compound InputGroup boundaries present. Same 100ms motion follow-up. |
| popover | 2 | Confirmed shared gap fixed: 10px padding ->8px, 16px gap ->8px, compact title14px ->11px. Both comparison and annotation-admission consumers tested; native/review proof pending. |
| drawer | 3 | Header/body/footer density and matched scope icons corrected; native and independent bounded review complete for reported drawer issues. |
| tooltip | 2 | Canonical frame, 11px text, 8px horizontal/4px vertical padding. Motion-state consistency remains to inspect. |
| field | 2 | Live comparison uses Field/FieldTitle; no FieldSet/FieldGroup consumers found. Their 16px grouping gaps are not an established live defect; do not modify speculatively. |
| label | 0 | Internally used by Field; 11px text and explicit disabled foreground. |
| alert | 5 | 8px horizontal/6px vertical padding; status icon/text semantics differ from toolbar controls. Remaining feature-local empty-state layouts require separate classification. |
| sonner | 2 | Canonical floating palette/elevation; 11px title/9px detail and14px status icons. Do not relabel status glyphs as toolbar icons. |
| avatar | 1 | 24px circular identity badge in annotations; intentionally distinct from action buttons. |
| collapsible | 2 | Annotation threads/output history; 200ms opening and150ms closing currently require motion-scale reconciliation. |
| skeleton | 2 | Loading placeholders; caller dimensions describe absent content rather than button recipes. |
| separator | 0 | Internal Field consumer; semantic border and1px divider. |
| scroll-area | 0 | No direct production importer found; overflow wrapper, not a control recipe. |
| resizable | 1 | Shared rail layout; border/focus roles. Handle dimensions serve dragging, not button density. |

## Confirmed consumer gaps

- Annotation admission used 20px `xs` action buttons inside a popover. All its session
  choices now select the existing 28px default Button size; handlers and eligibility unchanged.
- Admission's local `gap-2` override became redundant after the shared Popover correction
  and was removed.
- Comparison had a14px title assertion; it now measures the shared11px compact title.
- Review applied `opacity-50` to both canvas and tree during comparison loading.
  Candidate removes only fading/opacity transitions: `inert`, pointer blocking,
  `aria-busy` and status banner remain. Clean RED measured0.5vs1; GREEN14tests exit0.
  Logs: `tmp/plan-workflows/2026-09-05-review-loading-contrast-red-clean.log` and
  `tmp/plan-workflows/2026-09-05-review-loading-contrast-green.log`. Native visual proof pending.

No production raw pixel text/radius override or additional numeric opacity hit was found
in the scanned Bridge adapter/File/Review/annotation TSX paths beyond those two loading
wrappers. This is a bounded literal-pattern result, not proof against all composed styles.

## Shared motion correction

The table's100/150ms motion findings now have a working-tree correction:
canonical Tailwind default transition duration uses existing `--motion-fast`; Popover,
DropdownMenu/submenu, Combobox and Tooltip use120ms explicitly. Collapsible uses200ms
expansion and120ms closing; existing `motion-reduce:transition-none` is preserved.
No lifecycle, callback or timer policy was changed. Motion waits in tests observe actual
ending attributes and advance bounded animation frames within React act.

RED: computed defaults/popover/menu mismatches and actual Collapsible ending150vs120,
4failed/4passed in `tmp/plan-workflows/2026-09-05-shared-motion-frame-red.log`.
Earlier test-harness attempts are preserved separately and are not the final RED.
GREEN: shared style/tooltip/admission/inline annotation suites4files22tests pass,exit0,
`tmp/plan-workflows/2026-09-05-shared-motion-green.log`. Native motion/reduced-motion
manual proof and independent review remain open; source preservation alone is not proof.

## Latest combined verification

`mise run test:bridge-web:check` passed,exit0. Full browser suite:357passed,
1known post-Save admission failure,5skipped,exit1. Raw logs:
`tmp/plan-workflows/2026-09-05-shared-component-check.log` and
`tmp/plan-workflows/2026-09-05-shared-component-browser.log`.

Standard native launch succeeded (11.53s build,exit0), PID69936/window122594,
marker `debug-observability-1owk-1788625518-68943`. Exact-window capture refused because
the macOS GUI session is locked. No image was produced and no subsequent UI action was
attempted. Unlock is required for current native visual/motion proof; earlier screenshots
are not promoted to evidence for the latest Popover/loading/motion changes.

## Popover proof

- RED:2failed/9passed, exit1; shared10px inset versus8px and undersized admission action.
  `tmp/plan-workflows/2026-09-05-popover-density-red.log`.
- GREEN:4files/29tests passed, exit0, covering shared frame plus real comparison/admission
  React consumers. `tmp/plan-workflows/2026-09-05-popover-density-green.log`.
- Quality: `mise run test:bridge-web:check`, exit0 after scoped test formatting;
  `tmp/plan-workflows/2026-09-05-popover-density-check-green.log`.
- Parent inspected `tmp/bridgeweb-admission-popover-density.png`. Geometry waits for
  actual opening-animation completion, not an arbitrary sleep.
- Still required: native comparison/admission visual proof and independent correction
  review. Full Save/reply/Share remains tracked separately; no whole-UI completion claim.
