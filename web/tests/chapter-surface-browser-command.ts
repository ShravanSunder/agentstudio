import { defineBrowserCommand } from "@vitest/browser-playwright";

/** One chapter's title anchor and its rail node, read from the served home page. */
export interface ChapterTitleAnchorObservation {
  readonly width: number;
  readonly chapterId: string;
  readonly anchorTagName: string;
  /** Elements inside the chapter whose whole text reads "Chapter N". */
  readonly eyebrowCount: number;
  readonly titleFirstLineCenterY: number;
  readonly nodeCenterY: number;
}

/** One step tab in the step list. */
export interface ChapterStepTabObservation {
  readonly stepId: string;
  readonly accessibleName: string;
  readonly centerX: number;
  readonly centerY: number;
  readonly width: number;
  readonly height: number;
  /** Whether the step label inside the tab is visibly rendered. */
  readonly labelVisible: boolean;
}

/** The step region at one moment: which copy is visible and where focus is. */
export interface ChapterStepSnapshot {
  readonly visiblePanelIds: readonly string[];
  /** Visible text of the visible panels. */
  readonly visibleText: string;
  readonly focusedStepId: string | undefined;
}

export interface ChapterStepRowObservation {
  readonly width: number;
  readonly orientation: string | null;
  readonly role: string | null;
  readonly tabs: readonly ChapterStepTabObservation[];
  readonly labels: Readonly<Record<string, string>>;
  readonly initial: ChapterStepSnapshot;
  readonly afterSceneAdvance: ChapterStepSnapshot;
  readonly afterArrowRight: ChapterStepSnapshot;
  readonly afterHome: ChapterStepSnapshot;
  readonly afterEnd: ChapterStepSnapshot;
  /** The same chapter served with JavaScript off. */
  readonly withoutScript: ChapterStepSnapshot;
}

interface ChapterStepRowRequest {
  readonly pageUrl: string;
  readonly width: number;
  readonly chapterId: string;
}

function observeTitleAnchors(width: number): ChapterTitleAnchorObservation[] {
  return [...document.querySelectorAll<HTMLElement>("article[data-chapter]")].map((article) => {
    const chapterId = article.dataset["chapter"] ?? "";
    const anchor = article.querySelector<HTMLElement>("[data-rail-anchor]");
    const node = document.querySelector(`[data-topology-chapter-node="${chapterId}"] circle`);
    if (anchor === null || node === null) {
      throw new Error(`Chapter ${chapterId} is missing its anchor or rail node`);
    }
    const range = document.createRange();
    range.selectNodeContents(anchor);
    const firstLine = [...range.getClientRects()].find((box) => box.width > 0 && box.height > 0);
    const nodeBounds = node.getBoundingClientRect();
    return {
      width,
      chapterId,
      anchorTagName: anchor.tagName,
      eyebrowCount: [...article.querySelectorAll("*")].filter((element) =>
        /^chapter\s+\d+$/iu.test(element.textContent.trim()),
      ).length,
      titleFirstLineCenterY:
        firstLine === undefined ? Number.NaN : firstLine.top + firstLine.height / 2,
      nodeCenterY: nodeBounds.top + nodeBounds.height / 2,
    };
  });
}

/**
 * Loads the served home page at each width with reduced motion (so glass
 * surfaces do not lift mid-read) and reports every chapter's title anchor and
 * the rail node drawn for it.
 */
export const verifyChapterTitleAnchors = defineBrowserCommand(
  async (
    { context },
    pageUrl: string,
    widths: readonly number[],
  ): Promise<ChapterTitleAnchorObservation[]> => {
    const observations: ChapterTitleAnchorObservation[] = [];
    /* eslint-disable no-await-in-loop -- Each width needs its own fresh page. */
    for (const width of widths) {
      const applicationPage = await context.newPage();
      try {
        await applicationPage.emulateMedia({ reducedMotion: "reduce" });
        await applicationPage.setViewportSize({ width, height: 900 });
        await applicationPage.goto(pageUrl, { waitUntil: "networkidle" });
        await applicationPage.evaluate(async () => {
          await document.fonts.ready;
        });
        await applicationPage.waitForSelector(
          "[data-full-page-topology][data-topology-reveal-edge-y] [data-topology-chapter-node]",
          { state: "attached" },
        );
        observations.push(...(await applicationPage.evaluate(observeTitleAnchors, width)));
      } finally {
        await applicationPage.close();
      }
    }
    /* eslint-enable no-await-in-loop */
    return observations;
  },
);

function readStepTabs(chapterId: string): {
  readonly orientation: string | null;
  readonly role: string | null;
  readonly tabs: ChapterStepTabObservation[];
  readonly labels: Record<string, string>;
} {
  const root = document.querySelector(`[data-chapter-steps-root="${chapterId}"]`);
  const list = root?.querySelector("[data-chapter-step-list]");
  if (root === null || root === undefined || list === null || list === undefined) {
    throw new Error(`Chapter ${chapterId} has no step list`);
  }
  const labels: Record<string, string> = {};
  const tabs = [...list.querySelectorAll<HTMLButtonElement>("[data-chapter-step]")].map((tab) => {
    const stepId = tab.dataset["chapterStep"] ?? "";
    const label = tab.querySelector<HTMLElement>("[data-chapter-step-label]");
    const bounds = tab.getBoundingClientRect();
    const labelBounds = label?.getBoundingClientRect();
    labels[stepId] = label?.textContent.trim() ?? "";
    return {
      stepId,
      accessibleName: (tab.getAttribute("aria-label") ?? tab.textContent).trim(),
      centerX: bounds.left + bounds.width / 2,
      centerY: bounds.top + bounds.height / 2,
      width: bounds.width,
      height: bounds.height,
      labelVisible: labelBounds !== undefined && labelBounds.width > 1 && labelBounds.height > 1,
    };
  });
  return {
    orientation: list.getAttribute("aria-orientation"),
    role: list.getAttribute("role"),
    tabs,
    labels,
  };
}

function readStepSnapshot(chapterId: string): ChapterStepSnapshot {
  const root = document.querySelector<HTMLElement>(`[data-chapter-steps-root="${chapterId}"]`);
  if (root === null) {
    throw new Error(`Chapter ${chapterId} has no steps root`);
  }
  const visiblePanels = [...root.querySelectorAll<HTMLElement>("[data-chapter-step-panel]")].filter(
    (panel) => panel.getClientRects().length > 0,
  );
  const focused = document.activeElement;
  return {
    visiblePanelIds: visiblePanels.map((panel) => panel.dataset["chapterStepPanel"] ?? ""),
    visibleText: visiblePanels.map((panel) => panel.innerText).join("\n"),
    focusedStepId:
      focused instanceof HTMLElement && root.contains(focused)
        ? focused.dataset["chapterStep"]
        : undefined,
  };
}

/** The slice of a Playwright page that opening a chapter needs. */
interface NavigablePage {
  emulateMedia(options: { readonly reducedMotion: "reduce" }): Promise<void>;
  setViewportSize(size: { readonly width: number; readonly height: number }): Promise<void>;
  goto(url: string, options: { readonly waitUntil: "networkidle" }): Promise<unknown>;
}

async function openChapter(
  applicationPage: NavigablePage,
  request: ChapterStepRowRequest,
): Promise<void> {
  await applicationPage.emulateMedia({ reducedMotion: "reduce" });
  await applicationPage.setViewportSize({ width: request.width, height: 900 });
  const pageUrl = new URL(request.pageUrl);
  pageUrl.hash = request.chapterId;
  await applicationPage.goto(pageUrl.href, { waitUntil: "networkidle" });
}

/**
 * Loads one chapter at one width with reduced motion (scenes stay settled, so
 * only this command moves the steps), reads the step list's geometry and
 * semantics, then drives it: the scene reports its next step, then ArrowRight,
 * Home, and End from the focused tab. Finally reads the same chapter with
 * JavaScript off.
 */
export const verifyChapterStepRow = defineBrowserCommand(
  async ({ context }, request: ChapterStepRowRequest): Promise<ChapterStepRowObservation> => {
    const applicationPage = await context.newPage();
    const { chapterId } = request;
    let semantics: ReturnType<typeof readStepTabs>;
    let initial: ChapterStepSnapshot;
    let afterSceneAdvance: ChapterStepSnapshot;
    let afterArrowRight: ChapterStepSnapshot;
    let afterHome: ChapterStepSnapshot;
    let afterEnd: ChapterStepSnapshot;
    try {
      await openChapter(applicationPage, request);
      await applicationPage.waitForSelector(
        `[data-chapter-steps-root="${chapterId}"][data-enhanced="true"]`,
        { state: "attached" },
      );
      semantics = await applicationPage.evaluate(readStepTabs, chapterId);
      initial = await applicationPage.evaluate(readStepSnapshot, chapterId);
      const [, secondStep, thirdStep] = semantics.tabs;
      if (secondStep === undefined || thirdStep === undefined) {
        throw new Error(`Chapter ${chapterId} needs at least three steps`);
      }

      // The scene reaches its second step.
      await applicationPage.evaluate(
        ({ chapter, stepId }) => {
          document
            .querySelector(`[data-chapter-steps-root="${chapter}"] [data-scene-root]`)
            ?.dispatchEvent(
              new CustomEvent("agentstudio:scene-step-reached", {
                bubbles: true,
                detail: { stepId },
              }),
            );
        },
        { chapter: chapterId, stepId: secondStep.stepId },
      );
      await applicationPage.waitForSelector(
        `[data-chapter-step="${secondStep.stepId}"][aria-selected="true"]`,
        { state: "attached" },
      );
      afterSceneAdvance = await applicationPage.evaluate(readStepSnapshot, chapterId);

      // The visitor focuses the selected tab and moves right.
      await applicationPage.focus(`[data-chapter-step="${secondStep.stepId}"]`);
      await applicationPage.keyboard.press("ArrowRight");
      afterArrowRight = await applicationPage.evaluate(readStepSnapshot, chapterId);
      await applicationPage.keyboard.press("Home");
      afterHome = await applicationPage.evaluate(readStepSnapshot, chapterId);
      await applicationPage.keyboard.press("End");
      afterEnd = await applicationPage.evaluate(readStepSnapshot, chapterId);
    } finally {
      await applicationPage.close();
    }

    const browser = context.browser();
    if (browser === null) {
      throw new Error("The browser context has no browser to open a script-free context");
    }
    const scriptFreeContext = await browser.newContext({ javaScriptEnabled: false });
    let withoutScript: ChapterStepSnapshot;
    try {
      const scriptFreePage = await scriptFreeContext.newPage();
      await openChapter(scriptFreePage, request);
      withoutScript = await scriptFreePage.evaluate(readStepSnapshot, chapterId);
    } finally {
      await scriptFreeContext.close();
    }

    return {
      width: request.width,
      orientation: semantics.orientation,
      role: semantics.role,
      tabs: semantics.tabs,
      labels: semantics.labels,
      initial,
      afterSceneAdvance,
      afterArrowRight,
      afterHome,
      afterEnd,
      withoutScript,
    };
  },
);
