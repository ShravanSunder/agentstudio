import { expect, test } from "@playwright/test";

const activeSurfaceColor = "rgb(37, 39, 45)";
const darkFrostColor = "rgba(24, 26, 32, 0.72)";

test("gives primary and neutral controls consistent hover and pressed feedback", async ({
  page,
}, testInfo) => {
  test.skip(
    testInfo.project.name === "mobile-chrome",
    "Touch devices do not expose hover feedback",
  );
  await page.setViewportSize({ width: 1023, height: 900 });
  await page.goto("/");

  const copyButton = page.locator("[data-install-copy]");
  await copyButton.hover();
  await expect(copyButton).toHaveCSS("filter", "brightness(1.05)");
  await page.mouse.down();
  await expect(copyButton).toHaveCSS("filter", "brightness(0.9)");
  await page.mouse.up();

  const nextStoryButton = page.locator("[data-product-plate-next]");
  await nextStoryButton.hover();
  await expect(nextStoryButton).toHaveCSS("background-color", darkFrostColor);
  await page.mouse.down();
  await expect(nextStoryButton).toHaveCSS("background-color", activeSurfaceColor);
  await page.mouse.up();

  const restoredButton = page.getByRole("button", { name: "Restored" });
  await restoredButton.scrollIntoViewIfNeeded();
  await restoredButton.hover();
  await expect(restoredButton).toHaveCSS("background-color", darkFrostColor);
  await page.mouse.down();
  await expect(restoredButton).toHaveCSS("background-color", activeSurfaceColor);
  await page.mouse.up();
});

test("removes control transition duration when reduced motion is requested", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.setViewportSize({ width: 1023, height: 900 });
  await page.goto("/");

  const controls = [
    page.locator("[data-install-copy]"),
    page.locator("[data-product-plate-next]"),
    page.getByRole("button", { name: "Restored" }),
  ];

  await Promise.all(
    controls.map(async (control) => expect(control).toHaveCSS("transition-duration", "0s")),
  );
});
