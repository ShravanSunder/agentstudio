export const topologyRowUnit = 96;

export type WorktreeEndKind = "merge" | "open";

/**
 * The column unit is fluid with the viewport so the grid scales as one piece:
 * `clamp(40px, 5vw, 96px)`. 96px is the retired fixed column unit; 40px is the
 * narrowest step that still keeps a phone's single mainline clear of its text.
 */
export const topologyColumnUnitMinimum = 40;
export const topologyColumnUnitViewportRatio = 0.05;
export const topologyColumnUnitMaximum = 96;

/**
 * At most this many worktree lanes. The columns are anchored from the content
 * edge, so a wider gutter leaves empty whitespace left of the mainline.
 */
export const topologyMaximumLaneCount = 4;

/** The mainline never sits closer than this to the page's left edge. */
export const topologyGutterEdgeMargin = 16;

export function topologyColumnUnitFor(viewportWidth: number): number {
  return Math.min(
    topologyColumnUnitMaximum,
    Math.max(topologyColumnUnitMinimum, viewportWidth * topologyColumnUnitViewportRatio),
  );
}

/**
 * Worktree lanes that fit between the mainline and the content: every lane
 * needs its own column, plus one for the mainline, and the outermost lane is
 * always the column adjacent to the content (`attachX - unit`). Zero lanes
 * means a cramped gutter: only the mainline is drawn. Capped at
 * `topologyMaximumLaneCount`.
 */
export function topologyLaneCountFor(attachX: number, columnUnit: number): number {
  return Math.min(
    topologyMaximumLaneCount,
    Math.max(0, Math.floor((attachX - topologyGutterEdgeMargin) / columnUnit) - 1),
  );
}

export interface TopologyGutterColumns {
  readonly columnUnit: number;
  readonly mainlineX: number;
  /** Worktree lane x positions, from the lane next to the mainline to the lane next to the content. */
  readonly laneXs: readonly number[];
}

/**
 * Columns laid out leftward from the content edge, one unit apart. A lower
 * `maximumLaneCount` (fewer rows than lanes need) moves the mainline right so
 * every column stays one unit from the next.
 */
export function measureTopologyGutterColumns(props: {
  readonly attachX: number;
  readonly viewportWidth: number;
  readonly maximumLaneCount?: number;
}): TopologyGutterColumns {
  const columnUnit = topologyColumnUnitFor(props.viewportWidth);
  const laneCount = Math.min(
    props.maximumLaneCount ?? topologyMaximumLaneCount,
    topologyLaneCountFor(props.attachX, columnUnit),
  );
  return {
    columnUnit,
    mainlineX: props.attachX - (laneCount + 1) * columnUnit,
    laneXs: Array.from(
      { length: laneCount },
      (_, laneIndex) => props.attachX - (laneCount - laneIndex) * columnUnit,
    ),
  };
}

export interface TopologyRows {
  readonly rowYs: readonly number[];
  /** The row index of each anchor, in anchor order. */
  readonly anchorRows: readonly number[];
}

/**
 * Rows on the retired 96px pitch, made piecewise so every chapter anchor is a
 * row: each gap between anchors (and from the last anchor to `endY`, the
 * topology's last row) is split into `round(gap / 96)` equal rows.
 */
export function measureTopologyRows(props: {
  readonly anchorYs: readonly number[];
  readonly forcedYs?: readonly number[];
  readonly endY: number;
}): TopologyRows {
  const rowYs: number[] = [];
  const anchorRows: number[] = [];
  const pageEndY = props.endY;
  const points = [
    ...props.anchorYs.map((y, anchorIndex) => ({ y, anchorIndex })),
    ...(props.forcedYs ?? []).map((y) => ({ y, anchorIndex: undefined })),
  ].toSorted((first, second) => first.y - second.y);
  for (const [index, point] of points.entries()) {
    if (point.anchorIndex !== undefined) anchorRows[point.anchorIndex] = rowYs.length;
    rowYs.push(point.y);
    const nextPoint = points[index + 1];
    const gapEnd = nextPoint?.y ?? pageEndY;
    const gap = gapEnd - point.y;
    const rowCount =
      nextPoint === undefined
        ? Math.round(gap / topologyRowUnit)
        : Math.max(1, Math.round(gap / topologyRowUnit));
    for (let step = 1; step < rowCount; step += 1) {
      rowYs.push(point.y + (gap * step) / rowCount);
    }
    if (nextPoint === undefined && rowCount >= 1) {
      rowYs.push(gapEnd);
    }
  }
  return { rowYs, anchorRows };
}

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
