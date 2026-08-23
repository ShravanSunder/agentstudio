import { describe, expect, it } from "vitest";

import { authoredTopologyRoutes } from "../src/topology-lab/full-page-topology-contract";
import {
  assignTopologyRowOwners,
  assignWorktreeLanes,
  centeredTopologyColumnXs,
  measureFullPageTopologyGrid,
  resolveTopologyGlassBand,
} from "../src/topology-lab/full-page-topology-model";

const routeIdsByVariant = (variant: "compact" | "expanded" | "standard"): string[] =>
  authoredTopologyRoutes
    .filter((route) => route.variants.includes(variant))
    .map((route) => route.id);

describe("responsive topology composition", () => {
  it("preserves the full worktree story at standard width and a continuous compact story", () => {
    expect(routeIdsByVariant("compact")).toEqual([
      "worktree-a",
      "worktree-c",
      "worktree-d",
      "worktree-e",
    ]);
    expect(routeIdsByVariant("standard")).toEqual([
      "worktree-a",
      "worktree-b",
      "worktree-c",
      "worktree-d",
      "worktree-e",
      "worktree-f",
      "worktree-g",
    ]);
    expect(routeIdsByVariant("expanded")).toEqual(routeIdsByVariant("standard"));
  });
});

describe("topology row ownership", () => {
  it("distributes unreserved row dots across active worktrees and main", () => {
    const owners = assignTopologyRowOwners({
      reservedRows: new Set([0, 2, 4, 6, 10, 11, 14, 16, 17, 18, 20]),
      rowCount: 21,
      worktrees: [
        { endRow: 18, id: "a", priority: 1, startRow: 2 },
        { endRow: 10, id: "b", priority: 2, startRow: 4 },
        { endRow: 20, id: "c", priority: 3, startRow: 6 },
        { endRow: 16, id: "d", priority: 4, startRow: 14 },
        { endRow: 17, id: "e", priority: 2, startRow: 11 },
      ],
    });

    expect(owners).toHaveLength(10);
    expect(new Set(owners.map((owner) => owner.row)).size).toBe(owners.length);
    expect(new Set(owners.map((owner) => owner.ownerId))).toEqual(
      new Set(["main", "a", "b", "c", "d", "e"]),
    );
    expect(owners.filter((owner) => owner.ownerId === "main").length).toBeLessThan(owners.length);
  });

  it("uses main only when no worktree is active", () => {
    expect(
      assignTopologyRowOwners({
        reservedRows: new Set([0, 3]),
        rowCount: 4,
        worktrees: [],
      }),
    ).toEqual([
      { ownerId: "main", row: 1 },
      { ownerId: "main", row: 2 },
    ]);
  });
});

describe("side-specific worktree lane allocation", () => {
  it("uses the nearest free column when every worktree forks from main", () => {
    expect(
      assignWorktreeLanes(
        [
          { endKind: "open", endRow: 18, forkRow: 2, id: "a" },
          { endKind: "merge", endRow: 10, forkRow: 4, id: "b" },
          { endKind: "merge", endRow: 20, forkRow: 8, id: "c" },
          { endKind: "open", endRow: 16, forkRow: 14, id: "d" },
          { endKind: "open", endRow: 17, forkRow: 11, id: "e" },
        ],
        4,
      ),
    ).toEqual([
      { id: "a", lane: 0 },
      { id: "b", lane: 1 },
      { id: "c", lane: 2 },
      { id: "e", lane: 1 },
      { id: "d", lane: 3 },
    ]);
  });

  it("reuses a nearer released column instead of skipping it", () => {
    expect(
      assignWorktreeLanes(
        [
          { endKind: "merge", endRow: 6, forkRow: 2, id: "a" },
          { endKind: "merge", endRow: 10, forkRow: 4, id: "b" },
          { endKind: "open", endRow: 12, forkRow: 7, id: "c" },
        ],
        4,
      ),
    ).toEqual([
      { id: "a", lane: 0 },
      { id: "b", lane: 1 },
      { id: "c", lane: 0 },
    ]);
  });

  it("sorts allocation by fork chronology instead of source order", () => {
    expect(
      assignWorktreeLanes(
        [
          { endKind: "open", endRow: 20, forkRow: 10, id: "late" },
          { endKind: "merge", endRow: 5, forkRow: 2, id: "early" },
        ],
        3,
      ),
    ).toEqual([
      { id: "early", lane: 0 },
      { id: "late", lane: 0 },
    ]);
  });

  it("does not release a lane when the illustrated worktree remains open", () => {
    expect(
      assignWorktreeLanes(
        [
          { endKind: "open", endRow: 6, forkRow: 2, id: "open" },
          { endKind: "merge", endRow: 10, forkRow: 7, id: "later" },
        ],
        3,
      ),
    ).toEqual([
      { id: "open", lane: 0 },
      { id: "later", lane: 1 },
    ]);
  });

  it("rejects two forks competing for the same physical row", () => {
    expect(
      assignWorktreeLanes(
        [
          { endKind: "open", endRow: 12, forkRow: 2, id: "a" },
          { endKind: "merge", endRow: 10, forkRow: 2, id: "b" },
        ],
        3,
      ),
    ).toBeUndefined();
  });
});

describe("full-page topology grid measurement", () => {
  it("selects capacity tiers at exact centered-frame gutter thresholds", () => {
    expect(
      measureFullPageTopologyGrid({
        frameLeft: 191.5,
        frameRight: 1631.5,
        height: 5200,
        width: 1823,
      }),
    ).toBeUndefined();

    expect(
      measureFullPageTopologyGrid({
        frameLeft: 192,
        frameRight: 1632,
        height: 5200,
        width: 1824,
      }),
    ).toMatchObject({
      columnCapacity: 2,
      variant: "compact",
    });

    expect(
      measureFullPageTopologyGrid({
        frameLeft: 288,
        frameRight: 1728,
        height: 5200,
        width: 2016,
      }),
    ).toMatchObject({ columnCapacity: 3, variant: "standard" });

    expect(
      measureFullPageTopologyGrid({
        frameLeft: 384,
        frameRight: 1824,
        height: 5200,
        width: 2208,
      }),
    ).toMatchObject({ columnCapacity: 4, variant: "expanded" });

    expect(
      measureFullPageTopologyGrid({
        frameLeft: 680,
        frameRight: 2120,
        height: 5200,
        width: 2800,
      }),
    ).toMatchObject({ columnCapacity: 4, variant: "expanded" });
  });

  it("measures the two gutter capacities independently and selects the smaller tier", () => {
    expect(
      measureFullPageTopologyGrid({
        frameLeft: 288,
        frameRight: 1600,
        height: 5200,
        width: 2000,
      }),
    ).toMatchObject({
      columnCapacity: 3,
      leftColumnCapacity: 3,
      rightColumnCapacity: 4,
      variant: "standard",
    });
  });

  it("centers only the required columns at an exact 96px pitch", () => {
    expect(centeredTopologyColumnXs({ columnCount: 3, gutterEnd: 480, gutterStart: 0 })).toEqual([
      144, 240, 336,
    ]);
    expect(centeredTopologyColumnXs({ columnCount: 4, gutterEnd: 480, gutterStart: 0 })).toEqual([
      96, 192, 288, 384,
    ]);
    expect(
      centeredTopologyColumnXs({ columnCount: 2, gutterEnd: 1920, gutterStart: 1680 }),
    ).toEqual([1752, 1848]);
    expect(
      centeredTopologyColumnXs({ columnCount: 4, gutterEnd: 383, gutterStart: 0 }),
    ).toBeUndefined();
  });

  it("keeps row geometry independent from centered column capacity", () => {
    const compactGrid = measureFullPageTopologyGrid({
      frameLeft: 288,
      frameRight: 1712,
      height: 5200,
      width: 2000,
    });
    expect(compactGrid?.rowCount).toBe(53);
    expect(compactGrid?.topPadding).toBe(96);
  });

  it("projects the first and last glass surfaces onto authored grid rows", () => {
    const grid = measureFullPageTopologyGrid({
      frameLeft: 576,
      frameRight: 1424,
      height: 5200,
      requestedTopPadding: 96,
      width: 2000,
    });
    if (grid === undefined) {
      throw new Error("Expected an eligible topology grid");
    }

    expect(
      resolveTopologyGlassBand({
        glassSurfaces: [
          { bottom: 672, top: 480 },
          { bottom: 1920, top: 1728 },
          { bottom: 2688, top: 2496 },
          { bottom: 2784, top: 2592 },
        ],
        grid,
      }),
    ).toEqual({ firstCrossRow: 5, lastCrossRow: 27 });
  });

  it("rejects glass geometry that cannot hold the authored 20-slot composition", () => {
    const grid = measureFullPageTopologyGrid({
      frameLeft: 576,
      frameRight: 1424,
      height: 5200,
      requestedTopPadding: 96,
      width: 2000,
    });
    if (grid === undefined) {
      throw new Error("Expected an eligible topology grid");
    }

    expect(
      resolveTopologyGlassBand({
        glassSurfaces: [
          { bottom: 672, top: 480 },
          { bottom: 2496, top: 2304 },
        ],
        grid,
      }),
    ).toBeUndefined();
  });
});
