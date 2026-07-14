import { afterEach, describe, expect, test } from 'vitest';
import { cleanup } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production app CSS.
import '../../app/bridge-app.css';
import {
	advanceBridgeReviewRecoveryWitnessFrames,
	disposeBridgeReviewRecoveryWitnessHarnesses,
	makeBridgeReviewRecoveryWitnessFiles,
	renderBridgeReviewRecoveryWitness,
	scanBridgeReviewRecoveryWitnessDocument,
} from './bridge-viewer-browser.recovery-witness.test-support.js';

describe('Bridge Review sustained deep-scroll Browser witness', () => {
	afterEach(async (): Promise<void> => {
		cleanup();
		disposeBridgeReviewRecoveryWitnessHarnesses();
		await advanceBridgeReviewRecoveryWitnessFrames(2);
		document.body.replaceChildren();
	});

	test('keeps one continuous Review document painted through deep scrolling', async () => {
		// Arrange
		const files = makeBridgeReviewRecoveryWitnessFiles({
			count: 27,
			lineCount: 64,
			markerPrefix: 'DEEP_SCROLL',
		});
		const earlyFile = files[0];
		const middleFile = files[Math.floor(files.length / 2)];
		const finalFile = files.at(-1);
		if (earlyFile === undefined || middleFile === undefined || finalFile === undefined) {
			throw new Error('Deep-scroll Review recovery witness requires traversal markers.');
		}
		const harness = renderBridgeReviewRecoveryWitness(files);
		await expect
			.element(harness.renderResult.getByTestId('bridge-review-fallback-frame'))
			.toBeVisible();

		// Act
		await harness.publishDisplay();
		await expect.poll(() => harness.selectedItemCommandCount()).toBe(1);
		await expect
			.element(harness.renderResult.getByTestId('bridge-code-view-panel'))
			.toHaveAttribute('data-code-view-item-count', String(files.length));
		await expect.poll(() => harness.codeScrollOwner()).not.toBeNull();
		const scrollOwner = harness.codeScrollOwner();
		if (scrollOwner === null) throw new Error('Production Review CodeView has no scroll owner.');
		const scrollTopBeforeHydration = scrollOwner.scrollTop;
		await harness.publishCompleteContent();
		await expect
			.element(harness.renderResult.getByTestId('review-viewer-shell'))
			.toHaveAttribute('data-selected-content-state', 'ready');
		await expect.poll(() => scrollOwner.scrollHeight > scrollOwner.clientHeight).toBe(true);
		await advanceBridgeReviewRecoveryWitnessFrames(4);
		const initialVisibleText = harness.visibleCodeText(scrollOwner);
		if (!initialVisibleText.includes(earlyFile.contentMarker)) {
			const codePanel = harness.renderResult.container.querySelector(
				'[data-testid="bridge-code-view-panel"]',
			);
			throw new Error(
				`initial hydration anchor diagnostic=${JSON.stringify({
					selectedInitialItemIndex: codePanel?.getAttribute('data-selected-initial-item-index'),
					selectedInitialItemIsFirst: codePanel?.getAttribute(
						'data-selected-initial-item-is-first',
					),
					selectedItemId: codePanel?.getAttribute('data-selected-item-id'),
					selectionScrollDidScroll: codePanel?.getAttribute('data-selection-scroll-did-scroll'),
					selectionScrollItemTop: codePanel?.getAttribute('data-selection-scroll-item-top'),
					selectionScrollReason: codePanel?.getAttribute('data-selection-scroll-reason'),
					scrollTopAfterHydration: scrollOwner.scrollTop,
					scrollTopBeforeHydration,
					visibleTextPrefix: initialVisibleText.slice(0, 240),
				})}`,
			);
		}
		const scan = await scanBridgeReviewRecoveryWitnessDocument({
			markerItemIds: [earlyFile.itemId, middleFile.itemId, finalFile.itemId],
			markers: [earlyFile.contentMarker, middleFile.contentMarker, finalFile.contentMarker],
			orderedItemIds: files.map((file): string => file.itemId),
			sampleCount: 25,
			scrollOwner,
			visibleItemIds: (): readonly string[] => {
				const viewportBounds = scrollOwner.getBoundingClientRect();
				return harness
					.paintedCodeViewItems()
					.filter(
						(paintedItem): boolean =>
							paintedItem.bottom > viewportBounds.top && paintedItem.top < viewportBounds.bottom,
					)
					.map((paintedItem): string => paintedItem.itemId);
			},
			visibleCodeText: harness.visibleCodeText,
		});

		// Assert
		const scanDiagnostic = {
			blankPaintSampleCount: scan.blankPaintSampleCount,
			didObserveFinal: scan.observedMarkers.has(finalFile.contentMarker),
			didObserveMiddle: scan.observedMarkers.has(middleFile.contentMarker),
			markerConvergenceSamples: scan.markerConvergenceSamples,
			maximumScrollTop: scan.maximumScrollTop,
		};
		expect(
			scan.maximumScrollTop > 0 &&
				scan.blankPaintSampleCount === 0 &&
				scan.observedMarkers.has(middleFile.contentMarker) &&
				scan.observedMarkers.has(finalFile.contentMarker),
			`G0 REVIEW DEEP SCROLL MISSING: expected sustained scrolling to reach final Review source while the continuous Pierre CodeView stayed painted; diagnostic=${JSON.stringify(scanDiagnostic)}`,
		).toBe(true);
		expect(scan.sampleCount - scan.convergenceSampleCount).toBe(25);
	});
});
