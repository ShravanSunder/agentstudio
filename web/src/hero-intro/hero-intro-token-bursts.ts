import type { SceneTimeline } from "../motion-scenes/scene-contract";

interface HeroPoint {
  readonly x: number;
  readonly y: number;
}

interface RoutePoint extends HeroPoint {
  readonly normalX: number;
  readonly normalY: number;
}

const tokenColours = ["#b4c6e4", "#d4bcad", "#bccfb9", "#c9bfd9", "#b5cdd8", "#d6cdb4"];
const installTokens = ["brew", "{ }", "✦", "tap", "⟨/⟩", "#", "cask", "▍", "→", "✦", "01"];
const railTokens = ["wt", "main", "✦", "{ }", "drawer", "▍", "→", "review", "·"];
const svgNamespace = "http://www.w3.org/2000/svg";

function clampUnit(value: number): number {
  return Math.max(0, Math.min(1, value));
}

function easeInOut(progress: number): number {
  return progress < 0.5
    ? 4 * progress * progress * progress
    : 1 - Math.pow(-2 * progress + 2, 3) / 2;
}

/** The route uses distance, so a short bend cannot consume most of the burst. */
export function pointAlongHeroRoute(route: readonly HeroPoint[], fraction: number): RoutePoint {
  if (route.length < 2) throw new Error("A hero token route needs two points");
  const segmentLengths = route.slice(1).map((point, index) => {
    const previous = route[index];
    if (previous === undefined) throw new Error("Hero route segment is missing");
    return Math.hypot(point.x - previous.x, point.y - previous.y);
  });
  const routeLength = segmentLengths.reduce((total, length) => total + length, 0);
  let distance = clampUnit(fraction) * routeLength;
  for (const [index, length] of segmentLengths.entries()) {
    const start = route[index];
    const end = route[index + 1];
    if (start === undefined || end === undefined) throw new Error("Hero route point is missing");
    if (distance <= length || index === segmentLengths.length - 1) {
      const position = length === 0 ? 0 : Math.min(1, distance / length);
      return {
        x: start.x + (end.x - start.x) * position,
        y: start.y + (end.y - start.y) * position,
        normalX: length === 0 ? 0 : -(end.y - start.y) / length,
        normalY: length === 0 ? 0 : (end.x - start.x) / length,
      };
    }
    distance -= length;
  }
  throw new Error("Hero route has no segments");
}

export function heroBurstTokenOpacity(progress: number): number {
  const visibleFraction = (progress - 0.08) / 0.86;
  return visibleFraction > 0 && visibleFraction < 1
    ? Math.sin(Math.PI * visibleFraction) * 0.95
    : 0;
}

function installBurstTokenOpacity(progress: number): number {
  if (progress <= 0.04) return 0;
  if (progress < 0.16) return ((progress - 0.04) / 0.12) * 0.95;
  if (progress <= 0.95) return 0.95;
  return Math.pow((1 - progress) / 0.05, 0.15) * 0.95;
}

function textEnd(element: HTMLElement): HeroPoint {
  const textRange = document.createRange();
  textRange.selectNodeContents(element);
  const bounds = textRange.getBoundingClientRect();
  return { x: bounds.right, y: bounds.top + bounds.height / 2 };
}

function lastGlyphEnd(element: HTMLElement): HeroPoint {
  const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
  let lastTextNode: Text | undefined;
  while (walker.nextNode()) {
    const textNode = walker.currentNode;
    if (textNode instanceof Text && textNode.textContent?.trim()) lastTextNode = textNode;
  }
  if (lastTextNode === undefined) throw new Error("Hero Bash row has no text");
  const range = document.createRange();
  range.setStart(lastTextNode, Math.max(0, lastTextNode.length - 1));
  range.setEnd(lastTextNode, lastTextNode.length);
  const bounds = range.getBoundingClientRect();
  return { x: bounds.right, y: bounds.top + bounds.height / 2 };
}

function intersects(left: DOMRect, right: DOMRect): boolean {
  return (
    left.left < right.right + 2 &&
    left.right > right.left - 2 &&
    left.top < right.bottom + 2 &&
    left.bottom > right.top - 2
  );
}

function visibleTextRects(root: HTMLElement): DOMRect[] {
  const selectors = [
    ".hero-transcript-row",
    ".hero-claude-input",
    ".hero-codex-input",
    ".hero-claude-footer",
    ".hero-codex-footer",
    ".install-command__line",
    "[data-hero-intro-copy]",
    "[data-hero-intro-eyebrow-settled]",
  ];
  const rectangles: DOMRect[] = [];
  for (const footer of root.querySelectorAll<HTMLElement>(
    ".hero-claude-footer, .hero-codex-footer",
  )) {
    if (footer.checkVisibility({ opacityProperty: true, visibilityProperty: true }))
      rectangles.push(footer.getBoundingClientRect());
  }
  for (const element of root.querySelectorAll<HTMLElement>(selectors.join(","))) {
    if (!element.checkVisibility({ opacityProperty: true, visibilityProperty: true })) continue;
    const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
    while (walker.nextNode()) {
      const textNode = walker.currentNode;
      if ((textNode.textContent?.trim().length ?? 0) === 0) continue;
      const range = document.createRange();
      range.selectNodeContents(textNode);
      rectangles.push(...range.getClientRects());
    }
  }
  return rectangles;
}

interface TokenBurstOptions {
  readonly root: HTMLElement;
  readonly timeline: SceneTimeline;
  readonly width: number;
}

/** The only out-of-pane cues: short, seek-safe token bursts with no connectors. */
export function addHeroTokenBursts({ root, timeline, width }: TokenBurstOptions): void {
  const layer = document.createElementNS(svgNamespace, "svg");
  layer.setAttribute("data-hero-token-layer", "");
  layer.setAttribute("aria-hidden", "true");
  layer.style.cssText =
    "position:fixed;inset:0;width:100vw;height:100vh;overflow:visible;pointer-events:none;z-index:5";
  root.append(layer);

  const visible = (selector: string): HTMLElement | null =>
    [...root.querySelectorAll<HTMLElement>(selector)].find(
      (element) => element.getClientRects().length > 0,
    ) ?? null;
  const windowNode = root.querySelector<HTMLElement>("[data-hero-terminal-window]");
  const install = root.querySelector<HTMLElement>("[data-hero-intro-install]");
  const bashRow =
    [
      ...root.querySelectorAll<HTMLElement>(
        ".hero-terminal-pane--claude .hero-transcript-row--tool-call",
      ),
    ].find((row) => row.getClientRects().length > 0 && row.querySelector("[data-hero-bash-dot]")) ??
    null;
  const firstInstallCommand = install?.querySelector<HTMLElement>(".install-command__line");
  const result = visible(
    `.hero-terminal-pane--${width < 1024 ? "claude" : "codex"} [data-hero-worktree-result]`,
  );
  const railNode = document.querySelector<SVGGElement>('[data-topology-chapter-node="hero"]');

  const addBurst = (
    label: string,
    start: number,
    tokens: readonly string[],
    getRoute: () => HeroPoint[] | null,
  ): void => {
    timeline.addLabel(label, start);
    const state = { fraction: 0 };
    timeline.to(
      state,
      {
        fraction: 1,
        duration: 0.9,
        ease: "none",
        onUpdate: () => {
          layer.replaceChildren();
          const route = getRoute();
          if (route === null) return;
          if (label === "burst:rail") {
            const endpoint = route.at(-1);
            if (endpoint !== undefined) {
              layer.setAttribute("data-hero-burst-end-x", String(endpoint.x));
              layer.setAttribute("data-hero-burst-end-y", String(endpoint.y));
            }
          }
          if (label === "burst:install") {
            const source = route[0];
            const endpoint = route.at(-1);
            if (source !== undefined && endpoint !== undefined) {
              layer.setAttribute("data-hero-install-start-x", String(source.x));
              layer.setAttribute("data-hero-install-start-y", String(source.y));
              layer.setAttribute("data-hero-install-end-x", String(endpoint.x));
              layer.setAttribute("data-hero-install-end-y", String(endpoint.y));
            }
          }
          const blocked = visibleTextRects(root);
          tokens.forEach((token, index) => {
            const maximumLag = 0.3;
            const lag = (index / tokens.length) * maximumLag;
            const travelTime = label === "burst:install" ? 1 - maximumLag : 1 - lag;
            const progress = clampUnit((state.fraction - lag) / travelTime);
            const pathProgress = label === "burst:install" ? progress : easeInOut(progress);
            const opacity =
              label === "burst:install"
                ? installBurstTokenOpacity(pathProgress)
                : heroBurstTokenOpacity(progress);
            if (opacity <= 0) return;
            const point = pointAlongHeroRoute(route, pathProgress);
            const offset = (index % 2 === 0 ? -1 : 1) * (3 + ((index * 7) % 6));
            const text = document.createElementNS(svgNamespace, "text");
            text.setAttribute("data-hero-burst-token-index", String(index));
            text.setAttribute("x", String(point.x + point.normalX * offset));
            text.setAttribute("y", String(point.y + point.normalY * offset + 3));
            text.setAttribute("text-anchor", "middle");
            text.setAttribute("font-size", String(12 + (index % 3)));
            text.setAttribute("font-family", "ui-monospace, SF Mono, Menlo, monospace");
            text.setAttribute("font-weight", "600");
            text.setAttribute("fill", tokenColours[index % tokenColours.length] ?? "#b4c6e4");
            text.setAttribute("opacity", opacity.toFixed(3));
            text.textContent = token;
            layer.append(text);
            if (blocked.some((rectangle) => intersects(text.getBoundingClientRect(), rectangle)))
              text.remove();
          });
        },
        onComplete: () => layer.replaceChildren(),
      },
      start,
    );
  };

  addBurst("burst:install", 7.05, installTokens, () => {
    if (
      bashRow === null ||
      windowNode === null ||
      install === null ||
      firstInstallCommand === undefined ||
      firstInstallCommand === null
    )
      return null;
    const source = lastGlyphEnd(bashRow);
    const windowRect = windowNode.getBoundingClientRect();
    const pane = bashRow.closest<HTMLElement>(".hero-terminal-pane");
    if (pane === null) return null;
    const paneRect = pane.getBoundingClientRect();
    const target = firstInstallCommand.getBoundingClientRect();
    const boxRect = install.querySelector<HTMLElement>(".install-command")?.getBoundingClientRect();
    if (boxRect === undefined) return null;
    const clearMarginX = Math.max(source.x + 8, paneRect.right - 18);
    const gapHeight = boxRect.top - windowRect.bottom;
    const gapY = gapHeight >= 16 ? windowRect.bottom + gapHeight / 2 : windowRect.bottom + 8;
    const arrivalX = target.left - 14;
    const lineMidY = target.top + target.height / 2;
    return [
      { x: source.x + 8, y: source.y },
      { x: clearMarginX, y: source.y },
      { x: clearMarginX, y: gapY },
      { x: arrivalX, y: gapY },
      { x: arrivalX, y: lineMidY },
    ];
  });
  addBurst("burst:rail", width >= 1024 ? 12.35 : 12.65, railTokens, () => {
    if (result === null || windowNode === null || railNode === null) return null;
    const source = textEnd(result);
    const windowRect = windowNode.getBoundingClientRect();
    const target = railNode.getBoundingClientRect();
    const clearY = windowRect.top - 24;
    return [
      { x: source.x + 12, y: source.y },
      { x: windowRect.right + 22, y: source.y + 6 },
      { x: windowRect.right + 22, y: clearY },
      { x: target.left + target.width / 2 + 24, y: clearY },
      { x: target.left + target.width / 2, y: clearY },
      { x: target.left + target.width / 2, y: target.top + target.height / 2 },
    ];
  });
}
