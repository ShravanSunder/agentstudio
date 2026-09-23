// The rail's corner language, recovered from the retired full-page topology
// (`localForkPath` / `localMergePath` in topology-lab/full-page-topology-paths.ts
// at 721d72458). A path is straight horizontal and vertical runs; every turn is
// one cubic bend with the old curve's control ratios, confined to a small
// square corner box so the turn reads as a crisp right angle with a softened
// corner:
//
//   fork  (horizontal into vertical): C (x0 + dx*0.9, y0 + dy*0.08) (x1, y0 + dy*0.1) (x1, y1)
//   merge (vertical into horizontal): the same bend traversed in reverse
//
// where dx = dy = the box size. Any other curve is not part of the language.

export interface RailPoint {
  readonly x: number;
  readonly y: number;
}

/** Along the horizontal run, the bend's control sits this far toward the corner. */
export const railBendHorizontalControlRatio = 0.9;
/** That control drops this fraction of the vertical run off the horizontal line. */
export const railBendHorizontalLiftRatio = 0.08;
/** The other control sits on the vertical run, this fraction of it past the corner. */
export const railBendVerticalControlRatio = 0.1;

/** Wide and laptop: each bend's square corner box, in px. Everything else is straight. */
export const railBendCornerSize = 16;
/** Phone: the corner box, scaled down with the phone gutter. */
export const phoneRailBendCornerSize = 12;

export function roundRailCoordinate(value: number): number {
  return Math.round(value * 100) / 100;
}

function samePoint(first: RailPoint, second: RailPoint): boolean {
  return Math.abs(first.x - second.x) < 0.01 && Math.abs(first.y - second.y) < 0.01;
}

function isCorner(previous: RailPoint, point: RailPoint, next: RailPoint): boolean {
  const turn =
    (point.x - previous.x) * (next.y - point.y) - (point.y - previous.y) * (next.x - point.x);
  return Math.abs(turn) >= 0.01;
}

/** Drops repeated and collinear points so every remaining interior point is a turn. */
export function railRouteCorners(points: readonly RailPoint[]): readonly RailPoint[] {
  const distinctPoints = points.filter(
    (point, index) => index === 0 || !samePoint(point, points[index - 1] ?? point),
  );
  return distinctPoints.filter((point, index) => {
    const previous = distinctPoints[index - 1];
    const next = distinctPoints[index + 1];
    return previous === undefined || next === undefined || isCorner(previous, point, next);
  });
}

/**
 * How much of one run a bend may use. A run at the start or end of the route
 * serves one bend and offers all of its length; a run between two bends
 * offers each half.
 */
function availableRunLength(runLength: number, sharedWithAnotherBend: boolean): number {
  return sharedWithAnotherBend ? runLength / 2 : runLength;
}

/**
 * A bend's square box: the corner size, shrunk only when a run it touches is
 * too short to give it that much.
 */
export function railBendBoxSize(props: {
  readonly cornerSize: number;
  readonly incomingRunLength: number;
  readonly incomingShared: boolean;
  readonly outgoingRunLength: number;
  readonly outgoingShared: boolean;
}): number {
  return Math.min(
    props.cornerSize,
    availableRunLength(props.incomingRunLength, props.incomingShared),
    availableRunLength(props.outgoingRunLength, props.outgoingShared),
  );
}

function formatPoint(point: RailPoint): string {
  return `${roundRailCoordinate(point.x)} ${roundRailCoordinate(point.y)}`;
}

function towards(from: RailPoint, to: RailPoint, distance: number): RailPoint {
  const length = Math.hypot(to.x - from.x, to.y - from.y);
  return length === 0
    ? from
    : {
        x: from.x + ((to.x - from.x) / length) * distance,
        y: from.y + ((to.y - from.y) / length) * distance,
      };
}

/**
 * Draws an orthogonal route (only horizontal and vertical runs between its
 * points) with the rail's tight bend at every turn.
 */
export function railBendPath(points: readonly RailPoint[], cornerSize: number): string {
  const corners = railRouteCorners(points);
  const start = corners[0];
  const end = corners.at(-1);
  if (start === undefined || end === undefined || corners.length < 2) {
    return "";
  }
  const commands = [`M ${formatPoint(start)}`];
  let current = start;
  const lastIndex = corners.length - 1;
  for (let index = 1; index < lastIndex; index += 1) {
    const previous = corners[index - 1];
    const corner = corners[index];
    const next = corners[index + 1];
    if (previous === undefined || corner === undefined || next === undefined) {
      continue;
    }
    const incomingVertical = Math.abs(previous.x - corner.x) < 0.01;
    const boxSize = railBendBoxSize({
      cornerSize,
      incomingRunLength: Math.hypot(corner.x - previous.x, corner.y - previous.y),
      incomingShared: index > 1,
      outgoingRunLength: Math.hypot(next.x - corner.x, next.y - corner.y),
      outgoingShared: index + 1 < lastIndex,
    });
    const bendStart = towards(corner, previous, boxSize);
    const bendEnd = towards(corner, next, boxSize);
    const horizontalEnd = incomingVertical ? bendEnd : bendStart;
    const verticalEnd = incomingVertical ? bendStart : bendEnd;
    const horizontalControl = {
      x: horizontalEnd.x + (corner.x - horizontalEnd.x) * railBendHorizontalControlRatio,
      y: corner.y + (verticalEnd.y - corner.y) * railBendHorizontalLiftRatio,
    };
    const verticalControl = {
      x: corner.x,
      y: corner.y + (verticalEnd.y - corner.y) * railBendVerticalControlRatio,
    };
    if (!samePoint(current, bendStart)) {
      commands.push(`L ${formatPoint(bendStart)}`);
    }
    const [firstControl, secondControl] = incomingVertical
      ? [verticalControl, horizontalControl]
      : [horizontalControl, verticalControl];
    commands.push(
      `C ${formatPoint(firstControl)} ${formatPoint(secondControl)} ${formatPoint(bendEnd)}`,
    );
    current = bendEnd;
  }
  if (!samePoint(current, end)) {
    commands.push(`L ${formatPoint(end)}`);
  }
  return commands.join(" ");
}
