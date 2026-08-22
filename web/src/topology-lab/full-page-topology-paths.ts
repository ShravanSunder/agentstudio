import type { TopologyRouteContract } from "./full-page-topology-contract";
import {
  closestTopologySurfaceRow,
  topologyRowUnit,
  type FullPageTopologyGrid,
  type TopologyGlassBand,
  type TopologyGlassSurfaceBounds,
} from "./full-page-topology-model";

export interface FullPageTopologyPortal {
  readonly frameLeft: number;
  readonly frameRight: number;
  readonly glassSurfaces: readonly TopologyGlassSurfaceBounds[];
}

export type ResolvedTopologyRoute = TopologyRouteContract & {
  readonly endRow: number;
  readonly forkRow: number;
};

export interface ResolvedTopologyRouteGeometry {
  readonly endRow: number;
  readonly forkRow: number;
  readonly pathData: string;
  readonly sourceX: number;
  readonly targetX: number;
}

function rowForGlassIndex(
  glassIndex: number | undefined,
  portal: FullPageTopologyPortal,
  grid: FullPageTopologyGrid,
  band: TopologyGlassBand,
): number | undefined {
  if (glassIndex === undefined) {
    return undefined;
  }
  if (glassIndex === 0) {
    return band.firstCrossRow;
  }
  if (glassIndex === portal.glassSurfaces.length - 1) {
    return band.lastCrossRow;
  }
  const surface = portal.glassSurfaces[glassIndex];
  return surface === undefined ? undefined : closestTopologySurfaceRow(surface, grid, 0.5);
}

export function resolveTopologyRouteRows(
  route: TopologyRouteContract,
  portal: FullPageTopologyPortal,
  grid: FullPageTopologyGrid,
  band: TopologyGlassBand,
): ResolvedTopologyRoute | undefined {
  const forkRow = route.forkPageRow ?? rowForGlassIndex(route.forkGlassIndex, portal, grid, band);
  const endRow =
    route.endPageRow ??
    (route.endPageOffset === undefined ? undefined : grid.finalRow - route.endPageOffset) ??
    rowForGlassIndex(route.endGlassIndex, portal, grid, band);
  if (
    forkRow === undefined ||
    endRow === undefined ||
    forkRow < 1 ||
    forkRow >= grid.finalRow ||
    endRow < 1 ||
    endRow >= grid.finalRow ||
    endRow <= forkRow
  ) {
    return undefined;
  }
  return { ...route, endRow, forkRow };
}

function localForkPath(
  sourceX: number,
  targetX: number,
  forkY: number,
  arrivalY: number,
): readonly string[] {
  return [
    `M ${sourceX} ${forkY}`,
    `C ${sourceX + (targetX - sourceX) * 0.9} ${forkY + (arrivalY - forkY) * 0.08} ${targetX} ${forkY + (arrivalY - forkY) * 0.1} ${targetX} ${arrivalY}`,
  ];
}

function localMergePath(
  sourceX: number,
  targetX: number,
  approachY: number,
  mergeY: number,
): readonly string[] {
  return [
    `L ${targetX} ${approachY}`,
    `C ${targetX} ${approachY + (mergeY - approachY) * 0.9} ${targetX + (sourceX - targetX) * 0.1} ${approachY + (mergeY - approachY) * 0.92} ${sourceX} ${mergeY}`,
  ];
}

function crossFrameForkPath(
  sourceX: number,
  targetX: number,
  forkY: number,
  arrivalY: number,
  portal: FullPageTopologyPortal,
): readonly string[] {
  return [
    `M ${sourceX} ${forkY}`,
    `L ${portal.frameLeft} ${forkY}`,
    `C ${portal.frameLeft + (targetX - portal.frameLeft) * 0.9} ${forkY + (arrivalY - forkY) * 0.08} ${targetX} ${forkY + (arrivalY - forkY) * 0.1} ${targetX} ${arrivalY}`,
  ];
}

function crossFrameMergePath(
  sourceX: number,
  targetX: number,
  approachY: number,
  mergeY: number,
  portal: FullPageTopologyPortal,
): readonly string[] {
  return [
    `L ${targetX} ${approachY}`,
    `C ${targetX} ${approachY + (mergeY - approachY) * 0.9} ${targetX + (portal.frameLeft - targetX) * 0.1} ${approachY + (mergeY - approachY) * 0.92} ${portal.frameLeft} ${mergeY}`,
    `L ${sourceX} ${mergeY}`,
  ];
}

export function resolveTopologyRouteGeometry(
  route: ResolvedTopologyRoute,
  sourceX: number,
  targetX: number,
  grid: FullPageTopologyGrid,
  portal: FullPageTopologyPortal,
): ResolvedTopologyRouteGeometry {
  const { endRow, forkRow } = route;
  const arrivalRow = Math.min(forkRow + 1, endRow);
  const yForRow = (row: number): number => grid.topPadding + row * topologyRowUnit;
  const segments = [
    ...(route.placement === "local-right"
      ? localForkPath(sourceX, targetX, yForRow(forkRow), yForRow(arrivalRow))
      : crossFrameForkPath(sourceX, targetX, yForRow(forkRow), yForRow(arrivalRow), portal)),
  ];
  if (route.endKind === "merge") {
    const approachRow = Math.max(endRow - 1, arrivalRow);
    segments.push(
      ...(route.placement === "local-right"
        ? localMergePath(sourceX, targetX, yForRow(approachRow), yForRow(endRow))
        : crossFrameMergePath(sourceX, targetX, yForRow(approachRow), yForRow(endRow), portal)),
    );
  } else {
    segments.push(`L ${targetX} ${yForRow(endRow)}`);
  }
  return { endRow, forkRow, pathData: segments.join(" "), sourceX, targetX };
}

export function topologyPathLengthFractionAtY(path: SVGPathElement, targetY: number): number {
  const totalLength = path.getTotalLength();
  let lowerLength = 0;
  let upperLength = totalLength;
  for (let iteration = 0; iteration < 24; iteration += 1) {
    const middleLength = lowerLength + (upperLength - lowerLength) / 2;
    if (path.getPointAtLength(middleLength).y <= targetY) {
      lowerLength = middleLength;
    } else {
      upperLength = middleLength;
    }
  }
  return totalLength <= 0 ? 0 : lowerLength / totalLength;
}

export function topologyPathPointAtY(path: SVGPathElement, targetY: number): DOMPoint {
  return path.getPointAtLength(
    path.getTotalLength() * topologyPathLengthFractionAtY(path, targetY),
  );
}
