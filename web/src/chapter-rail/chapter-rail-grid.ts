// The rail's git-graph grid, recovered from the retired full-page topology
// (topology-lab/full-page-topology-model.ts at 721d72458): rows on a regular
// pitch with exactly one dot each, and lanes in columns centered in the left
// gutter. Chapter anchors must stay level with their dots, so rows are
// piecewise uniform: every anchor is a row, and each gap between anchors is
// split into whole rows as close to the base pitch as possible.

/** Wide and laptop row pitch: the old topology's row unit. */
export const railRowUnit = 96;

/**
 * Phone row pitch. Phone type and gutters run about three quarters of desktop,
 * and 72px keeps roughly the same dots per screen (844 / 72 ≈ 11.7) as desktop
 * (1080 / 96 ≈ 11.3) instead of spreading them out.
 */
export const phoneRailRowUnit = 72;

/** Lane spacing: the old topology's column unit. Narrower gutters scale it down. */
export const railColumnUnit = 96;

/** Wide and laptop: the main lane plus up to two worktree lanes. */
export const wideRailColumnCount = 3;

/** Wide and laptop lanes never sit closer than this; a narrow gutter drops lanes instead. */
export const minimumWideRailColumnSpacing = 48;

/** Phone: the main lane plus one worktree lane, however narrow the gutter. */
export const phoneRailColumnCount = 2;

export interface RailRows {
  readonly rowYs: readonly number[];
  /** The row index of each anchor, in anchor order. */
  readonly anchorRowIndexes: readonly number[];
}

/**
 * Rows from the first anchor to `pageEnd`. Each anchor is a row; the gap to
 * the next anchor (and from the last anchor to the page end) is split into
 * `round(gap / rowUnit)` equal rows.
 */
export function layoutRailRows(props: {
  readonly anchorYs: readonly number[];
  readonly pageEnd: number;
  readonly rowUnit: number;
}): RailRows {
  const rowYs: number[] = [];
  const anchorRowIndexes: number[] = [];
  for (const [index, anchorY] of props.anchorYs.entries()) {
    anchorRowIndexes.push(rowYs.length);
    rowYs.push(anchorY);
    const nextAnchorY = props.anchorYs[index + 1];
    const gapEnd = nextAnchorY ?? props.pageEnd;
    const gap = gapEnd - anchorY;
    const rowCount =
      nextAnchorY === undefined
        ? Math.round(gap / props.rowUnit)
        : Math.max(1, Math.round(gap / props.rowUnit));
    for (let step = 1; step < rowCount; step += 1) {
      rowYs.push(anchorY + (gap * step) / rowCount);
    }
    if (nextAnchorY === undefined && rowCount >= 1) {
      rowYs.push(gapEnd);
    }
  }
  return { rowYs, anchorRowIndexes };
}

/** The distance from a row to the next one (the last row reuses the previous pitch). */
export function railRowPitchAt(
  rowYs: readonly number[],
  rowIndex: number,
  rowUnit: number,
): number {
  const rowY = rowYs[rowIndex];
  const nextY = rowYs[rowIndex + 1];
  const previousY = rowYs[rowIndex - 1];
  if (rowY !== undefined && nextY !== undefined) {
    return nextY - rowY;
  }
  if (rowY !== undefined && previousY !== undefined) {
    return rowY - previousY;
  }
  return rowUnit;
}

/**
 * Lane x positions, centered in the gutter like the old topology's
 * `centeredTopologyColumnXs`. Column 0 is the main lane.
 */
export function layoutRailColumns(props: {
  readonly gutterWidth: number;
  readonly maximumColumnCount: number;
  readonly minimumSpacing: number;
}): readonly number[] {
  const columnCount = Math.max(
    1,
    Math.min(props.maximumColumnCount, Math.floor(props.gutterWidth / props.minimumSpacing)),
  );
  const spacing = Math.min(railColumnUnit, props.gutterWidth / columnCount);
  const firstX = (props.gutterWidth - (columnCount - 1) * spacing) / 2;
  return Array.from({ length: columnCount }, (_, column) => firstX + column * spacing);
}

export interface RailWorktreeRowClaim {
  readonly laneId: string;
  /** Higher wins a tie, as the old topology preferred worktree lanes over main. */
  readonly priority: number;
  /** Rows where this lane runs straight down its column and can carry a dot. */
  readonly eligibleRowIndexes: ReadonlySet<number>;
}

export const mainRailLaneId = "main";

/**
 * One owner per row, like the old `assignTopologyRowOwners`: reserved rows
 * keep their owner; every other row goes to the least-used candidate among
 * main and the worktree lanes that can carry a dot there, ties to the higher
 * priority.
 */
export function assignRailRowOwners(props: {
  readonly rowCount: number;
  readonly reservedRowOwners: ReadonlyMap<number, string>;
  readonly worktreeClaims: readonly RailWorktreeRowClaim[];
}): readonly string[] {
  const assignedCounts = new Map<string, number>();
  return Array.from({ length: props.rowCount }, (_, rowIndex) => {
    const reservedOwner = props.reservedRowOwners.get(rowIndex);
    if (reservedOwner !== undefined) {
      return reservedOwner;
    }
    const candidates = [
      ...props.worktreeClaims
        .filter((claim) => claim.eligibleRowIndexes.has(rowIndex))
        .map((claim) => ({ laneId: claim.laneId, priority: claim.priority })),
      { laneId: mainRailLaneId, priority: 0 },
    ].toSorted((left, right) => {
      const countDifference =
        (assignedCounts.get(left.laneId) ?? 0) - (assignedCounts.get(right.laneId) ?? 0);
      return countDifference === 0 ? right.priority - left.priority : countDifference;
    });
    const owner = candidates[0]?.laneId ?? mainRailLaneId;
    assignedCounts.set(owner, (assignedCounts.get(owner) ?? 0) + 1);
    return owner;
  });
}
