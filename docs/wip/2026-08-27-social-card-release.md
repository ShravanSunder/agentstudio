# Agent Studio social-card release

Status: owner approved for release

## Scope

- Replace only the website/Open Graph/X `1200x630` social card.
- Preserve the current website copy, layout, slideshow, and product imagery.
- Use the canonical Agent Studio transparent logo.
- Keep the social card free of topology, screenshots, decorative rails, and nodes.
- Keep wider topology treatments out of this release; they belong to later 16:9 YouTube or video assets.

## Accepted copy

- `Native macOS. Repo-aware. Terminal-first.`
- `Agent Studio`
- `Run dozens of agents in one workspace.`
- `Stay oriented. Miss nothing.`

## Proof checklist

- [x] Owner approved the clean topology-free direction.
- [x] Full-size browser candidate inspected at `1200x630`.
- [x] Reduced browser candidate inspected at `600x315`.
- [x] Browser geometry: 72px side margins and 74.59375px headline-to-icon gap.
- [x] No product screenshot, topology, disconnected line, node, cursor, or private content.
- [x] Production generator reproduces the approved HTML composition.
- [x] Generated PNG is `1200x630`, sRGB, and tracked through Git LFS.
- [x] Format, lint, typecheck, unit, browser, build, and Cloudflare dry-run gates pass.
- [ ] Exact committed artifact is deployed.
- [ ] Production metadata and image integrity pass with a cache-busting query.
