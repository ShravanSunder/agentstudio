import { describe, expect, it } from "vitest";

import { measureFullPageTopologyGrid } from "../src/topology-lab/full-page-topology-layout";

describe("full-page topology grid measurement", () => {
  it("derives fixed-unit columns and rows from the container dimensions", () => {
    const ultrawideGrid = measureFullPageTopologyGrid(2992, 5200);
    expect(ultrawideGrid).toMatchObject({
      columnCount: 28,
      finalRow: 52,
      rowCount: 53,
      topPadding: 96,
    });
    expect(ultrawideGrid?.mainlineX).toBeCloseTo(2737.68, 6);

    const mediumGrid = measureFullPageTopologyGrid(960, 2120);
    expect(mediumGrid).toMatchObject({
      columnCount: 9,
      finalRow: 20,
      rowCount: 21,
      topPadding: 96,
    });
    expect(mediumGrid?.mainlineX).toBeCloseTo(878.4, 6);

    const narrowGrid = measureFullPageTopologyGrid(672, 1352);
    expect(narrowGrid).toMatchObject({
      columnCount: 6,
      finalRow: 12,
      rowCount: 13,
      topPadding: 96,
    });
    expect(narrowGrid?.mainlineX).toBe(608);
  });

  it("rejects containers that cannot hold the edge padding", () => {
    expect(measureFullPageTopologyGrid(0, 5200)).toBeUndefined();
    expect(measureFullPageTopologyGrid(960, 192)).toBeUndefined();
  });
});
