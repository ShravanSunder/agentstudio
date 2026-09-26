import type {
  TopologyAccent,
  TopologyAnchorMeasurement,
  TopologyPageMeasurement,
  TopologyRoute,
  TopologyRowDot,
} from "./full-page-topology-composition";
import { localForkPath, localMergePath } from "./full-page-topology-paths";
import { topologyRectBottom } from "./topology-end-geometry";
import {
  mainlineOwnerId,
  topologyHeroLaneMinimumTravel,
  type WorktreeLane,
} from "./topology-lane-planning";

/** A wide branch enters its glass on a row at least this far inside the glass. */
export const topologyAttachBandInset = 40;
/** Stacked branches clear the glass's rounded corner. */
export const topologyStackedDropCornerInset = 24;
/** Stacked drops finish with a straight vertical entry. */
export const topologyStackedVerticalEntry = 8;
/** Hero stacked forks clear copy above the glass. */
export const topologyStackedForkCopyClearance = 4;
/** A free row must leave at least this much drop. */
export const topologyStackedMinimumDrop = 12;
/** A chapter without a free row forks this far above its glass. */
export const topologyStackedFallbackDrop = 32;

export function attachXFor(
  anchor: TopologyAnchorMeasurement,
  stacked: boolean,
): number | undefined {
  const surface = anchor.surface;
  if (!stacked && anchor.stepPill !== undefined) return anchor.stepPill.left;
  if (surface === undefined) {
    return undefined;
  }
  return stacked || anchor.id === "hero"
    ? Math.min(surface.left + topologyStackedDropCornerInset, surface.left + surface.width / 2)
    : surface.left;
}

/** A left-edge attach uses the retired merge bend. */
function leftEdgePortPath(sourceX: number, edgeX: number, forkY: number, attachY: number): string {
  return [`M ${sourceX} ${forkY}`, ...localMergePath(edgeX, sourceX, forkY, attachY)].join(" ");
}

/** A stacked attach uses the retired fork bend and a short vertical entry. */
function stackedDropPortPath(sourceX: number, dropX: number, forkY: number, edgeY: number): string {
  const entry = Math.min(topologyStackedVerticalEntry, (edgeY - forkY) / 2);
  return [...localForkPath(sourceX, dropX, forkY, edgeY - entry), `L ${dropX} ${edgeY}`].join(" ");
}

interface AttachRoutePlanProps {
  readonly page: TopologyPageMeasurement;
  readonly stacked: boolean;
  readonly rowYs: readonly number[];
  readonly anchorRows: readonly number[];
  readonly reserved: Map<number, Omit<TopologyRowDot, "row" | "y">>;
  readonly mainlineX: number;
  readonly outermostLane: WorktreeLane | undefined;
}

/** Choose one fork and attach path for every measured target. */
export function planAttachRoutes(props: AttachRoutePlanProps): TopologyRoute[] {
  const { page, stacked, rowYs, anchorRows, reserved, mainlineX, outermostLane } = props;
  const attachRoutes: TopologyRoute[] = [];
  for (const [index, anchor] of page.anchors.entries()) {
    const anchorRow = anchorRows[index] ?? 0;
    const attachX = attachXFor(anchor, stacked);
    const target = anchor.surface;
    if (attachX === undefined || target === undefined) {
      continue;
    }
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
        : { id: mainlineOwnerId, x: mainlineX, column: 0, accent: "main" };

    if (!stacked && anchor.stepPill !== undefined) {
      const centerY = anchor.stepPill.top + anchor.stepPill.height / 2;
      const attachRow = rowYs.findIndex((rowY) => Math.abs(rowY - centerY) <= 0.5);
      const forkRow = attachRow - 1;
      const forkY = rowYs[forkRow];
      if (forkY === undefined) continue;
      const source = sourceAt(forkRow);
      // In G7 the title precedes the pill, so its chapter row can also be
      // the row above the pill. Keep that chapter marker when the branch forks.
      if (!reserved.has(forkRow)) {
        reserved.set(forkRow, {
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
        pathData: leftEdgePortPath(source.x, attachX, forkY, centerY),
        parentColumn: source.column,
        column: source.column + 1,
        startY: forkY,
        endY: centerY,
        anchorId: anchor.id,
        targetEdge: "left",
        targetPoint: { x: attachX, y: centerY },
        sourceAccent: source.accent,
      });
      continue;
    }

    if (stacked || anchor.id === "hero") {
      const copyAboveGlass = anchor.rect.top < target.top;
      const previousSurface = page.anchors[index - 1]?.surface;
      const clearTop = copyAboveGlass
        ? topologyRectBottom(anchor.copyBlock ?? anchor.rect)
        : previousSurface === undefined
          ? 0
          : topologyRectBottom(previousSurface);
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
        targetPoint: { x: attachX, y: target.top },
        sourceAccent: source.accent,
      });
      continue;
    }
    const bandTop = target.top + Math.min(topologyAttachBandInset, target.height / 2);
    const bandBottom =
      topologyRectBottom(target) - Math.min(topologyAttachBandInset, target.height / 2);
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
      targetPoint: { x: attachX, y: attachY },
      sourceAccent: source.accent,
    });
  }
  return attachRoutes;
}
