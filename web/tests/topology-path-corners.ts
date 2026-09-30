interface Point {
  readonly x: number;
  readonly y: number;
}

interface Segment {
  readonly startTangent: Point;
  readonly endTangent: Point;
}

function tangent(from: Point, to: Point): Point {
  return { x: to.x - from.x, y: to.y - from.y };
}

/** Inspect every join, including line-to-curve joins with a sharp initial tangent. */
export function sharpCornerCount(pathData: string): number {
  const tokens = pathData.match(/[MLHVC]|[-+]?(?:\d*\.?\d+)(?:[eE][-+]?\d+)?/gu) ?? [];
  let cursor = 0;
  let point: Point = { x: 0, y: 0 };
  let previous: Segment | undefined;
  let sharpCorners = 0;
  const nextNumber = (): number => {
    const token = tokens[cursor++];
    if (token === undefined || !Number.isFinite(Number(token)))
      throw new Error(`Unsupported SVG path: ${pathData}`);
    return Number(token);
  };
  const append = (segment: Segment): void => {
    if (previous !== undefined) {
      const incoming = previous.endTangent;
      const outgoing = segment.startTangent;
      const incomingLength = Math.hypot(incoming.x, incoming.y);
      const outgoingLength = Math.hypot(outgoing.x, outgoing.y);
      if (incomingLength > 0 && outgoingLength > 0) {
        const cosine =
          (incoming.x * outgoing.x + incoming.y * outgoing.y) / (incomingLength * outgoingLength);
        if (cosine < 0.2) sharpCorners += 1;
      }
    }
    previous = segment;
  };
  while (cursor < tokens.length) {
    const command = tokens[cursor++];
    if (command === "M") {
      point = { x: nextNumber(), y: nextNumber() };
      previous = undefined;
    } else if (command === "L" || command === "H" || command === "V") {
      const end = {
        x: command === "V" ? point.x : nextNumber(),
        y: command === "H" ? point.y : nextNumber(),
      };
      const direction = tangent(point, end);
      append({ startTangent: direction, endTangent: direction });
      point = end;
    } else if (command === "C") {
      const first = { x: nextNumber(), y: nextNumber() };
      const second = { x: nextNumber(), y: nextNumber() };
      const end = { x: nextNumber(), y: nextNumber() };
      append({ startTangent: tangent(point, first), endTangent: tangent(second, end) });
      point = end;
    } else {
      throw new Error(`Unsupported SVG path command ${String(command)}: ${pathData}`);
    }
  }
  return sharpCorners;
}
