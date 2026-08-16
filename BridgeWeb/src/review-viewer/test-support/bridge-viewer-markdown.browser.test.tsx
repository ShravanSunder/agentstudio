import { act } from 'react';
import { afterEach, describe, expect, test } from 'vitest';
import { cleanup } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production app CSS.
import '../../app/bridge-app.css';
import {
	advanceBridgeReviewRecoveryWitnessFrames,
	disposeBridgeReviewRecoveryWitnessHarnesses,
	renderBridgeReviewRecoveryWitness,
} from './bridge-viewer-browser.recovery-witness.test-support.js';

describe('Bridge Review Markdown Browser Mode', () => {
	afterEach(async (): Promise<void> => {
		await cleanup();
		disposeBridgeReviewRecoveryWitnessHarnesses();
		await advanceBridgeReviewRecoveryWitnessFrames(2);
		document.body.replaceChildren();
	});

	test('keeps Markdown in the exact Pierre Diff and offers Open after the change counts', async () => {
		const baseContent = ['# Review Markdown proof', '', 'Previous paragraph.', ''].join('\n');
		const headContent = [
			'# Review Markdown proof',
			'',
			'Changed paragraph.',
			'',
			'```swift',
			'let reviewMarkdownProof: String = "Current Swift"',
			'```',
			'',
		].join('\n');
		const harness = await renderBridgeReviewRecoveryWitness([
			{
				baseContent,
				contentMarker: 'REVIEW_MARKDOWN_CURRENT',
				extension: 'md',
				fileClass: 'docs',
				headContent,
				itemId: 'review-markdown-item',
				language: 'markdown',
				lineCount: headContent.split('\n').length - 1,
				mimeType: 'text/markdown',
				path: 'docs/review-markdown-proof.md',
			},
		]);

		await harness.publishDisplay();
		await expect.poll(() => harness.selectedItemCommandCount()).toBe(1);
		expect(harness.selectedItemPresentations()).toEqual([undefined]);
		const selectedItemCommandCountBeforeOpen = harness.selectedItemCommandCount();
		await harness.publishCompleteContent();
		await waitForReviewSelector('[data-testid="bridge-code-view-panel"]');
		await waitForReviewCondition(
			(): boolean =>
				harness
					.paintedCodeViewItems()
					.some((paintedItem): boolean => paintedItem.text.includes('Changed paragraph.')),
			'Pierre paint containing the current Markdown line',
		);

		const reviewShell = requireHTMLElement(
			document.querySelector('[data-testid="review-viewer-shell"]'),
		);
		const headerMetadata = requireHTMLElement(
			document.querySelector('[data-testid="bridge-code-view-header-metadata"]'),
		);
		const openButton = requireHTMLElement(
			headerMetadata.querySelector('button[aria-label="Open"]'),
		);

		expect(reviewShell.getAttribute('data-selected-display-path')).toBe(
			'docs/review-markdown-proof.md',
		);
		expect(reviewShell.getAttribute('data-review-canvas-branch')).toBe('code');
		expect(document.querySelector('[data-testid="bridge-markdown-canvas"]')).toBeNull();
		expect(
			document.querySelector('[data-testid="bridge-markdown-review-projection-rendered"]'),
		).toBeNull();
		expect(
			document.querySelector('[data-testid="bridge-markdown-review-projection-diff"]'),
		).toBeNull();
		expect(headerMetadata.textContent).toContain('-');
		expect(headerMetadata.textContent).toContain('+');
		expect(openButton.getAttribute('aria-label')).toBe('Open');
		expect(openButton.getAttribute('title')).toBe('Open');
		expect(harness.renderedCodeViewItemIds()).toEqual(['review-markdown-item']);

		await act(async (): Promise<void> => {
			openButton.click();
			await Promise.resolve();
		});
		await expect
			.poll(() => harness.selectedItemCommandCount())
			.toBe(selectedItemCommandCountBeforeOpen + 1);
		expect(harness.selectedItemPresentations().at(-1)).toBe('file');
		await harness.publishFileContentForItemId('review-markdown-item');
		await expect
			.poll((): readonly (string | null)[] => {
				const codeViewPanel = document.querySelector('[data-testid="bridge-code-view-panel"]');
				return [
					codeViewPanel?.getAttribute('data-selected-content-state') ?? null,
					codeViewPanel?.getAttribute('data-selected-content-roles') ?? null,
					codeViewPanel?.getAttribute('data-selected-presentation-kind') ?? null,
				];
			})
			.toEqual(['ready', 'head', 'file']);
		await waitForReviewCondition(
			(): boolean =>
				harness
					.paintedCodeViewItems()
					.some(
						(paintedItem): boolean =>
							paintedItem.text.includes('Changed paragraph.') &&
							!paintedItem.text.includes('Previous paragraph.'),
					),
			'complete current Markdown file paint',
		);

		const diffButton = requireHTMLElement(
			document.querySelector(
				'[data-testid="bridge-code-view-header-metadata"] button[aria-label="Diff"]',
			),
		);
		await act(async (): Promise<void> => {
			diffButton.click();
			await Promise.resolve();
		});
		await expect
			.poll(() => harness.selectedItemCommandCount())
			.toBe(selectedItemCommandCountBeforeOpen + 2);
		expect(harness.selectedItemPresentations().at(-1)).toBe('diff');
		await harness.publishCompleteContent();
		await waitForReviewCondition(
			(): boolean =>
				harness
					.paintedCodeViewItems()
					.some(
						(paintedItem): boolean =>
							paintedItem.text.includes('Changed paragraph.') &&
							paintedItem.text.includes('Previous paragraph.'),
					),
			'exact Markdown diff paint after restoring Diff',
		);
	});

	test('opens a newly selected Markdown item with one click', async () => {
		const firstHeadContent = ['# First Markdown file', '', 'First current paragraph.', ''].join(
			'\n',
		);
		const secondHeadContent = ['# Second Markdown file', '', 'Second current paragraph.', ''].join(
			'\n',
		);
		const harness = await renderBridgeReviewRecoveryWitness([
			{
				baseContent: '# First Markdown file\n\nFirst previous paragraph.\n',
				contentMarker: 'REVIEW_MARKDOWN_FIRST_CURRENT',
				extension: 'md',
				fileClass: 'docs',
				headContent: firstHeadContent,
				itemId: 'review-markdown-first-item',
				language: 'markdown',
				lineCount: firstHeadContent.split('\n').length - 1,
				mimeType: 'text/markdown',
				path: 'docs/review-markdown-first.md',
			},
			{
				baseContent: '# Second Markdown file\n\nSecond previous paragraph.\n',
				contentMarker: 'REVIEW_MARKDOWN_SECOND_CURRENT',
				extension: 'md',
				fileClass: 'docs',
				headContent: secondHeadContent,
				itemId: 'review-markdown-second-item',
				language: 'markdown',
				lineCount: secondHeadContent.split('\n').length - 1,
				mimeType: 'text/markdown',
				path: 'docs/review-markdown-second.md',
			},
		]);

		await harness.publishDisplay();
		await expect.poll(() => harness.selectedItemCommandCount()).toBe(1);
		await harness.publishCompleteContent();
		await waitForReviewSelector('[data-testid="bridge-code-view-panel"]');
		const secondContainer = Array.from(document.querySelectorAll('diffs-container')).find(
			(container): boolean =>
				container.shadowRoot?.textContent?.includes('docs/review-markdown-second.md') ?? false,
		);
		if (!(secondContainer instanceof HTMLElement)) {
			throw new Error('Expected the second Markdown CodeView container.');
		}
		const openButton = requireHTMLElement(
			secondContainer.querySelector(
				'[data-testid="bridge-code-view-header-metadata"] button[aria-label="Open"]',
			),
		);

		await act(async (): Promise<void> => {
			openButton.click();
			await Promise.resolve();
		});

		await expect.poll(() => harness.selectedItemCommandCount()).toBe(2);
		expect(harness.selectedItemPresentations().at(-1)).toBe('file');
		await harness.publishFileContentForItemId('review-markdown-second-item');
		await expect
			.poll((): readonly (string | null)[] => {
				const codeViewPanel = document.querySelector('[data-testid="bridge-code-view-panel"]');
				return [
					codeViewPanel?.getAttribute('data-selected-display-path') ?? null,
					codeViewPanel?.getAttribute('data-selected-content-state') ?? null,
					codeViewPanel?.getAttribute('data-selected-presentation-kind') ?? null,
				];
			})
			.toEqual(['docs/review-markdown-second.md', 'ready', 'file']);
		expect(
			Array.from(
				document.querySelectorAll(
					'[data-testid="bridge-code-view-header-metadata"] button[aria-label="Open"]',
				),
			).some((button): boolean => button.getAttribute('aria-pressed') === 'true'),
		).toBe(true);
	});

	test('reports deleted current content unavailable while keeping Diff recovery available', async () => {
		const harness = await renderBridgeReviewRecoveryWitness([
			{
				baseContent: '# Deleted Markdown\n\nPrevious content.\n',
				changeKind: 'deleted',
				contentMarker: 'DELETED_MARKDOWN_CURRENT_UNAVAILABLE',
				extension: 'md',
				fileClass: 'docs',
				headContent: '',
				itemId: 'deleted-markdown-item',
				language: 'markdown',
				lineCount: 3,
				mimeType: 'text/markdown',
				path: 'docs/deleted-markdown.md',
			},
		]);

		await harness.publishDisplay();
		await harness.publishCompleteContent();
		await waitForReviewSelector('[data-testid="bridge-code-view-header-metadata"]');
		const openButton = requireHTMLElement(
			document.querySelector(
				'[data-testid="bridge-code-view-header-metadata"] button[aria-label="Open"]',
			),
		);
		await act(async (): Promise<void> => {
			openButton.click();
			await Promise.resolve();
		});
		await harness.publishUnavailableContentForItemId('deleted-markdown-item');
		await waitForReviewSelector('[data-testid="bridge-review-content-unavailable"]');

		expect(document.querySelector('[data-testid="bridge-code-view-panel"]')).not.toBeNull();
		const diffButton = requireHTMLElement(
			document.querySelector(
				'[data-testid="bridge-code-view-header-metadata"] button[aria-label="Diff"]',
			),
		);
		await act(async (): Promise<void> => {
			diffButton.click();
			await Promise.resolve();
		});
		await harness.publishCompleteContent();
		await waitForReviewCondition(
			(): boolean =>
				document.querySelector('[data-testid="bridge-review-content-unavailable"]') === null &&
				document
					.querySelector('[data-testid="bridge-code-view-panel"]')
					?.getAttribute('data-selected-materialized-item-type') === 'diff',
			'Diff recovery after unavailable deleted current content',
		);
	});
});

async function waitForReviewSelector(selector: string, attempt = 0): Promise<void> {
	if (document.querySelector(selector) !== null) {
		return;
	}
	if (attempt >= 60) {
		throw new Error(`Expected Review selector to appear: ${selector}`);
	}
	await advanceBridgeReviewRecoveryWitnessFrames(1);
	await waitForReviewSelector(selector, attempt + 1);
}

async function waitForReviewCondition(
	condition: () => boolean,
	description: string,
	attempt = 0,
): Promise<void> {
	if (condition()) {
		return;
	}
	if (attempt >= 60) {
		throw new Error(`Expected Review condition: ${description}`);
	}
	await advanceBridgeReviewRecoveryWitnessFrames(1);
	await waitForReviewCondition(condition, description, attempt + 1);
}

function requireHTMLElement(element: Element | null): HTMLElement {
	if (!(element instanceof HTMLElement)) {
		throw new Error('Expected an HTMLElement.');
	}
	return element;
}
