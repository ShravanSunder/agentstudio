import { expect, test } from "@playwright/test";

const productStoryCases = [
  { id: "parallel-work", accessibleName: /Parallel work/ },
  { id: "pane-drawer", accessibleName: /Pane drawer/ },
  { id: "quick-find", accessibleName: /Quick Find/ },
  { id: "review", accessibleName: /Review/ },
  { id: "git-context", accessibleName: /Git context/ },
] as const;

const verificationViewports = [
  { width: 1600, height: 1000 },
  { width: 390, height: 844 },
] as const;

test("renders the claim-first homepage and switches product stories", async ({ page }) => {
  await page.goto("/");

  await expect(page.getByRole("heading", { level: 1 })).toHaveText(
    "Stay oriented without losing context.",
  );
  await expect(page.locator('meta[name="theme-color"]')).toHaveAttribute("content", "#2E3036");
  expect(
    await page.locator("body").evaluate((body) => getComputedStyle(body).backgroundColor),
  ).toBe("rgb(46, 48, 54)");
  expect(
    await page.locator("body").evaluate((body) => getComputedStyle(body).backgroundImage),
  ).toBe("none");
  await expect(page.getByRole("link", { name: "GitHub", exact: true })).toHaveCount(2);
  await expect(page.locator(".site-header .header-social-action")).toHaveCount(2);
  await expect(page.locator(".final-cta .github-action")).toHaveCount(1);
  await expect(page.locator(".hero__actions a")).toHaveCount(0);
  await expect(page.locator("[data-install-command-root]")).toHaveCount(1);
  await expect(page.getByRole("link", { name: "Shravan Sunder on X" })).toBeVisible();
  await expect(page.locator(".site-footer")).toHaveCount(0);

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

  const plateGeometry = await page.locator(".product-plate").evaluate((plate) => {
    const selectors = plate.querySelector(".product-plate__selectors")?.getBoundingClientRect();
    const panels = plate.querySelector(".product-plate__panels")?.getBoundingClientRect();
    const image = plate
      .querySelector('[data-product-plate-panel="parallel-work"] img')
      ?.getBoundingClientRect();
    const selected = plate.querySelector('[aria-selected="true"]');

    if (
      selectors === undefined ||
      panels === undefined ||
      image === undefined ||
      selected === null
    ) {
      throw new Error("Product plate geometry is incomplete");
    }

    return {
      stackedLayout: selectors.bottom <= image.top + 1,
      imageGap: Math.abs(selectors.right - image.left),
      stackedImageGap: Math.abs(selectors.bottom - image.top),
      panelImageTopOffset: Math.abs(panels.top - image.top),
      panelImageBottomOffset: Math.abs(panels.bottom - image.bottom),
      selectedBackground: getComputedStyle(selected).backgroundColor,
    };
  });
  if (plateGeometry.stackedLayout) {
    expect(plateGeometry.stackedImageGap).toBeLessThanOrEqual(1);
  } else {
    expect(plateGeometry.imageGap).toBeLessThanOrEqual(1);
  }
  expect(plateGeometry.panelImageTopOffset).toBeLessThanOrEqual(2);
  expect(plateGeometry.panelImageBottomOffset).toBeLessThanOrEqual(2);
  expect(plateGeometry.selectedBackground).toBe("rgb(37, 39, 45)");

  const originalUrl = page.url();
  await page.getByRole("tab", { name: /Pane drawer/ }).click();
  await expect(page.getByRole("tabpanel", { name: /Pane drawer/ })).toBeVisible();
  expect(page.url()).toBe(originalUrl);

  await page.getByRole("tab", { name: /Pane drawer/ }).press("ArrowRight");
  await expect(page.getByRole("tab", { name: /Quick Find/ })).toHaveAttribute(
    "aria-selected",
    "true",
  );

  await page.getByRole("tab", { name: /Git context/ }).click();
  await expect(page.getByRole("tabpanel", { name: /Git context/ })).toBeVisible();

  const persistencePanel = page.locator(".feature-detail").first();
  const beforeFrameButton = persistencePanel.getByRole("button", { name: "Before close" });
  const restoredFrameButton = persistencePanel.getByRole("button", { name: "Restored" });
  await expect(beforeFrameButton).toHaveAttribute("aria-pressed", "true");
  await expect(restoredFrameButton).toHaveAttribute("aria-pressed", "false");
  await expect(persistencePanel.locator('[data-persistence-frame="before"]')).toBeVisible();
  await expect(persistencePanel.locator('[data-persistence-frame="restored"]')).toBeHidden();

  const beforeFrameGeometry = await persistencePanel.evaluate((panel) => {
    const image = panel.querySelector('[data-persistence-frame="before"] img');
    const media = panel.querySelector(".feature-detail__media");

    if (!(image instanceof HTMLImageElement) || !(media instanceof HTMLElement)) {
      throw new Error("Before persistence frame or media boundary is missing");
    }

    const panelBounds = media.getBoundingClientRect();
    const imageBounds = image.getBoundingClientRect();
    return {
      widthDifference: Math.abs(panelBounds.width - imageBounds.width),
      unusedAreaBelow: panelBounds.bottom - imageBounds.bottom,
    };
  });
  expect(beforeFrameGeometry.widthDifference).toBeLessThanOrEqual(2);
  expect(beforeFrameGeometry.unusedAreaBelow).toBeLessThanOrEqual(64);

  await restoredFrameButton.click();
  await expect(beforeFrameButton).toHaveAttribute("aria-pressed", "false");
  await expect(restoredFrameButton).toHaveAttribute("aria-pressed", "true");
  await expect(persistencePanel.locator('[data-persistence-frame="before"]')).toBeHidden();
  await expect(persistencePanel.locator('[data-persistence-frame="restored"]')).toBeVisible();

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

for (const viewport of verificationViewports) {
  for (const productStory of productStoryCases) {
    test(`loads and fits ${productStory.id} at ${viewport.width}x${viewport.height}`, async ({
      page,
    }) => {
      await page.setViewportSize(viewport);
      await page.goto("/");
      await page.getByRole("tab", { name: productStory.accessibleName }).click();

      const selectedPanel = page.locator(`[data-product-plate-panel="${productStory.id}"]`);
      await expect(selectedPanel).toBeVisible();
      await expect(page.locator("[data-product-plate-panel]:not([hidden])")).toHaveCount(1);

      const productImages = selectedPanel.locator("img");
      await expect
        .poll(() =>
          productImages
            .first()
            .evaluate((image) => (image instanceof HTMLImageElement ? image.naturalWidth : 0)),
        )
        .toBeGreaterThan(0);

      const imageGeometry = await productImages.evaluateAll((images) =>
        images.map((image) => {
          if (!(image instanceof HTMLImageElement)) {
            throw new Error("Product proof contains a non-image media element");
          }

          const imageBounds = image.getBoundingClientRect();
          const panelBounds = image.closest("[data-product-plate-panel]")?.getBoundingClientRect();
          if (panelBounds === undefined) {
            throw new Error("Product proof image is not owned by a product panel");
          }

          return {
            naturalWidth: image.naturalWidth,
            naturalHeight: image.naturalHeight,
            renderedWidth: imageBounds.width,
            renderedHeight: imageBounds.height,
            unusedPanelRegionBelow: panelBounds.bottom - imageBounds.bottom,
            containedHorizontally:
              imageBounds.left >= panelBounds.left - 1 &&
              imageBounds.right <= panelBounds.right + 1,
            containedVertically:
              imageBounds.top >= panelBounds.top - 1 &&
              imageBounds.bottom <= panelBounds.bottom + 1,
          };
        }),
      );

      expect(imageGeometry.length).toBe(1);
      expect(imageGeometry.filter((image) => image.renderedWidth > 0)).toHaveLength(1);
      for (const image of imageGeometry) {
        expect(image.naturalWidth).toBeGreaterThan(0);
        expect(image.naturalHeight).toBeGreaterThan(0);
        if (image.renderedWidth > 0) {
          expect(image.renderedHeight).toBeGreaterThan(0);
          expect(image.containedHorizontally).toBe(true);
          expect(image.containedVertically).toBe(true);
          expect(image.unusedPanelRegionBelow).toBeLessThanOrEqual(1);
          expect(
            Math.abs(
              image.renderedWidth / image.renderedHeight - image.naturalWidth / image.naturalHeight,
            ),
          ).toBeLessThan(0.01);
        }
      }

      const documentWidths = await page.evaluate(() => ({
        clientWidth: document.documentElement.clientWidth,
        scrollWidth: document.documentElement.scrollWidth,
      }));
      expect(documentWidths.scrollWidth).toBeLessThanOrEqual(documentWidths.clientWidth);
    });
  }
}

test("uses product focus color for the selected story and neutral inactive indices", async ({
  page,
}) => {
  await page.goto("/");

  const selectedIndex = page.locator('.product-plate__selector[aria-selected="true"] span');
  const inactiveIndices = page.locator('.product-plate__selector[aria-selected="false"] span');

  expect(await selectedIndex.evaluate((index) => getComputedStyle(index).color)).toBe(
    "rgb(137, 180, 250)",
  );
  expect(
    await inactiveIndices.evaluateAll((indices) => [
      ...new Set(indices.map((index) => getComputedStyle(index).color)),
    ]),
  ).toEqual(["rgb(155, 161, 173)"]);

  await page.getByRole("tab", { name: /Review/ }).click();
  await expect(page.getByRole("tab", { name: /Review/ })).toHaveAttribute("aria-selected", "true");
  expect(await selectedIndex.evaluate((index) => getComputedStyle(index).color)).toBe(
    "rgb(137, 180, 250)",
  );
});

test("presents supporting features as text and product media without numbered disclosures", async ({
  page,
}) => {
  await page.goto("/");

  const featureDetails = page.locator(".feature-detail");
  await expect(featureDetails).toHaveCount(4);
  await expect(page.locator(".feature-detail__number")).toHaveCount(0);
  await expect(page.locator(".feature-detail details, .feature-detail summary")).toHaveCount(0);
  await expect(page.locator(".feature-detail__media")).toHaveCount(4);
  await expect(page.locator(".feature-detail__media img")).toHaveCount(5);

  const featureGeometry = await featureDetails.evaluateAll((features) =>
    features.map((feature) => {
      const copy = feature.querySelector(".feature-detail__copy");
      const media = feature.querySelector(".feature-detail__media");
      if (!(copy instanceof HTMLElement) || !(media instanceof HTMLElement)) {
        throw new Error("Supporting feature is missing copy or media");
      }

      const copyBounds = copy.getBoundingClientRect();
      const mediaBounds = media.getBoundingClientRect();
      return {
        copyWidth: copyBounds.width,
        mediaWidth: mediaBounds.width,
        mediaFollowsCopy:
          mediaBounds.left >= copyBounds.right || mediaBounds.top >= copyBounds.bottom,
      };
    }),
  );

  for (const geometry of featureGeometry) {
    expect(geometry.copyWidth).toBeGreaterThan(0);
    expect(geometry.mediaWidth).toBeGreaterThan(0);
    expect(geometry.mediaFollowsCopy).toBe(true);
  }
});

test("separates the showcase and follow-up with spacing instead of a duplicate rule", async ({
  page,
}) => {
  await page.setViewportSize({ width: 1600, height: 1000 });
  await page.goto("/");

  const transitionGeometry = await page.evaluate(() => {
    const productPlate = document.querySelector(".product-plate");
    const featureHeading = document.querySelector(".feature-details .section-heading");
    const finalCallToAction = document.querySelector(".final-cta");
    if (
      !(productPlate instanceof HTMLElement) ||
      !(featureHeading instanceof HTMLElement) ||
      !(finalCallToAction instanceof HTMLElement)
    ) {
      throw new Error("Homepage transition surfaces are incomplete");
    }

    return {
      showcaseToDetailsGap:
        featureHeading.getBoundingClientRect().top - productPlate.getBoundingClientRect().bottom,
      finalCallToActionBorderTopWidth: getComputedStyle(finalCallToAction).borderTopWidth,
    };
  });

  expect(transitionGeometry.showcaseToDetailsGap).toBeGreaterThanOrEqual(80);
  expect(transitionGeometry.finalCallToActionBorderTopWidth).toBe("0px");
});

test("morphs the frame-width header into a max-w-2xl floating glass pill", async ({ page }) => {
  await page.setViewportSize({ width: 1600, height: 1000 });
  await page.goto("/");

  const headerActions = page.locator(".site-header .header-social-action");
  await expect(headerActions).toHaveCount(2);
  expect(
    await headerActions.evaluateAll((actions) =>
      actions.map((action) => {
        const actionBounds = action.getBoundingClientRect();
        const iconBounds = action.querySelector("svg")?.getBoundingClientRect();
        if (iconBounds === undefined) {
          throw new Error("Header action is missing its icon");
        }

        return {
          actionWidth: actionBounds.width,
          actionHeight: actionBounds.height,
          iconWidth: iconBounds.width,
          iconHeight: iconBounds.height,
        };
      }),
    ),
  ).toEqual([
    { actionWidth: 32, actionHeight: 32, iconWidth: 18, iconHeight: 18 },
    { actionWidth: 32, actionHeight: 32, iconWidth: 16, iconHeight: 16 },
  ]);

  const headerFrost = page.locator(".site-header-frost");
  await expect(headerFrost).toHaveCSS("opacity", "0");

  const restingGeometry = await page.evaluate(() => {
    const header = document.querySelector(".site-header");
    const frame = document.querySelector(".site-frame");
    const main = frame?.querySelector(":scope > main");
    const brand = header?.querySelector(".brand-link");
    const heroEyebrow = document.querySelector(".hero .eyebrow");
    if (
      !(header instanceof HTMLElement) ||
      !(frame instanceof HTMLElement) ||
      !(main instanceof HTMLElement) ||
      !(brand instanceof HTMLElement) ||
      !(heroEyebrow instanceof HTMLElement)
    ) {
      throw new Error("Site shell surfaces are incomplete");
    }

    const headerStyle = getComputedStyle(header);
    const mainStyle = getComputedStyle(main);
    const headerBounds = header.getBoundingClientRect();
    const frameBounds = frame.getBoundingClientRect();
    return {
      headerState: header.dataset["visualState"],
      header: {
        top: headerStyle.borderTopWidth,
        right: headerStyle.borderRightWidth,
        bottom: headerStyle.borderBottomWidth,
        left: headerStyle.borderLeftWidth,
        radius: headerStyle.borderRadius,
        width: headerBounds.width,
        x: headerBounds.x,
        paddingLeft: headerStyle.paddingLeft,
        paddingRight: headerStyle.paddingRight,
      },
      frame: {
        width: frameBounds.width,
        x: frameBounds.x,
      },
      main: {
        right: mainStyle.borderRightWidth,
        left: mainStyle.borderLeftWidth,
      },
      contentAlignmentDelta: Math.abs(
        brand.getBoundingClientRect().x - heroEyebrow.getBoundingClientRect().x,
      ),
    };
  });

  expect(restingGeometry.headerState).toBe("resting");
  expect(restingGeometry.header).toMatchObject({
    top: "1px",
    right: "1px",
    bottom: "1px",
    left: "1px",
  });
  expect(restingGeometry.header.radius).toBe("24px");
  expect(restingGeometry.header.width).toBe(restingGeometry.frame.width);
  expect(restingGeometry.header.x).toBe(restingGeometry.frame.x);
  expect(restingGeometry.header.paddingLeft).toBe("72px");
  expect(restingGeometry.header.paddingRight).toBe("72px");
  expect(restingGeometry.contentAlignmentDelta).toBeLessThanOrEqual(1);
  expect(restingGeometry.main).toEqual({ right: "0px", left: "0px" });

  await page.evaluate(() => window.scrollTo({ top: 500, behavior: "instant" }));
  const siteHeader = page.locator(".site-header");
  await expect(siteHeader).toHaveAttribute("data-visual-state", "floating");
  await expect(siteHeader).toHaveCSS("width", "672px");
  await expect(siteHeader).toHaveCSS("border-radius", "24px");
  await expect(headerFrost).toHaveCSS("opacity", "1");

  const floatingGeometry = await siteHeader.evaluate((header) => {
    const headerStyle = getComputedStyle(header);
    const bounds = header.getBoundingClientRect();
    return {
      width: bounds.width,
      top: bounds.top,
      radius: headerStyle.borderRadius,
      backgroundColor: headerStyle.backgroundColor,
      backdropFilter: headerStyle.backdropFilter,
      boxShadow: headerStyle.boxShadow,
    };
  });

  expect(floatingGeometry.width).toBe(672);
  expect(floatingGeometry.top).toBeGreaterThanOrEqual(10);
  expect(floatingGeometry.radius).toBe("24px");
  expect(floatingGeometry.backgroundColor).not.toBe("rgb(46, 48, 54)");
  expect(floatingGeometry.backdropFilter).not.toBe("none");
  expect(floatingGeometry.boxShadow).not.toBe("none");

  const frostGeometry = await page.evaluate(() => {
    const header = document.querySelector(".site-header");
    const frost = document.querySelector(".site-header-frost");
    if (!(header instanceof HTMLElement) || !(frost instanceof HTMLElement)) {
      throw new Error("Floating header frost surfaces are incomplete");
    }

    const headerBounds = header.getBoundingClientRect();
    const frostBounds = frost.getBoundingClientRect();
    const headerStyle = getComputedStyle(header);
    const frostStyle = getComputedStyle(frost);
    return {
      sameLeft: frostBounds.left === headerBounds.left,
      sameRight: frostBounds.right === headerBounds.right,
      frostTop: frostBounds.top,
      frostBottom: frostBounds.bottom,
      headerTop: headerBounds.top,
      headerTopRadius: Number(headerStyle.borderTopLeftRadius.replace("px", "")),
      backgroundColor: frostStyle.backgroundColor,
      backdropFilter: frostStyle.backdropFilter,
      maskImage: frostStyle.maskImage,
    };
  });

  expect(frostGeometry.sameLeft).toBe(true);
  expect(frostGeometry.sameRight).toBe(true);
  expect(frostGeometry.frostTop).toBe(0);
  expect(frostGeometry.headerTop).toBe(16);
  expect(frostGeometry.frostBottom).toBe(frostGeometry.headerTop + frostGeometry.headerTopRadius);
  expect(frostGeometry.backgroundColor).toBe("rgba(0, 0, 0, 0)");
  expect(frostGeometry.backdropFilter).toBe("blur(8px) saturate(1.2)");
  expect(frostGeometry.maskImage).toContain("rgb(0, 0, 0) 8px");
});

test("contains phone composition within the document viewport", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/");

  const siteHeader = page.locator(".site-header");
  const documentWidths = await page.evaluate(() => {
    const header = document.querySelector(".site-header");
    if (!(header instanceof HTMLElement)) {
      throw new Error("Site header is missing");
    }

    return {
      clientWidth: document.documentElement.clientWidth,
      scrollWidth: document.documentElement.scrollWidth,
      attachedHeaderWidth: header.getBoundingClientRect().width,
    };
  });

  expect(documentWidths.scrollWidth).toBeLessThanOrEqual(documentWidths.clientWidth);
  expect(documentWidths.attachedHeaderWidth).toBe(documentWidths.clientWidth - 2);

  await page.evaluate(() => window.scrollTo({ top: 500, behavior: "instant" }));
  await expect(siteHeader).toHaveAttribute("data-visual-state", "floating");
  await expect(siteHeader).toHaveCSS("width", "312px");
  await expect(page.getByRole("tab", { name: /Git context/ })).toBeAttached();
  await expect(page.getByRole("button", { name: "Before close" })).toBeAttached();
});
