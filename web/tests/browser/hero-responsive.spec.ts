import { expect, test } from "@playwright/test";

interface HeroPlaneExpectation {
  readonly height: number;
  readonly right: string;
  readonly scale: string;
  readonly top: string;
  readonly visible: boolean;
  readonly width: number;
}

const heroPlaneExpectations: readonly HeroPlaneExpectation[] = [
  { width: 1280, height: 900, visible: true, top: "56px", right: "96px", scale: "0.78" },
  { width: 1279, height: 900, visible: true, top: "52px", right: "80px", scale: "0.7" },
  { width: 1024, height: 900, visible: true, top: "52px", right: "80px", scale: "0.7" },
  { width: 1023, height: 900, visible: true, top: "52px", right: "64px", scale: "0.6" },
  { width: 768, height: 900, visible: true, top: "52px", right: "64px", scale: "0.6" },
  { width: 767, height: 900, visible: true, top: "48px", right: "32px", scale: "0.46" },
  { width: 640, height: 844, visible: true, top: "48px", right: "32px", scale: "0.46" },
  { width: 639, height: 844, visible: false, top: "48px", right: "32px", scale: "0.46" },
] as const;

for (const expectation of heroPlaneExpectations) {
  test(`uses the ${expectation.width}px hero-plane composition`, async ({ page }) => {
    await page.setViewportSize({ width: expectation.width, height: expectation.height });
    await page.goto("/");

    const heroPlanes = page.locator(".hero__planes");
    expect(await page.locator("html").evaluate((html) => html.scrollWidth - html.clientWidth)).toBe(
      0,
    );

    if (!expectation.visible) {
      await expect(heroPlanes).toBeHidden();
      return;
    }

    await expect(heroPlanes).toBeVisible();
    expect(
      await heroPlanes.evaluate((element) => {
        const style = getComputedStyle(element);
        return { right: style.right, scale: style.scale, top: style.top };
      }),
    ).toEqual({ right: expectation.right, scale: expectation.scale, top: expectation.top });
  });
}
