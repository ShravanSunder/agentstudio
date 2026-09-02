import { describe, expect, test } from 'vitest';

import {
	fileUsablePaintIsVisible,
	reviewUsablePaintIsVisible,
} from './bridge-complete-journey-usable-paint.ts';

describe('Bridge complete journey usable-paint proof', () => {
	test('keeps Review pending until reading and navigation controls are enabled', () => {
		document.body.innerHTML = `
			<div data-testid="bridge-viewer-mode-host-review" data-bridge-viewer-mode-active="true">
				<div data-testid="review-viewer-shell" data-review-metadata-item-count="1" data-selected-content-state="ready"></div>
				<div data-testid="bridge-review-trees-panel"></div>
				<div data-testid="bridge-code-view-panel"></div>
				<button data-testid="bridge-viewer-context-file">Files</button>
				<button data-testid="bridge-review-view-settings-trigger">View settings</button>
			</div>
		`;
		makeProofElementsVisible();

		expect(reviewUsablePaintIsVisible()).toBe(true);
		const readingControl = requiredButton('bridge-review-view-settings-trigger');
		readingControl.disabled = true;
		expect(reviewUsablePaintIsVisible()).toBe(false);
		readingControl.disabled = false;
		requiredButton('bridge-viewer-context-file').disabled = true;
		expect(reviewUsablePaintIsVisible()).toBe(false);
	});

	test('keeps File pending until reading and navigation controls are enabled', () => {
		document.body.innerHTML = `
			<div data-testid="bridge-viewer-mode-host-file" data-bridge-viewer-mode-active="true">
				<div data-testid="bridge-file-viewer-shell" data-file-display-status="ready"></div>
				<div data-testid="bridge-file-viewer-pierre-file-tree"></div>
				<div data-testid="bridge-file-viewer-code-canvas" data-worktree-open-file-state="ready" data-worktree-open-file-path="tracked.txt"></div>
				<button data-testid="bridge-viewer-context-review">Review</button>
				<button data-testid="bridge-file-view-settings-trigger">View settings</button>
			</div>
		`;
		makeProofElementsVisible();

		expect(fileUsablePaintIsVisible()).toBe(true);
		const navigationControl = requiredButton('bridge-viewer-context-review');
		navigationControl.disabled = true;
		expect(fileUsablePaintIsVisible()).toBe(false);
		navigationControl.disabled = false;
		requiredButton('bridge-file-view-settings-trigger').disabled = true;
		expect(fileUsablePaintIsVisible()).toBe(false);
	});
});

function makeProofElementsVisible(): void {
	for (const element of document.body.querySelectorAll<HTMLElement>('[data-testid]')) {
		element.style.display = 'block';
		element.style.height = '10px';
		element.style.width = '10px';
	}
}

function requiredButton(testId: string): HTMLButtonElement {
	const element = document.querySelector(`[data-testid="${testId}"]`);
	if (!(element instanceof HTMLButtonElement)) throw new Error(`Missing ${testId}`);
	return element;
}
