import { describe, expect, it } from "vitest";

import { railBendPath } from "../src/chapter-rail/chapter-rail-bend-path";

// The retired topology's corner formulas (topology-lab/full-page-topology-paths.ts
// at 721d72458), kept here as the reference the rail must reproduce. Numbers
// are rounded to hundredths, as the rail writes them.
function hundredths(value: number): number {
  return Math.round(value * 100) / 100;
}

function retiredLocalForkPath(
  sourceX: number,
  targetX: number,
  forkY: number,
  arrivalY: number,
): string {
  return `M ${sourceX} ${forkY} C ${hundredths(sourceX + (targetX - sourceX) * 0.9)} ${hundredths(forkY + (arrivalY - forkY) * 0.08)} ${targetX} ${hundredths(forkY + (arrivalY - forkY) * 0.1)} ${targetX} ${arrivalY}`;
}

function retiredLocalMergePath(
  sourceX: number,
  targetX: number,
  approachY: number,
  mergeY: number,
): string {
  return `L ${targetX} ${approachY} C ${targetX} ${hundredths(approachY + (mergeY - approachY) * 0.9)} ${hundredths(targetX + (sourceX - targetX) * 0.1)} ${hundredths(approachY + (mergeY - approachY) * 0.92)} ${sourceX} ${mergeY}`;
}

describe("railBendPath", () => {
  it("forks with the retired topology's tight bend, one row down, then runs straight", () => {
    // Arrange: out of a dot at (0, 0), across one column, down five rows.
    const route = [
      { x: 0, y: 0 },
      { x: 96, y: 0 },
      { x: 96, y: 480 },
    ];

    // Act
    const pathData = railBendPath(route, 96);

    // Assert
    expect(pathData).toBe(`${retiredLocalForkPath(0, 96, 0, 96)} L 96 480`);
  });

  it("merges with the retired topology's tight bend from the row above", () => {
    // Arrange: down a lane, then across into x = 0 on the last row.
    const route = [
      { x: 96, y: 0 },
      { x: 96, y: 480 },
      { x: 0, y: 480 },
    ];

    // Act
    const pathData = railBendPath(route, 96);

    // Assert
    expect(pathData).toBe(`M 96 0 ${retiredLocalMergePath(0, 96, 384, 480)}`);
  });

  it("draws a route without turns as one straight run", () => {
    // Arrange
    const route = [
      { x: 20, y: 300 },
      { x: 180, y: 300 },
    ];

    // Act / Assert
    expect(railBendPath(route, 96)).toBe("M 20 300 L 180 300");
  });

  it("shares a run between two bends and never lets a bend exceed one row", () => {
    // Arrange: fork, a long lane, then turn into a glass edge.
    const route = [
      { x: 0, y: 0 },
      { x: 96, y: 0 },
      { x: 96, y: 1000 },
      { x: 192, y: 1000 },
    ];

    // Act
    const pathData = railBendPath(route, 96);

    // Assert: fork bend ends one row down; the entry bend starts one row up.
    expect(pathData).toBe(
      "M 0 0 C 86.4 7.68 96 9.6 96 96 L 96 904 C 96 990.4 105.6 992.32 192 1000",
    );
  });
});
