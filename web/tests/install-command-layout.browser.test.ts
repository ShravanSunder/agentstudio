import { expect, inject, it } from "vitest";
import { commands } from "vitest/browser";

import type { InstallBoxObservation } from "./install-command-layout-browser-command";

declare module "vitest/browser" {
  interface BrowserCommands {
    verifyInstallCommandLayout(pageUrl: string): Promise<InstallBoxObservation[]>;
  }
}

it("keeps both install commands on one row and copies without a horizontal scrollbar", async () => {
  const observations = await commands.verifyInstallCommandLayout(
    inject("siteHeaderBrowserTestUrl"),
  );
  for (const { width, boxes } of observations) {
    expect(boxes).toHaveLength(2);
    for (const box of boxes) {
      if (width >= 360) expect(box.codeOverflow, `${width}px`).toBeLessThanOrEqual(0);
      expect(box.commandRowHeights, `${width}px`).toHaveLength(2);
      for (const rowHeight of box.commandRowHeights)
        expect(rowHeight, `${width}px`).toBeLessThanOrEqual(box.lineHeight + 1);
      expect(box.copied).toContain("brew tap ShravanSunder/agentstudio");
      if (width < 620) {
        expect(box.compact, `${width}px`).toBe(true);
        expect(box.copyWidth, `${width}px`).toBeCloseTo(36, 0);
      }
    }
  }
});
