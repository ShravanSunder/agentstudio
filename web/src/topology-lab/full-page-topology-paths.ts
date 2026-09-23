// The topology's corner geometry. A fork runs horizontally from its parent
// lane and bends down into its own column within one row; a merge bends from
// its column back into the parent within one row. With every fork and merge
// moving exactly one column, each bend spans one column × one row.

export function localForkPath(
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

export function localMergePath(
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
