import { expect, test } from "@playwright/test";

const productStoryCases = [
  { id: "parallel-work", accessibleName: /Parallel agents/ },
  { id: "pane-drawer", accessibleName: /Pane drawer/ },
  { id: "quick-find", accessibleName: /Quick Find/ },
  { id: "review", accessibleName: /Review/ },
  { id: "git-context", accessibleName: /Git and PR context/ },
] as const;

const verificationViewports = [
  { width: 1600, height: 1000 },
  { width: 390, height: 844 },
] as const;

interface PhoneProductPlateComposition {
  readonly captionAfterImage: boolean;
  readonly captionBackground: string;
  readonly captionStoryId: string | undefined;
  readonly imageStoryId: string | null | undefined;
  readonly imageUsesPlateWidth: boolean;
  readonly imageUsesUncroppedMaster: boolean;
  readonly stageHeight: number;
  readonly titleBeforeImage: boolean;
  readonly visibleCaptionCount: number;
}

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
  await expect(page.getByRole("link", { name: "GitHub", exact: true })).toHaveCount(1);
  await expect(page.locator(".site-header .header-social-action")).toHaveCount(2);
  await expect(page.locator(".final-cta .github-action")).toHaveCount(0);
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
  await expect(page.getByRole("tab", { name: /Parallel agents/ })).toHaveAttribute(
    "aria-selected",
    "true",
  );

  const plateGeometry = await page.locator(".product-plate").evaluate((plate) => {
    const selectors = plate.querySelector(".product-plate__selectors")?.getBoundingClientRect();
    const panels = plate.querySelector(".product-plate__panels")?.getBoundingClientRect();
    const image = plate
      .querySelector('[data-product-plate-panel="parallel-work"] img')
      ?.getBoundingClientRect();
    const caption = plate.querySelector('[data-product-plate-caption="parallel-work"]');
    const selected = plate.querySelector('[aria-selected="true"]');

    if (
      selectors === undefined ||
      panels === undefined ||
      image === undefined ||
      selected === null
    ) {
      throw new Error("Product plate geometry is incomplete");
    }

    const captionBounds = caption?.getBoundingClientRect();
    const captionIsVisible =
      caption instanceof HTMLElement && getComputedStyle(caption).display !== "none";
    const finalContentBottom =
      captionIsVisible && captionBounds !== undefined ? captionBounds.bottom : image.bottom;

    return {
      phoneLayout: window.matchMedia("(max-width: 38.75rem)").matches,
      stackedLayout: selectors.bottom <= image.top + 1,
      imageGap: Math.abs(selectors.right - image.left),
      stackedImageGap: Math.abs(selectors.bottom - image.top),
      panelImageTopOffset: Math.abs(panels.top - image.top),
      panelContentBottomOffset: Math.abs(panels.bottom - finalContentBottom),
      selectedBackground: getComputedStyle(selected).backgroundColor,
    };
  });
  if (plateGeometry.stackedLayout) {
    expect(plateGeometry.stackedImageGap).toBeLessThanOrEqual(1);
  } else {
    expect(plateGeometry.imageGap).toBeLessThanOrEqual(1);
  }
  expect(plateGeometry.panelImageTopOffset).toBeLessThanOrEqual(2);
  expect(plateGeometry.panelContentBottomOffset).toBeLessThanOrEqual(2);
  expect(plateGeometry.selectedBackground).toBe("rgb(36, 38, 43)");

  const originalUrl = page.url();
  await page.getByRole("tab", { name: /Pane drawer/ }).click();
  await expect(page.getByRole("tabpanel", { name: /Pane drawer/ })).toBeVisible();
  expect(page.url()).toBe(originalUrl);

  await page.getByRole("tab", { name: /Pane drawer/ }).press("ArrowRight");
  await expect(page.getByRole("tab", { name: /Quick Find/ })).toHaveAttribute(
    "aria-selected",
    "true",
  );

  await page.getByRole("tab", { name: /Git and PR context/ }).click();
  await expect(page.getByRole("tabpanel", { name: /Git and PR context/ })).toBeVisible();

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
  const carouselActions = page.locator("[data-product-plate-previous], [data-product-plate-next]");
  await expect(carouselActions).toHaveCount(2);
  const allSelectorsDisabled = await selectors.evaluateAll((buttons) =>
    buttons.every((button) => button instanceof HTMLButtonElement && button.disabled),
  );
  const allCarouselActionsDisabled = await carouselActions.evaluateAll((buttons) =>
    buttons.every((button) => button instanceof HTMLButtonElement && button.disabled),
  );
  expect(allSelectorsDisabled).toBe(true);
  expect(allCarouselActionsDisabled).toBe(true);
  await expect(page.locator('[data-product-plate-panel="parallel-work"]')).toBeVisible();
  await expect(page.locator('[data-product-plate-panel="review"]')).toBeHidden();
  await expect(page.locator("[data-product-plate-selectors]")).not.toHaveAttribute(
    "role",
    "tablist",
  );

  await context.close();
});

test("synchronizes collapsed product-story text and imagery as one carousel", async ({ page }) => {
  await page.setViewportSize({ width: 1023, height: 900 });
  await page.goto("/");

  const previousStory = page.getByRole("button", { name: "Previous workspace view" });
  const nextStory = page.getByRole("button", { name: "Next workspace view" });
  const selectorViewport = page.locator("[data-product-plate-selectors]");

  await expect(previousStory).toBeVisible();
  await expect(previousStory).toBeEnabled();
  await expect(nextStory).toBeVisible();
  await expect(nextStory).toBeEnabled();
  await expect(previousStory).toHaveCSS("color", "rgb(197, 200, 198)");
  await expect(nextStory).toHaveCSS("color", "rgb(197, 200, 198)");
  await expect(page.locator('[data-product-plate-caption="parallel-work"]')).toBeVisible();

  const collapsedGeometry = await selectorViewport.evaluate((selectors) => {
    const selectorBounds = selectors.getBoundingClientRect();
    const selectorStageBounds = selectors.parentElement?.getBoundingClientRect();
    const selectedImageBounds = document
      .querySelector("[data-product-plate-panel]:not([hidden]) img")
      ?.getBoundingClientRect();
    const storyBounds = [...selectors.querySelectorAll("[data-product-plate-selector]")].map(
      (story) => story.getBoundingClientRect(),
    );
    const selectedStory = selectors.querySelector('[aria-selected="true"]');
    const selectedTitle = selectedStory?.querySelector("strong");
    const selectedDescription = selectedStory?.querySelector("[data-product-plate-description]");
    const previousButton = selectors.parentElement?.querySelector("[data-product-plate-previous]");
    const nextButton = selectors.parentElement?.querySelector("[data-product-plate-next]");

    if (
      selectorStageBounds === undefined ||
      selectedImageBounds === undefined ||
      !(selectedStory instanceof HTMLElement) ||
      !(selectedTitle instanceof HTMLElement) ||
      !(selectedDescription instanceof HTMLElement) ||
      !(previousButton instanceof HTMLElement) ||
      !(nextButton instanceof HTMLElement)
    ) {
      throw new Error("Collapsed carousel is missing its stage or selected image");
    }

    return {
      arrowBackgrounds: [previousButton, nextButton].map(
        (button) => getComputedStyle(button).backgroundColor,
      ),
      descriptionDisplay: getComputedStyle(selectedDescription).display,
      imageGap: selectedImageBounds.top - selectorStageBounds.bottom,
      overflowX: getComputedStyle(selectors).overflowX,
      selectedBackground: getComputedStyle(selectedStory).backgroundColor,
      selectorStageHeight: selectorStageBounds.height,
      selectorWidth: selectorBounds.width,
      storyWidths: storyBounds.map((story) => story.width),
      storyOffsets: storyBounds.map((story) => story.left - selectorBounds.left),
      titleColor: getComputedStyle(selectedTitle).color,
      titleCenterDelta: Math.abs(
        selectedTitle.getBoundingClientRect().left +
          selectedTitle.getBoundingClientRect().width / 2 -
          (selectorBounds.left + selectorBounds.width / 2),
      ),
    };
  });

  expect(collapsedGeometry.arrowBackgrounds).toEqual(["rgb(36, 38, 43)", "rgb(36, 38, 43)"]);
  expect(collapsedGeometry.descriptionDisplay).toBe("none");
  expect(collapsedGeometry.overflowX).toBe("auto");
  expect(collapsedGeometry.imageGap).toBeLessThanOrEqual(1);
  await expect(page.locator("[data-product-plate-index]")).toHaveCount(0);
  expect(collapsedGeometry.selectedBackground).toBe("rgb(36, 38, 43)");
  expect(collapsedGeometry.selectorStageHeight).toBeLessThanOrEqual(64);
  expect(collapsedGeometry.titleColor).toBe("rgb(255, 255, 255)");
  expect(collapsedGeometry.titleCenterDelta).toBeLessThanOrEqual(1);
  expect(
    collapsedGeometry.storyWidths.every(
      (storyWidth) => Math.abs(storyWidth - collapsedGeometry.selectorWidth) <= 1,
    ),
  ).toBe(true);
  expect(collapsedGeometry.storyOffsets[0]).toBeCloseTo(0, 0);
  expect(collapsedGeometry.storyOffsets[1]).toBeCloseTo(collapsedGeometry.selectorWidth, 0);

  await nextStory.click();
  await expect(page.locator('[data-product-plate-selector="pane-drawer"]')).toHaveAttribute(
    "aria-selected",
    "true",
  );
  await expect(page.locator('[data-product-plate-panel="pane-drawer"]')).toBeVisible();
  await expect(page.locator('[data-product-plate-caption="pane-drawer"]')).toBeVisible();
  await expect(page.locator('[data-product-plate-caption="parallel-work"]')).toBeHidden();
  await expect
    .poll(async () =>
      Math.abs(
        (await selectorViewport.evaluate((selectors) => selectors.scrollLeft)) -
          collapsedGeometry.selectorWidth,
      ),
    )
    .toBeLessThanOrEqual(1);

  await selectorViewport.evaluate((selectors) => {
    selectors.style.scrollBehavior = "auto";
    selectors.scrollTo({ behavior: "auto", left: selectors.clientWidth * 2 });
    selectors.dispatchEvent(new Event("scrollend"));
  });
  await expect(page.locator('[data-product-plate-selector="quick-find"]')).toHaveAttribute(
    "aria-selected",
    "true",
  );
  await expect(page.locator('[data-product-plate-panel="quick-find"]')).toBeVisible();
  await expect(page.locator('[data-product-plate-caption="quick-find"]')).toBeVisible();

  await previousStory.click();
  await expect(page.locator('[data-product-plate-selector="pane-drawer"]')).toHaveAttribute(
    "aria-selected",
    "true",
  );
  await expect(page.locator('[data-product-plate-caption="pane-drawer"]')).toBeVisible();

  await page.setViewportSize({ width: 1600, height: 1000 });
  await expect(previousStory).toBeHidden();
  await expect(nextStory).toBeHidden();
});

test("keeps the desktop selector at Tailwind's exact lg boundary", async ({ page }) => {
  await page.setViewportSize({ width: 1024, height: 900 });
  await page.goto("/");

  await expect(page.getByRole("button", { name: "Previous workspace view" })).toBeHidden();
  await expect(page.getByRole("button", { name: "Next workspace view" })).toBeHidden();
  await expect(page.locator('[data-product-plate-caption="parallel-work"]')).toBeHidden();

  const boundaryGeometry = await page.locator(".product-plate").evaluate((plate) => {
    const selectors = plate.querySelector(".product-plate__selectors");
    const selectedImage = plate.querySelector('[data-product-plate-panel="parallel-work"] img');

    if (!(selectors instanceof HTMLElement) || !(selectedImage instanceof HTMLImageElement)) {
      throw new Error("Desktop boundary is missing its selector or selected image");
    }

    const selectorBounds = selectors.getBoundingClientRect();
    const imageBounds = selectedImage.getBoundingClientRect();
    return {
      imageFollowsRail: Math.abs(selectorBounds.right - imageBounds.left) <= 1,
      selectorWidth: selectorBounds.width,
    };
  });

  expect(boundaryGeometry).toEqual({ imageFollowsRail: true, selectorWidth: 280 });
});

test("presents the phone carousel as title, image, then matching caption", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/");

  const plate = page.locator(".product-plate");
  const nextStory = page.getByRole("button", { name: "Next workspace view" });

  const readPhoneComposition = async (): Promise<PhoneProductPlateComposition> =>
    plate.evaluate((productPlate) => {
      const stage = productPlate.querySelector(".product-plate__selector-stage");
      const image = productPlate.querySelector("[data-product-plate-panel]:not([hidden]) img");
      const visibleCaptions = [
        ...productPlate.querySelectorAll("[data-product-plate-caption]"),
      ].filter((caption) => {
        const bounds = caption.getBoundingClientRect();
        return bounds.width > 0 && bounds.height > 0;
      });

      if (!(stage instanceof HTMLElement) || !(image instanceof HTMLImageElement)) {
        throw new Error("Phone product plate is missing its title stage or selected image");
      }

      const caption = visibleCaptions[0];
      if (!(caption instanceof HTMLElement)) {
        throw new Error("Phone product plate is missing its selected caption");
      }

      const plateBounds = productPlate.getBoundingClientRect();
      const stageBounds = stage.getBoundingClientRect();
      const imageBounds = image.getBoundingClientRect();
      const captionBounds = caption.getBoundingClientRect();

      return {
        captionStoryId: caption.dataset["productPlateCaption"],
        imageStoryId: image
          .closest("[data-product-plate-panel]")
          ?.getAttribute("data-product-plate-panel"),
        stageHeight: stageBounds.height,
        titleBeforeImage: stageBounds.bottom <= imageBounds.top + 1,
        captionAfterImage: captionBounds.top >= imageBounds.bottom - 1,
        captionBackground: getComputedStyle(caption).backgroundColor,
        imageUsesPlateWidth: Math.abs(imageBounds.width - plateBounds.width) <= 2,
        imageUsesUncroppedMaster: Math.abs(image.naturalWidth / image.naturalHeight - 1.6) < 0.01,
        visibleCaptionCount: visibleCaptions.length,
      };
    });

  await expect(page.locator('[data-product-plate-caption="parallel-work"]')).toBeVisible();
  expect(await readPhoneComposition()).toMatchObject({
    captionStoryId: "parallel-work",
    imageStoryId: "parallel-work",
    titleBeforeImage: true,
    captionAfterImage: true,
    captionBackground: "rgb(36, 38, 43)",
    imageUsesPlateWidth: true,
    imageUsesUncroppedMaster: true,
    visibleCaptionCount: 1,
  });
  expect((await readPhoneComposition()).stageHeight).toBeLessThanOrEqual(96);

  await nextStory.click();
  await expect(page.locator('[data-product-plate-caption="pane-drawer"]')).toBeVisible();
  expect(await readPhoneComposition()).toMatchObject({
    captionStoryId: "pane-drawer",
    imageStoryId: "pane-drawer",
    visibleCaptionCount: 1,
  });
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

          const caption = image
            .closest("[data-product-plate-panel]")
            ?.querySelector("[data-product-plate-caption]");
          const captionBounds = caption?.getBoundingClientRect();
          const captionIsVisible =
            caption instanceof HTMLElement && getComputedStyle(caption).display !== "none";
          const finalContentBottom =
            captionIsVisible && captionBounds !== undefined
              ? captionBounds.bottom
              : imageBounds.bottom;

          return {
            naturalWidth: image.naturalWidth,
            naturalHeight: image.naturalHeight,
            renderedWidth: imageBounds.width,
            renderedHeight: imageBounds.height,
            unusedPanelRegionBelow: panelBounds.bottom - finalContentBottom,
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

test("divides the desktop selector into five equal story rows", async ({ page }) => {
  await page.setViewportSize({ width: 1600, height: 1000 });
  await page.goto("/");

  const selectedStory = page.locator('.product-plate__selector[aria-selected="true"]');
  const parallelStory = page.locator('[data-product-plate-selector="parallel-work"]');
  const selectedTitle = selectedStory.locator("strong");
  const storyRows = page.locator(".product-plate__selector");
  const storyDescriptions = storyRows.locator("[data-product-plate-description]");

  await expect(selectedStory).toHaveCSS("background-color", "rgb(36, 38, 43)");
  await expect(page.locator("[data-product-plate-index]")).toHaveCount(0);
  await expect(selectedTitle).toHaveCSS("color", "rgb(255, 255, 255)");
  await expect(selectedStory.locator("[data-product-plate-description]")).toHaveCSS(
    "color",
    "rgb(255, 255, 255)",
  );
  await expect(storyDescriptions).toHaveCount(5);
  expect(
    await storyDescriptions.evaluateAll((descriptions) =>
      descriptions.every((description) => getComputedStyle(description).display !== "none"),
    ),
  ).toBe(true);

  const desktopAccordionGeometry = await page.locator(".product-plate").evaluate((plate) => {
    const selectors = plate.querySelector(".product-plate__selectors");
    const panels = plate.querySelector(".product-plate__panels");
    const stories = [...plate.querySelectorAll<HTMLElement>(".product-plate__selector")];
    if (!(selectors instanceof HTMLElement) || !(panels instanceof HTMLElement)) {
      throw new Error("Desktop selector geometry is incomplete");
    }

    const storyHeights = stories.map((story) => story.getBoundingClientRect().height);
    return {
      railPanelHeightDelta: Math.abs(
        selectors.getBoundingClientRect().height - panels.getBoundingClientRect().height,
      ),
      rowHeightSpread: Math.max(...storyHeights) - Math.min(...storyHeights),
    };
  });

  expect(desktopAccordionGeometry.railPanelHeightDelta).toBeLessThanOrEqual(1);
  expect(desktopAccordionGeometry.rowHeightSpread).toBeLessThanOrEqual(1);

  await page.getByRole("tab", { name: /Review/ }).click();
  const reviewStory = page.getByRole("tab", { name: /Review/ });
  await expect(reviewStory).toHaveAttribute("aria-selected", "true");
  await expect(reviewStory.locator("strong")).toHaveCSS("color", "rgb(255, 255, 255)");
  await expect(reviewStory.locator("[data-product-plate-description]")).toBeVisible();
  await expect(reviewStory.locator("[data-product-plate-description]")).toHaveCSS(
    "color",
    "rgb(255, 255, 255)",
  );
  await expect(parallelStory.locator("[data-product-plate-description]")).toBeVisible();
  await expect(parallelStory.locator("[data-product-plate-description]")).toHaveCSS(
    "color",
    "rgb(197, 200, 198)",
  );

  await page.setViewportSize({ width: 1023, height: 900 });
  await expect(reviewStory).toHaveCSS("background-color", "rgb(36, 38, 43)");
  await expect(reviewStory.locator("strong")).toHaveCSS("color", "rgb(255, 255, 255)");
  await expect(reviewStory.locator("[data-product-plate-description]")).toBeHidden();
});

test("presents supporting features as text and product media without numbered disclosures", async ({
  page,
}) => {
  await page.goto("/");

  const featureDetails = page.locator(".feature-detail");
  await expect(featureDetails).toHaveCount(3);
  await expect(page.locator(".feature-detail__number")).toHaveCount(0);
  await expect(page.locator(".feature-detail details, .feature-detail summary")).toHaveCount(0);
  await expect(page.locator(".feature-detail__media")).toHaveCount(3);
  await expect(page.locator(".feature-detail__media img")).toHaveCount(5);
  await expect(page.getByRole("heading", { name: "Run the agents you already use." })).toHaveCount(
    0,
  );

  const arrangementsPanel = page.locator(".feature-detail").nth(1);
  const savedLayoutButton = arrangementsPanel.getByRole("button", { name: "Saved layout" });
  const paneZoomButton = arrangementsPanel.getByRole("button", { name: "Pane Zoom" });
  await expect(savedLayoutButton).toHaveAttribute("aria-pressed", "true");
  await expect(paneZoomButton).toHaveAttribute("aria-pressed", "false");
  await paneZoomButton.click();
  await expect(savedLayoutButton).toHaveAttribute("aria-pressed", "false");
  await expect(paneZoomButton).toHaveAttribute("aria-pressed", "true");

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
    const hero = document.querySelector(".hero");
    if (
      !(header instanceof HTMLElement) ||
      !(frame instanceof HTMLElement) ||
      !(main instanceof HTMLElement) ||
      !(brand instanceof HTMLElement) ||
      !(heroEyebrow instanceof HTMLElement) ||
      !(hero instanceof HTMLElement)
    ) {
      throw new Error("Site shell surfaces are incomplete");
    }

    const headerStyle = getComputedStyle(header);
    const mainStyle = getComputedStyle(main);
    const headerBounds = header.getBoundingClientRect();
    const frameBounds = frame.getBoundingClientRect();
    const heroBounds = hero.getBoundingClientRect();
    const heroStyle = getComputedStyle(hero);
    const heroContentLeft = heroBounds.left + Number(heroStyle.paddingLeft.replace("px", ""));
    const heroContentRight = heroBounds.right - Number(heroStyle.paddingRight.replace("px", ""));
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
      headerLeftToHeroContentDelta: Math.abs(headerBounds.left - heroContentLeft),
      headerRightToHeroContentDelta: Math.abs(headerBounds.right - heroContentRight),
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
  expect(restingGeometry.header.width).toBeLessThan(restingGeometry.frame.width);
  expect(restingGeometry.header.paddingLeft).toBe("22px");
  expect(restingGeometry.header.paddingRight).toBe("22px");
  expect(restingGeometry.headerLeftToHeroContentDelta).toBeLessThanOrEqual(1);
  expect(restingGeometry.headerRightToHeroContentDelta).toBeLessThanOrEqual(1);
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
  expect(frostGeometry.headerTop).toBe(12);
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
  expect(documentWidths.attachedHeaderWidth).toBe(documentWidths.clientWidth - 36);

  await page.evaluate(() => window.scrollTo({ top: 500, behavior: "instant" }));
  await expect(siteHeader).toHaveAttribute("data-visual-state", "floating");
  await expect(siteHeader).toHaveCSS("width", "312px");
  await expect(page.getByRole("tab", { name: /Git and PR context/ })).toBeAttached();
  await expect(page.getByRole("button", { name: "Before close" })).toBeAttached();
});
