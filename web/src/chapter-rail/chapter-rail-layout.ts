// Pure geometry for the left chapter rail: one vertical git lane, one dot per
// rail anchor, and one branch per dot into that anchor's glass. It reads
// measured rectangles and never decides page layout.
//
// Git language (from the retired full-page topology): vertical lanes, every
// turn a quarter-radius elbow, no other curves, plain dots with no tip icons.

/** A measured element rectangle in the rail's own coordinate space (CSS px). */
export interface RailRect {
  readonly left: number;
  readonly top: number;
  readonly width: number;
  readonly height: number;
}

export interface RailPoint {
  readonly x: number;
  readonly y: number;
}

/** One `data-rail-anchor` element, in document order. */
export interface RailAnchorMeasurement {
  readonly id: string;
  readonly rect: RailRect;
}

export interface ChapterRailLayoutProps {
  readonly viewportWidth: number;
  readonly pageHeight: number;
  readonly anchors: readonly RailAnchorMeasurement[];
  /** `data-rail-surface-target` rectangles keyed by the anchor id they serve. */
  readonly surfaceTargets: ReadonlyMap<string, RailRect>;
  /** `data-rail-media-target` rectangles keyed by the anchor id they serve. */
  readonly mediaTargets: ReadonlyMap<string, RailRect>;
}

/** Which target edge a branch lands on: wide and laptop join the glass's left edge; phone drops into the media's top edge. */
export type RailBranchTargetEdge = "left" | "top";

export interface ChapterRailBranchLayout {
  readonly targetEdge: RailBranchTargetEdge;
  readonly pathData: string;
  readonly end: RailPoint;
}

export interface ChapterRailNodeLayout {
  readonly anchorId: string;
  readonly x: number;
  readonly y: number;
  readonly branch: ChapterRailBranchLayout | undefined;
}

export type ChapterRailLayout =
  | { readonly kind: "empty" }
  | {
      readonly kind: "drawn";
      readonly railX: number;
      readonly lanePath: string;
      readonly nodes: readonly ChapterRailNodeLayout[];
    };

export type RailNodeState = "passed" | "current" | "upcoming";

/**
 * Viewports narrower than this use the phone branch. Mirrors
 * `--breakpoint-phone: 38.75rem` in `src/styles/global.css` (Tailwind's
 * `max-phone:` is `width < 38.75rem`); a unit test keeps the two in step.
 */
export const chapterRailPhoneBreakpointWidth = 620;

/** Radius of every git elbow. Shorter segments shrink it so turns never overshoot. */
export const railElbowRadius = 12;

/** The rail begins this far above the first dot, so it reads as starting under the nav logo. */
export const railLeadIn = 96;

/** The rail never sits closer than this to the page's left edge, so a whole dot stays visible. */
export const minimumRailX = 8;

/**
 * Wide and laptop: when a glass starts below its dot (the hero frame under its
 * eyebrow), the branch enters the glass's left edge this far below its top.
 */
export const wideBranchEntryInset = 40;

/**
 * Branches land at least this far from a target's corner, which clears the
 * site's largest corner radius (`--radius-floating-shell: 24px`). Phone: the
 * branch drops in line with the chapter's text column (the rail anchor's left
 * edge), clamped at least this far inside the media glass's left edge. Wide:
 * a dot this far inside its glass's top and bottom joins it straight across.
 */
export const railTargetCornerInset = 24;

/** The fraction of the viewport height whose line decides the current chapter. */
export const railReadingLineRatio = 0.4;

function roundCoordinate(value: number): number {
  return Math.round(value * 100) / 100;
}

function clamp(value: number, minimum: number, maximum: number): number {
  return Math.min(Math.max(value, minimum), maximum);
}

function samePoint(first: RailPoint, second: RailPoint): boolean {
  return Math.abs(first.x - second.x) < 0.01 && Math.abs(first.y - second.y) < 0.01;
}

/**
 * Builds an orthogonal path through `points`, rounding each turn with a
 * quarter-circle elbow. End segments give their whole length to the one turn
 * they touch; shared segments give each turn half.
 */
export function roundedOrthogonalPath(points: readonly RailPoint[], radius: number): string {
  const distinctPoints = points.filter(
    (point, index) => index === 0 || !samePoint(point, points[index - 1] ?? point),
  );
  const [start, ...rest] = distinctPoints;
  if (start === undefined || rest.length === 0) {
    return "";
  }
  const commands = [`M ${roundCoordinate(start.x)} ${roundCoordinate(start.y)}`];
  const lastIndex = distinctPoints.length - 1;
  for (let index = 1; index < lastIndex; index += 1) {
    const previous = distinctPoints[index - 1];
    const corner = distinctPoints[index];
    const next = distinctPoints[index + 1];
    if (previous === undefined || corner === undefined || next === undefined) {
      continue;
    }
    const incomingX = corner.x - previous.x;
    const incomingY = corner.y - previous.y;
    const outgoingX = next.x - corner.x;
    const outgoingY = next.y - corner.y;
    const incomingLength = Math.hypot(incomingX, incomingY);
    const outgoingLength = Math.hypot(outgoingX, outgoingY);
    const turn = incomingX * outgoingY - incomingY * outgoingX;
    if (Math.abs(turn) < 0.01) {
      continue;
    }
    const elbowRadius = Math.min(
      radius,
      index === 1 ? incomingLength : incomingLength / 2,
      index + 1 === lastIndex ? outgoingLength : outgoingLength / 2,
    );
    const elbowStart = {
      x: corner.x - (incomingX / incomingLength) * elbowRadius,
      y: corner.y - (incomingY / incomingLength) * elbowRadius,
    };
    const elbowEnd = {
      x: corner.x + (outgoingX / outgoingLength) * elbowRadius,
      y: corner.y + (outgoingY / outgoingLength) * elbowRadius,
    };
    const sweep = turn > 0 ? 1 : 0;
    commands.push(
      `L ${roundCoordinate(elbowStart.x)} ${roundCoordinate(elbowStart.y)}`,
      `A ${roundCoordinate(elbowRadius)} ${roundCoordinate(elbowRadius)} 0 0 ${sweep} ${roundCoordinate(elbowEnd.x)} ${roundCoordinate(elbowEnd.y)}`,
    );
  }
  const end = distinctPoints[lastIndex] ?? start;
  commands.push(`L ${roundCoordinate(end.x)} ${roundCoordinate(end.y)}`);
  return commands.join(" ");
}

function branchFromPoints(
  targetEdge: RailBranchTargetEdge,
  points: readonly RailPoint[],
): ChapterRailBranchLayout | undefined {
  const end = points.at(-1);
  if (end === undefined) {
    return undefined;
  }
  return {
    targetEdge,
    pathData: roundedOrthogonalPath(points, railElbowRadius),
    end: { x: roundCoordinate(end.x), y: roundCoordinate(end.y) },
  };
}

/**
 * Wide and laptop: join the glass's left edge. A glass that spans the dot's
 * height gets a straight branch at the dot's y; a glass below the dot gets a
 * git fork: out of the dot, down a parallel lane, and into the left edge.
 */
function layoutWideBranch(node: RailPoint, surface: RailRect): ChapterRailBranchLayout | undefined {
  if (surface.left <= node.x) {
    return undefined;
  }
  const surfaceBottom = surface.top + surface.height;
  const spansDot =
    node.y >= surface.top + railTargetCornerInset &&
    node.y <= surfaceBottom - railTargetCornerInset;
  if (spansDot) {
    return branchFromPoints("left", [node, { x: surface.left, y: node.y }]);
  }
  const entryInset = Math.min(wideBranchEntryInset, surface.height / 2);
  const entryY = clamp(node.y, surface.top + entryInset, surfaceBottom - entryInset);
  const parallelLaneX = node.x + (surface.left - node.x) / 2;
  return branchFromPoints("left", [
    node,
    { x: parallelLaneX, y: node.y },
    { x: parallelLaneX, y: entryY },
    { x: surface.left, y: entryY },
  ]);
}

/**
 * Phone: run right from the dot, take one git elbow, and drop into the media
 * glass's top edge in line with the chapter's text column, clear of its
 * rounded corner.
 */
function layoutPhoneBranch(
  node: RailPoint,
  anchor: RailRect,
  media: RailRect,
): ChapterRailBranchLayout | undefined {
  if (media.top <= node.y) {
    return undefined;
  }
  const mediaRight = media.left + media.width;
  const dropX =
    media.width > railTargetCornerInset * 2
      ? clamp(anchor.left, media.left + railTargetCornerInset, mediaRight - railTargetCornerInset)
      : media.left + media.width / 2;
  if (dropX <= node.x) {
    return undefined;
  }
  return branchFromPoints("top", [node, { x: dropX, y: node.y }, { x: dropX, y: media.top }]);
}

/**
 * The rail sits centered in the left gutter: halfway between the page's left
 * edge and the leftmost anchor or target it serves.
 */
function railXForGutter(props: ChapterRailLayoutProps): number {
  const contentLefts = [
    ...props.anchors.map((anchor) => anchor.rect.left),
    ...props.anchors.flatMap((anchor) => {
      const surface = props.surfaceTargets.get(anchor.id);
      const media = props.mediaTargets.get(anchor.id);
      return [surface?.left, media?.left].filter((left) => left !== undefined);
    }),
  ];
  return roundCoordinate(Math.max(minimumRailX, Math.min(...contentLefts) / 2));
}

export function layoutChapterRail(props: ChapterRailLayoutProps): ChapterRailLayout {
  if (props.anchors.length === 0) {
    return { kind: "empty" };
  }
  const railX = railXForGutter(props);
  const phoneLayout = props.viewportWidth < chapterRailPhoneBreakpointWidth;
  const nodes = props.anchors.map((anchor): ChapterRailNodeLayout => {
    const node = { x: railX, y: roundCoordinate(anchor.rect.top + anchor.rect.height / 2) };
    const surface = props.surfaceTargets.get(anchor.id);
    const media = props.mediaTargets.get(anchor.id);
    let branch: ChapterRailBranchLayout | undefined;
    if (phoneLayout) {
      branch = media === undefined ? undefined : layoutPhoneBranch(node, anchor.rect, media);
    } else {
      branch = surface === undefined ? undefined : layoutWideBranch(node, surface);
    }
    return { anchorId: anchor.id, ...node, branch };
  });
  const firstY = nodes[0]?.y ?? 0;
  const lastY = nodes.at(-1)?.y ?? firstY;
  const laneTop = Math.max(0, firstY - railLeadIn);
  const laneBottom = Math.min(props.pageHeight, lastY);
  return {
    kind: "drawn",
    railX,
    lanePath: `M ${railX} ${roundCoordinate(laneTop)} L ${railX} ${roundCoordinate(laneBottom)}`,
    nodes,
  };
}

/**
 * The current node is the last one at or above the reading line (40% down the
 * viewport, expressed in rail coordinates). Before the first anchor reaches
 * that line there is no current node.
 */
export function selectCurrentRailNodeIndex(
  nodeYs: readonly number[],
  readingLineY: number,
): number | undefined {
  let currentIndex: number | undefined;
  for (const [index, nodeY] of nodeYs.entries()) {
    if (nodeY > readingLineY) {
      break;
    }
    currentIndex = index;
  }
  return currentIndex;
}

export function railNodeStateAt(index: number, currentIndex: number | undefined): RailNodeState {
  if (currentIndex === undefined || index > currentIndex) {
    return "upcoming";
  }
  return index === currentIndex ? "current" : "passed";
}
