import type { SceneTimeline } from "../motion-scenes/scene-contract";

interface HeroPoint {
  readonly x: number;
  readonly y: number;
}

interface RoutePoint extends HeroPoint {
  readonly normalX: number;
  readonly normalY: number;
}

const tokenColours = ["#9aafcf", "#bfa597", "#a5b8a3", "#b3a8c4", "#9db6c2", "#c2b9a0"];
const installTokens = ["brew", "{ }", "✦", "tap", "⟨/⟩", "#", "cask", "▍", "→", "✦", "01"];
const codexTokens = ["map", "✦", "λ", "{ }", "git", "⟨/⟩", "▍", "✦", "tree", "→", "01"];
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
  const visibleFraction = (progress - 0.22) / 0.62;
  return visibleFraction > 0 && visibleFraction < 1
    ? Math.sin(Math.PI * visibleFraction) * 0.72
    : 0;
}

function textEnd(element: HTMLElement): HeroPoint {
  const textRange = document.createRange();
  textRange.selectNodeContents(element);
  const bounds = textRange.getBoundingClientRect();
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
    ".install-command__line",
    "[data-hero-intro-copy]",
    "[data-hero-intro-eyebrow-settled]",
  ];
  const rectangles: DOMRect[] = [];
  for (const element of root.querySelectorAll<HTMLElement>(selectors.join(","))) {
    const style = getComputedStyle(element);
    if (style.display === "none" || style.visibility === "hidden" || Number(style.opacity) < 0.05)
      continue;
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
  const readyArrow = visible("[data-hero-intro-ready-arrow]");
  const codexInput = root.querySelector<HTMLElement>(".hero-codex-input");
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
        duration: 0.5,
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
          const blocked = visibleTextRects(root);
          tokens.forEach((token, index) => {
            const lag = (index / tokens.length) * 0.3;
            const progress = clampUnit((state.fraction - lag) / (1 - lag * 0.6));
            const opacity = heroBurstTokenOpacity(progress);
            if (opacity <= 0) return;
            const point = pointAlongHeroRoute(route, easeInOut(progress));
            const offset = (index % 2 === 0 ? -1 : 1) * (3 + ((index * 7) % 6));
            const text = document.createElementNS(svgNamespace, "text");
            text.setAttribute("x", String(point.x + point.normalX * offset));
            text.setAttribute("y", String(point.y + point.normalY * offset + 3));
            text.setAttribute("text-anchor", "middle");
            text.setAttribute("font-size", String(11 + (index % 3)));
            text.setAttribute("font-family", "ui-monospace, SF Mono, Menlo, monospace");
            text.setAttribute("font-weight", "500");
            text.setAttribute("fill", tokenColours[index % tokenColours.length] ?? "#9aafcf");
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
    if (readyArrow === null || windowNode === null || install === null) return null;
    const source = textEnd(readyArrow);
    const windowRect = windowNode.getBoundingClientRect();
    const target = install.getBoundingClientRect();
    return [
      { x: source.x + 12, y: source.y },
      { x: source.x + 48, y: windowRect.bottom + 18 },
      { x: target.left - 24, y: target.top - 18 },
      { x: target.left + 18, y: target.top + 8 },
    ];
  });
  if (width >= 1024)
    addBurst("burst:codex", 8.57, codexTokens, () => {
      if (readyArrow === null || windowNode === null || codexInput === null) return null;
      const source = textEnd(readyArrow);
      const windowRect = windowNode.getBoundingClientRect();
      const target = codexInput.getBoundingClientRect();
      return [
        { x: source.x + 12, y: source.y },
        { x: source.x + 42, y: windowRect.bottom + 20 },
        { x: target.left - 20, y: windowRect.bottom + 20 },
        { x: target.left + 12, y: target.top + target.height / 2 },
      ];
    });
  addBurst("burst:rail", 12.25, railTokens, () => {
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
