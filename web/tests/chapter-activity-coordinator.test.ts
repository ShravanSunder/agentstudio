import { describe, expect, it } from "vitest";

import { selectReadingChapter } from "../src/home-page/chapter-activity-coordinator";

describe("chapter activity at the title reading line", () => {
  it("selects the latest title above the line and hands back when scrolling up", () => {
    const titles = [
      { chapterId: "many-agents", top: -800 },
      { chapterId: "context-with-task", top: 449 },
      { chapterId: "review", top: 1300 },
    ];
    expect(selectReadingChapter(titles, 450)).toBe("context-with-task");
    expect(
      selectReadingChapter(
        titles.map((title) => ({ ...title, top: title.top + 2 })),
        450,
      ),
    ).toBe("many-agents");
    expect(selectReadingChapter([{ chapterId: "many-agents", top: 451 }], 450)).toBeUndefined();
  });
});
