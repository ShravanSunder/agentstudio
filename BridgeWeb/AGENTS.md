# BridgeWeb Agent Rules

BridgeWeb is the React app embedded by Agent Studio Bridge. Follow the root
`AGENTS.md` first, then these BridgeWeb-specific rules.

## UI Components

- Use owned shadcn-style primitives from `src/components/ui/` for React controls.
  If a needed primitive is missing, add or adapt the primitive there first.
- Do not hand-roll route-local buttons, toggles, segmented controls, inputs, or
  icon chrome when an owned primitive can express the interaction.
- Shared BridgeViewer chrome belongs in shared app/component modules, not in
  FileViewer-only or ReviewViewer-only visual language.
- FileViewer and ReviewViewer controls with the same interaction semantics must
  share scale, focus, hover, active, spacing, and icon sizing.

## BridgeViewer Proof

- Visible UX checkpoints require Vitest Browser, Playwright/dev-server, or native
  WKWebView proof. `jsdom` can cover lower-level state logic but cannot close a
  visible UX checkpoint.
- Browser proof for shared chrome must assert real geometry and screenshots:
  content header over the left content region only, right rail top-aligned,
  compact shared controls, and no standalone second app.
- A second agent/onlook should inspect screenshots and relevant source paths
  before a visible UX checkpoint is treated as ready.

## Rendering Ownership

- FileViewer and ReviewViewer must render through Pierre FileTree plus
  Pierre/Shiki CodeView/File paths with workers where the route enables workers.
- Do not replace Pierre/Shiki rendering with route-local file lists, `<pre>`
  renderers, or custom tree implementations for product proof.
- Large content bodies and render workers stay out of Zustand; Zustand stores
  navigation, selection, refs, and small facts only.

## Git Boundaries

- Production Swift/native git data prep belongs to `agentstudio-git`.
- TypeScript git helpers are allowed only in clearly marked Vite dev-server or
  test fixture utilities.
