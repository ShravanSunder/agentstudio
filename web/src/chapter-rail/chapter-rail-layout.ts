// Pure geometry for the left chapter rail: a git-graph grid in the left gutter.
// The main lane (column 0) carries chapter progress; worktree lanes sit in
// their own columns. Every row has exactly one dot, owned by one lane, and
// every chapter anchor is a row. Each anchor's branch joins its glass. The
// module reads measured rectangles and never decides page layout.
//
// Grid rules: chapter-rail-grid.ts. Corner shape: chapter-rail-bend-path.ts.

import {
  railBendPath,
  railBendSpan,
  roundRailCoordinate,
  type RailPoint,
} from "./chapter-rail-bend-path";
import {
  assignRailRowOwners,
  layoutRailColumns,
  layoutRailRows,
  mainRailLaneId,
  minimumWideRailColumnSpacing,
  phoneRailColumnCount,
  phoneRailRowUnit,
  railRowPitchAt,
  railRowUnit,
  wideRailColumnCount,
  type RailWorktreeRowClaim,
} from "./chapter-rail-grid";

export type { RailPoint } from "./chapter-rail-bend-path";

/** A measured element rectangle in the rail's own coordinate space (CSS px). */
export interface RailRect {
  readonly left: number;
  readonly top: number;
  readonly width: number;
  readonly height: number;
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
  /**
   * Each anchor's copy block: the eyebrow, title and any copy between the
   * anchor and its media target, keyed by anchor id. Phone branches turn below
   * it. A missing entry falls back to the anchor's own rectangle.
   */
  readonly copyBlocks: ReadonlyMap<string, RailRect>;
}

/** Which target edge a branch lands on: wide and laptop join the glass's left edge; phone drops into the media's top edge. */
export type RailBranchTargetEdge = "left" | "top";

/**
 * A lane's color. Chapter progress and chapter branches use `main`; the
 * worktree lanes that fork into a separate frame (the hero's app frame) use
 * the parallel-work accents, peach first, then cyan.
 */
export type RailLaneAccent = "main" | "peach" | "cyan";

export interface ChapterRailBranchLayout {
  readonly anchorId: string;
  readonly accent: RailLaneAccent;
  readonly targetEdge: RailBranchTargetEdge;
  readonly pathData: string;
  readonly end: RailPoint;
}

/** One row's single dot. `anchorId` marks a chapter dot on the main lane. */
export interface ChapterRailRowDot {
  readonly rowIndex: number;
  readonly x: number;
  readonly y: number;
  readonly accent: RailLaneAccent;
  readonly anchorId: string | undefined;
}

export interface ChapterRailAnchorNode {
  readonly anchorId: string;
  readonly rowIndex: number;
  readonly x: number;
  readonly y: number;
}

export type ChapterRailLayout =
  | { readonly kind: "empty" }
  | {
      readonly kind: "drawn";
      readonly railX: number;
      readonly columnXs: readonly number[];
      readonly rowUnit: number;
      readonly lanePath: string;
      readonly rows: readonly ChapterRailRowDot[];
      readonly anchorNodes: readonly ChapterRailAnchorNode[];
      readonly branches: readonly ChapterRailBranchLayout[];
    };

export type RailNodeState = "passed" | "current" | "upcoming";

/**
 * Viewports narrower than this use the phone branch. Mirrors
 * `--breakpoint-phone: 38.75rem` in `src/styles/global.css` (Tailwind's
 * `max-phone:` is `width < 38.75rem`); a unit test keeps the two in step.
 */
export const chapterRailPhoneBreakpointWidth = 620;

/** The main lane begins this far above the first dot, so it reads as starting under the nav logo. */
export const railLeadIn = 96;

/** Phone lanes never sit closer than this; the phone gutter always holds two. */
const minimumPhoneRailColumnSpacing = 16;

/**
 * Wide and laptop: a worktree lane enters its frame's left edge on a row at
 * least this far inside the frame's top and bottom.
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

const worktreeAccents = ["peach", "cyan"] as const satisfies readonly RailLaneAccent[];

function clamp(value: number, minimum: number, maximum: number): number {
  return Math.min(Math.max(value, minimum), maximum);
}

function bottomOf(rect: RailRect): number {
  return rect.top + rect.height;
}

/** A worktree lane that can carry commit dots on the rows where it runs straight. */
interface RailWorktreeLane {
  readonly laneId: string;
  readonly x: number;
  readonly accent: RailLaneAccent;
  readonly straightTop: number;
  readonly straightBottom: number;
}

interface AnchorRoutes {
  readonly branches: readonly ChapterRailBranchLayout[];
  readonly lanes: readonly RailWorktreeLane[];
  /** Rows this anchor's routes reserve, with the dot each shows. */
  readonly reservedDots: ReadonlyMap<number, Omit<ChapterRailRowDot, "rowIndex" | "y">>;
}

interface RailGrid {
  readonly rowYs: readonly number[];
  readonly rowUnit: number;
  readonly mainX: number;
  readonly worktreeXs: readonly number[];
}

const noRoutes: AnchorRoutes = { branches: [], lanes: [], reservedDots: new Map() };

/**
 * Wide and laptop, glass beside its dot: one straight branch at the dot's row
 * into the glass's left edge.
 */
function straightBranch(anchorId: string, dot: RailPoint, surface: RailRect): AnchorRoutes {
  return {
    branches: [
      {
        anchorId,
        accent: "main",
        targetEdge: "left",
        pathData: railBendPath([dot, { x: surface.left, y: dot.y }], railRowUnit),
        end: { x: roundRailCoordinate(surface.left), y: dot.y },
      },
    ],
    lanes: [],
    reservedDots: new Map(),
  };
}

/**
 * Wide and laptop, frame below its dot (the hero): worktree lanes fork from
 * the main lane on consecutive rows starting at the anchor row, outermost
 * column first, run down their columns, and enter the frame's left edge on
 * consecutive rows inside it, in the same order. Opening and closing in the
 * same order keeps every horizontal run clear of the other lanes. Each fork
 * bends from one row to the next and each entry from the row above, like the
 * old topology. Without a free worktree column the branch uses a lane midway
 * to the frame that carries no dots.
 */
function worktreeEntryRoutes(props: {
  readonly anchorId: string;
  readonly anchorRowIndex: number;
  readonly nextAnchorRowIndex: number;
  readonly surface: RailRect;
  readonly grid: RailGrid;
}): AnchorRoutes {
  const { anchorId, anchorRowIndex, nextAnchorRowIndex, surface, grid } = props;
  const bandTop = surface.top + Math.min(wideBranchEntryInset, surface.height / 2);
  const bandBottom = bottomOf(surface) - Math.min(wideBranchEntryInset, surface.height / 2);
  const laneXs = grid.worktreeXs.toReversed().filter((x) => x < surface.left);
  const branches: ChapterRailBranchLayout[] = [];
  const lanes: RailWorktreeLane[] = [];
  const reservedDots = new Map<number, Omit<ChapterRailRowDot, "rowIndex" | "y">>();
  let previousEntryRow = anchorRowIndex;
  const routeLanes =
    laneXs.length === 0
      ? [{ x: grid.mainX + (surface.left - grid.mainX) / 2, carriesDots: false }]
      : laneXs.map((x) => ({ x, carriesDots: true }));
  for (const [laneIndex, routeLane] of routeLanes.entries()) {
    const forkRow = anchorRowIndex + laneIndex;
    const entryRow = grid.rowYs.findIndex(
      (rowY, rowIndex) =>
        rowIndex >= Math.max(forkRow + 2, previousEntryRow + 1) &&
        rowIndex < nextAnchorRowIndex &&
        rowY >= bandTop &&
        rowY <= bandBottom,
    );
    const forkY = grid.rowYs[forkRow];
    const entryY = grid.rowYs[entryRow];
    if (
      forkRow >= nextAnchorRowIndex ||
      entryRow < 0 ||
      forkY === undefined ||
      entryY === undefined
    ) {
      break;
    }
    const accent: RailLaneAccent = routeLane.carriesDots
      ? (worktreeAccents[laneIndex] ?? "peach")
      : "main";
    const pitch = railRowPitchAt(grid.rowYs, forkRow, grid.rowUnit);
    branches.push({
      anchorId,
      accent,
      targetEdge: "left",
      pathData: railBendPath(
        [
          { x: grid.mainX, y: forkY },
          { x: routeLane.x, y: forkY },
          { x: routeLane.x, y: entryY },
          { x: surface.left, y: entryY },
        ],
        pitch,
      ),
      end: { x: roundRailCoordinate(surface.left), y: roundRailCoordinate(entryY) },
    });
    if (forkRow !== anchorRowIndex) {
      reservedDots.set(forkRow, { x: grid.mainX, accent: "main", anchorId: undefined });
    }
    reservedDots.set(entryRow, { x: grid.mainX, accent: "main", anchorId: undefined });
    if (routeLane.carriesDots) {
      const verticalSpan = Math.min(pitch, (entryY - forkY) / 2);
      lanes.push({
        laneId: `${anchorId}-${accent}`,
        x: routeLane.x,
        accent,
        straightTop: forkY + verticalSpan,
        straightBottom: entryY - verticalSpan,
      });
    }
    previousEntryRow = entryRow;
  }
  return { branches, lanes, reservedDots };
}

/**
 * Phone: the branch must never cross the chapter's copy, which sits beside the
 * rail. It forks out of the dot into the worktree column, runs down past the
 * copy block, turns right in the gap between the copy's bottom and the media
 * glass's top, and drops into that top edge in line with the text column,
 * clear of the glass's rounded corner.
 */
function phoneDropRoute(props: {
  readonly anchorId: string;
  readonly dot: RailPoint;
  readonly anchor: RailRect;
  readonly copyBlock: RailRect;
  readonly media: RailRect;
  readonly accent: RailLaneAccent;
  readonly grid: RailGrid;
}): AnchorRoutes {
  const { anchorId, dot, anchor, copyBlock, media, accent, grid } = props;
  if (media.top <= dot.y) {
    return noRoutes;
  }
  const mediaRight = media.left + media.width;
  const dropX =
    media.width > railTargetCornerInset * 2
      ? clamp(anchor.left, media.left + railTargetCornerInset, mediaRight - railTargetCornerInset)
      : media.left + media.width / 2;
  const textColumnLeft = Math.min(anchor.left, copyBlock.left);
  const laneX = grid.worktreeXs[0] ?? dot.x + Math.max(0, (textColumnLeft - dot.x) / 2);
  if (laneX >= textColumnLeft || dropX <= laneX) {
    return noRoutes;
  }
  // Turn in the middle of the gap. Copy that reaches the glass leaves no gap,
  // so the turn falls back to the glass's top edge.
  const gapTop = clamp(bottomOf(copyBlock), dot.y, media.top);
  const crossingY = gapTop + (media.top - gapTop) / 2;
  const verticalSpan = railBendSpan({
    runLength: crossingY - dot.y,
    sharedWithAnotherBend: true,
    vertical: true,
    verticalSpanLimit: grid.rowUnit,
  });
  return {
    branches: [
      {
        anchorId,
        accent,
        targetEdge: "top",
        pathData: railBendPath(
          [
            dot,
            { x: laneX, y: dot.y },
            { x: laneX, y: crossingY },
            { x: dropX, y: crossingY },
            { x: dropX, y: media.top },
          ],
          grid.rowUnit,
        ),
        end: { x: roundRailCoordinate(dropX), y: roundRailCoordinate(media.top) },
      },
    ],
    lanes:
      grid.worktreeXs[0] === undefined
        ? []
        : [
            {
              laneId: `${anchorId}-${accent}`,
              x: laneX,
              accent,
              straightTop: dot.y + verticalSpan,
              straightBottom: crossingY - verticalSpan,
            },
          ],
    reservedDots: new Map(),
  };
}

function gutterWidthFor(props: ChapterRailLayoutProps): number {
  const contentLefts = [
    ...props.anchors.map((anchor) => anchor.rect.left),
    ...props.anchors.flatMap((anchor) => {
      const surface = props.surfaceTargets.get(anchor.id);
      const media = props.mediaTargets.get(anchor.id);
      return [surface?.left, media?.left].filter((left) => left !== undefined);
    }),
  ];
  return Math.max(0, Math.min(...contentLefts));
}

export function layoutChapterRail(props: ChapterRailLayoutProps): ChapterRailLayout {
  if (props.anchors.length === 0) {
    return { kind: "empty" };
  }
  const phoneLayout = props.viewportWidth < chapterRailPhoneBreakpointWidth;
  const rowUnit = phoneLayout ? phoneRailRowUnit : railRowUnit;
  const columnXs = layoutRailColumns({
    gutterWidth: gutterWidthFor(props),
    maximumColumnCount: phoneLayout ? phoneRailColumnCount : wideRailColumnCount,
    minimumSpacing: phoneLayout ? minimumPhoneRailColumnSpacing : minimumWideRailColumnSpacing,
  }).map(roundRailCoordinate);
  const mainX = columnXs[0] ?? 0;
  const anchorYs = props.anchors.map((anchor) =>
    roundRailCoordinate(anchor.rect.top + anchor.rect.height / 2),
  );
  const { rowYs: rawRowYs, anchorRowIndexes } = layoutRailRows({
    anchorYs,
    pageEnd: props.pageHeight - rowUnit,
    rowUnit,
  });
  const rowYs = rawRowYs.map(roundRailCoordinate);
  const grid: RailGrid = { rowYs, rowUnit, mainX, worktreeXs: columnXs.slice(1) };

  const anchorNodes = props.anchors.map((anchor, index): ChapterRailAnchorNode => {
    const rowIndex = anchorRowIndexes[index] ?? 0;
    return { anchorId: anchor.id, rowIndex, x: mainX, y: rowYs[rowIndex] ?? 0 };
  });
  const routes = props.anchors.map((anchor, index): AnchorRoutes => {
    const node = anchorNodes[index];
    const surface = props.surfaceTargets.get(anchor.id);
    const media = props.mediaTargets.get(anchor.id);
    if (node === undefined) {
      return noRoutes;
    }
    const dot = { x: node.x, y: node.y };
    const frameBelowDot = surface !== undefined && surface.top > dot.y;
    if (phoneLayout) {
      return media === undefined
        ? noRoutes
        : phoneDropRoute({
            anchorId: anchor.id,
            dot,
            anchor: anchor.rect,
            copyBlock: props.copyBlocks.get(anchor.id) ?? anchor.rect,
            media,
            accent: frameBelowDot ? "peach" : "main",
            grid,
          });
    }
    if (surface === undefined || surface.left <= dot.x) {
      return noRoutes;
    }
    const spansDot =
      dot.y >= surface.top + railTargetCornerInset &&
      dot.y <= bottomOf(surface) - railTargetCornerInset;
    if (spansDot) {
      return straightBranch(anchor.id, dot, surface);
    }
    return worktreeEntryRoutes({
      anchorId: anchor.id,
      anchorRowIndex: node.rowIndex,
      nextAnchorRowIndex: anchorNodes[index + 1]?.rowIndex ?? rowYs.length,
      surface,
      grid,
    });
  });

  const reservedDots = new Map<number, Omit<ChapterRailRowDot, "rowIndex" | "y">>();
  for (const node of anchorNodes) {
    reservedDots.set(node.rowIndex, { x: mainX, accent: "main", anchorId: node.anchorId });
  }
  for (const route of routes) {
    for (const [rowIndex, dot] of route.reservedDots) {
      if (!reservedDots.has(rowIndex)) {
        reservedDots.set(rowIndex, dot);
      }
    }
  }
  const lanes = routes.flatMap((route) => route.lanes);
  const worktreeClaims = lanes.map((lane, index): RailWorktreeRowClaim => ({
    laneId: lane.laneId,
    priority: lanes.length - index,
    eligibleRowIndexes: new Set(
      rowYs.flatMap((rowY, rowIndex) =>
        rowY >= lane.straightTop - 0.5 && rowY <= lane.straightBottom + 0.5 ? [rowIndex] : [],
      ),
    ),
  }));
  const owners = assignRailRowOwners({
    rowCount: rowYs.length,
    reservedRowOwners: new Map([...reservedDots.keys()].map((rowIndex) => [rowIndex, "reserved"])),
    worktreeClaims,
  });
  const laneById = new Map(lanes.map((lane) => [lane.laneId, lane]));
  const rows = rowYs.map((y, rowIndex): ChapterRailRowDot => {
    const reserved = reservedDots.get(rowIndex);
    if (reserved !== undefined) {
      return { rowIndex, y, ...reserved };
    }
    const lane = laneById.get(owners[rowIndex] ?? mainRailLaneId);
    return lane === undefined
      ? { rowIndex, y, x: mainX, accent: "main", anchorId: undefined }
      : { rowIndex, y, x: lane.x, accent: lane.accent, anchorId: undefined };
  });

  const firstY = rowYs[0] ?? 0;
  const lastY = rowYs.at(-1) ?? firstY;
  const laneTop = Math.max(0, firstY - railLeadIn);
  return {
    kind: "drawn",
    railX: mainX,
    columnXs,
    rowUnit,
    lanePath: `M ${mainX} ${roundRailCoordinate(laneTop)} L ${mainX} ${lastY}`,
    rows,
    anchorNodes,
    branches: routes.flatMap((route) => route.branches),
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
