import { act } from 'react';
import { expect } from 'vitest';

import type { BridgeProductWorktreeAnnotationOperation } from '../core/comm-worker/bridge-product-call-contracts.js';
import type { RecordingAnnotationBrowserSurface } from './worktree-annotation-browser-test-support.js';

export function findLastOperation(
	surface: RecordingAnnotationBrowserSurface,
	kind: 'output.handled.clear' | 'output.scope.commit',
): BridgeProductWorktreeAnnotationOperation | undefined {
	return surface.sentOperations.findLast((operation): boolean => operation.kind === kind);
}

export function requireShareScopeButton(
	labelPrefix: 'All comments' | 'Pending comments',
): HTMLButtonElement {
	const button = document.querySelector<HTMLButtonElement>(`button[aria-label^="${labelPrefix},"]`);
	if (button !== null) return button;
	const availableLabels = [...document.querySelectorAll<HTMLElement>('button[aria-label]')].map(
		(candidate) => candidate.getAttribute('aria-label'),
	);
	throw new Error(
		`Expected ${labelPrefix} scope button. Available button labels: ${JSON.stringify(availableLabels)}.`,
	);
}

export function outputHandledClearOperations(
	surface: RecordingAnnotationBrowserSurface,
): readonly Extract<
	BridgeProductWorktreeAnnotationOperation,
	{ readonly kind: 'output.handled.clear' }
>[] {
	return surface.sentOperations.filter(
		(
			operation,
		): operation is Extract<
			BridgeProductWorktreeAnnotationOperation,
			{ readonly kind: 'output.handled.clear' }
		> => operation.kind === 'output.handled.clear',
	);
}

export function isToastAction(value: unknown): value is {
	readonly action: { readonly onClick: () => void };
} {
	if (typeof value !== 'object' || value === null || !('action' in value)) return false;
	const action = value.action;
	return (
		typeof action === 'object' &&
		action !== null &&
		'onClick' in action &&
		typeof action.onClick === 'function'
	);
}

export async function performBrowserAction(action: () => Promise<void> | void): Promise<void> {
	await act(async (): Promise<void> => {
		await action();
		await settleInteraction();
	});
}

export async function settleInteraction(): Promise<void> {
	await Promise.resolve();
	await new Promise<void>((resolve) => requestAnimationFrame(() => resolve()));
	await Promise.resolve();
}

export async function waitForShareShelfOpeningMotion(shelf: HTMLElement): Promise<void> {
	await expect.poll(() => shelf.hasAttribute('data-starting-style')).toBe(false);
	await Promise.all(shelf.getAnimations().map((animation) => animation.finished));
}

export async function finishShareShelfMotion(shelf: HTMLElement): Promise<void> {
	await waitForShareShelfEndingStyle(shelf);
	const animations = shelf.getAnimations({ subtree: true });
	for (const animation of animations) animation.finish();
	await Promise.all(animations.map((animation) => animation.finished.catch((): void => {})));
	await new Promise<void>((resolve) => requestAnimationFrame(() => resolve()));
	await Promise.resolve();
}

async function waitForShareShelfEndingStyle(
	shelf: HTMLElement,
	remainingFrames = 10,
): Promise<void> {
	if (!shelf.isConnected || shelf.hasAttribute('data-ending-style')) return;
	if (remainingFrames <= 0) throw new Error('Share shelf did not enter its closing transition.');
	await new Promise<void>((resolve) => requestAnimationFrame(() => resolve()));
	await waitForShareShelfEndingStyle(shelf, remainingFrames - 1);
}

export function requireHtmlElement(element: HTMLElement | SVGElement): HTMLElement {
	if (!(element instanceof HTMLElement)) throw new Error('Expected an HTML element.');
	return element;
}

export function clickHtmlButton(element: HTMLElement | SVGElement): void {
	requireHtmlButton(element).click();
}

export function requireHtmlButton(element: HTMLElement | SVGElement): HTMLButtonElement {
	if (!(element instanceof HTMLButtonElement)) throw new Error('Expected an HTML button.');
	return element;
}
