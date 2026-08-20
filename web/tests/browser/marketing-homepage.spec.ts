import { expect, test } from "@playwright/test";

test("renders the claim-first homepage and switches product stories", async ({ page }) => {
  await page.goto("/");

  await expect(page.getByRole("heading", { level: 1 })).toHaveText(
    "Stay oriented without losing context.",
  );
  await expect(page.locator('meta[name="theme-color"]')).toHaveAttribute("content", "#2E3036");
  expect(
    await page.locator("body").evaluate((body) => getComputedStyle(body).backgroundColor),
  ).toBe("rgb(46, 48, 54)");
  await expect(page.getByRole("link", { name: "GitHub", exact: true })).toHaveCount(1);
  await expect(page.locator(".hero__actions a")).toHaveCount(0);

  const installCenterOffset = await page.locator(".hero").evaluate((hero) => {
    const actions = hero.querySelector(".hero__actions");
    if (!(actions instanceof HTMLElement)) {
      throw new Error("Hero action surface is missing");
    }

    const installCommand = actions.querySelector(".install-command");
    if (!(installCommand instanceof HTMLElement)) {
      throw new Error("Hero install command is missing");
    }

    const heroBounds = hero.getBoundingClientRect();
    const installBounds = installCommand.getBoundingClientRect();
    return Math.abs(
      heroBounds.left + heroBounds.width / 2 - (installBounds.left + installBounds.width / 2),
    );
  });
  expect(installCenterOffset).toBeLessThanOrEqual(1);

  const productTabs = page.getByRole("tab");
  await expect(productTabs).toHaveCount(5);
  await expect(page.getByRole("tab", { name: /Parallel work/ })).toHaveAttribute(
    "aria-selected",
    "true",
  );

  const originalUrl = page.url();
  await page.getByRole("tab", { name: /Pane drawer/ }).click();
  await expect(page.getByRole("tabpanel", { name: /Pane drawer/ })).toBeVisible();
  expect(page.url()).toBe(originalUrl);

  await page.getByRole("tab", { name: /Pane drawer/ }).press("ArrowRight");
  await expect(page.getByRole("tab", { name: /Quick Find/ })).toHaveAttribute(
    "aria-selected",
    "true",
  );

  await page.getByRole("tab", { name: /Persistent terminal sessions/ }).click();
  const persistencePanel = page.getByRole("tabpanel", {
    name: /Persistent terminal sessions/,
  });
  await expect(persistencePanel.getByText("Before close")).toBeVisible();
  await expect(persistencePanel.getByText("Restored")).toBeVisible();

  await expect
    .poll(() =>
      page
        .locator('[data-product-plate-panel="parallel-work"] img')
        .evaluate((image) => (image instanceof HTMLImageElement ? image.naturalWidth : 0)),
    )
    .toBeGreaterThan(0);
  await expect
    .poll(() =>
      persistencePanel
        .locator("img")
        .evaluateAll((images) =>
          images.every((image) => image instanceof HTMLImageElement && image.naturalWidth > 0),
        ),
    )
    .toBe(true);
  await expect(persistencePanel.locator("img")).toHaveCount(2);
});

test("keeps the static product plate honest without JavaScript", async ({ browser }) => {
  const context = await browser.newContext({ javaScriptEnabled: false });
  const page = await context.newPage();

  await page.goto("/");

  const selectors = page.locator("[data-product-plate-selector]");
  await expect(selectors).toHaveCount(5);
  const allSelectorsDisabled = await selectors.evaluateAll((buttons) =>
    buttons.every((button) => button instanceof HTMLButtonElement && button.disabled),
  );
  expect(allSelectorsDisabled).toBe(true);
  await expect(page.locator('[data-product-plate-panel="parallel-work"]')).toBeVisible();
  await expect(page.locator('[data-product-plate-panel="review"]')).toBeHidden();
  await expect(page.locator("[data-product-plate-selectors]")).not.toHaveAttribute(
    "role",
    "tablist",
  );

  await context.close();
});

test("contains phone composition within the document viewport", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/");

  const documentWidths = await page.evaluate(() => ({
    clientWidth: document.documentElement.clientWidth,
    scrollWidth: document.documentElement.scrollWidth,
  }));

  expect(documentWidths.scrollWidth).toBeLessThanOrEqual(documentWidths.clientWidth);
  await expect(page.getByRole("tab", { name: /Persistent terminal sessions/ })).toBeAttached();
});
