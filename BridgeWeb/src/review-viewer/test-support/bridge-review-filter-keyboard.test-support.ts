import { act } from 'react';
import { userEvent } from 'vitest/browser';

export async function dispatchReviewViewerShortcut(
	modifiers: Readonly<{ altKey?: boolean; shiftKey?: boolean }>,
): Promise<void> {
	const hasAlt = modifiers.altKey === true;
	const hasShift = modifiers.shiftKey === true;
	if (hasAlt === hasShift) {
		throw new Error('Review viewer shortcut requires exactly one of Alt or Shift');
	}
	const modifier = hasAlt ? 'Alt' : 'Shift';

	await act(async (): Promise<void> => {
		await userEvent.keyboard(`{Meta>}{${modifier}>}f{/${modifier}}{/Meta}`);
	});
}

export async function dispatchReviewViewerMenuKey(
	key: 'ArrowDown' | 'ArrowRight' | 'Enter' | 'Escape',
): Promise<void> {
	await act(async (): Promise<void> => {
		await userEvent.keyboard(`{${key}}`);
	});
}

export async function navigateReviewViewerMenuTo(label: string): Promise<void> {
	for (let optionIndex = 0; optionIndex < 14; optionIndex += 1) {
		if (highlightedReviewViewerMenuOptionLabel() === label) {
			return;
		}
		await dispatchReviewViewerMenuKey('ArrowDown');
	}
	throw new Error(`Expected Base UI arrow navigation to focus ${label}.`);
}

export function highlightedReviewViewerMenuOption(): HTMLElement {
	return requireReviewHTMLElement(
		document.querySelector('[data-testid="bridge-review-facet-option"][data-highlighted]'),
	);
}

export function highlightedReviewViewerMenuOptionLabel(): string {
	const highlightedOption = document.querySelector(
		'[data-testid="bridge-review-facet-option"][data-highlighted]',
	);
	return (
		highlightedOption
			?.querySelector('[data-testid="bridge-review-facet-option-label"]')
			?.textContent?.trim() ?? ''
	);
}

function requireReviewHTMLElement(element: Element | null): HTMLElement {
	if (!(element instanceof HTMLElement)) throw new Error('Expected a real Review browser element.');
	return element;
}
