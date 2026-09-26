import { act } from 'react';

import { findBridgeViewerTreeItemButton } from '../review-viewer/test-support/bridge-viewer-browser-dom.js';
import { actFrame } from './bridge-file-viewer-browser-test-harness.js';

interface FileViewerUiTraceEntry {
	readonly contentStateText: string | null;
	readonly hasLazyFrame: boolean;
	readonly hasShell: boolean;
	readonly initialSurfaceState: string | null;
	readonly metadataTreeRowCount: string | null;
	readonly timestampMilliseconds: number;
	readonly visibleText: string;
}

declare global {
	interface Window {
		bridgeFileViewerUiTrace?: FileViewerUiTraceEntry[];
	}
}

export function startFileViewerUiTrace(): () => void {
	window.bridgeFileViewerUiTrace = [];
	const recordSnapshot = (): void => {
		const shell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
		const contentState = document.querySelector('[data-testid="bridge-file-viewer-content-state"]');
		window.bridgeFileViewerUiTrace?.push({
			contentStateText: normalizedText(contentState?.textContent ?? null),
			hasLazyFrame:
				document.querySelector('[data-testid="bridge-file-viewer-lazy-loading-frame"]') !== null,
			hasShell: shell !== null,
			initialSurfaceState: shell?.getAttribute('data-worktree-initial-surface-state') ?? null,
			metadataTreeRowCount: shell?.getAttribute('data-worktree-metadata-tree-row-count') ?? null,
			timestampMilliseconds: performance.now(),
			visibleText: normalizedText(document.body.textContent ?? '') ?? '',
		});
	};
	recordSnapshot();
	const observer = new MutationObserver(recordSnapshot);
	observer.observe(document.body, {
		attributes: true,
		childList: true,
		characterData: true,
		subtree: true,
	});
	return (): void => {
		observer.disconnect();
		recordSnapshot();
	};
}

export async function waitForFileViewerTrace(
	predicate: (entries: readonly FileViewerUiTraceEntry[]) => boolean,
	attempt = 0,
): Promise<void> {
	if (predicate(fileViewerUiTraceEntries())) {
		return;
	}
	if (attempt >= 60) {
		throw new Error(
			`Expected FileView UI trace predicate to pass; entries=${JSON.stringify(
				fileViewerUiTraceEntries().slice(-5),
			)}`,
		);
	}
	await actFrame();
	await waitForFileViewerTrace(predicate, attempt + 1);
}

export function fileViewerUiTraceEntries(): readonly FileViewerUiTraceEntry[] {
	return window.bridgeFileViewerUiTrace ?? [];
}

function normalizedText(text: string | null): string | null {
	if (text === null) {
		return null;
	}
	return text.replace(/\s+/gu, ' ').trim();
}

export function fileViewerPendingCanvasIsVisible(visibleText: string): boolean {
	return (
		visibleText.includes('Select a file') ||
		visibleText.includes('Preparing code viewer') ||
		visibleText.includes('Code highlighting worker unavailable')
	);
}

export async function waitForFileViewerHTMLElement(props: {
	readonly selector: string;
	readonly remainingAttempts?: number;
}): Promise<HTMLElement> {
	const element = document.querySelector(props.selector);
	if (element instanceof HTMLElement) {
		return element;
	}
	const remainingAttempts = props.remainingAttempts ?? 180;
	if (remainingAttempts <= 0) {
		throw new Error(`Expected FileView browser element for selector ${props.selector}.`);
	}
	await actFrame();
	return waitForFileViewerHTMLElement({
		...props,
		remainingAttempts: remainingAttempts - 1,
	});
}

export async function waitForFileViewerTreeItemButtonInAct(props: {
	readonly path: string;
	readonly remainingAttempts?: number;
}): Promise<HTMLButtonElement> {
	const button = findBridgeViewerTreeItemButton(props.path);
	if (button !== null) {
		return button;
	}
	const remainingAttempts = props.remainingAttempts ?? 180;
	if (remainingAttempts <= 0) {
		throw new Error(`Expected FileView tree item button for ${props.path}.`);
	}
	await actFrame();
	return waitForFileViewerTreeItemButtonInAct({
		...props,
		remainingAttempts: remainingAttempts - 1,
	});
}

export async function waitForFileViewerMenuOptionContaining(props: {
	readonly text: string;
}): Promise<HTMLElement> {
	return waitForFileViewerDomState(() => {
		const matchingOption = [
			...document.querySelectorAll('[data-testid="worktree-file-filter-menu-option"]'),
		]
			.filter((option): option is HTMLElement => option instanceof HTMLElement)
			.find((option): boolean => option.textContent?.includes(props.text) ?? false);
		return matchingOption;
	});
}

export async function actInteractAndSettleFileViewerCheckedMenuOption(props: {
	readonly interaction: () => Promise<void>;
	readonly option: HTMLElement;
}): Promise<void> {
	await props.interaction();
	await act(async (): Promise<void> => {
		await waitForFileViewerAnimationsToFinish(props.option);
	});
	// Base UI clears its starting-style state from an animation-frame callback.
	// Ending this act first lets React commit that callback's state update before
	// the event-driven DOM assertion below observes the transition attributes.
	await actFrame();
	await waitForFileViewerDomState(() => {
		const checkedIndicator = props.option.querySelector(
			'[data-slot="dropdown-menu-checkbox-item-indicator"] [data-checked]',
		);
		return props.option.getAttribute('aria-checked') === 'true' &&
			checkedIndicator instanceof HTMLElement &&
			!checkedIndicator.hasAttribute('data-starting-style') &&
			!checkedIndicator.hasAttribute('data-ending-style')
			? true
			: undefined;
	});

	const checkedIndicator = props.option.querySelector(
		'[data-slot="dropdown-menu-checkbox-item-indicator"] [data-checked]',
	);
	if (!(checkedIndicator instanceof HTMLElement)) {
		throw new Error(
			'Expected FileView checkbox option transition to finish with a mounted data-checked indicator.',
		);
	}
	if (
		props.option.getAttribute('aria-checked') !== 'true' ||
		checkedIndicator.hasAttribute('data-starting-style') ||
		checkedIndicator.hasAttribute('data-ending-style')
	) {
		throw new Error(
			'Expected FileView checkbox option transition to finish with aria-checked=true and no transition style.',
		);
	}
}

export async function actClickAndSettleFileViewerMenu(element: HTMLElement): Promise<void> {
	const expectedExpandedState = element.getAttribute('aria-expanded') === 'true' ? 'false' : 'true';
	await act(async (): Promise<void> => {
		element.click();
	});
	const popup = await waitForFileViewerMenuState({ element, expectedExpandedState });
	if (popup === null) {
		return;
	}

	await actFrame();
	await act(async (): Promise<void> => {
		await waitForFileViewerAnimationsToFinish(popup);
	});
	await waitForFileViewerTransitionStylesToClear(popup);
	if (expectedExpandedState === 'false') {
		await waitForFileViewerDomState(() => (popup.isConnected ? undefined : true));
	}
}

async function waitForFileViewerMenuState(props: {
	readonly element: HTMLElement;
	readonly expectedExpandedState: 'false' | 'true';
}): Promise<HTMLElement | null> {
	return waitForFileViewerDomState(() => {
		if (props.element.getAttribute('aria-expanded') !== props.expectedExpandedState) {
			return undefined;
		}

		const popup = document.querySelector('[data-testid="worktree-file-filter-menu-popover"]');
		if (props.expectedExpandedState === 'true') {
			return popup instanceof HTMLElement && popup.hasAttribute('data-open') ? popup : undefined;
		}

		if (popup === null) {
			return null;
		}
		return popup instanceof HTMLElement && popup.hasAttribute('data-closed') ? popup : undefined;
	});
}

async function waitForFileViewerAnimationsToFinish(element: HTMLElement): Promise<void> {
	const animations = element.getAnimations({ subtree: true });
	if (animations.length === 0) {
		return;
	}
	await Promise.allSettled(animations.map((animation): Promise<Animation> => animation.finished));

	const activeAnimations = element.getAnimations({ subtree: true }).filter((animation): boolean => {
		return (
			animation.pending ||
			animation.playState === 'running' ||
			animation.playState === 'paused' ||
			(!animations.includes(animation) && animation.playState !== 'finished')
		);
	});
	if (activeAnimations.length > 0) {
		await waitForFileViewerAnimationsToFinish(element);
	}
}

async function waitForFileViewerTransitionStylesToClear(element: HTMLElement): Promise<void> {
	await waitForFileViewerDomState(() => {
		if (!element.isConnected) return true;
		const transitionStylesRemain =
			element.hasAttribute('data-starting-style') ||
			element.hasAttribute('data-ending-style') ||
			element.querySelector('[data-starting-style], [data-ending-style]') !== null;
		return transitionStylesRemain ? undefined : true;
	});
}

function waitForFileViewerDomState<TStateValue>(
	readState: () => TStateValue | undefined,
): Promise<TStateValue> {
	const initialState = readState();
	if (initialState !== undefined) {
		return Promise.resolve(initialState);
	}

	return new Promise<TStateValue>((resolve): void => {
		const observer = new MutationObserver((): void => {
			const observedState = readState();
			if (observedState !== undefined) {
				observer.disconnect();
				resolve(observedState);
			}
		});
		observer.observe(document.body, { attributes: true, childList: true, subtree: true });

		const stateAfterObservationStarted = readState();
		if (stateAfterObservationStarted !== undefined) {
			observer.disconnect();
			resolve(stateAfterObservationStarted);
		}
	});
}
