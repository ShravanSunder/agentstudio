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
  /** `data-rail-media-target`: phone branches drop into its top edge. */
  readonly media: TopologyRect | undefined;
  /** The copy between the anchor and its media target; phone branches turn below it. */
  readonly copyBlock: TopologyRect | undefined;
}

export interface TopologyPageMeasurement {
  readonly viewportWidth: number;
  readonly height: number;
  readonly anchors: readonly TopologyAnchorMeasurement[];
}

export type TopologyAccent = "main" | "peach" | "cyan";
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

/** Viewports narrower than this are phones (`--breakpoint-phone: 38.75rem`). */
export const topologyPhoneBreakpointWidth = 620;
/** A wide branch enters its glass on a row at least this far inside the glass. */
export const topologyAttachBandInset = 40;
/**
 * Phone: the branch drops on the text line, but at least this far inside the
 * media glass's left edge, clear of its rounded corner (14px on phone).
 */
export const topologyPhoneDropCornerInset = 16;
/**
 * Phone: when the row above the stage sits inside the copy, the branch forks
 * this far below the copy instead, giving the drop the whole gap's height.
 */
export const topologyPhoneForkCopyClearance = 4;
/** Phone: a row above the stage only hosts the fork when it leaves at least this much drop. */
export const topologyPhoneMinimumDrop = 12;

export const mainlineOwnerId = "main";
const worktreeAccents = ["peach", "cyan"] as const satisfies readonly TopologyAccent[];

function bottomOf(rect: TopologyRect): number {
  return rect.top + rect.height;
}

function centerYOf(rect: TopologyRect): number {
  return rect.top + rect.height / 2;
}

/** Where a branch lands: the glass's left edge on wide screens, the drop point on phones. */
function attachXFor(anchor: TopologyAnchorMeasurement, phone: boolean): number | undefined {
  if (phone) {
    const media = anchor.media;
    if (media === undefined) {
      return undefined;
    }
    return Math.min(
      Math.max(anchor.rect.left, media.left + topologyPhoneDropCornerInset),
      media.left + media.width - topologyPhoneDropCornerInset,
    );
  }
  return anchor.surface?.left;
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
 * consecutive rows) starting at the first row below the first anchor's copy,
 * and close the same way in reverse after the last target, so no lane runs
 * beside text and every fork and merge moves one column.
 */
function planWorktreeLanes(props: {
  readonly laneXs: readonly number[];
  readonly mainlineX: number;
  readonly rowYs: readonly number[];
  readonly openBelowY: number;
  readonly closeBelowY: number;
  readonly lastUsableRow: number;
}): LanePlan | undefined {
  const laneCount = props.laneXs.length;
  if (laneCount === 0) {
    return { lanes: [], reserved: new Map() };
  }
  const openRow = props.rowYs.findIndex((rowY) => rowY >= props.openBelowY);
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
    });
  }
  return { lanes, reserved };
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
  const phone = page.viewportWidth < topologyPhoneBreakpointWidth;
  const attachXs = page.anchors.flatMap((anchor) => {
    const attachX = attachXFor(anchor, phone);
    return attachX === undefined ? [] : [attachX];
  });
  const contentX = Math.min(
    ...(attachXs.length > 0 ? attachXs : page.anchors.map((anchor) => anchor.rect.left)),
  );
  const columns = measureTopologyGutterColumns({
    attachX: contentX,
    viewportWidth: page.viewportWidth,
  });
  const { rowYs, anchorRows } = measureTopologyRows({
    anchorYs: page.anchors.map((anchor) => centerYOf(anchor.rect)),
    height: page.height,
  });
  const finalRow = rowYs.length - 1;
  const firstAnchor = page.anchors[0];
  const targetBottoms = page.anchors.flatMap((anchor) => {
    const target = phone ? anchor.media : anchor.surface;
    return target === undefined ? [] : [bottomOf(target)];
  });

  // Fewer lanes when the page has too few rows to open and close them all.
  let laneXs = columns.laneXs;
  let lanePlan: LanePlan | undefined;
  for (;;) {
    lanePlan = planWorktreeLanes({
      laneXs,
      mainlineX: columns.mainlineX,
      rowYs,
      openBelowY: bottomOf(
        firstAnchor?.copyBlock ?? firstAnchor?.rect ?? { left: 0, top: 0, width: 0, height: 0 },
      ),
      closeBelowY: Math.max(...targetBottoms, 0),
      lastUsableRow: finalRow - 1,
    });
    if (lanePlan !== undefined || laneXs.length === 0) {
      break;
    }
    laneXs = laneXs.slice(1);
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
    const attachX = attachXFor(anchor, phone);
    const target = phone ? anchor.media : anchor.surface;
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

    if (phone) {
      // Fork on the last row above the media's top edge when that row is below
      // the copy; otherwise just below the copy.
      const copyBottom = bottomOf(anchor.copyBlock ?? anchor.rect);
      const rowAbove = rowYs.findLastIndex((rowY) => rowY < target.top);
      const rowAboveY = rowYs[rowAbove];
      const forkOnRow =
        rowAboveY !== undefined &&
        rowAbove > anchorRow &&
        rowAboveY >= copyBottom &&
        target.top - rowAboveY >= topologyPhoneMinimumDrop &&
        !reserved.has(rowAbove);
      const forkY = forkOnRow
        ? rowAboveY
        : copyBottom + Math.min(topologyPhoneForkCopyClearance, (target.top - copyBottom) / 2);
      const source = sourceAt(forkOnRow ? rowAbove : anchorRow);
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
        accent: source.accent,
        pathData: localForkPath(source.x, attachX, forkY, target.top).join(" "),
        parentColumn: source.column,
        column: source.column + 1,
        startY: forkY,
        endY: target.top,
        anchorId: anchor.id,
        targetEdge: "top",
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
      (forkRow > outermostLane.forkRow && forkRow < outermostLane.mergeRow);
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
      accent: source.accent,
      pathData: localForkPath(source.x, attachX, forkY, attachY).join(" "),
      parentColumn: source.column,
      column: source.column + 1,
      startY: forkY,
      endY: attachY,
      anchorId: anchor.id,
      targetEdge: "left",
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
