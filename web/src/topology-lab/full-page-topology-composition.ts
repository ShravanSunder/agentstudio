// Composes the page topology from measured page hooks: the mainline on the
// left with one dot per row, worktree lanes in the gutter columns between the
// mainline and the content, and one short branch into each chapter target.
//
// Rules:
// - Every fork and merge moves exactly one column (one column × one row bend).
// - A cramped gutter (no room for a lane column) draws only the mainline.
// - A branch into a target forks one row above the attach edge from the column
//   next to that target and steps one column in; it never runs beside copy.
// - Worktree lanes open below the first anchor's copy and close after the last
//   target, so they never run beside text.
//
// Relative imports keep this module loadable by Vitest, which has no "@/" alias.
import {
  assignTopologyRowOwners,
  measureTopologyGutterColumns,
  measureTopologyRows,
  type TopologyRowWorktree,
} from "./full-page-topology-model";
import {
  attachXFor,
  planAttachRoutes,
  topologyStackedDropCornerInset,
} from "./topology-attach-geometry";
import { topologyEndY, topologyRectBottom, topologyRectCenterY } from "./topology-end-geometry";
import {
  heroLaneOpenRow,
  mainlineOwnerId,
  planWorktreeLanes,
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
  readonly rect: TopologyRect;
  /** `data-rail-surface-target`: wide and laptop branches enter its left edge. */
  readonly surface: TopologyRect | undefined;
  /** `data-rail-media-target`: the stage inside the glass. */
  readonly media: TopologyRect | undefined;
  /** `data-rail-step-pill-target`: multi-step chapters attach here. */
  readonly stepPill?: TopologyRect | undefined;
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
  /**
   * Where the rail ends (the final call to action). Without it, the topology
   * runs to one row above the page end.
   */
  readonly end?: TopologyEndMeasurement;
}

export interface TopologyEndMeasurement {
  /** `data-rail-end-section`: CTA section used when either midpoint input is unavailable. */
  readonly section: TopologyRect;
  /** `data-rail-end-mark`: the CTA icon. */
  readonly mark: TopologyRect | undefined;
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
  const contentX = Math.min(
    ...page.anchors.map((anchor) =>
      anchor.stepPill === undefined
        ? (attachXFor(anchor, stacked) ?? anchor.rect.left)
        : stacked
          ? (anchor.surface?.left ?? anchor.rect.left) + topologyStackedDropCornerInset
          : (anchor.surface?.left ?? anchor.rect.left),
    ),
  );
  const { rowYs, anchorRows } = measureTopologyRows({
    anchorYs: page.anchors.map((anchor) => anchor.lineY ?? topologyRectCenterY(anchor.rect)),
    forcedYs: stacked
      ? []
      : page.anchors.flatMap((anchor) =>
          anchor.stepPill === undefined ? [] : [topologyRectCenterY(anchor.stepPill)],
        ),
    endY: topologyEndY(page),
  });
  const finalRow = rowYs.length - 1;
  const firstAnchor = page.anchors[0];
  const targetBottoms = page.anchors.flatMap((anchor) =>
    anchor.surface === undefined ? [] : [topologyRectBottom(anchor.surface)],
  );

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
      closeBelowY: Math.max(...targetBottoms, 0),
      lastUsableRow: finalRow - 1,
    });
    if (lanePlan !== undefined || columns.laneXs.length === 0) {
      break;
    }
    columns = measureTopologyGutterColumns({
      attachX: contentX,
      viewportWidth: page.viewportWidth,
      maximumLaneCount: columns.laneXs.length - 1,
    });
  }
  const lanes = lanePlan?.lanes ?? [];
  const outermostLane = lanes.at(-1);

  const reserved = new Map<number, Omit<TopologyRowDot, "row" | "y">>();
  for (const [index, anchor] of page.anchors.entries()) {
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
    if (!reserved.has(row)) {
      reserved.set(row, dot);
    }
  }
  if (!reserved.has(finalRow)) {
    reserved.set(finalRow, {
      x: columns.mainlineX,
      ownerId: mainlineOwnerId,
      accent: "main",
      kind: "end",
      anchorId: undefined,
    });
  }

  const attachRoutes = planAttachRoutes({
    page,
    stacked,
    rowYs,
    anchorRows,
    reserved,
    mainlineX: columns.mainlineX,
    outermostLane,
  });

  const worktrees: TopologyRowWorktree[] = lanes.map((lane) => ({
    endRow: lane.mergeRow,
    id: lane.id,
    priority: lane.column,
    startRow: lane.forkRow,
  }));
  const owners = assignTopologyRowOwners({
    reservedRows: new Set(reserved.keys()),
    rowCount: rowYs.length,
    worktrees,
  });
  const ownerByRow = new Map(owners.map((owner) => [owner.row, owner.ownerId]));
  const laneById = new Map(lanes.map((lane) => [lane.id, lane]));
  const rows = rowYs.map((y, row): TopologyRowDot => {
    const reservedDot = reserved.get(row);
    if (reservedDot !== undefined) {
      return { row, y, ...reservedDot };
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
        }
      : {
          row,
          y,
          x: lane.x,
          ownerId: lane.id,
          accent: lane.accent,
          kind: "commit",
          anchorId: undefined,
        };
  });

  const worktreeRoutes = lanes.map((lane): TopologyRoute => ({
    id: lane.id,
    kind: "worktree",
    accent: lane.accent,
    pathData: worktreePath(lane, rowYs),
    parentColumn: lane.column - 1,
    column: lane.column,
    startY: rowYs[lane.forkRow] ?? 0,
    endY: rowYs[lane.mergeRow] ?? 0,
    anchorId: undefined,
    targetEdge: undefined,
    targetPoint: undefined,
    sourceAccent: undefined,
  }));

  return {
    columnUnit: columns.columnUnit,
    mainlineX: columns.mainlineX,
    laneXs: lanes.map((lane) => lane.x),
    rowYs,
    rows,
    routes: [...worktreeRoutes, ...attachRoutes],
    mainlinePath: `M ${columns.mainlineX} 0 L ${columns.mainlineX} ${rowYs.at(-1) ?? 0}`,
  };
}
