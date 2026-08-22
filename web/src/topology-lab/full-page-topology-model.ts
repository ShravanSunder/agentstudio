const authoredBandSlotCount = 20;
const columnUnit = 96;
const edgeColumnCount = 1;
const minimumUsableColumnCount = 2;
export const topologyRowUnit = 96;

export type FullPageTopologyVariant = "compact" | "expanded" | "standard";
export type WorktreeEndKind = "merge" | "open";

export interface FullPageTopologyGrid {
  readonly finalRow: number;
  readonly leftLaneXs: readonly number[];
  readonly rightLaneXs: readonly number[];
  readonly rowCount: number;
  readonly topPadding: number;
  readonly usableColumnCount: number;
  readonly variant: FullPageTopologyVariant;
}

interface MeasureFullPageTopologyGridProps {
  readonly frameLeft: number;
  readonly frameRight: number;
  readonly height: number;
  readonly requestedTopPadding?: number;
  readonly width: number;
}

export interface TopologyGlassSurfaceBounds {
  readonly bottom: number;
  readonly top: number;
}

interface ResolveTopologyGlassBandProps {
  readonly glassSurfaces: readonly TopologyGlassSurfaceBounds[];
  readonly grid: FullPageTopologyGrid;
}

export interface TopologyGlassBand {
  readonly firstCrossRow: number;
  readonly lastCrossRow: number;
  readonly slotCount: number;
}

export interface WorktreeLifecycle {
  readonly endKind: WorktreeEndKind;
  readonly endSlot: number;
  readonly forkSlot: number;
  readonly id: string;
}

export interface AssignedWorktreeColumn {
  readonly id: string;
  readonly lane: number;
}

interface AssignedWorktreeLifecycle extends AssignedWorktreeColumn, WorktreeLifecycle {}

function variantForColumnCount(usableColumnCount: number): FullPageTopologyVariant {
  if (usableColumnCount >= 4) {
    return "expanded";
  }
  if (usableColumnCount >= 3) {
    return "standard";
  }
  return "compact";
}

export function assignWorktreeColumns(
  lifecycles: readonly WorktreeLifecycle[],
  usableColumnCount: number,
): readonly AssignedWorktreeColumn[] | undefined {
  if (usableColumnCount < minimumUsableColumnCount) {
    return undefined;
  }

  const assigned: AssignedWorktreeLifecycle[] = [];
  const ids = new Set<string>();
  const forkSlots = new Set<number>();
  for (const lifecycle of lifecycles) {
    if (
      ids.has(lifecycle.id) ||
      forkSlots.has(lifecycle.forkSlot) ||
      lifecycle.forkSlot < 0 ||
      lifecycle.endSlot <= lifecycle.forkSlot
    ) {
      return undefined;
    }
    ids.add(lifecycle.id);
    forkSlots.add(lifecycle.forkSlot);
  }

  for (const lifecycle of lifecycles.toSorted((left, right) => left.forkSlot - right.forkSlot)) {
    const occupiedLanes = new Set(
      assigned
        .filter((prior) => prior.endKind === "open" || prior.endSlot >= lifecycle.forkSlot)
        .map((prior) => prior.lane),
    );
    const lane = Array.from(
      { length: usableColumnCount - 1 },
      (_, laneIndex) => laneIndex + 1,
    ).find((candidateLane) => !occupiedLanes.has(candidateLane));
    if (lane === undefined) {
      return undefined;
    }
    assigned.push({ ...lifecycle, lane });
  }
  return assigned.map(({ id, lane }) => ({ id, lane }));
}

export function measureFullPageTopologyGrid(
  props: MeasureFullPageTopologyGridProps,
): FullPageTopologyGrid | undefined {
  const { frameLeft, frameRight, height, requestedTopPadding = topologyRowUnit, width } = props;
  if (width <= 0 || height <= 0 || frameLeft < 0 || frameRight <= frameLeft || frameRight > width) {
    return undefined;
  }

  const edgeReserve = edgeColumnCount * columnUnit;
  const smallerGutterWidth = Math.min(frameLeft, width - frameRight);
  const usableColumnCount = Math.floor((smallerGutterWidth - edgeReserve) / columnUnit);
  if (usableColumnCount < minimumUsableColumnCount) {
    return undefined;
  }

  const topPadding = Math.max(topologyRowUnit, requestedTopPadding);
  const availableHeight = height - topPadding - topologyRowUnit;
  if (availableHeight < topologyRowUnit) {
    return undefined;
  }

  const rowCount = Math.floor(availableHeight / topologyRowUnit) + 1;
  return {
    finalRow: rowCount - 1,
    leftLaneXs: Array.from(
      { length: usableColumnCount },
      (_, laneIndex) => edgeReserve + columnUnit / 2 + laneIndex * columnUnit,
    ),
    rightLaneXs: Array.from(
      { length: usableColumnCount },
      (_, laneIndex) => width - edgeReserve - columnUnit / 2 - laneIndex * columnUnit,
    ),
    rowCount,
    topPadding,
    usableColumnCount,
    variant: variantForColumnCount(usableColumnCount),
  };
}

function rowsInsideSurface(
  surface: TopologyGlassSurfaceBounds,
  grid: FullPageTopologyGrid,
): readonly number[] {
  return Array.from({ length: grid.rowCount }, (_, row) => row).filter((row) => {
    const y = grid.topPadding + row * topologyRowUnit;
    return y >= surface.top && y <= surface.bottom;
  });
}

export function closestTopologySurfaceRow(
  surface: TopologyGlassSurfaceBounds,
  grid: FullPageTopologyGrid,
  verticalRatio: number,
): number | undefined {
  const targetY = surface.top + (surface.bottom - surface.top) * verticalRatio;
  return rowsInsideSurface(surface, grid).toSorted((leftRow, rightRow) => {
    const leftDistance = Math.abs(grid.topPadding + leftRow * topologyRowUnit - targetY);
    const rightDistance = Math.abs(grid.topPadding + rightRow * topologyRowUnit - targetY);
    return leftDistance - rightDistance;
  })[0];
}

export function resolveTopologyGlassBand(
  props: ResolveTopologyGlassBandProps,
): TopologyGlassBand | undefined {
  const { glassSurfaces, grid } = props;
  const firstSurface = glassSurfaces[0];
  const lastSurface = glassSurfaces.at(-1);
  if (firstSurface === undefined || lastSurface === undefined || firstSurface === lastSurface) {
    return undefined;
  }

  const firstCrossRow = closestTopologySurfaceRow(firstSurface, grid, 0.7);
  const lastCrossRow = closestTopologySurfaceRow(lastSurface, grid, 0.3);
  if (
    firstCrossRow === undefined ||
    lastCrossRow === undefined ||
    lastCrossRow - firstCrossRow < authoredBandSlotCount ||
    lastCrossRow >= grid.finalRow
  ) {
    return undefined;
  }
  return { firstCrossRow, lastCrossRow, slotCount: authoredBandSlotCount };
}
