// Composes the page topology from measured page hooks: the mainline on the
// left with one dot per row, worktree lanes in the gutter columns between the
// mainline and the content, and one short branch into each chapter target.
//
// Rules:
// - Every fork and merge moves exactly one column (one column × one row bend).
// - A cramped gutter (no room for a lane column) draws only the mainline.
// - A branch into a target forks one row above the attach edge from the column
//   next to that target and steps one column in; it never runs beside copy.
// - Worktree lanes open below the first anchor's copy; at the finale, outer
//   pairs merge and stop while the first side lane joins the trunk.
//
// Relative imports keep this module loadable by Vitest, which has no "@/" alias.
import {
  assignTopologyRowOwners,
  measureTopologyGutterColumns,
  measureTopologyRows,
  topologyRowUnit,
  type TopologyRowWorktree,
} from "./full-page-topology-model";
import {
  attachXFor,
  planAttachRoutes,
  topologyStackedDropCornerInset,
} from "./topology-attach-geometry";
import { topologyEndY, topologyRectCenterY } from "./topology-end-geometry";
import {
  heroLaneOpenRow,
  mainlineOwnerId,
  planWorktreeLanes,
  topologyHeroLaneMinimumTravel,
  worktreeVerticalEndPath,
  worktreePath,
  type LanePlan,
} from "./topology-lane-planning";

export {
  topologyAttachBandInset,
  topologyStackedDropCornerInset,
  topologyStackedVerticalEntry,
  topologyStackedForkCopyClearance,
  topologyStackedMinimumDrop,
  topologyStackedFallbackDrop,
} from "./topology-attach-geometry";
export {
  mainlineOwnerId,
  topologyHeroLaneMinimumTravel,
  topologyHeroLaneMaximumTravel,
} from "./topology-lane-planning";

/** A measured element rectangle in the artwork's coordinate space (CSS px). */
export interface TopologyRect {
  readonly left: number;
  readonly top: number;
  readonly width: number;
  readonly height: number;
}

export interface TopologyAnchorMeasurement {
  readonly id: string;
  /** Chapter anchors require a step-line target; generic anchors may still use a glass edge. */
  readonly chapter?: boolean;
  readonly rect: TopologyRect;
  /** `data-rail-surface-target`: wide and laptop branches enter its left edge. */
  readonly surface: TopologyRect | undefined;
  /** Surface-declared preferred edge on wide layouts; stacked layouts enter the top. */
  readonly targetEdge?: TopologyTargetEdge | undefined;
  /** A DOM-declared final target receives a branch with no endpoint dot. */
  readonly terminalTarget?: boolean;
  /** `data-rail-media-target`: the stage inside the glass. */
  readonly media: TopologyRect | undefined;
  /** `data-rail-step-line-target`: the line's start before its first dot. */
  readonly stepLine?: TopologyRect | undefined;
  /** The copy between the anchor and its media target; a hero phone branch turns below it. */
  readonly copyBlock: TopologyRect | undefined;
  /**
   * The vertical center of the anchor's first line of text: a wrapped chapter
   * title's marker sits level with its first line. Defaults to the rect's center.
   */
  readonly lineY?: number | undefined;
}

export interface TopologyPageMeasurement {
  readonly viewportWidth: number;
  readonly height: number;
  readonly anchors: readonly TopologyAnchorMeasurement[];
}

/**
 * A route's color. Lanes use the mainline or worktree colors; `port` is the
 * primary-blue connector that enters a target edge.
 */
export type TopologyAccent = "main" | "peach" | "cyan" | "port";
export type TopologyRouteKind = "worktree" | "attach";
export type TopologyTargetEdge = "left" | "top";

export interface TopologyRoute {
  readonly id: string;
  readonly kind: TopologyRouteKind;
  readonly accent: TopologyAccent;
  readonly pathData: string;
  /** Column the route leaves from and column it lives in (worktrees) or attaches at. */
  readonly parentColumn: number;
  readonly column: number;
  readonly startY: number;
  readonly endY: number;
  /** Attach branches only: the anchor whose target this branch enters. */
  readonly anchorId: string | undefined;
  readonly targetEdge: TopologyTargetEdge | undefined;
  /** Attach branches only: the path's last point on the target edge. */
  readonly targetPoint: { readonly x: number; readonly y: number } | undefined;
  /** Attach branches only: the accent of the lane the port leaves, where its gradient starts. */
  readonly sourceAccent: TopologyAccent | undefined;
  /** The reveal fires the final CTA event when this branch reaches its target. */
  readonly terminal?: boolean;
}

export type TopologyDotKind = "chapter" | "commit" | "fork" | "merge" | "end";

/** One row's single dot. */
export interface TopologyRowDot {
  readonly row: number;
  readonly x: number;
  readonly y: number;
  readonly ownerId: string;
  readonly accent: TopologyAccent;
  readonly kind: TopologyDotKind;
  readonly anchorId: string | undefined;
  /**
   * Merge dots only: the color of the lane merging in. `accent` is the lane
   * that receives the merge, which the dot sits on.
   */
  readonly incomingAccent?: TopologyAccent;
  /** A terminal merge also carries the final halo and one reveal pulse. */
  readonly terminal?: boolean;
  /** The step line owns this row's visible dot while the rail keeps one row record. */
  readonly suppressPaint?: boolean;
}

export interface TopologyComposition {
  readonly columnUnit: number;
  readonly mainlineX: number;
  readonly laneXs: readonly number[];
  readonly rowYs: readonly number[];
  readonly rows: readonly TopologyRowDot[];
  readonly routes: readonly TopologyRoute[];
  readonly mainlinePath: string;
}

/**
 * Below this width chapter glasses stack (title, stage, steps in one glass),
 * so branches drop into each glass's top edge; at and above it they enter the
 * glass's left edge. Tailwind's `lg` boundary (`--breakpoint-lg: 64rem`).
 */
export const topologyStackedLayoutBreakpointWidth = 1024;

export function composeFullPageTopology(
  page: TopologyPageMeasurement,
): TopologyComposition | undefined {
  if (page.anchors.length === 0) {
    return undefined;
  }
  const stacked = page.viewportWidth < topologyStackedLayoutBreakpointWidth;
  // The gutter stays aligned to the glass even when a pill projects further
  // into the chapter. Its attach path can extend past the nearest lane column.
  const chapterAnchors = page.anchors.filter((anchor) => !anchor.terminalTarget);
  const gutterAnchors = chapterAnchors.length > 0 ? chapterAnchors : page.anchors;
  const contentX = Math.min(
    ...gutterAnchors.map((anchor) =>
      anchor.stepLine === undefined
        ? (attachXFor(anchor, stacked) ?? anchor.rect.left)
        : stacked
          ? (anchor.surface?.left ?? anchor.rect.left) + topologyStackedDropCornerInset
          : (anchor.surface?.left ?? anchor.rect.left),
    ),
  );
  const terminalAnchor = page.anchors.find(
    (anchor) => anchor.terminalTarget && anchor.surface !== undefined,
  );
  const { rowYs, anchorRows } = measureTopologyRows({
    anchorYs: page.anchors.map((anchor) => anchor.lineY ?? topologyRectCenterY(anchor.rect)),
    forcedYs: [
      ...page.anchors.flatMap((anchor) =>
        anchor.stepLine === undefined
          ? []
          : stacked
            ? [
                topologyRectCenterY(anchor.stepLine) - topologyRowUnit,
                topologyRectCenterY(anchor.stepLine),
              ]
            : [topologyRectCenterY(anchor.stepLine)],
      ),
      ...(terminalAnchor?.surface === undefined ? [] : [terminalAnchor.surface.top + 2]),
    ],
    endY: topologyEndY(page),
  });
  const finalRow = rowYs.length - 1;
  const finalMainlineRow = terminalAnchor === undefined ? finalRow : Math.max(finalRow - 1, 0);
  const closingEndRow = terminalAnchor === undefined ? finalMainlineRow : finalMainlineRow - 1;
  const lastChapterGlass = page.anchors.filter((anchor) => !anchor.terminalTarget).at(-1)?.surface;
  const lastGlassBottom =
    lastChapterGlass === undefined ? 0 : lastChapterGlass.top + lastChapterGlass.height;
  const lastGlassRow = rowYs.findLastIndex((rowY) => rowY <= lastGlassBottom);
  const firstAnchor = page.anchors[0];

  // Fewer lanes when the page has too few rows to open and close them all.
  // Each retry lays the columns out again, so the mainline moves right and
  // every fork and merge still moves one column.
  let columns = measureTopologyGutterColumns({
    attachX: contentX,
    viewportWidth: page.viewportWidth,
  });
  let lanePlan: LanePlan | undefined;
  for (;;) {
    lanePlan = planWorktreeLanes({
      laneXs: columns.laneXs,
      mainlineX: columns.mainlineX,
      rowYs,
      openRow: heroLaneOpenRow({
        rowYs,
        heroRow: anchorRows[0] ?? 0,
        heroCopy: firstAnchor?.copyBlock ?? firstAnchor?.rect,
        heroTarget: firstAnchor?.surface,
        laneCount: columns.laneXs.length,
      }),
      endRow: closingEndRow,
      lastAttachRow: terminalAnchor === undefined ? (anchorRows.at(-1) ?? 0) : lastGlassRow,
      stepLineYs: page.anchors.flatMap((anchor) =>
        anchor.stepLine === undefined || anchor.surface === undefined
          ? []
          : [topologyRectCenterY(anchor.stepLine)],
      ),
    });
    const heroTop = firstAnchor?.surface?.top;
    const heroForkRow = heroTop === undefined ? -1 : rowYs.findLastIndex((rowY) => rowY < heroTop);
    const outerForkRow = lanePlan?.lanes.at(-1)?.forkRow;
    if (outerForkRow !== undefined && heroForkRow - outerForkRow < topologyHeroLaneMinimumTravel) {
      lanePlan = undefined;
    }
    if (lanePlan !== undefined || columns.laneXs.length === 0) {
      break;
    }
    columns = measureTopologyGutterColumns({
      attachX: contentX,
      viewportWidth: page.viewportWidth,
      maximumLaneCount: columns.laneXs.length - 1,
    });
  }
  const plannedLanes = lanePlan?.lanes ?? [];
  const terminalLaneId = terminalAnchor === undefined ? undefined : plannedLanes.at(-1)?.id;
  const sideLaneCount = terminalLaneId === undefined ? 0 : plannedLanes.length - 1;
  // L1 joins the trunk. Pair L2..Ln from the outside inward: each outer lane
  // joins its neighbour, which stops on the next row; an unpaired L2 stops.
  const stoppingLaneIds = new Set(
    plannedLanes
      .slice(0, sideLaneCount)
      .filter(
        (lane) =>
          lane.column >= 2 && (lane.column === 2 || (sideLaneCount - lane.column) % 2 === 1),
      )
      .map((lane) => lane.id),
  );
  const lanes = plannedLanes.map((lane) =>
    lane.id === terminalLaneId ? { ...lane, mergeRow: finalMainlineRow } : lane,
  );
  const outermostLane = lanes.at(-1);

  const reserved = new Map<number, Omit<TopologyRowDot, "row" | "y">>();
  for (const [index, anchor] of page.anchors.entries()) {
    if (anchor.terminalTarget) continue;
    const row = anchorRows[index];
    if (row !== undefined) {
      reserved.set(row, {
        x: columns.mainlineX,
        ownerId: mainlineOwnerId,
        accent: "main",
        kind: "chapter",
        anchorId: anchor.id,
      });
    }
  }
  for (const [row, dot] of lanePlan?.reserved ?? new Map()) {
    if (row === plannedLanes.at(-1)?.mergeRow && terminalLaneId !== undefined) continue;
    const stoppingLane = plannedLanes.find(
      (lane) => lane.mergeRow === row && stoppingLaneIds.has(lane.id),
    );
    if (!reserved.has(row))
      reserved.set(
        row,
        stoppingLane === undefined
          ? dot
          : {
              x: stoppingLane.x,
              ownerId: stoppingLane.id,
              accent: stoppingLane.accent,
              kind: "commit",
              anchorId: undefined,
            },
      );
  }
  if (!reserved.has(finalMainlineRow)) {
    reserved.set(finalMainlineRow, {
      x: outermostLane?.x ?? columns.mainlineX,
      ownerId: outermostLane?.id ?? mainlineOwnerId,
      accent: outermostLane?.accent ?? "main",
      kind: terminalAnchor === undefined ? "end" : "commit",
      anchorId: undefined,
      suppressPaint: terminalAnchor === undefined && outermostLane !== undefined,
    });
  }

  const attachRoutes = planAttachRoutes({
    page,
    stacked,
    rowYs,
    anchorRows,
    reserved,
    mainlineX: columns.mainlineX,
    terminalLane: outermostLane,
    outermostLane,
    columnUnit: columns.columnUnit,
    finalMainlineRow,
  });

  const worktrees: TopologyRowWorktree[] = lanes.map((lane) => ({
    endRow: lane.mergeRow,
    id: lane.id,
    priority: lane.column,
    startRow: lane.forkRow,
  }));
  const owners = assignTopologyRowOwners({
    reservedRows: new Set(reserved.keys()),
    rowCount: finalMainlineRow + 1,
    worktrees,
  });
  const ownerByRow = new Map(owners.map((owner) => [owner.row, owner.ownerId]));
  const laneById = new Map(lanes.map((lane) => [lane.id, lane]));
  const stepLineSpans = attachRoutes.flatMap((route) => {
    const anchor = page.anchors.find((candidate) => candidate.id === route.anchorId);
    return anchor?.stepLine === undefined
      ? []
      : [
          {
            x: columns.mainlineX + route.parentColumn * columns.columnUnit,
            startY: route.startY,
            endY: route.endY,
          },
        ];
  });
  const rows = rowYs.slice(0, finalMainlineRow + 1).map((y, row): TopologyRowDot => {
    const reservedDot = reserved.get(row);
    const suppressPaintFor = (x: number): boolean =>
      stepLineSpans.some(
        (span) => Math.abs(x - span.x) <= 0.5 && y > span.startY + 0.5 && y <= span.endY + 0.5,
      );
    if (reservedDot !== undefined) {
      return {
        row,
        y,
        ...reservedDot,
        suppressPaint: reservedDot.suppressPaint === true || suppressPaintFor(reservedDot.x),
      };
    }
    const lane = laneById.get(ownerByRow.get(row) ?? mainlineOwnerId);
    return lane === undefined
      ? {
          row,
          y,
          x: columns.mainlineX,
          ownerId: mainlineOwnerId,
          accent: "main",
          kind: "commit",
          anchorId: undefined,
          suppressPaint: suppressPaintFor(columns.mainlineX),
        }
      : {
          row,
          y,
          x: lane.x,
          ownerId: lane.id,
          accent: lane.accent,
          kind: "commit",
          anchorId: undefined,
          suppressPaint: suppressPaintFor(lane.x),
        };
  });

  const worktreeRoutes = lanes.map((lane): TopologyRoute => ({
    id: lane.id,
    kind: "worktree",
    accent: lane.accent,
    pathData:
      lane.id === terminalLaneId || stoppingLaneIds.has(lane.id)
        ? worktreeVerticalEndPath(lane, rowYs)
        : worktreePath(lane, rowYs),
    parentColumn: lane.column - 1,
    column: lane.column,
    startY: rowYs[lane.forkRow] ?? 0,
    endY: rowYs[lane.mergeRow] ?? 0,
    anchorId: undefined,
    targetEdge: undefined,
    targetPoint: undefined,
    sourceAccent: undefined,
  }));

  const mainlineEndY = rowYs[terminalLaneId === undefined ? finalMainlineRow : closingEndRow] ?? 0;
  const mainlinePath = `M ${columns.mainlineX} 0 L ${columns.mainlineX} ${mainlineEndY}`;

  return {
    columnUnit: columns.columnUnit,
    mainlineX: columns.mainlineX,
    laneXs: lanes.map((lane) => lane.x),
    rowYs,
    rows,
    routes: [...worktreeRoutes, ...attachRoutes],
    mainlinePath,
  };
}
