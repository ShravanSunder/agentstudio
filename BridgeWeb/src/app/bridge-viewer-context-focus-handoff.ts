import { useCallback, useLayoutEffect, useRef } from 'react';

export type BridgeViewerContextMode = 'file' | 'review';

export function useBridgeViewerContextFocusHandoff(
	activeViewerMode: BridgeViewerContextMode,
): (viewerMode: BridgeViewerContextMode) => void {
	const activeViewerModeRef = useRef(activeViewerMode);
	activeViewerModeRef.current = activeViewerMode;
	const pendingFocusHandoffRef = useRef<BridgeViewerContextMode | null>(null);

	useLayoutEffect((): (() => void) | undefined => {
		if (pendingFocusHandoffRef.current !== activeViewerMode) return undefined;
		pendingFocusHandoffRef.current = null;
		const frameId = requestAnimationFrame((): void => {
			if (activeViewerModeRef.current !== activeViewerMode) return;
			focusActiveBridgeViewerContextControl(activeViewerMode);
		});
		return (): void => cancelAnimationFrame(frameId);
	}, [activeViewerMode]);

	return useCallback((viewerMode: BridgeViewerContextMode): void => {
		pendingFocusHandoffRef.current = viewerMode;
		const focusedElement = document.activeElement;
		if (
			focusedElement instanceof HTMLElement &&
			focusedElement.closest('[data-testid="bridge-viewer-context-switcher"]') !== null
		) {
			focusedElement.blur();
		}
	}, []);
}

function focusActiveBridgeViewerContextControl(activeViewerMode: BridgeViewerContextMode): void {
	const activeHost = document.querySelector<HTMLElement>(
		`[data-bridge-viewer-mode-host="${activeViewerMode}"][data-bridge-viewer-mode-active="true"]`,
	);
	const incomingControl = activeHost?.querySelector<HTMLElement>(
		`[data-bridge-viewer-context-target="${activeViewerMode}"]`,
	);
	incomingControl?.focus({ preventScroll: true });
}
