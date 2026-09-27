import { defineBrowserCommand } from "@vitest/browser-playwright";

export interface StepControlVariantObservation {
  readonly variant: "line" | "capsule";
  readonly chapterId: string;
  readonly width: number;
  readonly capsuleBackdrop: string;
  readonly labelBackground: string;
  readonly labelBorderWidth: string;
  readonly labelBackdrop: string;
  readonly labelDotVisible: boolean;
  readonly firstLabel: string;
  readonly thirdLabel: string;
  readonly firstBranchPath: string;
  readonly thirdBranchPath: string;
  readonly railLandingOffset: number;
}

export const verifyStepControlVariant = defineBrowserCommand(
  async (
    { context },
    pageUrl: string,
    width: number,
    chapterId: string,
    variant: "line" | "capsule",
  ): Promise<StepControlVariantObservation> => {
    const page = await context.newPage();
    try {
      await page.emulateMedia({ reducedMotion: "reduce" });
      await page.setViewportSize({ width, height: width < 620 ? 844 : 1000 });
      const url = new URL(pageUrl);
      if (variant === "capsule") url.searchParams.set("steps", "capsule");
      await page.goto(url.href, { waitUntil: "domcontentloaded" });
      await page
        .locator(`[data-chapter-steps-root="${chapterId}"][data-step-control-variant="${variant}"]`)
        .waitFor();
      return await page.evaluate(
        ({ chapterId, variant, width }): StepControlVariantObservation => {
          const root = document.querySelector<HTMLElement>(
            `[data-chapter-steps-root="${chapterId}"]`,
          );
          const line = root?.querySelector<HTMLElement>("[data-chapter-step-line]");
          const label = root?.querySelector<HTMLElement>("[data-chapter-step-active-label]");
          const dot = label?.querySelector<HTMLElement>(".chapter-step-active-label__dot");
          const branch = root?.querySelector<SVGPathElement>("[data-chapter-step-branch]");
          const steps = [
            ...(root?.querySelectorAll<HTMLButtonElement>("[data-chapter-step]") ?? []),
          ];
          const target = root?.querySelector<HTMLElement>("[data-rail-step-line-target]");
          const rail = document.querySelector<SVGPathElement>(
            `[data-route-anchor="${chapterId}"] [data-topology-path-role="core"]`,
          );
          if (
            root === null ||
            line === undefined ||
            line === null ||
            label === undefined ||
            label === null ||
            dot === undefined ||
            dot === null ||
            branch === undefined ||
            branch === null ||
            target === undefined ||
            target === null ||
            rail === null ||
            steps.length < 3
          )
            throw new Error("Step-control variant markup is missing");
          const railMatrix = rail.getScreenCTM();
          if (railMatrix === null) throw new Error("Step-control rail transform is missing");
          const railEnd = rail.getPointAtLength(rail.getTotalLength()).matrixTransform(railMatrix);
          const targetRect = target.getBoundingClientRect();
          const targetX = (targetRect.left + targetRect.right) / 2;
          const targetY = (targetRect.top + targetRect.bottom) / 2;
          const firstLabel = label.textContent?.trim() ?? "";
          const firstBranchPath = branch.getAttribute("d") ?? "";
          steps[2]?.click();
          return {
            variant,
            chapterId,
            width,
            capsuleBackdrop: getComputedStyle(line).backdropFilter,
            labelBackground: getComputedStyle(label).backgroundImage,
            labelBorderWidth: getComputedStyle(label).borderTopWidth,
            labelBackdrop: getComputedStyle(label).backdropFilter,
            labelDotVisible: getComputedStyle(dot).display !== "none",
            firstLabel,
            thirdLabel: label.textContent?.trim() ?? "",
            firstBranchPath,
            thirdBranchPath: branch.getAttribute("d") ?? "",
            railLandingOffset: Math.hypot(railEnd.x - targetX, railEnd.y - targetY),
          };
        },
        { chapterId, variant, width },
      );
    } finally {
      await page.close();
    }
  },
);
