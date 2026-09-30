export interface ChapterTitlePosition {
  readonly chapterId: string;
  readonly top: number;
}

/** The title at or above the reading line that entered most recently. */
export function selectReadingChapter(
  titles: readonly ChapterTitlePosition[],
  readingLineY: number,
): string | undefined {
  return titles
    .filter((title) => title.top <= readingLineY)
    .reduce<ChapterTitlePosition | undefined>(
      (latest, title) => (latest === undefined || title.top > latest.top ? title : latest),
      undefined,
    )?.chapterId;
}

export const chapterActivityChangedEventName = "chapter-activity-changed";

export interface ChapterActivityTransition {
  readonly activeChapterId: string | undefined;
  readonly newlyActiveChapterId: string | undefined;
  readonly changed: boolean;
}

/** One scroll-owned selection across all chapter titles. */
export function createChapterActivityCoordinator(roots: readonly HTMLElement[]): {
  readonly read: () => ChapterActivityTransition;
  readonly publish: (transition: ChapterActivityTransition) => void;
} {
  let activeChapterId: string | undefined;
  return {
    read: (): ChapterActivityTransition => {
      const positions = roots.flatMap((root): ChapterTitlePosition[] => {
        const chapterId = root.dataset["chapterStepsRoot"];
        const title = root.querySelector<HTMLElement>(".chapter-title");
        return chapterId === undefined || title === null
          ? []
          : [{ chapterId, top: title.getBoundingClientRect().top }];
      });
      const nextChapterId = selectReadingChapter(positions, window.innerHeight * 0.45);
      const changed = nextChapterId !== activeChapterId;
      activeChapterId = nextChapterId;
      return {
        activeChapterId,
        newlyActiveChapterId: changed ? nextChapterId : undefined,
        changed,
      };
    },
    publish: (transition): void => {
      if (!transition.changed) return;
      document.dispatchEvent(
        new CustomEvent(chapterActivityChangedEventName, {
          detail: { chapterId: transition.activeChapterId },
        }),
      );
    },
  };
}
