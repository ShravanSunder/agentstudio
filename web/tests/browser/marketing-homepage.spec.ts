import { expect, test } from "@playwright/test";

const productStoryCases = [
  { id: "parallel-work", accessibleName: /Parallel agents/ },
  { id: "watch-folder", accessibleName: /Watch folders/ },
  { id: "quick-find", accessibleName: /Command bar/ },
  { id: "files", accessibleName: /^Files/ },
  { id: "review", accessibleName: /Review/ },
] as const;

const verificationViewports = [
  { width: 1600, height: 1000 },
  { width: 390, height: 844 },
] as const;

function invertSmoothstep(target: number): number {
  let lowerBound = 0;
  let upperBound = 1;
  for (let iteration = 0; iteration < 24; iteration += 1) {
    const midpoint = (lowerBound + upperBound) / 2;
    const eased = midpoint * midpoint * (3 - 2 * midpoint);
    if (eased < target) {
      lowerBound = midpoint;
    } else {
      upperBound = midpoint;
    }
  }
  return (lowerBound + upperBound) / 2;
}

interface PhoneProductPlateComposition {
  readonly captionAfterImage: boolean;
  readonly captionIsOutlined: boolean;
  readonly captionIsRounded: boolean;
  readonly captionStoryId: string | undefined;
  readonly captionUsesNeutralSurface: boolean;
  readonly imageStoryId: string | null | undefined;
  readonly imageIsInsetWithinPlate: boolean;
  readonly imagePaneIsOutlined: boolean;
  readonly imagePaneIsRounded: boolean;
  readonly imageUsesPortraitCrop: boolean;
  readonly panelAnimationName: string;
  readonly selectedDotDisplay: string;
  readonly sharedWrapperIsTransparent: boolean;
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
    const image = plate
      .querySelector('[data-product-plate-panel="parallel-work"] img')
      ?.getBoundingClientRect();
    const selected = plate.querySelector('[aria-selected="true"]');

    if (selectors === undefined || image === undefined || selected === null) {
      throw new Error("Product plate geometry is incomplete");
    }

    return {
      stackedLayout: selectors.bottom <= image.top + 1,
      imageGap: Math.abs(selectors.right - image.left),
      stackedImageGap: Math.abs(selectors.bottom - image.top),
      selectedBackground: getComputedStyle(selected).backgroundColor,
    };
  });
  if (plateGeometry.stackedLayout) {
    expect(plateGeometry.stackedImageGap).toBeGreaterThan(0);
    expect(plateGeometry.selectedBackground).not.toBe("rgba(0, 0, 0, 0)");
  } else {
    expect(plateGeometry.imageGap).toBeGreaterThan(0);
    expect(plateGeometry.selectedBackground).toBe("rgba(0, 0, 0, 0)");
  }

  const originalUrl = page.url();
  await page.getByRole("tab", { name: /Watch folders/ }).click();
  await expect(page.getByRole("tabpanel", { name: /Watch folders/ })).toBeVisible();
  expect(page.url()).toBe(originalUrl);

  await page.getByRole("tab", { name: /Watch folders/ }).press("ArrowRight");
  await expect(page.getByRole("tab", { name: /Command bar/ })).toHaveAttribute(
    "aria-selected",
    "true",
  );

  await page.getByRole("tab", { name: /Review/ }).click();
  await expect(page.getByRole("tabpanel", { name: /Review/ })).toBeVisible();

  const persistencePanel = page.locator(".feature-detail").filter({
    has: page.getByRole("heading", { name: "Close the app, not your sessions." }),
  });
  const sessionRestoreVideo = persistencePanel.locator("[data-session-restore-video]");
  await expect(sessionRestoreVideo).toBeVisible();
  await expect(sessionRestoreVideo).toHaveAttribute("controls", "");
  await expect(sessionRestoreVideo).toHaveAttribute("muted", "");
  await expect(sessionRestoreVideo).toHaveAttribute("playsinline", "");
  await expect(sessionRestoreVideo).toHaveAttribute("preload", "metadata");
  await expect(sessionRestoreVideo.locator('source[type="video/mp4"]')).toHaveCount(1);
  await expect(sessionRestoreVideo.locator("a")).toHaveCount(0);
  await expect(sessionRestoreVideo.locator("span")).toHaveText(
    "This browser cannot play the session restore video.",
  );

  const videoGeometry = await persistencePanel.evaluate((panel) => {
    const video = panel.querySelector("[data-session-restore-video]");
    const media = panel.querySelector(".feature-detail__media");

    if (!(video instanceof HTMLVideoElement) || !(media instanceof HTMLElement)) {
      throw new Error("Session restore video or media boundary is missing");
    }

    const panelBounds = media.getBoundingClientRect();
    const videoBounds = video.getBoundingClientRect();
    return {
      leftInset: videoBounds.left - panelBounds.left,
      rightInset: panelBounds.right - videoBounds.right,
      aspectRatio: videoBounds.width / videoBounds.height,
    };
  });
  expect(videoGeometry.leftInset).toBeGreaterThan(0);
  expect(Math.abs(videoGeometry.leftInset - videoGeometry.rightInset)).toBeLessThanOrEqual(1);
  expect(videoGeometry.aspectRatio).toBeCloseTo(16 / 9, 2);

  await expect
    .poll(() =>
      page
        .locator('[data-product-plate-panel="parallel-work"] img')
        .evaluate((image) => (image instanceof HTMLImageElement ? image.naturalWidth : 0)),
    )
    .toBeGreaterThan(0);
  await expect
    .poll(() =>
      sessionRestoreVideo.evaluate((video) =>
        video instanceof HTMLVideoElement
          ? video.readyState >= HTMLMediaElement.HAVE_METADATA
          : false,
      ),
    )
    .toBe(true);
});

test("coordinates session video playback with glass focus and manual intent", async ({ page }) => {
  await page.setViewportSize({ width: 1600, height: 1000 });
  await page.goto("/");

  const video = page.locator("[data-session-restore-video]");
  const materialSurface = page.locator("[data-scroll-material-surface]").filter({ has: video });
  await expect(video).toHaveAttribute("data-scroll-autoplay-start-progress", "0.95");
  await expect(video).toHaveAttribute("data-scroll-autoplay-stop-progress", "0.9");
  await expect(video).toHaveAttribute("data-scroll-autoplay-replay-delay-ms", "3000");
  await expect
    .poll(() =>
      video.evaluate((element) =>
        element instanceof HTMLVideoElement
          ? element.readyState >= HTMLMediaElement.HAVE_METADATA
          : false,
      ),
    )
    .toBe(true);

  const moveSurfaceToProgress = async (targetProgress: number): Promise<void> => {
    const rawProgress = invertSmoothstep(targetProgress);
    await materialSurface.evaluate(async (surface, uneasedProgress) => {
      const surfaceStyle = getComputedStyle(surface);
      const currentLift = Number.parseFloat(
        surfaceStyle.getPropertyValue("--scroll-material-lift"),
      );
      const surfaceBounds = surface.getBoundingClientRect();
      const documentTop =
        window.scrollY + surfaceBounds.top - (Number.isFinite(currentLift) ? currentLift : 0);
      const bottomBookend = window.innerHeight * 0.9;
      const targetSurfaceTop = bottomBookend - uneasedProgress * surfaceBounds.height;
      window.scrollTo({ top: documentTop - targetSurfaceTop, behavior: "instant" });
      await new Promise<void>((resolve) =>
        window.requestAnimationFrame(() => window.requestAnimationFrame(() => resolve())),
      );
    }, rawProgress);
  };

  const readVideoState = async (): Promise<{
    readonly currentTime: number;
    readonly duration: number;
    readonly ended: boolean;
    readonly paused: boolean;
  }> =>
    video.evaluate((element) => {
      if (!(element instanceof HTMLVideoElement)) {
        throw new Error("Session restore media is not a video");
      }
      return {
        currentTime: element.currentTime,
        duration: element.duration,
        ended: element.ended,
        paused: element.paused,
      };
    });

  const playManually = async (): Promise<void> => {
    await video.evaluate(async (element) => {
      if (!(element instanceof HTMLVideoElement)) {
        throw new Error("Session restore media is not a video");
      }
      await element.play();
    });
  };

  const pauseManually = async (): Promise<void> => {
    await video.evaluate((element) => {
      if (!(element instanceof HTMLVideoElement)) {
        throw new Error("Session restore media is not a video");
      }
      element.pause();
    });
  };

  await moveSurfaceToProgress(0);
  await expect.poll(async () => (await readVideoState()).paused).toBe(true);

  await moveSurfaceToProgress(0.96);
  await expect.poll(async () => (await readVideoState()).paused, { timeout: 500 }).toBe(false);

  await moveSurfaceToProgress(0.92);
  await expect.poll(async () => (await readVideoState()).paused).toBe(false);

  await moveSurfaceToProgress(0.89);
  await expect.poll(async () => (await readVideoState()).paused).toBe(true);

  await playManually();
  await moveSurfaceToProgress(0);
  await expect.poll(async () => (await readVideoState()).paused).toBe(false);

  await video.evaluate((element) => {
    if (!(element instanceof HTMLVideoElement)) {
      throw new Error("Session restore media is not a video");
    }
    element.currentTime = Math.max(0, element.duration - 0.1);
  });
  await expect
    .poll(async () => {
      const state = await readVideoState();
      return state.paused && state.currentTime < 0.1;
    })
    .toBe(true);
  await page.waitForTimeout(3200);
  await expect
    .poll(async () => {
      const state = await readVideoState();
      return state.paused && state.currentTime < 0.1;
    })
    .toBe(true);

  await moveSurfaceToProgress(0.96);
  await page.waitForTimeout(700);
  await expect.poll(async () => (await readVideoState()).paused).toBe(true);
  await moveSurfaceToProgress(0.97);
  await page.waitForTimeout(700);
  await moveSurfaceToProgress(0.96);
  await page.waitForTimeout(700);
  await moveSurfaceToProgress(0.97);
  await page.waitForTimeout(1200);
  await expect.poll(async () => (await readVideoState()).paused, { timeout: 500 }).toBe(false);

  await pauseManually();
  await moveSurfaceToProgress(0.92);
  await expect.poll(async () => (await readVideoState()).paused).toBe(true);
  await moveSurfaceToProgress(0.89);
  await moveSurfaceToProgress(0.96);
  await expect.poll(async () => (await readVideoState()).paused).toBe(false);
});

test("keeps reduced-motion video autoplay disabled without blocking manual play", async ({
  page,
}) => {
  await page.setViewportSize({ width: 1600, height: 1000 });
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/");

  const video = page.locator("[data-session-restore-video]");
  const readPaused = async (): Promise<boolean> =>
    video.evaluate((element) => {
      if (!(element instanceof HTMLVideoElement)) {
        throw new Error("Session restore media is not a video");
      }
      return element.paused;
    });
  await expect.poll(readPaused).toBe(true);
  await video.evaluate(async (element) => {
    if (!(element instanceof HTMLVideoElement)) {
      throw new Error("Session restore media is not a video");
    }
    await element.play();
  });
  await page.evaluate(() => window.scrollTo({ top: 800, behavior: "instant" }));
  await expect.poll(readPaused).toBe(false);
});

for (const viewport of verificationViewports) {
  test(`fills every comparison header at ${viewport.width}x${viewport.height}`, async ({
    page,
  }) => {
    await page.setViewportSize(viewport);
    await page.goto("/");

    const controlRows = page.locator('[data-persistence-proof] [role="group"]');
    await expect(controlRows).toHaveCount(1);

    const rowGeometry = await controlRows.evaluateAll((rows) =>
      rows.map((row) => {
        const controls = [...row.querySelectorAll("button")];
        if (controls.length !== 2) {
          throw new Error("Comparison header must contain exactly two controls");
        }

        const rowBounds = row.getBoundingClientRect();
        const firstControlBounds = controls[0]?.getBoundingClientRect();
        const secondControlBounds = controls[1]?.getBoundingClientRect();
        if (firstControlBounds === undefined || secondControlBounds === undefined) {
          throw new Error("Comparison controls are missing");
        }

        const selectedControl = controls.find(
          (control) => control.getAttribute("aria-pressed") === "true",
        );
        const unselectedControl = controls.find(
          (control) => control.getAttribute("aria-pressed") === "false",
        );
        if (
          !(selectedControl instanceof HTMLElement) ||
          !(unselectedControl instanceof HTMLElement)
        ) {
          throw new Error("Comparison selection state is missing");
        }
        const selectedFrostStyle = getComputedStyle(selectedControl, "::before");
        const selectedDotStyle = getComputedStyle(selectedControl, "::after");
        const unselectedFrostStyle = getComputedStyle(unselectedControl, "::before");
        const selectedLabel = selectedControl.querySelector("span");
        if (!(selectedLabel instanceof HTMLElement)) {
          throw new Error("Comparison selected label is missing");
        }

        return {
          controlsFillRow:
            Math.abs(firstControlBounds.left - rowBounds.left) <= 1 &&
            Math.abs(secondControlBounds.right - rowBounds.right) <= 1,
          controlsHaveEqualWidth:
            Math.abs(firstControlBounds.width - secondControlBounds.width) <= 1,
          labelFontSize: getComputedStyle(selectedControl).fontSize,
          selectedLabel: {
            color: getComputedStyle(selectedLabel).color,
            height: selectedLabel.getBoundingClientRect().height,
            text: selectedLabel.textContent?.trim(),
            width: selectedLabel.getBoundingClientRect().width,
            zIndex: getComputedStyle(selectedLabel).zIndex,
          },
          selectedDot: {
            animationName: selectedDotStyle.animationName,
            backgroundColor: selectedDotStyle.backgroundColor,
            display: selectedDotStyle.display,
            height: selectedDotStyle.height,
            width: selectedDotStyle.width,
          },
          selectedFrostOpacity: selectedFrostStyle.opacity,
          selectedFrostZIndex: selectedFrostStyle.zIndex,
          unselectedFrostOpacity: unselectedFrostStyle.opacity,
        };
      }),
    );

    expect(rowGeometry.every(({ controlsFillRow }) => controlsFillRow)).toBe(true);
    expect(rowGeometry.every(({ controlsHaveEqualWidth }) => controlsHaveEqualWidth)).toBe(true);
    expect(rowGeometry.every(({ labelFontSize }) => labelFontSize === "11px")).toBe(true);
    expect(
      rowGeometry.every(
        ({ selectedFrostZIndex, selectedLabel }) =>
          selectedLabel.color === "rgb(255, 255, 255)" &&
          selectedLabel.height > 0 &&
          selectedLabel.width > 0 &&
          selectedLabel.text !== undefined &&
          selectedLabel.text.length > 0 &&
          Number(selectedLabel.zIndex) > Number(selectedFrostZIndex),
      ),
    ).toBe(true);
    expect(rowGeometry.every(({ selectedFrostOpacity }) => selectedFrostOpacity === "1")).toBe(
      true,
    );
    expect(rowGeometry.every(({ unselectedFrostOpacity }) => unselectedFrostOpacity === "0")).toBe(
      true,
    );
    for (const geometry of rowGeometry) {
      expect(geometry.selectedDot.backgroundColor).toBe("rgb(137, 180, 250)");
      expect(geometry.selectedDot.width).toBe("8px");
      expect(geometry.selectedDot.height).toBe("8px");
      if (viewport.width < 1024) {
        expect(geometry.selectedDot.display).toBe("none");
      } else {
        expect(geometry.selectedDot.display).not.toBe("none");
        expect(geometry.selectedDot.animationName).not.toBe("none");
      }
    }
  });
}

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
    const selectorStage = selectors.parentElement;
    const selectorStageBounds = selectorStage?.getBoundingClientRect();
    const selectedImageBounds = document
      .querySelector("[data-product-plate-panel]:not([hidden]) img")
      ?.getBoundingClientRect();
    const storyBounds = [...selectors.querySelectorAll("[data-product-plate-selector]")].map(
      (story) => story.getBoundingClientRect(),
    );
    const selectedStory = selectors.querySelector('[aria-selected="true"]');
    const selectedTitle = selectedStory?.querySelector("strong");
    const selectedDescription = selectedStory?.querySelector("[data-product-plate-description]");
    const previousButton = selectorStage?.querySelector("[data-product-plate-previous]");
    const nextButton = selectorStage?.querySelector("[data-product-plate-next]");
    const imagePane = document.querySelector(".product-plate__image-frame");

    if (
      !(selectorStage instanceof HTMLElement) ||
      selectorStageBounds === undefined ||
      selectedImageBounds === undefined ||
      !(selectedStory instanceof HTMLElement) ||
      !(selectedTitle instanceof HTMLElement) ||
      !(selectedDescription instanceof HTMLElement) ||
      !(previousButton instanceof HTMLElement) ||
      !(nextButton instanceof HTMLElement) ||
      !(imagePane instanceof HTMLElement)
    ) {
      throw new Error("Collapsed carousel is missing its stage or selected image");
    }

    const compactControls = [previousButton, selectedStory, nextButton];
    return {
      arrowBackgrounds: [previousButton, nextButton].map(
        (button) => getComputedStyle(button).backgroundColor,
      ),
      controlGap: Number.parseFloat(getComputedStyle(selectorStage).columnGap),
      controlsAreOutlined: compactControls.every(
        (control) =>
          Number.parseFloat(getComputedStyle(control).borderTopWidth) > 0 &&
          getComputedStyle(control).borderTopColor !== "rgba(0, 0, 0, 0)",
      ),
      controlsAreRounded: compactControls.every(
        (control) => Number.parseFloat(getComputedStyle(control).borderTopLeftRadius) > 0,
      ),
      descriptionDisplay: getComputedStyle(selectedDescription).display,
      imageGap: selectedImageBounds.top - selectorStageBounds.bottom,
      imagePaneBackground: getComputedStyle(imagePane).backgroundColor,
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

  expect(collapsedGeometry.arrowBackgrounds).toEqual([
    collapsedGeometry.imagePaneBackground,
    collapsedGeometry.imagePaneBackground,
  ]);
  expect(collapsedGeometry.selectedBackground).toBe(collapsedGeometry.imagePaneBackground);
  expect(collapsedGeometry.controlGap).toBeGreaterThan(0);
  expect(collapsedGeometry.controlsAreOutlined).toBe(true);
  expect(collapsedGeometry.controlsAreRounded).toBe(true);
  expect(collapsedGeometry.descriptionDisplay).toBe("none");
  expect(collapsedGeometry.overflowX).toBe("auto");
  expect(collapsedGeometry.imageGap).toBeGreaterThan(0);
  await expect(page.locator("[data-product-plate-index]")).toHaveCount(0);
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
  await expect(page.locator('[data-product-plate-selector="watch-folder"]')).toHaveAttribute(
    "aria-selected",
    "true",
  );
  await expect(page.locator('[data-product-plate-panel="watch-folder"]')).toBeVisible();
  await expect(page.locator('[data-product-plate-caption="watch-folder"]')).toBeVisible();
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
  await expect(page.locator('[data-product-plate-selector="watch-folder"]')).toHaveAttribute(
    "aria-selected",
    "true",
  );
  await expect(page.locator('[data-product-plate-caption="watch-folder"]')).toBeVisible();

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
      imageIsSeparatedFromRail: imageBounds.left > selectorBounds.right,
      selectorWidth: selectorBounds.width,
    };
  });

  expect(boundaryGeometry).toEqual({ imageIsSeparatedFromRail: true, selectorWidth: 280 });
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
      const panel = image?.closest("[data-product-plate-panel]");
      const imagePane = image?.closest(".product-plate__image-frame");
      const imageColumn = productPlate.querySelector(".product-plate__image-column");
      const visibleCaptions = [
        ...productPlate.querySelectorAll("[data-product-plate-caption]"),
      ].filter((caption) => {
        const bounds = caption.getBoundingClientRect();
        return bounds.width > 0 && bounds.height > 0;
      });

      if (
        !(stage instanceof HTMLElement) ||
        !(image instanceof HTMLImageElement) ||
        !(panel instanceof HTMLElement) ||
        !(imagePane instanceof HTMLElement) ||
        !(imageColumn instanceof HTMLElement)
      ) {
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
      const captionStyle = getComputedStyle(caption);
      const imagePaneStyle = getComputedStyle(imagePane);
      const selectedStory = productPlate.querySelector('[aria-selected="true"]');
      if (!(selectedStory instanceof HTMLElement)) {
        throw new Error("Phone product plate is missing its selected story");
      }

      return {
        captionStoryId: caption.dataset["productPlateCaption"],
        imageStoryId: image
          .closest("[data-product-plate-panel]")
          ?.getAttribute("data-product-plate-panel"),
        stageHeight: stageBounds.height,
        titleBeforeImage: stageBounds.bottom <= imageBounds.top + 1,
        captionAfterImage: captionBounds.top >= imageBounds.bottom - 1,
        captionIsOutlined: Number.parseFloat(captionStyle.borderTopWidth) > 0,
        captionIsRounded: Number.parseFloat(captionStyle.borderTopLeftRadius) > 0,
        imageIsInsetWithinPlate:
          imageBounds.left > plateBounds.left && imageBounds.right < plateBounds.right,
        captionUsesNeutralSurface: captionStyle.backgroundColor === imagePaneStyle.backgroundColor,
        imagePaneIsOutlined: Number.parseFloat(imagePaneStyle.borderTopWidth) > 0,
        imagePaneIsRounded: Number.parseFloat(imagePaneStyle.borderTopLeftRadius) > 0,
        imageUsesPortraitCrop: Math.abs(image.naturalWidth / image.naturalHeight - 0.8) < 0.01,
        panelAnimationName: getComputedStyle(panel).animationName,
        selectedDotDisplay: getComputedStyle(selectedStory, "::after").display,
        sharedWrapperIsTransparent:
          getComputedStyle(imageColumn).backgroundColor === "rgba(0, 0, 0, 0)",
        visibleCaptionCount: visibleCaptions.length,
      };
    });

  await expect(page.locator('[data-product-plate-caption="parallel-work"]')).toBeVisible();
  expect(await readPhoneComposition()).toMatchObject({
    captionStoryId: "parallel-work",
    imageStoryId: "parallel-work",
    titleBeforeImage: true,
    captionAfterImage: true,
    captionIsOutlined: true,
    captionIsRounded: true,
    captionUsesNeutralSurface: true,
    imageIsInsetWithinPlate: true,
    imagePaneIsOutlined: true,
    imagePaneIsRounded: true,
    imageUsesPortraitCrop: true,
    panelAnimationName: "none",
    selectedDotDisplay: "none",
    sharedWrapperIsTransparent: true,
    visibleCaptionCount: 1,
  });
  expect((await readPhoneComposition()).stageHeight).toBeLessThanOrEqual(96);

  await nextStory.click();
  await expect(page.locator('[data-product-plate-caption="watch-folder"]')).toBeVisible();
  expect(await readPhoneComposition()).toMatchObject({
    captionStoryId: "watch-folder",
    imageStoryId: "watch-folder",
    visibleCaptionCount: 1,
  });
});

test("uses the focused command-bar crop at phone width", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/");
  await page.getByRole("tab", { name: /Command bar/ }).click();

  const commandBarImage = page.locator('[data-product-plate-panel="quick-find"] img');
  await expect
    .poll(() =>
      commandBarImage.evaluate((image) =>
        image instanceof HTMLImageElement
          ? {
              height: image.naturalHeight,
              source: image.currentSrc,
              width: image.naturalWidth,
            }
          : null,
      ),
    )
    .toEqual({
      height: 1600,
      source: expect.stringContaining("command-bar-phone.png"),
      width: 1280,
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
          expect(image.unusedPanelRegionBelow).toBeLessThanOrEqual(4.01);
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

  await expect(selectedStory).toHaveCSS("background-color", "rgba(0, 0, 0, 0)");
  await expect(page.locator("[data-product-plate-index]")).toHaveCount(0);
  await expect(selectedTitle).toHaveCSS("color", "rgb(255, 255, 255)");
  expect(
    await selectedStory
      .locator("[data-product-plate-description]")
      .evaluate((description) => getComputedStyle(description).color),
  ).toContain("/ 0.85)");
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
  expect(
    await reviewStory
      .locator("[data-product-plate-description]")
      .evaluate((description) => getComputedStyle(description).color),
  ).toContain("/ 0.85)");
  await expect(parallelStory.locator("[data-product-plate-description]")).toBeVisible();
  await expect(parallelStory.locator("[data-product-plate-description]")).toHaveCSS(
    "color",
    "rgb(197, 200, 198)",
  );

  await page.setViewportSize({ width: 1023, height: 900 });
  await expect(reviewStory).not.toHaveCSS("background-color", "rgba(0, 0, 0, 0)");
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
  await expect(page.locator(".feature-detail__media img")).toHaveCount(3);
  await expect(page.locator(".feature-detail__media video")).toHaveCount(1);
  await expect(featureDetails.first().locator("picture source")).toHaveCount(0);
  await expect(featureDetails.first().getByRole("heading")).toHaveText("Keep tabs on your code.");
  await expect(page.getByRole("heading", { name: "Run the agents you already use." })).toHaveCount(
    0,
  );

  const arrangementsPanel = page.locator(".feature-detail").filter({
    has: page.getByRole("heading", { name: "Go big on one pane." }),
  });
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
      const title = feature.querySelector(".feature-detail__title");
      const description = feature.querySelector(".feature-detail__description");
      const media = feature.querySelector(".feature-detail__media");
      if (
        !(copy instanceof HTMLElement) ||
        !(title instanceof HTMLElement) ||
        !(description instanceof HTMLElement) ||
        !(media instanceof HTMLElement)
      ) {
        throw new Error("Supporting feature is missing copy or media");
      }

      const copyBounds = copy.getBoundingClientRect();
      const titleBounds = title.getBoundingClientRect();
      const descriptionBounds = description.getBoundingClientRect();
      const mediaBounds = media.getBoundingClientRect();
      const copyStyle = getComputedStyle(copy);
      const titleStyle = getComputedStyle(title);
      const descriptionStyle = getComputedStyle(description);
      const mediaStyle = getComputedStyle(media);
      const featureStyle = getComputedStyle(feature);
      const compactLayout = window.matchMedia("(width < 64rem)").matches;
      const visiblePaneStyles = compactLayout
        ? [titleStyle, mediaStyle, descriptionStyle]
        : [copyStyle, mediaStyle];
      return {
        compactLayout,
        copyWidth: compactLayout ? titleBounds.width : copyBounds.width,
        descriptionAfterMedia: descriptionBounds.top >= mediaBounds.bottom,
        desktopCopyLeftAlignment: Math.abs(titleBounds.left - descriptionBounds.left),
        desktopDescriptionBelowTitle: descriptionBounds.top >= titleBounds.bottom,
        hasScrollMaterialOwner: feature.hasAttribute("data-scroll-material-surface"),
        paneGap: Number.parseFloat(featureStyle.gap),
        panesAreOutlined: visiblePaneStyles.every(
          (style) => Number.parseFloat(style.borderTopWidth) > 0,
        ),
        panesAreRounded: visiblePaneStyles.every(
          (style) => Number.parseFloat(style.borderTopLeftRadius) > 0,
        ),
        panesShareMaterial: visiblePaneStyles.every(
          (style) => style.backgroundColor === visiblePaneStyles[0]?.backgroundColor,
        ),
        sideBySide: mediaBounds.left >= copyBounds.right,
        titleBeforeMedia: titleBounds.bottom <= mediaBounds.top,
        desktopHeightDelta: Math.abs(copyBounds.height - mediaBounds.height),
        mediaWidth: mediaBounds.width,
        mediaFollowsCopy:
          mediaBounds.left >= copyBounds.right || titleBounds.bottom <= mediaBounds.top,
      };
    }),
  );

  for (const geometry of featureGeometry) {
    expect(geometry.copyWidth).toBeGreaterThan(0);
    expect(geometry.mediaWidth).toBeGreaterThan(0);
    expect(geometry.mediaFollowsCopy).toBe(true);
    expect(geometry.hasScrollMaterialOwner).toBe(true);
    expect(geometry.paneGap).toBeGreaterThan(0);
    expect(geometry.panesAreOutlined).toBe(true);
    expect(geometry.panesAreRounded).toBe(true);
    expect(geometry.panesShareMaterial).toBe(true);
    if (geometry.compactLayout) {
      expect(geometry.titleBeforeMedia).toBe(true);
      expect(geometry.descriptionAfterMedia).toBe(true);
    } else {
      expect(geometry.sideBySide).toBe(true);
      expect(geometry.desktopHeightDelta).toBeLessThanOrEqual(1);
      expect(geometry.desktopDescriptionBelowTitle).toBe(true);
      expect(geometry.desktopCopyLeftAlignment).toBeLessThanOrEqual(1);
    }
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
  expect(frostGeometry.backdropFilter).toBe("blur(4px) saturate(1.2)");
  expect(frostGeometry.maskImage).toContain("rgb(0, 0, 0) 8px");
});

test("lifts the slideshow on one detached glass surface", async ({ page }) => {
  await page.setViewportSize({ width: 1600, height: 1000 });
  await page.goto("/");

  const showcaseSurface = page.locator("[data-showcase-surface]");
  await expect(showcaseSurface).toHaveCount(1);
  await expect(page.locator(".showcase-surface-frost")).toHaveCount(0);
  await expect(showcaseSurface).toHaveAttribute("data-visual-state", "resting");

  const restingMaterial = await showcaseSurface.evaluate((surface) => {
    const surfaceStyle = getComputedStyle(surface);
    return {
      backgroundColor: surfaceStyle.backgroundColor,
      borderColor: surfaceStyle.borderTopColor,
      progress: surfaceStyle.getPropertyValue("--scroll-material-progress"),
    };
  });
  expect(restingMaterial).toEqual({
    backgroundColor: "rgba(30, 30, 46, 0)",
    borderColor: "rgba(137, 180, 250, 0)",
    progress: "0.000",
  });

  await showcaseSurface.evaluate(async (surface) => {
    const surfaceStyle = getComputedStyle(surface);
    const lift = Number.parseFloat(surfaceStyle.getPropertyValue("--scroll-material-lift")) || 0;
    const bounds = surface.getBoundingClientRect();
    const documentTop = window.scrollY + bounds.top - lift;
    const bottomBookendTop = window.innerHeight - bounds.height;
    const midpointTop = (bottomBookendTop + 96) / 2;
    window.scrollTo({ top: documentTop - midpointTop, behavior: "instant" });
    await new Promise<void>((resolve) =>
      window.requestAnimationFrame(() => window.requestAnimationFrame(() => resolve())),
    );
  });
  await expect(showcaseSurface).toHaveAttribute("data-visual-state", "floating");

  const liftedSurface = await showcaseSurface.evaluate((surface) => {
    const surfaceStyle = getComputedStyle(surface);
    const selectedImage = surface.querySelector("[data-product-plate-panel]:not([hidden]) img");
    const selectorRail = surface.querySelector(".product-plate__selectors");
    const selectorStage = surface.querySelector(".product-plate__selector-stage");
    const imageColumn = surface.querySelector(".product-plate__image-column");
    const imageFrame = selectedImage?.closest(".product-plate__image-frame");
    const selectedSelector = selectorRail?.querySelector('[aria-selected="true"]');
    if (
      !(selectedImage instanceof HTMLImageElement) ||
      !(selectorRail instanceof HTMLElement) ||
      !(selectorStage instanceof HTMLElement) ||
      !(imageColumn instanceof HTMLElement) ||
      !(imageFrame instanceof HTMLElement) ||
      !(selectedSelector instanceof HTMLElement)
    ) {
      throw new Error("Morphed showcase surface is missing its image or glass selector rail");
    }

    const imageBounds = selectedImage.getBoundingClientRect();
    const selectedTitle = selectedSelector.querySelector("strong");
    if (!(selectedTitle instanceof HTMLElement)) {
      throw new Error("Selected showcase story is missing its title");
    }
    const selectedTitleBounds = selectedTitle.getBoundingClientRect();
    const selectedSelectorBounds = selectedSelector.getBoundingClientRect();
    const selectorStageBounds = selectorStage.getBoundingClientRect();
    const imageColumnBounds = imageColumn.getBoundingClientRect();
    const imageFrameBounds = imageFrame.getBoundingClientRect();
    const selectedGlassStyle = getComputedStyle(selectedSelector, "::before");
    const selectedDotStyle = getComputedStyle(selectedSelector, "::after");
    const selectedDotCenter =
      selectedSelectorBounds.top +
      Number.parseFloat(selectedDotStyle.top) +
      Number.parseFloat(selectedDotStyle.width) / 2;
    return {
      backdropFilter: surfaceStyle.backdropFilter,
      backgroundColor: surfaceStyle.backgroundColor,
      borderColor: surfaceStyle.borderTopColor,
      boxShadow: surfaceStyle.boxShadow,
      imageWidth: imageBounds.width,
      imageColumnBackground: getComputedStyle(imageColumn).backgroundColor,
      imageColumnBlur: getComputedStyle(imageColumn).backdropFilter,
      imageInset: {
        top: imageBounds.top - imageFrameBounds.top,
        right: imageFrameBounds.right - imageBounds.right,
        bottom: imageFrameBounds.bottom - imageBounds.bottom,
        left: imageBounds.left - imageFrameBounds.left,
      },
      outerGap: getComputedStyle(surface).gap,
      outerPadding: getComputedStyle(surface).padding,
      selectorStageHeightDelta: Math.abs(selectorStageBounds.height - imageColumnBounds.height),
      selectedGlassBackdropFilter: selectedGlassStyle.backdropFilter,
      selectedGlassBackgroundColor: selectedGlassStyle.backgroundColor,
      selectedGlassOpacity: selectedGlassStyle.opacity,
      selectedDotAnimationName: selectedDotStyle.animationName,
      selectedDotBackgroundColor: selectedDotStyle.backgroundColor,
      selectedDotTitleCenterDelta: Math.abs(
        selectedTitleBounds.top + selectedTitleBounds.height / 2 - selectedDotCenter,
      ),
      progress: Number(surfaceStyle.getPropertyValue("--scroll-material-progress")),
      transform: surfaceStyle.transform,
    };
  });

  expect(liftedSurface.backdropFilter).not.toBe("none");
  expect(liftedSurface.backgroundColor).not.toBe("rgba(30, 30, 46, 0)");
  expect(liftedSurface.borderColor).toBe("rgba(137, 180, 250, 0.38)");
  expect(liftedSurface.boxShadow).not.toBe("none");
  expect(liftedSurface.imageWidth).toBeGreaterThan(900);
  expect(liftedSurface.imageColumnBackground).not.toBe("rgba(0, 0, 0, 0)");
  expect(liftedSurface.imageColumnBlur).not.toBe("none");
  expect(liftedSurface.imageInset).toEqual({ top: 4, right: 4, bottom: 4, left: 4 });
  expect(liftedSurface.outerGap).toBe("4px");
  expect(liftedSurface.outerPadding).toBe("4px");
  expect(liftedSurface.selectorStageHeightDelta).toBeLessThanOrEqual(1);
  expect(liftedSurface.selectedGlassBackdropFilter).not.toBe("none");
  expect(liftedSurface.selectedGlassBackgroundColor).not.toBe("rgba(0, 0, 0, 0)");
  expect(liftedSurface.selectedGlassOpacity).toBe("1");
  expect(liftedSurface.selectedDotAnimationName).not.toBe("none");
  expect(liftedSurface.selectedDotBackgroundColor).toBe("rgb(137, 180, 250)");
  expect(liftedSurface.selectedDotTitleCenterDelta).toBeLessThanOrEqual(1);
  expect(liftedSurface.progress).toBeGreaterThanOrEqual(0.98);
  expect(liftedSurface.transform).not.toBe("none");
});

test("holds full glass while the complete showcase remains visible", async ({ page }) => {
  await page.setViewportSize({ width: 1600, height: 1000 });
  await page.goto("/");

  const showcaseSurface = page.locator("[data-showcase-surface]");
  await expect
    .poll(() =>
      showcaseSurface
        .locator('[data-product-plate-panel="parallel-work"] img')
        .evaluate((image) => (image instanceof HTMLImageElement ? image.naturalWidth : 0)),
    )
    .toBeGreaterThan(0);

  const geometry = await showcaseSurface.evaluate((surface) => {
    const bounds = surface.getBoundingClientRect();
    return {
      height: bounds.height,
      viewportHeight: window.innerHeight,
    };
  });

  const readProgressAt = async (surfaceTop: number): Promise<number> => {
    await showcaseSurface.evaluate(async (surface, targetSurfaceTop) => {
      const surfaceStyle = getComputedStyle(surface);
      const lift = Number.parseFloat(surfaceStyle.getPropertyValue("--scroll-material-lift")) || 0;
      const documentTop = window.scrollY + surface.getBoundingClientRect().top - lift;
      window.scrollTo({ top: documentTop - targetSurfaceTop, behavior: "instant" });
      await new Promise<void>((resolve) =>
        window.requestAnimationFrame(() => window.requestAnimationFrame(() => resolve())),
      );
    }, surfaceTop);
    return showcaseSurface.evaluate((surface) =>
      Number(getComputedStyle(surface).getPropertyValue("--scroll-material-progress")),
    );
  };

  const entryStartTop = geometry.viewportHeight * 0.9;
  const fullyEnteredTop = entryStartTop - geometry.height;
  const visibleTop = geometry.viewportHeight * 0.1;
  const fullyVisibleMidpointTop = (fullyEnteredTop + visibleTop) / 2;
  const exitMidpointTop = visibleTop - geometry.height / 2;
  const fullyExitedTop = visibleTop - geometry.height;

  expect(await readProgressAt(entryStartTop)).toBeLessThanOrEqual(0.02);
  expect(await readProgressAt(fullyEnteredTop)).toBeGreaterThanOrEqual(0.98);
  expect(await readProgressAt(fullyVisibleMidpointTop)).toBeGreaterThanOrEqual(0.98);
  expect(await readProgressAt(visibleTop)).toBeGreaterThanOrEqual(0.98);
  expect(await readProgressAt(exitMidpointTop)).toBeCloseTo(0.5, 1);
  expect(await readProgressAt(fullyExitedTop)).toBeLessThanOrEqual(0.02);
  expect(await readProgressAt(exitMidpointTop)).toBeCloseTo(0.5, 1);
  expect(await readProgressAt(visibleTop)).toBeGreaterThanOrEqual(0.98);
  expect(await readProgressAt(fullyVisibleMidpointTop)).toBeGreaterThanOrEqual(0.98);
  expect(await readProgressAt(fullyEnteredTop)).toBeGreaterThanOrEqual(0.98);
  expect(await readProgressAt(entryStartTop)).toBeLessThanOrEqual(0.02);
});

test("keeps the glass slideshow surface static with reduced motion", async ({ page }) => {
  await page.setViewportSize({ width: 1600, height: 1000 });
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/");

  const showcaseSurface = page.locator("[data-showcase-surface]");
  await expect(showcaseSurface).toHaveAttribute("data-visual-state", "floating");

  const initialPresentation = await showcaseSurface.evaluate((surface) => {
    const surfaceStyle = getComputedStyle(surface);
    const selectedSelector = surface.querySelector('[aria-selected="true"]');
    if (!(selectedSelector instanceof HTMLElement)) {
      throw new Error("Reduced-motion showcase is missing its selected story");
    }
    const selectedDotStyle = getComputedStyle(selectedSelector, "::after");
    return {
      dotAnimationName: selectedDotStyle.animationName,
      dotOpacity: selectedDotStyle.opacity,
      progress: surfaceStyle.getPropertyValue("--scroll-material-progress"),
      transform: surfaceStyle.transform,
    };
  });

  await showcaseSurface.evaluate((surface) => {
    surface.scrollIntoView({ behavior: "instant", block: "start" });
  });

  expect(initialPresentation).toEqual({
    dotAnimationName: "none",
    dotOpacity: "0.8",
    progress: "1.000",
    transform: "none",
  });
  await expect(showcaseSurface).toHaveCSS("transform", "none");
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
      attachedHeader: {
        width: header.getBoundingClientRect().width,
        x: header.getBoundingClientRect().x,
        top: header.getBoundingClientRect().top,
        radius: getComputedStyle(header).borderRadius,
        borders: {
          top: getComputedStyle(header).borderTopWidth,
          right: getComputedStyle(header).borderRightWidth,
          bottom: getComputedStyle(header).borderBottomWidth,
          left: getComputedStyle(header).borderLeftWidth,
        },
      },
    };
  });

  expect(documentWidths.scrollWidth).toBeLessThanOrEqual(documentWidths.clientWidth);
  expect(documentWidths.attachedHeader).toEqual({
    width: documentWidths.clientWidth,
    x: 0,
    top: 0,
    radius: "0px",
    borders: {
      top: "0px",
      right: "0px",
      bottom: "0px",
      left: "0px",
    },
  });

  await page.evaluate(() => window.scrollTo({ top: 500, behavior: "instant" }));
  await expect(siteHeader).toHaveAttribute("data-visual-state", "floating");
  await expect(siteHeader).toHaveCSS("width", "312px");
  await expect(siteHeader).toHaveCSS("border-radius", "24px");
  await expect(page.getByRole("tab", { name: /^Files/ })).toBeAttached();
  await expect(page.locator("[data-session-restore-video]")).toBeAttached();
});

test("keeps the compact attached header edge-to-edge until it detaches", async ({ page }) => {
  await page.setViewportSize({ width: 900, height: 900 });
  await page.goto("/");

  const siteHeader = page.locator(".site-header");
  const attachedGeometry = await siteHeader.evaluate((header) => {
    const bounds = header.getBoundingClientRect();
    const style = getComputedStyle(header);
    return {
      clientWidth: document.documentElement.clientWidth,
      width: bounds.width,
      x: bounds.x,
      top: bounds.top,
      radius: style.borderRadius,
      borders: [
        style.borderTopWidth,
        style.borderRightWidth,
        style.borderBottomWidth,
        style.borderLeftWidth,
      ],
    };
  });

  expect(attachedGeometry.width).toBe(attachedGeometry.clientWidth);
  expect(attachedGeometry).toMatchObject({
    x: 0,
    top: 0,
    radius: "0px",
    borders: ["0px", "0px", "0px", "0px"],
  });

  await page.evaluate(() => window.scrollTo({ top: 500, behavior: "instant" }));
  await expect(siteHeader).toHaveAttribute("data-visual-state", "floating");
  await expect(siteHeader).toHaveCSS("width", "672px");
  await expect(siteHeader).toHaveCSS("border-radius", "24px");
  expect(
    await siteHeader.evaluate((header) => {
      const style = getComputedStyle(header);
      return [
        style.borderTopWidth,
        style.borderRightWidth,
        style.borderBottomWidth,
        style.borderLeftWidth,
      ];
    }),
  ).toEqual(["1px", "1px", "1px", "1px"]);
});
