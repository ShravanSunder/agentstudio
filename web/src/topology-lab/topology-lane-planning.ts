import type {
  TopologyAccent,
  TopologyRect,
  TopologyRowDot,
} from "./full-page-topology-composition";
import { localForkPath, localMergePath } from "./full-page-topology-paths";
import { topologyAttachBandInset } from "./topology-attach-geometry";
import { topologyRectCenterY } from "./topology-end-geometry";

export const mainlineOwnerId = "main";
const worktreeAccents = ["peach", "cyan"] as const satisfies readonly TopologyAccent[];

/**
 * On wide screens the lane next to the content runs at least this many rows,
 * and at most `topologyHeroLaneMaximumTravel`, between its fork and the row it
 * leaves for the hero frame.
 */
export const topologyHeroLaneMinimumTravel = 2;
export const topologyHeroLaneMaximumTravel = 4;

export interface WorktreeLane {
  readonly id: string;
  readonly column: number;
  readonly x: number;
  readonly parentId: string;
  readonly parentX: number;
  readonly accent: TopologyAccent;
  readonly forkRow: number;
  readonly mergeRow: number;
}

export interface LanePlan {
  readonly lanes: readonly WorktreeLane[];
  readonly reserved: ReadonlyMap<number, Omit<TopologyRowDot, "row" | "y">>;
}

/**
 * Worktree lanes open as a one-column staircase (lane k forks from lane k-1 on
 * consecutive rows) starting at `openRow`, in the gutter beside the hero copy,
 * and close the same way in reverse after the last target, so every fork and
 * merge moves one column.
 */
export function planWorktreeLanes(props: {
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

/** Wide hero lanes fork from the middle of the copy, then reach the frame. */
export function heroLaneOpenRow(props: {
  readonly rowYs: readonly number[];
  readonly heroRow: number;
  readonly heroCopy: TopologyRect | undefined;
  readonly heroTarget: TopologyRect | undefined;
  readonly laneCount: number;
}): number {
  const { rowYs, heroRow, heroCopy, heroTarget, laneCount } = props;
  const middleY = heroCopy === undefined ? (rowYs[heroRow] ?? 0) : topologyRectCenterY(heroCopy);
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
  const latestTravelOpenRow = bandStartRow - laneCount - topologyHeroLaneMaximumTravel;
  return Math.max(heroRow + 1, middleRow, latestTravelOpenRow);
}

export function worktreePath(lane: WorktreeLane, rowYs: readonly number[]): string {
  const forkY = rowYs[lane.forkRow] ?? 0;
  const arrivalY = rowYs[lane.forkRow + 1] ?? forkY;
  const approachY = rowYs[lane.mergeRow - 1] ?? arrivalY;
  const mergeY = rowYs[lane.mergeRow] ?? approachY;
  return [
    ...localForkPath(lane.parentX, lane.x, forkY, arrivalY),
    ...localMergePath(lane.parentX, lane.x, approachY, mergeY),
  ].join(" ");
}
