import { describe, expect, it } from "vitest";

import {
  composeFullPageTopology,
  topologyHeroLaneMaximumTravel,
  topologyHeroLaneMinimumTravel,
  topologyStackedDropCornerInset,
  topologyStackedLayoutBreakpointWidth,
  topologyStackedVerticalEntry,
  type TopologyAnchorMeasurement,
  type TopologyComposition,
  type TopologyPageMeasurement,
  type TopologyRect,
} from "../src/topology-lab/full-page-topology-composition";
import {
  assignTopologyRowOwners,
  topologyColumnUnitFor,
  topologyColumnUnitMaximum,
  topologyColumnUnitMinimum,
  topologyMaximumLaneCount,
  topologyRowUnit,
} from "../src/topology-lab/full-page-topology-model";
import { localForkPath, localMergePath } from "../src/topology-lab/full-page-topology-paths";
import { planWorktreeLanes } from "../src/topology-lab/topology-lane-planning";

function rect(left: number, top: number, width: number, height: number): TopologyRect {
  return { left, top, width, height };
}

function clamp(value: number, minimum: number, maximum: number): number {
  return Math.min(Math.max(value, minimum), maximum);
}

interface TopologyPageFixture {
  readonly page: TopologyPageMeasurement;
  /** Text the topology must never cross: eyebrows and copy blocks outside glass. */
  readonly textRects: readonly TopologyRect[];
}

/**
 * The home page at a viewport width, from the site's CSS: the centered site
 * frame (≥ 1024px), `--spacing-page-inline`, and `--spacing-rail-gutter`.
 */
function homePageAt(viewportWidth: number): TopologyPageFixture {
  const phone = viewportWidth < 620;
  const stacked = viewportWidth < topologyStackedLayoutBreakpointWidth;
  const frameLeft =
    viewportWidth >= 1024 ? (viewportWidth - Math.min(viewportWidth - 32, 1440)) / 2 : 0;
  const pageInline = phone ? 18 : clamp(viewportWidth * 0.033, 24, 72);
  const railGutter = phone ? 22 : clamp(viewportWidth * 0.045, 40, 80);
  const contentLeft = frameLeft + pageInline + railGutter;
  const contentWidth = viewportWidth - frameLeft - pageInline - contentLeft;
  const heroCopyLeft =
    contentLeft + (viewportWidth >= 1024 ? clamp(viewportWidth * 0.026, 24, 56) : 0);
  const heroFrame = rect(contentLeft, 540, contentWidth, (contentWidth * 10) / 16);
  const anchors: TopologyAnchorMeasurement[] = [
    {
      id: "hero",
      targetEdge: "top",
      rect: rect(heroCopyLeft, 110, 400, 12),
      surface: heroFrame,
      media: heroFrame,
      copyBlock: rect(heroCopyLeft, 110, contentWidth - 60, 380),
    },
  ];
  const firstChapterTop = heroFrame.top + heroFrame.height + 250;
  for (const index of [0, 1, 2, 3, 4]) {
    const anchorTop = firstChapterTop + index * 760;
    // Stacked (< lg): one glass holds the title at the top, then the stage.
    anchors.push(
      stacked
        ? {
            id: `chapter-${index + 1}`,
            rect: rect(contentLeft + 33, anchorTop, 250, 34),
            surface: rect(contentLeft, anchorTop - 32, contentWidth, 640),
            media: rect(contentLeft + 5, anchorTop + 60, contentWidth - 10, 320),
            copyBlock: rect(contentLeft + 33, anchorTop, contentWidth - 66, 34),
          }
        : {
            id: `chapter-${index + 1}`,
            rect: rect(contentLeft + 54, anchorTop, 90, 12),
            surface: rect(contentLeft, anchorTop - 54, contentWidth, 620),
            media: rect(contentLeft + contentWidth * 0.37, anchorTop - 40, contentWidth * 0.6, 440),
            copyBlock: rect(contentLeft + 54, anchorTop, 300, 110),
          },
    );
  }
  const lastAnchor = anchors.at(-1);
  const page = {
    viewportWidth,
    height: (lastAnchor?.rect.top ?? 0) + 1660,
    anchors,
  };
  const textRects = anchors.flatMap((anchor) =>
    stacked || anchor.id === "hero"
      ? [anchor.rect, anchor.copyBlock ?? anchor.rect]
      : [anchor.rect],
  );
  return { page, textRects };
}

function composed(fixture: TopologyPageFixture): TopologyComposition {
  const composition = composeFullPageTopology(fixture.page);
  if (composition === undefined) {
    throw new Error("Expected a composed topology");
  }
  return composition;
}

describe("step pill attachment", () => {
  it("keeps the title chapter dot when the desktop pill follows its title", () => {
    const fixture = homePageAt(1600);
    const firstChapter = fixture.page.anchors[1];
    if (firstChapter === undefined) throw new Error("First chapter is missing");
    const pill = rect(
      firstChapter.rect.left,
      firstChapter.rect.top + firstChapter.rect.height + 14,
      300,
      40,
    );
    const anchors = fixture.page.anchors.map((anchor, index) =>
      index === 1 ? { ...anchor, stepPill: pill } : anchor,
    );
    const composition = composeFullPageTopology({ ...fixture.page, anchors });
    expect(composition?.rows.find((row) => row.anchorId === firstChapter.id)?.kind).toBe("chapter");
    expect(
      composition?.routes.find((route) => route.anchorId === firstChapter.id)?.targetPoint,
    ).toEqual({ x: pill.left, y: pill.top + 20 });
  });
  it("enters the hero app-frame top edge even on desktop", () => {
    const fixture = homePageAt(1600);
    const hero = fixture.page.anchors[0];
    const route = composed(fixture).routes.find((candidate) => candidate.anchorId === "hero");
    expect(route?.targetEdge).toBe("top");
    expect(route?.targetPoint?.y).toBe(hero?.surface?.top);
  });
  it("enters a non-hero anchor's declared top edge on desktop", () => {
    const fixture = homePageAt(1600);
    const chapter = fixture.page.anchors[1];
    if (chapter?.surface === undefined) throw new Error("First chapter glass is missing");
    const anchors = fixture.page.anchors.map((anchor, index) =>
      index === 1 ? { ...anchor, targetEdge: "top" as const } : anchor,
    );
    const route = composeFullPageTopology({ ...fixture.page, anchors })?.routes.find(
      (candidate) => candidate.anchorId === chapter.id,
    );
    expect(route?.targetEdge).toBe("top");
    expect(route?.targetPoint?.y).toBe(chapter.surface.top);
    expect(route?.targetPoint?.x).toBe(chapter.surface.left + topologyStackedDropCornerInset);
  });
  for (const width of [390, 820, 1280, 1600]) {
    it(`uses the pill on desktop and glass top on stacked layouts at ${width}px`, () => {
      const fixture = homePageAt(width);
      const firstChapter = fixture.page.anchors[1];
      if (firstChapter?.surface === undefined) throw new Error("First chapter glass is missing");
      const pill = rect(
        firstChapter.surface.left + (width < 1024 ? 33 : 54),
        firstChapter.surface.top - 56,
        300,
        40,
      );
      const anchors = fixture.page.anchors.map((anchor, index) =>
        index === 1 ? { ...anchor, stepPill: pill } : anchor,
      );
      const composition = composeFullPageTopology({ ...fixture.page, anchors });
      if (composition === undefined) throw new Error("Pill topology did not compose");
      const route = composition.routes.find((candidate) => candidate.anchorId === firstChapter.id);
      if (width >= 1024) {
        expect(route?.targetPoint).toEqual({ x: pill.left, y: pill.top + pill.height / 2 });
        expect(composition.rowYs).toContain(pill.top + pill.height / 2);
      } else {
        expect(route?.targetEdge).toBe("top");
        expect(route?.targetPoint?.y).toBe(firstChapter.surface.top);
        expect(composition.rowYs).not.toContain(pill.top + pill.height / 2);
      }
      expect(composition.mainlineX).toBe(composed(fixture).mainlineX);
    });
  }
});

interface PathPoint {
  readonly x: number;
  readonly y: number;
}

interface PathCommand {
  readonly command: string;
  readonly from: PathPoint;
  readonly points: readonly PathPoint[];
}

function pathCommands(pathData: string): readonly PathCommand[] {
  const tokens = pathData.trim().split(/[\s,]+/u);
  const commands: PathCommand[] = [];
  let current: PathPoint = { x: Number.NaN, y: Number.NaN };
  let index = 0;
  while (index < tokens.length) {
    const command = tokens[index] ?? "";
    const coordinateCount = command === "C" ? 6 : 2;
    const values = tokens.slice(index + 1, index + 1 + coordinateCount).map(Number);
    const points = Array.from({ length: coordinateCount / 2 }, (_, pointIndex) => ({
      x: values[pointIndex * 2] ?? Number.NaN,
      y: values[pointIndex * 2 + 1] ?? Number.NaN,
    }));
    commands.push({ command, from: current, points });
    current = points.at(-1) ?? current;
    index += 1 + coordinateCount;
  }
  return commands;
}

function samplePoints(pathData: string): readonly PathPoint[] {
  return pathCommands(pathData)
    .slice(1)
    .flatMap((command) => {
      const [first, second, end] =
        command.command === "C"
          ? command.points
          : [command.from, command.points[0] ?? command.from, command.points[0] ?? command.from];
      if (first === undefined || second === undefined || end === undefined) {
        return [];
      }
      return Array.from({ length: 51 }, (_, step) => {
        const t = step / 50;
        const u = 1 - t;
        const weigh = (a: number, b: number, c: number, d: number): number =>
          u * u * u * a + 3 * u * u * t * b + 3 * u * t * t * c + t * t * t * d;
        return {
          x: weigh(command.from.x, first.x, second.x, end.x),
          y: weigh(command.from.y, first.y, second.y, end.y),
        };
      });
    });
}

const viewportWidths = [390, 800, 1280, 1920, 2560, 3440] as const;

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

describe("gutter columns", () => {
  it("scales the column unit with the viewport inside its clamp", () => {
    for (const width of [390, 768, 1024, 1280, 1440, 1920, 2560]) {
      const unit = topologyColumnUnitFor(width);
      expect(unit).toBeGreaterThanOrEqual(topologyColumnUnitMinimum);
      expect(unit).toBeLessThanOrEqual(topologyColumnUnitMaximum);
    }
    expect(topologyColumnUnitFor(1280)).toBeGreaterThan(topologyColumnUnitFor(1024));
  });

  it("limits lane columns when the midpoint leaves too few rows after the last glass", () => {
    // Act
    const laneCounts = viewportWidths.map((width) => composed(homePageAt(width)).laneXs.length);

    // Assert
    expect(laneCounts).toEqual([0, 0, 0, 2, 2, 2]);
    expect(Math.max(...laneCounts)).toBeLessThanOrEqual(topologyMaximumLaneCount);
  });

  it("forks the hero's lanes from the middle of the hero copy on wide screens", () => {
    for (const width of [1920, 2560, 3440]) {
      // Arrange
      const fixture = homePageAt(width);
      const heroCopy = fixture.page.anchors[0]?.copyBlock;
      if (heroCopy === undefined) {
        throw new Error("Fixture hero has no copy block");
      }

      // Act
      const composition = composed(fixture);

      // Assert
      const firstLane = composition.routes.find((route) => route.kind === "worktree");
      expect(firstLane?.startY).toBeGreaterThanOrEqual(heroCopy.top + heroCopy.height / 4);
      expect(firstLane?.startY).toBeLessThanOrEqual(heroCopy.top + (heroCopy.height * 3) / 4);
    }
  });

  it("runs the lane next to the content two to four rows before its hero port", () => {
    for (const width of [1920, 2560, 3440]) {
      // Act
      const composition = composed(homePageAt(width));

      // Assert
      const lanes = composition.routes.filter((route) => route.kind === "worktree");
      const outermost = lanes.at(-1);
      const heroPort = composition.routes.find((route) => route.anchorId === "hero");
      const forkRow = composition.rowYs.indexOf(outermost?.startY ?? Number.NaN);
      const portRow = composition.rowYs.indexOf(heroPort?.startY ?? Number.NaN);
      expect(forkRow).toBeGreaterThanOrEqual(0);
      expect(portRow - forkRow, String(width)).toBeGreaterThanOrEqual(
        topologyHeroLaneMinimumTravel,
      );
      expect(portRow - forkRow).toBeLessThanOrEqual(topologyHeroLaneMaximumTravel);
      expect(heroPort?.parentColumn).toBe(outermost?.column);
    }
  });

  it("marks each merge with the lane merging in and sits it on the receiving lane", () => {
    for (const width of [1920, 2560]) {
      // Act
      const composition = composed(homePageAt(width));

      // Assert
      const merges = composition.rows.filter((dot) => dot.kind === "merge");
      expect(merges).toHaveLength(composition.laneXs.length);
      const columnXs = [composition.mainlineX, ...composition.laneXs];
      for (const merge of merges) {
        expect(merge.incomingAccent).toBeDefined();
        expect(merge.incomingAccent).not.toBe(merge.accent);
        // The receiving lane is one column left of the lane that merges in.
        const receivingColumn = columnXs.indexOf(merge.x);
        expect(receivingColumn).toBeGreaterThanOrEqual(0);
        expect(receivingColumn).toBeLessThan(columnXs.length - 1);
      }
    }
  });

  it("anchors the mainline from the content and leaves any wider gutter empty", () => {
    for (const width of viewportWidths) {
      // Arrange
      const fixture = homePageAt(width);

      // Act
      const composition = composed(fixture);

      // Assert: the mainline sits (lanes + 1) columns left of the content edge
      // (the glass's left edge on wide screens, the drop point where glasses stack).
      const hero = fixture.page.anchors[0];
      const contentX =
        width < topologyStackedLayoutBreakpointWidth
          ? (hero?.surface?.left ?? 0) + topologyStackedDropCornerInset
          : (hero?.surface?.left ?? 0);
      expect(
        Math.abs(
          composition.mainlineX -
            (contentX - (composition.laneXs.length + 1) * composition.columnUnit),
        ),
      ).toBeLessThanOrEqual(1);
      // Nothing is drawn left of the mainline.
      for (const dot of composition.rows) {
        expect(dot.x).toBeGreaterThanOrEqual(composition.mainlineX);
      }
      for (const route of composition.routes) {
        for (const point of samplePoints(route.pathData)) {
          expect(point.x).toBeGreaterThanOrEqual(composition.mainlineX - 0.01);
        }
      }
    }
  });

  it("puts the outermost lane in the column next to the content, one unit apart", () => {
    for (const width of viewportWidths) {
      // Act
      const composition = composed(homePageAt(width));

      // Assert
      const columnXs = [composition.mainlineX, ...composition.laneXs];
      for (const [index, x] of columnXs.slice(1).entries()) {
        expect(x - (columnXs[index] ?? 0)).toBeCloseTo(composition.columnUnit, 6);
      }
      expect(composition.mainlineX).toBeGreaterThanOrEqual(16);
    }
  });
});

describe("composed topology", () => {
  for (const width of viewportWidths) {
    describe(`at ${width}px`, () => {
      const fixture = homePageAt(width);
      const composition = composed(fixture);

      it("runs the mainline from the top of the page", () => {
        expect(composition.mainlinePath).toMatch(
          new RegExp(`^M ${composition.mainlineX} 0 L `, "u"),
        );
      });

      it("gives every row exactly one dot, on a lane column", () => {
        const columnXs = [composition.mainlineX, ...composition.laneXs];
        expect(composition.rows.map((dot) => dot.row)).toEqual(
          composition.rowYs.map((_, row) => row),
        );
        for (const dot of composition.rows) {
          expect(columnXs).toContain(dot.x);
        }
        for (const [index, y] of composition.rowYs.slice(1).entries()) {
          const pitch = y - (composition.rowYs[index] ?? 0);
          expect(pitch).toBeGreaterThanOrEqual(topologyRowUnit * 0.75);
          expect(pitch).toBeLessThanOrEqual(topologyRowUnit * 1.25);
        }
      });

      it("keeps each chapter's mainline dot level with its eyebrow", () => {
        for (const anchor of fixture.page.anchors) {
          const dot = composition.rows.find((row) => row.anchorId === anchor.id);
          expect(dot?.kind).toBe("chapter");
          expect(dot?.x).toBe(composition.mainlineX);
          expect(dot?.y).toBeCloseTo(anchor.rect.top + anchor.rect.height / 2, 6);
        }
      });

      it("moves every fork and merge exactly one column, with no longer horizontal run", () => {
        for (const route of composition.routes) {
          expect(route.column).toBe(route.parentColumn + 1);
          for (const command of pathCommands(route.pathData).slice(1)) {
            const end = command.points.at(-1) ?? command.from;
            const heroTopInset =
              route.anchorId === "hero" && width >= topologyStackedLayoutBreakpointWidth
                ? topologyStackedDropCornerInset
                : 0;
            expect(Math.abs(end.x - command.from.x)).toBeLessThanOrEqual(
              composition.columnUnit + heroTopInset + 0.01,
            );
          }
        }
      });

      it("enters each target with a one-column branch whose last point meets the edge", () => {
        const attaches = composition.routes.filter((route) => route.kind === "attach");
        expect(attaches.map((route) => route.anchorId)).toEqual(
          fixture.page.anchors.map((anchor) => anchor.id),
        );
        for (const attach of attaches) {
          const commands = pathCommands(attach.pathData);
          const start = commands[0]?.points[0];
          const end = commands.at(-1)?.points.at(-1);
          if (start === undefined || end === undefined) {
            throw new Error("Attach branch is empty");
          }
          expect(attach.accent).toBe("port");
          const heroTopInset =
            attach.anchorId === "hero" && width >= topologyStackedLayoutBreakpointWidth
              ? topologyStackedDropCornerInset
              : 0;
          expect(end.x - start.x).toBeCloseTo(composition.columnUnit + heroTopInset, 6);
          expect(end.y - start.y).toBeGreaterThan(0);
          expect(end.y - start.y).toBeLessThanOrEqual(topologyRowUnit * 1.25);
          // Wide ports turn with the retired merge bend onto the target row and
          // run into the left edge; stacked-glass ports drop with the fork bend.
          expect(attach.pathData).toBe(
            attach.targetEdge === "left"
              ? [`M ${start.x} ${start.y}`, ...localMergePath(end.x, start.x, start.y, end.y)].join(
                  " ",
                )
              : [
                  ...localForkPath(
                    start.x,
                    end.x,
                    start.y,
                    end.y - Math.min(topologyStackedVerticalEntry, (end.y - start.y) / 2),
                  ),
                  `L ${end.x} ${end.y}`,
                ].join(" "),
          );
          const anchor = fixture.page.anchors.find((candidate) => candidate.id === attach.anchorId);
          if (attach.targetEdge === "top") {
            // Stacked ports enter the glass's top edge straight down, clear of its corner.
            expect(width < topologyStackedLayoutBreakpointWidth || attach.anchorId === "hero").toBe(
              true,
            );
            const lastRun = pathCommands(attach.pathData).at(-1);
            expect(lastRun?.command).toBe("L");
            expect(lastRun?.from.x).toBe(end.x);
            expect(end.x - (anchor?.surface?.left ?? 0)).toBeGreaterThanOrEqual(16 + 8);
          }
          const edge =
            attach.targetEdge === "left"
              ? { x: anchor?.surface?.left ?? Number.NaN, y: end.y }
              : { x: end.x, y: anchor?.surface?.top ?? Number.NaN };
          expect(Math.abs(end.x - edge.x)).toBeLessThanOrEqual(1);
          expect(Math.abs(end.y - edge.y)).toBeLessThanOrEqual(1);
          expect(attach.targetPoint).toEqual(end);
        }
      });

      it("never draws a branch through or beside text", () => {
        for (const route of composition.routes) {
          const besideText = samplePoints(route.pathData).filter((point) =>
            fixture.textRects.some(
              (text) =>
                point.x > text.left - 8 &&
                point.x < text.left + text.width &&
                point.y > text.top &&
                point.y < text.top + text.height,
            ),
          );
          expect(besideText).toEqual([]);
        }
      });
    });
  }

  it("draws only the mainline in a cramped phone gutter, with short drops into each glass's top edge", () => {
    // Arrange
    const fixture = homePageAt(390);

    // Act
    const composition = composed(fixture);

    // Assert
    expect(composition.laneXs).toEqual([]);
    expect(composition.routes.every((route) => route.kind === "attach")).toBe(true);
    for (const route of composition.routes) {
      const anchor = fixture.page.anchors.find((candidate) => candidate.id === route.anchorId);
      const glass = anchor?.surface;
      expect(route.targetEdge).toBe("top");
      expect(route.endY).toBe(glass?.top);
      expect(route.endY - route.startY).toBeLessThanOrEqual(topologyRowUnit);
      const end = pathCommands(route.pathData).at(-1)?.points.at(-1);
      expect(end?.x).toBe((glass?.left ?? 0) + topologyStackedDropCornerInset);
    }
  });

  it("ends at the last chapter glass center, with one terminal merge when lanes fit", () => {
    for (const width of [390, 1280, 1920]) {
      const fixture = homePageAt(width);
      const lastGlass = fixture.page.anchors.at(-1)?.surface;
      if (lastGlass === undefined) throw new Error("Last chapter glass is missing");
      const composition = composed(fixture);
      const endDot = composition.rows.at(-1);
      expect(endDot?.y).toBeCloseTo(lastGlass.top + lastGlass.height / 2, 1);
      if (composition.laneXs.length > 0) {
        expect(endDot?.kind).toBe("merge");
        expect(endDot?.terminal).toBe(true);
        expect(composition.routes.filter((route) => route.kind === "worktree").at(0)?.endY).toBe(
          endDot?.y,
        );
      } else {
        expect(endDot?.kind).toBe("end");
      }
      const lowestPoint = Math.max(
        ...composition.rows.map((dot) => dot.y),
        ...composition.routes.flatMap((route) =>
          samplePoints(route.pathData).map((point) => point.y),
        ),
        Number(/ ([\d.]+)$/u.exec(composition.mainlinePath)?.[1]),
      );
      expect(lowestPoint).toBeLessThanOrEqual((endDot?.y ?? 0) + 0.01);
    }
  });

  it("falls back to one row above page end when no glass is measured", () => {
    const fixture = homePageAt(1280);
    const composition = composeFullPageTopology({
      ...fixture.page,
      anchors: fixture.page.anchors.map((anchor) => ({ ...anchor, surface: undefined })),
    });
    expect(composition?.rows.at(-1)?.y).toBe(fixture.page.height - topologyRowUnit);
  });

  it("staircases one to four lanes into the last row, one merge per row", () => {
    const rowYs = Array.from({ length: 30 }, (_, row) => row * topologyRowUnit);
    for (const laneCount of [1, 2, 3, 4]) {
      const plan = planWorktreeLanes({
        laneXs: Array.from({ length: laneCount }, (_, index) => (index + 1) * 80),
        mainlineX: 0,
        rowYs,
        openRow: 1,
        endRow: 29,
        lastAttachRow: 20,
      });
      expect(plan?.terminalMerge).toBe(true);
      expect(plan?.lanes.map((lane) => lane.mergeRow)).toEqual(
        Array.from({ length: laneCount }, (_, index) => 29 - index),
      );
      expect(new Set(plan?.lanes.map((lane) => lane.mergeRow)).size).toBe(laneCount);
    }
  });

  it("reduces the lane count when a terminal staircase has no room", () => {
    const rowYs = Array.from({ length: 11 }, (_, row) => row * topologyRowUnit);
    const plan = planWorktreeLanes({
      laneXs: [80, 160],
      mainlineX: 0,
      rowYs,
      openRow: 1,
      endRow: 10,
      lastAttachRow: 8,
    });
    expect(plan).toBeUndefined();
  });

  it("draws nothing without chapter anchors", () => {
    expect(
      composeFullPageTopology({ viewportWidth: 1280, height: 4000, anchors: [] }),
    ).toBeUndefined();
  });
});
