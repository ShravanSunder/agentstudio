const minimumGlassBandRowSpan = 20;
const columnUnit = 96;
export const maximumGutterColumnCount = 4;
export const maximumRenderedTopologyRowCount = 128;
const minimumUsableColumnCount = 2;
export const topologyRowUnit = 96;

export type FullPageTopologyVariant = "compact" | "expanded" | "standard";
export type WorktreeEndKind = "merge" | "open";

export interface FullPageTopologyGrid {
  readonly columnCapacity: number;
  readonly finalRow: number;
  readonly leftColumnCapacity: number;
  readonly rowCount: number;
  readonly rightColumnCapacity: number;
  readonly topPadding: number;
  readonly variant: FullPageTopologyVariant;
}

interface CenteredTopologyColumnXsProps {
  readonly columnCount: number;
  readonly gutterEnd: number;
  readonly gutterStart: number;
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
}

export interface WorktreeLifecycle {
  readonly endRow: number;
  readonly endKind: WorktreeEndKind;
  readonly forkRow: number;
  readonly id: string;
}

export interface AssignedWorktreeColumn {
  readonly id: string;
  readonly lane: number;
}

interface AssignedWorktreeLifecycle extends AssignedWorktreeColumn, WorktreeLifecycle {}

export interface TopologyRowWorktree {
  readonly endRow: number;
  readonly id: string;
  readonly priority: number;
  readonly startRow: number;
}

export interface TopologyRowOwner {
  readonly ownerId: string;
  readonly row: number;
}

interface AssignTopologyRowOwnersProps {
  readonly reservedRows: ReadonlySet<number>;
  readonly rowCount: number;
  readonly worktrees: readonly TopologyRowWorktree[];
}

export function assignTopologyRowOwners(
  props: AssignTopologyRowOwnersProps,
): readonly TopologyRowOwner[] {
  const { reservedRows, rowCount, worktrees } = props;
  const assignedCounts = new Map<string, number>();
  return Array.from({ length: rowCount }, (_, row) => row).flatMap((row) => {
    if (reservedRows.has(row)) {
      return [];
    }
    const activeWorktrees = worktrees.filter(
      (worktree) => worktree.startRow < row && worktree.endRow > row,
    );
    const candidates = [
      ...activeWorktrees.map((worktree) => ({ id: worktree.id, priority: worktree.priority })),
      { id: "main", priority: 0 },
    ].toSorted((left, right) => {
      const countDifference =
        (assignedCounts.get(left.id) ?? 0) - (assignedCounts.get(right.id) ?? 0);
      return countDifference === 0 ? right.priority - left.priority : countDifference;
    });
    const owner = candidates[0];
    if (owner === undefined) {
      return [];
    }
    assignedCounts.set(owner.id, (assignedCounts.get(owner.id) ?? 0) + 1);
    return [{ ownerId: owner.id, row }];
  });
}

function variantForColumnCount(usableColumnCount: number): FullPageTopologyVariant {
  if (usableColumnCount >= topologyVariantColumnCapacities.expanded) {
    return "expanded";
  }
  if (usableColumnCount >= topologyVariantColumnCapacities.standard) {
    return "standard";
  }
  return "compact";
}

export const topologyVariantColumnCapacities = {
  compact: 2,
  expanded: 4,
  standard: 3,
} as const satisfies Record<FullPageTopologyVariant, number>;

export function assignWorktreeLanes(
  lifecycles: readonly WorktreeLifecycle[],
  laneCount: number,
): readonly AssignedWorktreeColumn[] | undefined {
  if (!Number.isInteger(laneCount) || laneCount < 1) {
    return undefined;
  }

  const assigned: AssignedWorktreeLifecycle[] = [];
  const ids = new Set<string>();
  const forkRows = new Set<number>();
  for (const lifecycle of lifecycles) {
    if (
      ids.has(lifecycle.id) ||
      forkRows.has(lifecycle.forkRow) ||
      lifecycle.forkRow < 0 ||
      lifecycle.endRow <= lifecycle.forkRow
    ) {
      return undefined;
    }
    ids.add(lifecycle.id);
    forkRows.add(lifecycle.forkRow);
  }

  for (const lifecycle of lifecycles.toSorted((left, right) => left.forkRow - right.forkRow)) {
    const occupiedLanes = new Set(
      assigned
        .filter((prior) => prior.endKind === "open" || prior.endRow >= lifecycle.forkRow)
        .map((prior) => prior.lane),
    );
    const lane = Array.from({ length: laneCount }, (_, laneIndex) => laneIndex).find(
      (candidateLane) => !occupiedLanes.has(candidateLane),
    );
    if (lane === undefined) {
      return undefined;
    }
    assigned.push({ ...lifecycle, lane });
  }
  return assigned.map(({ id, lane }) => ({ id, lane }));
}

export function centeredTopologyColumnXs(
  props: CenteredTopologyColumnXsProps,
): readonly number[] | undefined {
  const { columnCount, gutterEnd, gutterStart } = props;
  const gutterWidth = gutterEnd - gutterStart;
  if (
    !Number.isInteger(columnCount) ||
    columnCount < 0 ||
    columnCount > maximumGutterColumnCount ||
    gutterStart < 0 ||
    gutterWidth < columnCount * columnUnit
  ) {
    return undefined;
  }
  if (columnCount === 0) {
    return [];
  }
  const occupiedSpan = (columnCount - 1) * columnUnit;
  const firstCenter = gutterStart + (gutterWidth - occupiedSpan) / 2;
  return Array.from({ length: columnCount }, (_, columnIndex) => {
    return firstCenter + columnIndex * columnUnit;
  });
}

function columnCapacityForGutterWidth(gutterWidth: number): number {
  return Math.min(maximumGutterColumnCount, Math.floor(gutterWidth / columnUnit));
}

export function measureFullPageTopologyGrid(
  props: MeasureFullPageTopologyGridProps,
): FullPageTopologyGrid | undefined {
  const { frameLeft, frameRight, height, requestedTopPadding = topologyRowUnit, width } = props;
  if (width <= 0 || height <= 0 || frameLeft < 0 || frameRight <= frameLeft || frameRight > width) {
    return undefined;
  }

  const leftColumnCapacity = columnCapacityForGutterWidth(frameLeft);
  const rightColumnCapacity = columnCapacityForGutterWidth(width - frameRight);
  const columnCapacity = Math.min(leftColumnCapacity, rightColumnCapacity);
  if (columnCapacity < minimumUsableColumnCount) {
    return undefined;
  }

  const topPadding = Math.max(topologyRowUnit, requestedTopPadding);
  const availableHeight = height - topPadding - topologyRowUnit;
  if (availableHeight < topologyRowUnit) {
    return undefined;
  }

  const rowCount = Math.floor(availableHeight / topologyRowUnit) + 1;
  return {
    columnCapacity,
    finalRow: rowCount - 1,
    leftColumnCapacity,
    rowCount,
    rightColumnCapacity,
    topPadding,
    variant: variantForColumnCount(columnCapacity),
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

export function topologySurfaceRowsByDistance(
  surface: TopologyGlassSurfaceBounds,
  grid: FullPageTopologyGrid,
  verticalRatio: number,
): readonly number[] {
  const targetY = surface.top + (surface.bottom - surface.top) * verticalRatio;
  return rowsInsideSurface(surface, grid).toSorted((leftRow, rightRow) => {
    const leftDistance = Math.abs(grid.topPadding + leftRow * topologyRowUnit - targetY);
    const rightDistance = Math.abs(grid.topPadding + rightRow * topologyRowUnit - targetY);
    return leftDistance === rightDistance ? leftRow - rightRow : leftDistance - rightDistance;
  });
}

export function closestTopologySurfaceRow(
  surface: TopologyGlassSurfaceBounds,
  grid: FullPageTopologyGrid,
  verticalRatio: number,
): number | undefined {
  return topologySurfaceRowsByDistance(surface, grid, verticalRatio)[0];
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
    lastCrossRow - firstCrossRow < minimumGlassBandRowSpan ||
    lastCrossRow >= grid.finalRow
  ) {
    return undefined;
  }
  return { firstCrossRow, lastCrossRow };
}
