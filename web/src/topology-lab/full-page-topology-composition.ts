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
  topologyRowUnit,
  type TopologyRowWorktree,
} from "./full-page-topology-model";
import { localForkPath, localMergePath } from "./full-page-topology-paths";

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
  /** `data-rail-end-section`: nothing is drawn under or beside it, or below. */
  readonly section: TopologyRect;
  /** `data-rail-end`: the end node sits level with its center when the gutter has room. */
  readonly level: TopologyRect | undefined;
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
  /** Attach branches only: the port node exactly on the target edge. */
  readonly portNode: { readonly x: number; readonly y: number } | undefined;
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
/** A wide branch enters its glass on a row at least this far inside the glass. */
export const topologyAttachBandInset = 40;
/**
 * Stacked: the branch drops this far inside the glass's left edge: its
 * rounded corner (16px) plus a clear gap.
 */
export const topologyStackedDropCornerInset = 24;
/** Stacked: the drop ends in a straight vertical run this long into the glass's top edge. */
export const topologyStackedVerticalEntry = 8;
/**
 * Stacked: when the row above the glass sits inside the copy above it (the
 * hero), the branch forks this far below the copy instead.
 */
export const topologyStackedForkCopyClearance = 4;
/** Stacked: a row above the glass only hosts the fork when it leaves at least this much drop. */
export const topologyStackedMinimumDrop = 12;
/** Stacked: with no free row above a chapter's glass, the fork sits this far above its top edge. */
export const topologyStackedFallbackDrop = 32;
/**
 * The end sits beside the install command only when that command starts at
 * least this far right of the mainline; closer means the rail would run
 * beside or under the call to action.
 */
export const topologyEndContentClearance = 48;

/**
 * On wide screens the lane next to the content runs at least this many rows,
 * and at most `topologyHeroLaneMaximumTravel`, between its fork and the row it
 * leaves for the hero frame.
 */
export const topologyHeroLaneMinimumTravel = 2;
export const topologyHeroLaneMaximumTravel = 4;

export const mainlineOwnerId = "main";
const worktreeAccents = ["peach", "cyan"] as const satisfies readonly TopologyAccent[];

function bottomOf(rect: TopologyRect): number {
  return rect.top + rect.height;
}

function centerYOf(rect: TopologyRect): number {
  return rect.top + rect.height / 2;
}

/**
 * Where a branch lands: the glass's left edge on wide screens, the drop point
 * on its top edge, clear of the corner, where glasses stack.
 */
function attachXFor(anchor: TopologyAnchorMeasurement, stacked: boolean): number | undefined {
  const surface = anchor.surface;
  if (surface === undefined) {
    return undefined;
  }
  return stacked
    ? Math.min(surface.left + topologyStackedDropCornerInset, surface.left + surface.width / 2)
    : surface.left;
}

interface WorktreeLane {
  readonly id: string;
  readonly column: number;
  readonly x: number;
  readonly parentId: string;
  readonly parentX: number;
  readonly accent: TopologyAccent;
  readonly forkRow: number;
  readonly mergeRow: number;
}

interface LanePlan {
  readonly lanes: readonly WorktreeLane[];
  readonly reserved: ReadonlyMap<number, Omit<TopologyRowDot, "row" | "y">>;
}

/**
 * Worktree lanes open as a one-column staircase (lane k forks from lane k-1 on
 * consecutive rows) starting at `openRow`, in the gutter beside the hero copy,
 * and close the same way in reverse after the last target, so every fork and
 * merge moves one column.
 */
function planWorktreeLanes(props: {
  readonly laneXs: readonly number[];
  readonly mainlineX: number;
  readonly rowYs: readonly number[];
  readonly openRow: number;
  readonly closeBelowY: number;
  readonly lastUsableRow: number;
}): LanePlan | undefined {
  const laneCount = props.laneXs.length;
  if (laneCount === 0) {
    return { lanes: [], reserved: new Map() };
  }
  const openRow = props.openRow;
  const closeRow = props.rowYs.findIndex((rowY) => rowY >= props.closeBelowY);
  if (openRow < 0 || closeRow < 0 || closeRow + laneCount - 1 > props.lastUsableRow) {
    return undefined;
  }
  const lanes: WorktreeLane[] = [];
  const reserved = new Map<number, Omit<TopologyRowDot, "row" | "y">>();
  for (let laneIndex = 0; laneIndex < laneCount; laneIndex += 1) {
    const column = laneIndex + 1;
    const forkRow = openRow + laneIndex;
    const mergeRow = closeRow + (laneCount - 1 - laneIndex);
    if (mergeRow - forkRow < 2) {
      return undefined;
    }
    const parent = lanes[laneIndex - 1];
    const lane: WorktreeLane = {
      id: `worktree-${column}`,
      column,
      x: props.laneXs[laneIndex] ?? props.mainlineX,
      parentId: parent?.id ?? mainlineOwnerId,
      parentX: parent?.x ?? props.mainlineX,
      accent: worktreeAccents[laneIndex % worktreeAccents.length] ?? "peach",
      forkRow,
      mergeRow,
    };
    lanes.push(lane);
    const parentAccent = parent?.accent ?? "main";
    reserved.set(forkRow, {
      x: lane.parentX,
      ownerId: lane.parentId,
      accent: parentAccent,
      kind: "fork",
      anchorId: undefined,
    });
    reserved.set(mergeRow, {
      x: lane.parentX,
      ownerId: lane.parentId,
      accent: parentAccent,
      kind: "merge",
      anchorId: undefined,
      incomingAccent: lane.accent,
    });
  }
  return { lanes, reserved };
}

/**
 * The mainline's last row. Where the gutter has room beside the final call to
 * action, the end sits level with the install command; where that content
 * reaches the rail (phones), the rail stops one row above the section, so
 * nothing runs under or beside it or through the footer.
 */
function topologyEndY(page: TopologyPageMeasurement, mainlineX: number): number {
  const end = page.end;
  if (end === undefined) {
    return page.height - topologyRowUnit;
  }
  const level = end.level;
  if (level !== undefined && level.left >= mainlineX + topologyEndContentClearance) {
    return centerYOf(level);
  }
  return end.section.top - topologyRowUnit;
}

/**
 * Wide screens: the lanes fork from the middle of the hero copy, one column
 * per row, so the lane next to the content runs 2–4 rows before it leaves for
 * the hero frame. A frame far below the copy moves the forks down with it.
 */
function heroLaneOpenRow(props: {
  readonly rowYs: readonly number[];
  readonly heroRow: number;
  readonly heroCopy: TopologyRect | undefined;
  readonly heroTarget: TopologyRect | undefined;
  readonly laneCount: number;
}): number {
  const { rowYs, heroRow, heroCopy, heroTarget, laneCount } = props;
  const middleY = heroCopy === undefined ? (rowYs[heroRow] ?? 0) : centerYOf(heroCopy);
  let middleRow = heroRow + 1;
  for (const [row, rowY] of rowYs.entries()) {
    if (
      row > heroRow &&
      Math.abs(rowY - middleY) < Math.abs((rowYs[middleRow] ?? Infinity) - middleY)
    ) {
      middleRow = row;
    }
  }
  if (heroTarget === undefined) {
    return middleRow;
  }
  const bandTop = heroTarget.top + Math.min(topologyAttachBandInset, heroTarget.height / 2);
  const bandStartRow = rowYs.findIndex((rowY) => rowY >= bandTop);
  // The outermost lane forks on `openRow + laneCount - 1` and leaves on the
  // row above the frame's first band row, at most the maximum travel later.
  const latestTravelOpenRow = bandStartRow - laneCount - topologyHeroLaneMaximumTravel;
  return Math.max(heroRow + 1, middleRow, latestTravelOpenRow);
}

/**
 * A port: from the source lane's dot, the retired merge bend turns onto the
 * target row and runs one column straight into the target's left edge.
 */
function leftEdgePortPath(sourceX: number, edgeX: number, forkY: number, attachY: number): string {
  return [`M ${sourceX} ${forkY}`, ...localMergePath(edgeX, sourceX, forkY, attachY)].join(" ");
}

/**
 * A stacked-glass port: the retired fork bend runs out from the mainline and turns
 * down, then a short straight vertical run enters the glass's top edge.
 */
function stackedDropPortPath(sourceX: number, dropX: number, forkY: number, edgeY: number): string {
  const entry = Math.min(topologyStackedVerticalEntry, (edgeY - forkY) / 2);
  return [...localForkPath(sourceX, dropX, forkY, edgeY - entry), `L ${dropX} ${edgeY}`].join(" ");
}

function worktreePath(lane: WorktreeLane, rowYs: readonly number[]): string {
  const forkY = rowYs[lane.forkRow] ?? 0;
  const arrivalY = rowYs[lane.forkRow + 1] ?? forkY;
  const approachY = rowYs[lane.mergeRow - 1] ?? arrivalY;
  const mergeY = rowYs[lane.mergeRow] ?? approachY;
  return [
    ...localForkPath(lane.parentX, lane.x, forkY, arrivalY),
    ...localMergePath(lane.parentX, lane.x, approachY, mergeY),
  ].join(" ");
}

export function composeFullPageTopology(
  page: TopologyPageMeasurement,
): TopologyComposition | undefined {
  if (page.anchors.length === 0) {
    return undefined;
  }
  const stacked = page.viewportWidth < topologyStackedLayoutBreakpointWidth;
  const attachXs = page.anchors.flatMap((anchor) => {
    const attachX = attachXFor(anchor, stacked);
    return attachX === undefined ? [] : [attachX];
  });
  const contentX = Math.min(
    ...(attachXs.length > 0 ? attachXs : page.anchors.map((anchor) => anchor.rect.left)),
  );
  const { rowYs, anchorRows } = measureTopologyRows({
    anchorYs: page.anchors.map((anchor) => anchor.lineY ?? centerYOf(anchor.rect)),
    endY: topologyEndY(
      page,
      measureTopologyGutterColumns({ attachX: contentX, viewportWidth: page.viewportWidth })
        .mainlineX,
    ),
  });
  const finalRow = rowYs.length - 1;
  const firstAnchor = page.anchors[0];
  const targetBottoms = page.anchors.flatMap((anchor) =>
    anchor.surface === undefined ? [] : [bottomOf(anchor.surface)],
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

  const attachRoutes: TopologyRoute[] = [];
  for (const [index, anchor] of page.anchors.entries()) {
    const anchorRow = anchorRows[index] ?? 0;
    const attachX = attachXFor(anchor, stacked);
    const target = anchor.surface;
    if (attachX === undefined || target === undefined) {
      continue;
    }
    // The branch leaves from the column next to the target: the outermost lane
    // wherever it runs straight at the fork row, otherwise the mainline.
    const sourceAt = (
      row: number,
    ): { id: string; x: number; column: number; accent: TopologyAccent } =>
      outermostLane !== undefined && row > outermostLane.forkRow && row < outermostLane.mergeRow
        ? {
            id: outermostLane.id,
            x: outermostLane.x,
            column: outermostLane.column,
            accent: outermostLane.accent,
          }
        : { id: mainlineOwnerId, x: columns.mainlineX, column: 0, accent: "main" };

    if (stacked) {
      // The drop enters the glass's top edge, so the fork sits in the open
      // space above it: below the copy when the copy sits above the glass (the
      // hero), otherwise below the previous glass. It forks on the last free
      // row there; otherwise just below the copy, or a short way above the glass.
      const copyAboveGlass = anchor.rect.top < target.top;
      const previousSurface = page.anchors[index - 1]?.surface;
      const clearTop = copyAboveGlass
        ? bottomOf(anchor.copyBlock ?? anchor.rect)
        : previousSurface === undefined
          ? 0
          : bottomOf(previousSurface);
      const rowAbove = rowYs.findLastIndex((rowY) => rowY < target.top);
      const rowAboveY = rowYs[rowAbove];
      const forkOnRow =
        rowAboveY !== undefined &&
        rowAboveY >= clearTop &&
        target.top - rowAboveY >= topologyStackedMinimumDrop &&
        !reserved.has(rowAbove);
      const gap = target.top - clearTop;
      const fallbackForkY = copyAboveGlass
        ? clearTop + Math.min(topologyStackedForkCopyClearance, gap / 2)
        : target.top - Math.min(topologyStackedFallbackDrop, gap / 2);
      const forkY = forkOnRow ? rowAboveY : fallbackForkY;
      const source = sourceAt(forkOnRow ? rowAbove : Math.max(rowAbove, anchorRow));
      if (forkOnRow) {
        reserved.set(rowAbove, {
          x: source.x,
          ownerId: source.id,
          accent: source.accent,
          kind: "fork",
          anchorId: undefined,
        });
      }
      attachRoutes.push({
        id: `attach-${anchor.id}`,
        kind: "attach",
        accent: "port",
        pathData: stackedDropPortPath(source.x, attachX, forkY, target.top),
        parentColumn: source.column,
        column: source.column + 1,
        startY: forkY,
        endY: target.top,
        anchorId: anchor.id,
        targetEdge: "top",
        portNode: { x: attachX, y: target.top },
        sourceAccent: source.accent,
      });
      continue;
    }
    // Wide: enter the glass's left edge on the first row inside it whose row
    // above is free for the fork and, when lanes exist, where the lane next to
    // the content runs straight, so the step in is exactly one column.
    const bandTop = target.top + Math.min(topologyAttachBandInset, target.height / 2);
    const bandBottom = bottomOf(target) - Math.min(topologyAttachBandInset, target.height / 2);
    const forksFromOutermostLane = (forkRow: number): boolean =>
      outermostLane === undefined ||
      (forkRow >= outermostLane.forkRow + topologyHeroLaneMinimumTravel &&
        forkRow < outermostLane.mergeRow);
    const attachRow = rowYs.findIndex(
      (rowY, row) =>
        row > 0 &&
        rowY >= bandTop &&
        rowY <= bandBottom &&
        !reserved.has(row - 1) &&
        forksFromOutermostLane(row - 1),
    );
    const attachY = rowYs[attachRow];
    const forkY = rowYs[attachRow - 1];
    if (attachRow < 0 || attachY === undefined || forkY === undefined) {
      continue;
    }
    const source = sourceAt(attachRow - 1);
    reserved.set(attachRow - 1, {
      x: source.x,
      ownerId: source.id,
      accent: source.accent,
      kind: "fork",
      anchorId: undefined,
    });
    attachRoutes.push({
      id: `attach-${anchor.id}`,
      kind: "attach",
      accent: "port",
      pathData: leftEdgePortPath(source.x, attachX, forkY, attachY),
      parentColumn: source.column,
      column: source.column + 1,
      startY: forkY,
      endY: attachY,
      anchorId: anchor.id,
      targetEdge: "left",
      portNode: { x: attachX, y: attachY },
      sourceAccent: source.accent,
    });
  }

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
    portNode: undefined,
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
