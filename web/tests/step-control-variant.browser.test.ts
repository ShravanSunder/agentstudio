import { expect, inject, it } from "vitest";
import { commands } from "vitest/browser";

import type { StepControlVariantObservation } from "./step-control-variant-browser-command";
import { sharpCornerCount } from "./topology-path-corners";

declare module "vitest/browser" {
  interface BrowserCommands {
    verifyStepControlVariant(
      pageUrl: string,
      width: number,
      chapterId: string,
      variant: "line" | "capsule",
    ): Promise<StepControlVariantObservation>;
  }
}

for (const variant of ["line", "capsule"] as const) {
  for (const width of [390, 1600]) {
    for (const chapterId of ["many-agents", "context-with-task"]) {
      it(`shows ${variant} step control for ${chapterId} at ${width}px`, async () => {
        const result = await commands.verifyStepControlVariant(
          inject("siteHeaderBrowserTestUrl"),
          width,
          chapterId,
          variant,
        );
        expect(result.variant).toBe(variant);
        expect(result.labelDotVisible).toBe(variant === "capsule");
        expect(result.capsuleBackdrop.includes("blur")).toBe(variant === "capsule");
        if (variant === "capsule") {
          expect(result.labelBackground).toBe("none");
          expect(result.labelBorderWidth).toBe("0px");
          expect(result.labelBackdrop).toBe("none");
        }
        expect(result.firstLabel).not.toBe(result.thirdLabel);
        expect(result.railLandingOffset).toBeLessThanOrEqual(1);
        for (const path of [result.firstBranchPath, result.thirdBranchPath]) {
          expect(sharpCornerCount(path), `${width}px ${chapterId}: ${path}`).toBe(0);
          const numbers = path.match(/[-+]?\d*\.?\d+/gu)?.map(Number) ?? [];
          expect(numbers[2], path).toBeCloseTo(numbers[0] ?? Number.NaN, 1);
        }
      });
    }
  }
}
