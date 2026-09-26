import type { SceneTimeline } from "../motion-scenes/scene-contract";
import { layoutFullPageTopology } from "../topology-lab/full-page-topology-layout";

const railDrawStart = 5.85;
const railDrawEnd = 6.75;
const preferredHopDuration = 0.12;

interface RailDrawOptions {
  readonly timeline: SceneTimeline;
  readonly artwork: SVGSVGElement;
}

function requiredPath(artwork: SVGSVGElement, selector: string): SVGPathElement {
  const path = artwork.querySelector<SVGPathElement>(selector);
  if (path === null || path.getTotalLength() <= 0) {
    throw new Error(`Hero rail draw is missing ${selector}`);
  }
  return path;
}

function rowY(node: SVGGElement): number {
  return Number(node.querySelector("circle")?.getAttribute("cy"));
}

function clipAtY(artwork: SVGSVGElement, y: number): string {
  const bottomInset = 100 - Math.min(100, Math.max(0, (y / artwork.clientHeight) * 100));
  return `inset(0 0 ${bottomInset}% 0)`;
}

function paintPathFromStart(
  timeline: SceneTimeline,
  path: SVGPathElement,
  start: number,
  duration: number,
): void {
  const length = path.getTotalLength();
  path.setAttribute("data-hero-intro-rail-path", "");
  timeline.set(path, { strokeDasharray: length, strokeDashoffset: length }, 0);
  timeline.to(path, { strokeDashoffset: 0, duration, ease: "power2.inOut" }, start);
}

/** Reveal existing rail geometry a row at a time; the hero attach is the last hop. */
export function addHeroRailStaircase({ timeline, artwork }: RailDrawOptions): void {
  if (!layoutFullPageTopology(artwork)) {
    throw new Error("Hero rail draw could not lay out the topology");
  }
  const heroNode = artwork.querySelector<SVGGElement>('[data-topology-chapter-node="hero"]');
  if (heroNode === null) throw new Error("Hero rail mainline node is missing");
  const branchPath = requiredPath(
    artwork,
    '[data-route-anchor="hero"] [data-topology-path-role="core"]',
  );
  const branchStartY = branchPath.getPointAtLength(0).y;
  const branchEndY = branchPath.getPointAtLength(branchPath.getTotalLength()).y;
  const heroY = rowY(heroNode);
  const introNodes = [...artwork.querySelectorAll<SVGGElement>("[data-topology-node-progress]")]
    .filter((node) => rowY(node) >= heroY - 0.5 && rowY(node) <= branchStartY + 0.5)
    .sort((left, right) => rowY(left) - rowY(right));
  if (introNodes.length < 2) throw new Error("Hero rail staircase needs at least two dots");
  const rows: { y: number; nodes: SVGGElement[] }[] = [];
  for (const node of introNodes) {
    const y = rowY(node);
    const lastRow = rows.at(-1);
    if (lastRow !== undefined && Math.abs(lastRow.y - y) <= 0.5) lastRow.nodes.push(node);
    else rows.push({ y, nodes: [node] });
    node.setAttribute("data-hero-intro-rail-node", "");
    timeline.set(node, { opacity: 0, scale: 0.6, transformOrigin: "50% 50%" }, 0);
  }
  if (rows.length < 2) throw new Error("Hero rail staircase needs distinct rows");

  const hopCount = rows.length;
  const hopDuration = Math.min(preferredHopDuration, (railDrawEnd - railDrawStart) / hopCount);
  const hopInterval = (railDrawEnd - railDrawStart - hopDuration) / (hopCount - 1);
  timeline.addLabel("rail:start", railDrawStart);
  timeline.addLabel("rail:end", railDrawEnd);
  timeline.set(artwork, { clipPath: "inset(0 0 100% 0)" }, 0);
  timeline.set(artwork, { clipPath: clipAtY(artwork, rows[0]?.y ?? heroY) }, railDrawStart);

  for (const [rowIndex, row] of rows.entries()) {
    const arrival =
      rowIndex === 0 ? railDrawStart : railDrawStart + (rowIndex - 1) * hopInterval + hopDuration;
    const nextHopStart = railDrawStart + rowIndex * hopInterval;
    const popStart = rowIndex === 0 ? railDrawStart : Math.max(arrival, nextHopStart - 0.07);
    timeline.to(
      row.nodes,
      {
        opacity: 1,
        scale: 1,
        duration: 0.14,
        ease: "back.out(2)",
      },
      popStart,
    );
    if (rowIndex + 1 < rows.length) {
      const nextY = rows[rowIndex + 1]?.y;
      if (nextY === undefined) throw new Error("Hero rail staircase row is missing");
      timeline.to(
        artwork,
        {
          clipPath: clipAtY(artwork, nextY),
          duration: hopDuration,
          ease: "power2.inOut",
        },
        nextHopStart,
      );
    }
  }

  for (const group of artwork.querySelectorAll<SVGGElement>('[data-route-kind="worktree"]')) {
    const core = group.querySelector<SVGPathElement>('[data-topology-path-role="core"]');
    if (core === null || core.getTotalLength() <= 0) continue;
    const forkY = core.getPointAtLength(0).y;
    if (forkY < heroY - 0.5 || forkY > branchStartY + 0.5) continue;
    const forkRowIndex = rows.findLastIndex((row) => row.y <= forkY + 0.5);
    const forkStart = railDrawStart + Math.max(0, forkRowIndex) * hopInterval;
    for (const path of group.querySelectorAll<SVGPathElement>("[data-route]")) {
      paintPathFromStart(timeline, path, forkStart, hopDuration);
    }
  }

  const branchStart = railDrawStart + (hopCount - 1) * hopInterval;
  const branchGroup = branchPath.closest<SVGGElement>('[data-route-anchor="hero"]');
  if (branchGroup === null) throw new Error("Hero attach route group is missing");
  for (const path of branchGroup.querySelectorAll<SVGPathElement>("[data-route]")) {
    paintPathFromStart(timeline, path, branchStart, hopDuration);
  }
  timeline.to(
    artwork,
    {
      clipPath: clipAtY(artwork, branchEndY + 2),
      duration: hopDuration,
      ease: "power2.inOut",
    },
    branchStart,
  );
}

/** Playback completion returns every rail mark to its scroll-reveal owner. */
export function clearHeroRailStaircase(artwork: SVGSVGElement): void {
  for (const path of artwork.querySelectorAll<SVGPathElement>("[data-hero-intro-rail-path]")) {
    path.style.removeProperty("stroke-dasharray");
    path.style.removeProperty("stroke-dashoffset");
    path.removeAttribute("data-hero-intro-rail-path");
  }
  for (const node of artwork.querySelectorAll<SVGGElement>("[data-hero-intro-rail-node]")) {
    node.style.removeProperty("opacity");
    node.style.removeProperty("transform");
    node.removeAttribute("transform");
    node.removeAttribute("data-hero-intro-rail-node");
  }
}
