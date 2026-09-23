import { describe, expect, it } from "vitest";

import {
  phoneRailBendCornerSize,
  railBendCornerSize,
  railBendPath,
} from "../src/chapter-rail/chapter-rail-bend-path";

// The retired topology's fork bend (topology-lab/full-page-topology-paths.ts at
// 721d72458), confined to a corner box: the rail keeps its control ratios but
// draws it only across the last `size` px of each run. Numbers are rounded to
// hundredths, as the rail writes them.
function hundredths(value: number): number {
  return Math.round(value * 100) / 100;
}

function retiredForkBend(fromX: number, toX: number, fromY: number, toY: number): string {
  return `C ${hundredths(fromX + (toX - fromX) * 0.9)} ${hundredths(fromY + (toY - fromY) * 0.08)} ${toX} ${hundredths(fromY + (toY - fromY) * 0.1)} ${toX} ${toY}`;
}

function retiredMergeBend(fromX: number, toX: number, fromY: number, toY: number): string {
  return `C ${fromX} ${hundredths(fromY + (toY - fromY) * 0.9)} ${hundredths(fromX + (toX - fromX) * 0.1)} ${hundredths(fromY + (toY - fromY) * 0.92)} ${toX} ${toY}`;
}

describe("railBendPath", () => {
  it("names a small square corner box for wide screens and a smaller one for phones", () => {
    // Assert
    expect(railBendCornerSize).toBe(16);
    expect(phoneRailBendCornerSize).toBe(12);
  });

  it("forks with the retired bend inside one corner box, then runs straight", () => {
    // Arrange: out of a dot at (0, 0), across two columns, down five rows.
    const size = railBendCornerSize;
    const route = [
      { x: 0, y: 0 },
      { x: 192, y: 0 },
      { x: 192, y: 480 },
    ];

    // Act
    const pathData = railBendPath(route, size);

    // Assert
    expect(pathData).toBe(
      `M 0 0 L ${192 - size} 0 ${retiredForkBend(192 - size, 192, 0, size)} L 192 480`,
    );
  });

  it("merges with the retired bend inside one corner box", () => {
    // Arrange: down a lane, then across into x = 0 on the last row.
    const size = railBendCornerSize;
    const route = [
      { x: 192, y: 0 },
      { x: 192, y: 480 },
      { x: 0, y: 480 },
    ];

    // Act
    const pathData = railBendPath(route, size);

    // Assert
    expect(pathData).toBe(
      `M 192 0 L 192 ${480 - size} ${retiredMergeBend(192, 192 - size, 480 - size, 480)} L 0 480`,
    );
  });

  it("draws a route without turns as one straight run", () => {
    // Arrange
    const route = [
      { x: 20, y: 300 },
      { x: 180, y: 300 },
    ];

    // Act / Assert
    expect(railBendPath(route, railBendCornerSize)).toBe("M 20 300 L 180 300");
  });

  it("shrinks the box only when a run between two turns is shorter than two boxes", () => {
    // Arrange: fork into a lane 10px away, then a long lane, then a 12px run.
    const route = [
      { x: 0, y: 0 },
      { x: 10, y: 0 },
      { x: 10, y: 300 },
      { x: 22, y: 300 },
    ];

    // Act
    const pathData = railBendPath(route, railBendCornerSize);

    // Assert: each bend is square, sized by the shorter run it touches.
    expect(pathData).toBe(
      `M 0 0 ${retiredForkBend(0, 10, 0, 10)} L 10 288 ${retiredMergeBend(10, 22, 288, 300)}`,
    );
  });
});
