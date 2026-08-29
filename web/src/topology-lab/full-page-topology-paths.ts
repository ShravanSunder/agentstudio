import type { TopologyRouteContract } from "./full-page-topology-contract";
import {
  topologySurfaceRowsByDistance,
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

interface RouteRowOption {
  readonly endRow: number;
  readonly forkRow: number;
  readonly preferenceRank: number;
}

function rowsForGlassIndex(
  glassIndex: number | undefined,
  portal: FullPageTopologyPortal,
  grid: FullPageTopologyGrid,
  band: TopologyGlassBand,
): readonly number[] {
  if (glassIndex === undefined) {
    return [];
  }
  const surface = portal.glassSurfaces[glassIndex];
  if (surface === undefined) {
    return [];
  }
  const verticalRatio =
    glassIndex === 0 ? 0.7 : glassIndex === portal.glassSurfaces.length - 1 ? 0.3 : 0.5;
  const preferredRow =
    glassIndex === 0
      ? band.firstCrossRow
      : glassIndex === portal.glassSurfaces.length - 1
        ? band.lastCrossRow
        : undefined;
  const rowsByDistance = topologySurfaceRowsByDistance(surface, grid, verticalRatio);
  if (preferredRow === undefined || rowsByDistance[0] === preferredRow) {
    return rowsByDistance;
  }
  return [preferredRow, ...rowsByDistance.filter((row) => row !== preferredRow)];
}

function routeRowOptions(
  route: TopologyRouteContract,
  portal: FullPageTopologyPortal,
  grid: FullPageTopologyGrid,
  band: TopologyGlassBand,
): readonly RouteRowOption[] {
  const fixedEndRow =
    route.endPageRow ??
    (route.endPageOffset === undefined ? undefined : grid.finalRow - route.endPageOffset);
  const forkRows =
    route.forkPageRow === undefined
      ? rowsForGlassIndex(route.forkGlassIndex, portal, grid, band)
      : [route.forkPageRow];
  const endRows =
    fixedEndRow === undefined
      ? rowsForGlassIndex(route.endGlassIndex, portal, grid, band)
      : [fixedEndRow];
  return forkRows
    .flatMap((forkRow, forkPreferenceRank) =>
      endRows.map((endRow, endPreferenceRank) => ({
        endRow,
        forkRow,
        preferenceRank: forkPreferenceRank + endPreferenceRank,
      })),
    )
    .filter(
      ({ endRow, forkRow }) =>
        forkRow >= 1 &&
        forkRow < grid.finalRow &&
        endRow >= 1 &&
        endRow < grid.finalRow &&
        endRow > forkRow,
    )
    .toSorted((left, right) => {
      const preferenceDifference = left.preferenceRank - right.preferenceRank;
      if (preferenceDifference !== 0) {
        return preferenceDifference;
      }
      const forkDifference = left.forkRow - right.forkRow;
      return forkDifference === 0 ? left.endRow - right.endRow : forkDifference;
    });
}

export function resolveTopologyRouteRowsWithoutCollisions(
  routes: readonly TopologyRouteContract[],
  portal: FullPageTopologyPortal,
  grid: FullPageTopologyGrid,
  band: TopologyGlassBand,
): readonly ResolvedTopologyRoute[] | undefined {
  const occupiedRows = new Set([0, grid.finalRow]);
  const resolvedRoutes: ResolvedTopologyRoute[] = [];

  const assignRoute = (routeIndex: number): boolean => {
    const route = routes[routeIndex];
    if (route === undefined) {
      return true;
    }
    for (const option of routeRowOptions(route, portal, grid, band)) {
      if (occupiedRows.has(option.forkRow) || occupiedRows.has(option.endRow)) {
        continue;
      }
      occupiedRows.add(option.forkRow);
      occupiedRows.add(option.endRow);
      resolvedRoutes.push({
        ...route,
        endRow: option.endRow,
        forkRow: option.forkRow,
      });
      if (assignRoute(routeIndex + 1)) {
        return true;
      }
      resolvedRoutes.pop();
      occupiedRows.delete(option.forkRow);
      occupiedRows.delete(option.endRow);
    }
    return false;
  };

  return assignRoute(0) ? [...resolvedRoutes] : undefined;
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
