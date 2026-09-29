import type { SceneTimeline } from "../motion-scenes/scene-contract";
import { layoutFullPageTopology } from "../topology-lab/full-page-topology-layout";

const defaultRailDrawStart = 5.95;
const maximumDrawDuration = 1.6;
const preferredHopDuration = 0.1;
const preferredHoldDuration = 0.09;
const minimumHoldDuration = 0.05;
const dotPopDuration = 0.18;

interface RailHop {
  readonly start: number;
  readonly arrival: number;
  readonly drawDuration: number;
  readonly forkStart: number;
}

interface RailHopSchedule {
  readonly start: number;
  readonly end: number;
  readonly hops: readonly RailHop[];
}

export interface HeroRailDrawTiming {
  readonly finalHopStart: number;
  readonly end: number;
}

export function planHeroRailStaircase(
  hopCount: number,
  railDrawStart = defaultRailDrawStart,
): RailHopSchedule {
  if (!Number.isInteger(hopCount) || hopCount < 2)
    throw new Error("Hero rail staircase requires at least two hops");
  const holdCount = hopCount - 1;
  const drawDuration = Math.min(
    preferredHopDuration,
    (maximumDrawDuration - holdCount * minimumHoldDuration) / hopCount,
  );
  const holdDuration = Math.min(
    preferredHoldDuration,
    (maximumDrawDuration - hopCount * drawDuration) / holdCount,
  );
  const hops = Array.from({ length: hopCount }, (_, index): RailHop => {
    const start = railDrawStart + index * (drawDuration + holdDuration);
    const arrival = start + drawDuration;
    const dotArrival = index === 0 ? railDrawStart : start - holdDuration;
    return { start, arrival, drawDuration, forkStart: dotArrival + dotPopDuration + 0.06 };
  });
  return { start: railDrawStart, end: hops.at(-1)?.arrival ?? railDrawStart, hops };
}

interface RailDrawOptions {
  readonly timeline: SceneTimeline;
  readonly artwork: SVGSVGElement;
  readonly start?: number;
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

function nodeCircleOrigin(node: SVGGElement): string {
  // Topology can relayout after scene construction; resolve at tween render time.
  const circle = node.querySelector<SVGCircleElement>("circle");
  if (circle === null) throw new Error("Hero rail node circle is missing");
  return `${Number(circle.getAttribute("cx"))} ${Number(circle.getAttribute("cy"))}`;
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
  timeline.to(path, { strokeDashoffset: 0, duration, ease: "power2.out" }, start);
}

/** Reveal existing rail geometry a row at a time; the hero attach is the last hop. */
export function addHeroRailStaircase({
  timeline,
  artwork,
  start = defaultRailDrawStart,
}: RailDrawOptions): HeroRailDrawTiming {
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
    timeline.set(node, { opacity: 0, scale: 0.4, svgOrigin: () => nodeCircleOrigin(node) }, 0);
  }
  if (rows.length < 2) throw new Error("Hero rail staircase needs distinct rows");

  const schedule = planHeroRailStaircase(rows.length, start);
  timeline.addLabel("rail:start", start);
  timeline.addLabel("rail:end", schedule.end);
  timeline.set(artwork, { clipPath: "inset(0 0 100% 0)" }, 0);
  timeline.set(artwork, { clipPath: clipAtY(artwork, rows[0]?.y ?? heroY) }, start);

  for (const [rowIndex, row] of rows.entries()) {
    const hop = schedule.hops[rowIndex];
    if (hop === undefined) throw new Error("Hero rail staircase hop is missing");
    const popStart = rowIndex === 0 ? start : (schedule.hops[rowIndex - 1]?.arrival ?? start);
    for (const node of row.nodes) {
      timeline.fromTo(
        node,
        { opacity: 0, scale: 0.4, svgOrigin: () => nodeCircleOrigin(node) },
        {
          opacity: 1,
          scale: 1.15,
          svgOrigin: () => nodeCircleOrigin(node),
          duration: 0.12,
          ease: "back.out(2.4)",
        },
        popStart,
      );
      timeline.to(
        node,
        { scale: 1, svgOrigin: () => nodeCircleOrigin(node), duration: 0.06, ease: "power2.out" },
        popStart + 0.12,
      );
    }
    timeline.set(row.nodes, { clearProps: "transform" }, popStart + 0.2);
    // GSAP also writes SVG transform/origin attributes. A direct seek must leave
    // the finished node at its exact lane coordinate, even after relayout.
    timeline.call(
      () => {
        for (const node of row.nodes) {
          node.style.removeProperty("transform");
          node.removeAttribute("transform");
          node.removeAttribute("data-svg-origin");
        }
      },
      [],
      popStart + 0.2,
    );
    if (rowIndex + 1 < rows.length) {
      const nextY = rows[rowIndex + 1]?.y;
      if (nextY === undefined) throw new Error("Hero rail staircase row is missing");
      timeline.to(
        artwork,
        {
          clipPath: clipAtY(artwork, nextY),
          duration: hop.drawDuration,
          ease: "power2.out",
        },
        hop.start,
      );
    }
  }

  for (const group of artwork.querySelectorAll<SVGGElement>('[data-route-kind="worktree"]')) {
    const core = group.querySelector<SVGPathElement>('[data-topology-path-role="core"]');
    if (core === null || core.getTotalLength() <= 0) continue;
    const forkY = core.getPointAtLength(0).y;
    if (forkY < heroY - 0.5 || forkY > branchStartY + 0.5) continue;
    const forkRowIndex = rows.findLastIndex((row) => row.y <= forkY + 0.5);
    const forkStart = schedule.hops[Math.max(0, forkRowIndex)]?.forkStart;
    if (forkStart === undefined) throw new Error("Hero rail fork row is missing");
    for (const path of group.querySelectorAll<SVGPathElement>("[data-route]")) {
      paintPathFromStart(timeline, path, forkStart, preferredHopDuration);
    }
  }

  const finalHop = schedule.hops.at(-1);
  if (finalHop === undefined) throw new Error("Hero rail final hop is missing");
  const branchStart = finalHop.start;
  const branchGroup = branchPath.closest<SVGGElement>('[data-route-anchor="hero"]');
  if (branchGroup === null) throw new Error("Hero attach route group is missing");
  for (const path of branchGroup.querySelectorAll<SVGPathElement>("[data-route]")) {
    paintPathFromStart(timeline, path, branchStart, finalHop.drawDuration);
  }
  timeline.to(
    artwork,
    {
      clipPath: clipAtY(artwork, branchEndY + 2),
      duration: finalHop.drawDuration,
      ease: "power2.out",
    },
    branchStart,
  );
  return { finalHopStart: branchStart, end: schedule.end };
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
    node.removeAttribute("data-svg-origin");
    node.removeAttribute("data-hero-intro-rail-node");
  }
}
