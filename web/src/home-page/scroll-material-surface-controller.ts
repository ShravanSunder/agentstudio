const viewportEdgeInsetRatio = 0.1;
const phoneMediaQuery = "(max-width: 620px)";

let disposeActiveController: (() => void) | undefined;

function clampProgress(progress: number): number {
  return Math.min(1, Math.max(0, progress));
}

function easeProgress(progress: number): number {
  return progress * progress * (3 - 2 * progress);
}

function applySurfaceProgress(surface: HTMLElement, progress: number, shouldLift: boolean): void {
  const phoneLayout = window.matchMedia(phoneMediaQuery).matches;
  const liftDistance = phoneLayout ? 12 : 24;
  surface.style.setProperty("--scroll-material-progress", progress.toFixed(3));
  surface.style.setProperty(
    "--scroll-material-lift",
    `${shouldLift ? (-liftDistance * progress).toFixed(2) : "0"}px`,
  );
  surface.style.setProperty(
    "--scroll-material-border-color",
    `rgb(137 180 250 / ${(0.38 * progress).toFixed(3)})`,
  );
  surface.style.setProperty("--scroll-material-primary-alpha", (0.11 * progress).toFixed(3));
  surface.style.setProperty("--scroll-material-cyan-alpha", (0.06 * progress).toFixed(3));
  surface.style.setProperty("--scroll-material-ground-alpha", (0.88 * progress).toFixed(3));
  surface.style.setProperty("--scroll-material-shadow-alpha", (0.28 * progress).toFixed(3));
  surface.style.setProperty(
    "--scroll-material-secondary-shadow-alpha",
    (0.18 * progress).toFixed(3),
  );
  surface.style.setProperty("--scroll-material-highlight-alpha", (0.1 * progress).toFixed(3));
  surface.style.setProperty("--scroll-material-blur", `${(20 * progress).toFixed(2)}px`);
  surface.style.setProperty("--scroll-material-saturation", `${(100 + 20 * progress).toFixed(2)}%`);
  surface.style.setProperty(
    "--scroll-material-radius",
    `${(16 + (phoneLayout ? 2 : 4) * progress).toFixed(2)}px`,
  );
  surface.dataset["visualState"] =
    progress >= 0.98 ? "floating" : progress <= 0.02 ? "resting" : "transitioning";
}

function readSurfaceProgress(surface: HTMLElement): number {
  const surfaceBounds = surface.getBoundingClientRect();
  const currentLift = Number.parseFloat(
    getComputedStyle(surface).getPropertyValue("--scroll-material-lift"),
  );
  const surfaceTop = surfaceBounds.top - (Number.isFinite(currentLift) ? currentLift : 0);
  const surfaceBottom = surfaceTop + surfaceBounds.height;
  const topBookend = window.innerHeight * viewportEdgeInsetRatio;
  const bottomBookend = window.innerHeight * (1 - viewportEdgeInsetRatio);
  const fullyEnteredTop = bottomBookend - surfaceBounds.height;
  const rawProgress = clampProgress(
    surfaceTop >= fullyEnteredTop
      ? (bottomBookend - surfaceTop) / surfaceBounds.height
      : surfaceTop >= topBookend
        ? 1
        : (surfaceBottom - topBookend) / surfaceBounds.height,
  );
  return easeProgress(rawProgress);
}

export function initializeScrollMaterialSurfaces(): void {
  disposeActiveController?.();

  const surfaces = Array.from(
    document.querySelectorAll<HTMLElement>("[data-scroll-material-surface]"),
  );
  if (surfaces.length === 0) {
    return;
  }

  const reducedMotionQuery = window.matchMedia("(prefers-reduced-motion: reduce)");
  let pendingAnimationFrame: number | undefined;
  let isDisposed = false;

  const synchronizeSurfaces = (): void => {
    for (const surface of surfaces) {
      if (reducedMotionQuery.matches) {
        applySurfaceProgress(surface, 1, false);
        continue;
      }
      applySurfaceProgress(surface, readSurfaceProgress(surface), true);
    }
  };

  const scheduleSurfaceUpdate = (): void => {
    if (pendingAnimationFrame !== undefined) {
      return;
    }
    pendingAnimationFrame = window.requestAnimationFrame((): void => {
      pendingAnimationFrame = undefined;
      synchronizeSurfaces();
    });
  };

  const disposeSurfaceUpdates = (): void => {
    if (isDisposed) {
      return;
    }
    isDisposed = true;
    if (pendingAnimationFrame !== undefined) {
      window.cancelAnimationFrame(pendingAnimationFrame);
      pendingAnimationFrame = undefined;
    }
    window.removeEventListener("scroll", scheduleSurfaceUpdate);
    window.removeEventListener("resize", scheduleSurfaceUpdate);
    window.removeEventListener("pagehide", handlePageHide);
    reducedMotionQuery.removeEventListener("change", scheduleSurfaceUpdate);
    if (disposeActiveController === disposeSurfaceUpdates) {
      disposeActiveController = undefined;
    }
  };

  const handlePageHide = (event: PageTransitionEvent): void => {
    if (!event.persisted) {
      disposeSurfaceUpdates();
    }
  };

  disposeActiveController = disposeSurfaceUpdates;
  synchronizeSurfaces();
  window.addEventListener("scroll", scheduleSurfaceUpdate, { passive: true });
  window.addEventListener("resize", scheduleSurfaceUpdate, { passive: true });
  reducedMotionQuery.addEventListener("change", scheduleSurfaceUpdate);
  window.addEventListener("pagehide", handlePageHide);
}

if (import.meta.hot) {
  import.meta.hot.dispose((): void => {
    disposeActiveController?.();
  });
}
