import { act } from 'react';
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

describe('Bridge Review continuous large-document Browser witness', () => {
	afterEach(async (): Promise<void> => {
		cleanup();
		disposeBridgeReviewRecoveryWitnessHarnesses();
		await advanceBridgeReviewRecoveryWitnessFrames(2);
		document.body.replaceChildren();
	});

	test('traverses early, middle, and final Review files without another tree selection', async () => {
		// Arrange
		const files = makeBridgeReviewRecoveryWitnessFiles({
			count: 15,
			lineCount: 24,
			markerPrefix: 'LARGE_TRAVERSAL',
		});
		const earlyFile = files[0];
		const middleFile = files[Math.floor(files.length / 2)];
		const finalFile = files.at(-1);
		if (earlyFile === undefined || middleFile === undefined || finalFile === undefined) {
			throw new Error('Large Review recovery witness requires early, middle, and final files.');
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
		await harness.publishCompleteContent();
		await expect
			.element(harness.renderResult.getByTestId('review-viewer-shell'))
			.toHaveAttribute('data-selected-content-state', 'ready');
		await expect.poll(() => harness.codeScrollOwner()).not.toBeNull();
		const scrollOwner = harness.codeScrollOwner();
		if (scrollOwner === null) throw new Error('Production Review CodeView has no scroll owner.');
		const scan = await scanBridgeReviewRecoveryWitnessDocument({
			markers: [earlyFile.contentMarker, middleFile.contentMarker, finalFile.contentMarker],
			sampleCount: 17,
			scrollOwner,
			visibleCodeText: harness.visibleCodeText,
		});

		// Assert
		const traversalTrace = {
			paintedItems: harness
				.paintedCodeViewItems()
				.map(({ itemId, paintedLineCount }) => ({ itemId, paintedLineCount })),
			scan,
		};
		expect(harness.selectedItemCommandCount()).toBe(1);
		expect(scan.observedMarkers.has(earlyFile.contentMarker)).toBe(true);
		expect(
			scan.observedMarkers.has(middleFile.contentMarker),
			`G0 REVIEW CONTINUOUS TRAVERSAL MISSING: expected early, middle, and final Review files in one CodeView without tree selection; middle content was unreachable. ${JSON.stringify(traversalTrace)}`,
		).toBe(true);
		expect(scan.observedMarkers.has(finalFile.contentMarker)).toBe(true);
	});

	test('hydrates the ordered Review document progressively from viewport demand without tree clicks', async () => {
		// Arrange
		const files = makeBridgeReviewRecoveryWitnessFiles({
			count: 48,
			lineCount: 8,
			markerPrefix: 'PROGRESSIVE_TRAVERSAL',
		});
		const earlyFile = files[0];
		const middleFile = files[Math.floor(files.length / 2)];
		const finalFile = files.at(-1);
		if (earlyFile === undefined || middleFile === undefined || finalFile === undefined) {
			throw new Error('Progressive Review witness requires early, middle, and final files.');
		}
		const harness = renderBridgeReviewRecoveryWitness(files);

		// Act: metadata alone must install the complete ordered header manifest.
		await harness.publishDisplay();
		await expect.poll(() => harness.selectedItemCommandCount()).toBe(1);
		await expect
			.element(harness.renderResult.getByTestId('bridge-code-view-panel'))
			.toHaveAttribute('data-code-view-item-count', String(files.length));
		await advanceBridgeReviewRecoveryWitnessFrames(3);
		expect(harness.codeText()).not.toContain(finalFile.contentMarker);
		const initiallyHydratedItemIds = await harness.publishDemandedContent();
		await advanceBridgeReviewRecoveryWitnessFrames(4);

		// Assert: initial hydration is bounded to selected/rendered demand, not the full catalog.
		expect(initiallyHydratedItemIds.length).toBeGreaterThan(0);
		expect(harness.publishedContentItemIds().length).toBeLessThan(files.length);
		await expect.poll(() => harness.codeScrollOwner()).not.toBeNull();
		const scrollOwner = harness.codeScrollOwner();
		if (scrollOwner === null) throw new Error('Progressive Review CodeView has no scroll owner.');
		const scan = await scanBridgeReviewRecoveryWitnessDocument({
			markers: [earlyFile.contentMarker, middleFile.contentMarker, finalFile.contentMarker],
			publishDemandedContent: harness.publishDemandedContent,
			sampleCount: 48,
			scrollStrategy: 'viewportStep',
			scrollOwner,
			visibleCodeText: harness.visibleCodeText,
		});

		// Assert: viewport demand replaces existing records in place and reaches the full document.
		const viewportCommandVisibleItemIds = harness.viewportCommandVisibleItemIds();
		const demandedItemIds = new Set(viewportCommandVisibleItemIds.flat());
		const progressiveTrace = {
			demandedItemCount: demandedItemIds.size,
			paintedItems: harness
				.paintedCodeViewItems()
				.map(({ itemId, paintedLineCount }) => ({ itemId, paintedLineCount })),
			publishedItemCount: harness.publishedContentItemIds().length,
			scan,
			viewportTail: viewportCommandVisibleItemIds.slice(-5),
		};
		expect(harness.selectedItemCommandCount()).toBe(1);
		expect(scan.blankPaintSampleCount).toBe(0);
		expect(
			demandedItemIds.has(middleFile.itemId),
			`Review viewport demand never reached the middle item. ${JSON.stringify(progressiveTrace)}`,
		).toBe(true);
		expect(
			demandedItemIds.has(finalFile.itemId),
			`Review viewport demand never reached the final item. ${JSON.stringify(progressiveTrace)}`,
		).toBe(true);
		expect(harness.publishedContentItemIds(), JSON.stringify(progressiveTrace)).toHaveLength(
			files.length,
		);
		expect(scan.observedMarkers.has(earlyFile.contentMarker)).toBe(true);
		expect(
			scan.observedMarkers.has(middleFile.contentMarker),
			JSON.stringify(progressiveTrace),
		).toBe(true);
		expect(
			scan.observedMarkers.has(finalFile.contentMarker),
			JSON.stringify(progressiveTrace),
		).toBe(true);
		await expect
			.element(harness.renderResult.getByTestId('bridge-code-view-panel'))
			.toHaveAttribute('data-code-view-item-count', String(files.length));
	});

	test('publishes the newly settled Pierre window during sustained scrolling before scroll idle', async () => {
		// Arrange: settle the initial mounted window and its viewport command first.
		const files = makeBridgeReviewRecoveryWitnessFiles({
			count: 96,
			lineCount: 12,
			markerPrefix: 'SUSTAINED_SCROLL_VIEWPORT',
		});
		const harness = renderBridgeReviewRecoveryWitness(files);
		await harness.publishDisplay();
		await expect.poll(() => harness.selectedItemCommandCount()).toBe(1);
		await advanceBridgeReviewRecoveryWitnessFrames(4);
		const scrollOwner = harness.codeScrollOwner();
		if (scrollOwner === null) {
			throw new Error('Sustained-scroll Review witness has no CodeView scroll owner.');
		}
		const initialRenderedItemIds = new Set(harness.renderedCodeViewItemIds());
		const initialViewportCommandCount = harness.viewportCommandVisibleItemIds().length;
		expect(initialRenderedItemIds.size).toBeGreaterThan(0);

		// Act: dispatch a scroll burst without allowing the 120 ms idle repair to run.
		await act(async (): Promise<void> => {
			const maximumScrollTop = Math.max(0, scrollOwner.scrollHeight - scrollOwner.clientHeight);
			for (const progress of [0.25, 0.5, 0.75, 1]) {
				scrollOwner.scrollTop = Math.floor(maximumScrollTop * progress);
				scrollOwner.dispatchEvent(new Event('scroll', { bubbles: true }));
			}
			await Promise.resolve();
		});
		await advanceBridgeReviewRecoveryWitnessFrames(1);

		// Assert: the first committed Pierre render publishes its new mounted window immediately.
		const settledRenderedItemIds = [...new Set(harness.renderedCodeViewItemIds())];
		const viewportCommands = harness.viewportCommandVisibleItemIds();
		const latestViewportItemIds = viewportCommands.at(-1) ?? [];
		const trace = {
			initialRenderedItemIds: [...initialRenderedItemIds],
			initialViewportCommandCount,
			latestViewportItemIds,
			settledRenderedItemIds,
			viewportCommandCount: viewportCommands.length,
		};
		expect(
			settledRenderedItemIds.some((itemId): boolean => !initialRenderedItemIds.has(itemId)),
			JSON.stringify(trace),
		).toBe(true);
		expect(viewportCommands.length, JSON.stringify(trace)).toBeGreaterThan(
			initialViewportCommandCount,
		);
		expect(
			settledRenderedItemIds.every((itemId): boolean => latestViewportItemIds.includes(itemId)),
			`REVIEW_SUSTAINED_SCROLL_VIEWPORT_STALE: ${JSON.stringify(trace)}`,
		).toBe(true);
	});

	test('recovers retained selected-only content into the authoritative order without tree clicks', async () => {
		// Arrange
		const files = makeBridgeReviewRecoveryWitnessFiles({
			count: 24,
			lineCount: 8,
			markerPrefix: 'RETAINED_MANIFEST',
		});
		const retainedSelectedItemIndex = Math.floor(files.length / 2);
		const retainedSelectedFile = files[retainedSelectedItemIndex];
		const firstFile = files[0];
		const finalFile = files.at(-1);
		if (retainedSelectedFile === undefined || firstFile === undefined || finalFile === undefined) {
			throw new Error('Retained Review witness requires first, middle, and final files.');
		}
		const harness = renderBridgeReviewRecoveryWitness(files);

		// Act: reproduce the stale selected-only model, hydrate it, then publish the full same-epoch catalog.
		await harness.publishRetainedSelectedOnlyDisplay(retainedSelectedItemIndex);
		await expect
			.element(harness.renderResult.getByTestId('bridge-code-view-panel'))
			.toHaveAttribute('data-code-view-item-count', '1');
		await harness.publishDemandedContent();
		expect(harness.codeText()).toContain(retainedSelectedFile.contentMarker);
		await harness.publishAuthoritativeDisplayAfterRetainedSelection();
		await expect
			.element(harness.renderResult.getByTestId('bridge-code-view-panel'))
			.toHaveAttribute('data-code-view-item-count', String(files.length));
		const scrollOwner = harness.codeScrollOwner();
		if (scrollOwner === null)
			throw new Error('Retained Review witness has no CodeView scroll owner.');
		scrollOwner.scrollTop = 0;
		scrollOwner.dispatchEvent(new Event('scroll', { bubbles: true }));
		await advanceBridgeReviewRecoveryWitnessFrames(3);

		// Assert: the old selected item is retained as content, not retained as rank zero.
		expect(harness.renderedCodeViewItemIds()[0]).toBe(firstFile.itemId);
		expect(harness.selectedItemCommandCount()).toBe(1);
		await harness.publishCompleteContent();
		const scan = await scanBridgeReviewRecoveryWitnessDocument({
			markers: [
				firstFile.contentMarker,
				retainedSelectedFile.contentMarker,
				finalFile.contentMarker,
			],
			sampleCount: files.length,
			scrollStrategy: 'viewportStep',
			scrollOwner,
			visibleCodeText: harness.visibleCodeText,
		});
		const retainedTrace = {
			paintedItems: harness
				.paintedCodeViewItems()
				.map(({ itemId, paintedLineCount }) => ({ itemId, paintedLineCount })),
			scan,
		};
		expect(scan.blankPaintSampleCount).toBe(0);
		expect(scan.observedMarkers, JSON.stringify(retainedTrace)).toEqual(
			new Set([
				firstFile.contentMarker,
				retainedSelectedFile.contentMarker,
				finalFile.contentMarker,
			]),
		);
		expect(harness.selectedItemCommandCount()).toBe(1);
	});

	test('repairs retained Pierre membership before immediate selected-loading can append', async () => {
		// Arrange: preserve the exact long-lived failure shape behind the live report. React will own
		// the complete manifest, while the mounted Pierre model begins with one retained item.
		const files = makeBridgeReviewRecoveryWitnessFiles({
			count: 24,
			lineCount: 8,
			markerPrefix: 'SELECTED_LOADING_RECONCILE',
		});
		const retainedFile = files[0];
		const selectedFile = files[Math.floor(files.length / 2)];
		const finalFile = files.at(-1);
		if (retainedFile === undefined || selectedFile === undefined || finalFile === undefined) {
			throw new Error('Selected-loading reconcile witness requires first, middle, and final files.');
		}
		const harness = renderBridgeReviewRecoveryWitness(files);
		await harness.publishRetainedSelectedOnlyDisplay(0);
		await harness.publishDemandedContent();
		expect(harness.codeText()).toContain(retainedFile.contentMarker);

		// Act: publish the full same-source catalog and commit a different selection in the same React
		// turn, before the deferred authoritative reconciliation can settle.
		await harness.publishAuthoritativeDisplayWithImmediateLocalSelection(
			Math.floor(files.length / 2),
		);
		await harness.publishCompleteContent();
		const scrollOwner = harness.codeScrollOwner();
		if (scrollOwner === null) {
			throw new Error('Selected-loading reconcile witness has no CodeView scroll owner.');
		}
		const scan = await scanBridgeReviewRecoveryWitnessDocument({
			markers: [retainedFile.contentMarker, selectedFile.contentMarker, finalFile.contentMarker],
			markerItemIds: [retainedFile.itemId, selectedFile.itemId, finalFile.itemId],
			orderedItemIds: files.map((file): string => file.itemId),
			sampleCount: files.length,
			scrollStrategy: 'viewportStep',
			scrollOwner,
			visibleCodeText: harness.visibleCodeText,
			visibleItemIds: harness.renderedCodeViewItemIds,
		});

		// Assert: the actual mounted document, not the React manifest-count attribute, reaches the
		// authoritative final item in order after the selected-loading transition.
		expect(
			scan.observedMarkers,
			`REVIEW_SELECTED_LOADING_LIVE_MEMBERSHIP_RED: ${JSON.stringify({
				paintedItems: harness.paintedCodeViewItems(),
				scan,
			})}`,
		).toEqual(
			new Set([retainedFile.contentMarker, selectedFile.contentMarker, finalFile.contentMarker]),
		);
		expect(scan.blankPaintSampleCount).toBe(0);
	});

	test('keeps a far tree selection landed when late hydration follows an older CodeView scroll', async () => {
		// Arrange: keep the target's ancestors open before starting the older CodeView scroll.
		const files = makeBridgeReviewRecoveryWitnessFiles({
			count: 24,
			lineCount: 40,
			markerPrefix: 'ACTIVE_SCROLL_SELECTION',
		});
		const targetFile = files[5];
		if (targetFile === undefined) {
			throw new Error('Active-scroll selection witness requires a far target file.');
		}
		const harness = renderBridgeReviewRecoveryWitness(files);
		await harness.publishDisplay();
		await expect.poll(() => harness.selectedItemCommandCount()).toBe(1);
		await harness.publishDemandedContent();
		await advanceBridgeReviewRecoveryWitnessFrames(3);
		await act(async (): Promise<void> => {
			harness.pierreTreePath('Sources')?.click();
			await Promise.resolve();
		});
		await advanceBridgeReviewRecoveryWitnessFrames(2);
		await act(async (): Promise<void> => {
			harness.pierreTreePath('Sources/RecoveryGroup02')?.click();
			await Promise.resolve();
		});
		await advanceBridgeReviewRecoveryWitnessFrames(2);
		const targetTreeRow = harness.pierreTreePath(targetFile.path);
		if (targetTreeRow === null) {
			throw new Error(`Active-scroll selection tree target is missing: ${targetFile.path}`);
		}
		const scrollOwner = harness.codeScrollOwner();
		if (scrollOwner === null) {
			throw new Error('Active-scroll selection witness has no CodeView scroll owner.');
		}

		// Act: an older user scroll is still active when the distinct tree selection starts.
		await act(async (): Promise<void> => {
			scrollOwner.dispatchEvent(
				new WheelEvent('wheel', {
					bubbles: true,
					deltaY: Math.max(1, scrollOwner.scrollHeight - scrollOwner.clientHeight),
				}),
			);
			scrollOwner.scrollTop = Math.max(0, scrollOwner.scrollHeight - scrollOwner.clientHeight);
			scrollOwner.dispatchEvent(new Event('scroll', { bubbles: true }));
			targetTreeRow.click();
			await Promise.resolve();
		});
		await advanceBridgeReviewRecoveryWitnessFrames(2);
		await expect.poll(() => harness.selectedItemCommandCount()).toBe(2);
		await harness.publishDemandedContent();
		await advanceBridgeReviewRecoveryWitnessFrames(2);

		// Assert: the target stays mounted and visible after its body changes surrounding geometry.
		const selectedItemId = harness.renderResult.container
			.querySelector('[data-testid="bridge-code-view-panel"]')
			?.getAttribute('data-selected-item-id');
		const targetPaint = harness
			.paintedCodeViewItems()
			.find((paintedItem) => paintedItem.itemId === targetFile.itemId);
		const viewportBounds = scrollOwner.getBoundingClientRect();
		const trace = {
			paintedItemIds: harness.paintedCodeViewItems().map((paintedItem) => paintedItem.itemId),
			scrollTop: scrollOwner.scrollTop,
			selectedItemId,
			targetPaint,
			viewportBottom: viewportBounds.bottom,
			viewportTop: viewportBounds.top,
		};
		expect(selectedItemId).toBe(targetFile.itemId);
		expect(targetPaint, JSON.stringify(trace)).toBeDefined();
		expect(targetPaint?.paintedLineCount, JSON.stringify(trace)).toBeGreaterThan(0);
		expect(targetPaint?.bottom ?? Number.NEGATIVE_INFINITY, JSON.stringify(trace)).toBeGreaterThan(
			viewportBounds.top,
		);
		expect(targetPaint?.top ?? Number.POSITIVE_INFINITY, JSON.stringify(trace)).toBeLessThan(
			viewportBounds.bottom,
		);
	});

		test('keeps a newer user scroll authoritative when selected content hydrates', async () => {
			// Arrange: selection has already revealed a far loading header.
			const { harness, scrollOwner, targetFile } =
				await renderBridgeReviewPendingHydrationSelection('NEWER_USER_SCROLL');
			expect(scrollOwner.scrollTop).toBeGreaterThan(scrollOwner.clientHeight);

		// Act: a newer captured wheel intent moves away before the selected body arrives.
		await act(async (): Promise<void> => {
			scrollOwner.dispatchEvent(
				new WheelEvent('wheel', {
					bubbles: true,
					deltaY: -Math.max(1, scrollOwner.scrollTop),
				}),
			);
				scrollOwner.scrollTop = 0;
				scrollOwner.dispatchEvent(new Event('scroll', { bubbles: true }));
				await Promise.resolve();
			});
			await harness.publishContentForItemIds([targetFile.itemId]);

			// Assert: hydration does not override the newer user-authored viewport.
		const codePanel = harness.renderResult.container.querySelector(
			'[data-testid="bridge-code-view-panel"]',
		);
		expect(codePanel?.getAttribute('data-selected-item-id')).toBe(targetFile.itemId);
		expect(scrollOwner.scrollTop).toBeLessThanOrEqual(1);
	});

	test('does not treat Pierre programmatic onScroll as newer user input', async () => {
		// Arrange: selection has already revealed a far loading header.
		const { harness, scrollOwner, targetFile } = await renderBridgeReviewPendingHydrationSelection(
			'PIERRE_PROGRAMMATIC_SCROLL',
		);
		expect(scrollOwner.scrollTop).toBeGreaterThan(scrollOwner.clientHeight);

		// Act: Pierre reports a programmatic scroll without a captured wheel/touch/pointer intent.
		await act(async (): Promise<void> => {
				scrollOwner.scrollTop = 0;
				scrollOwner.dispatchEvent(new Event('scroll', { bubbles: true }));
				await Promise.resolve();
			});
			await harness.publishContentForItemIds([targetFile.itemId]);

			// Assert: the selected hydration correction remains live and returns to the target.
		const targetPaint = harness
			.paintedCodeViewItems()
			.find((paintedItem) => paintedItem.itemId === targetFile.itemId);
		const viewportBounds = scrollOwner.getBoundingClientRect();
		const trace = {
			scrollTop: scrollOwner.scrollTop,
			targetPaint,
			viewportBottom: viewportBounds.bottom,
			viewportTop: viewportBounds.top,
		};
		expect(scrollOwner.scrollTop, JSON.stringify(trace)).toBeGreaterThan(scrollOwner.clientHeight);
		expect(targetPaint?.paintedLineCount, JSON.stringify(trace)).toBeGreaterThan(0);
		expect(targetPaint?.bottom ?? Number.NEGATIVE_INFINITY, JSON.stringify(trace)).toBeGreaterThan(
			viewportBounds.top,
		);
		expect(targetPaint?.top ?? Number.POSITIVE_INFINITY, JSON.stringify(trace)).toBeLessThan(
			viewportBounds.bottom,
		);
	});

	test('traverses the deterministic 3,420-file 100,000-line Review class without tree clicks', async () => {
		// Arrange: 3,420 files with 15 base and 15 head lines produce 102,600 source lines.
		const files = makeBridgeReviewRecoveryWitnessFiles({
			count: 3_420,
			lineCount: 15,
			markerPrefix: 'PRODUCT_SCALE_TRAVERSAL',
		});
		const earlyFile = files[0];
		const middleFile = files[Math.floor(files.length / 2)];
		const finalFile = files.at(-1);
		if (earlyFile === undefined || middleFile === undefined || finalFile === undefined) {
			throw new Error('Product-scale Review witness requires early, middle, and final files.');
		}
		const totalSourceLineCount = files.reduce(
			(lineCount, file): number => lineCount + file.lineCount * 2,
			0,
		);
		expect(totalSourceLineCount).toBeGreaterThanOrEqual(100_000);
		const harness = renderBridgeReviewRecoveryWitness(files);

		// Act: metadata installs every header before interaction; bodies arrive only from CodeView demand.
		await harness.publishDisplay();
		await expect.poll(() => harness.selectedItemCommandCount()).toBe(1);
		await expect
			.element(harness.renderResult.getByTestId('bridge-code-view-panel'))
			.toHaveAttribute('data-code-view-item-count', String(files.length));
		await advanceBridgeReviewRecoveryWitnessFrames(3);
		await harness.publishDemandedContent();
		expect(harness.publishedContentItemIds().length).toBeLessThan(files.length);
		await expect.poll(() => harness.codeScrollOwner()).not.toBeNull();
		const scrollOwner = harness.codeScrollOwner();
		if (scrollOwner === null) throw new Error('Product-scale Review CodeView has no scroll owner.');
		const scan = await scanBridgeReviewRecoveryWitnessDocument({
			markerItemIds: [earlyFile.itemId, middleFile.itemId, finalFile.itemId],
			markers: [earlyFile.contentMarker, middleFile.contentMarker, finalFile.contentMarker],
			orderedItemIds: files.map((file): string => file.itemId),
			publishDemandedContent: harness.publishDemandedContent,
			sampleCount: 65,
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

		// Assert: one document reaches real early/middle/final bodies without selection-driven membership.
		const viewportItemIds = new Set(harness.viewportCommandVisibleItemIds().flat());
		const publishedItemIds = new Set(harness.publishedContentItemIds());
		const trace = {
			blankPaintSampleCount: scan.blankPaintSampleCount,
			convergenceSampleCount: scan.convergenceSampleCount,
			finalScrollHeight: scan.finalScrollHeight,
			markerConvergenceSamples: scan.markerConvergenceSamples,
			finalItemPublished: publishedItemIds.has(finalFile.itemId),
			finalItemVisibleDemand: viewportItemIds.has(finalFile.itemId),
			middleItemPublished: publishedItemIds.has(middleFile.itemId),
			middleItemVisibleDemand: viewportItemIds.has(middleFile.itemId),
			observedMarkers: [...scan.observedMarkers],
			publishedItemCount: harness.publishedContentItemIds().length,
			viewportItemCount: viewportItemIds.size,
		};
		expect(harness.selectedItemCommandCount()).toBe(1);
		expect(scan.blankPaintSampleCount, JSON.stringify(trace)).toBe(0);
		expect(scan.observedMarkers.has(earlyFile.contentMarker), JSON.stringify(trace)).toBe(true);
		expect(scan.observedMarkers.has(middleFile.contentMarker), JSON.stringify(trace)).toBe(true);
		expect(scan.observedMarkers.has(finalFile.contentMarker), JSON.stringify(trace)).toBe(true);
		expect(viewportItemIds.has(middleFile.itemId), JSON.stringify(trace)).toBe(true);
		expect(viewportItemIds.has(finalFile.itemId), JSON.stringify(trace)).toBe(true);
		await expect
			.element(harness.renderResult.getByTestId('bridge-code-view-panel'))
			.toHaveAttribute('data-code-view-item-count', String(files.length));
	});
});

async function renderBridgeReviewPendingHydrationSelection(markerPrefix: string): Promise<{
	readonly harness: ReturnType<typeof renderBridgeReviewRecoveryWitness>;
	readonly scrollOwner: HTMLElement;
	readonly targetFile: ReturnType<typeof makeBridgeReviewRecoveryWitnessFiles>[number];
}> {
	const files = makeBridgeReviewRecoveryWitnessFiles({
		count: 72,
		lineCount: 40,
		markerPrefix,
	});
	const targetFile = files[60];
	if (targetFile === undefined) {
		throw new Error('Pending-hydration selection witness requires a far target file.');
	}
	const harness = renderBridgeReviewRecoveryWitness(files);
	await harness.publishDisplay();
	await expect.poll(() => harness.selectedItemCommandCount()).toBe(1);
	await advanceBridgeReviewRecoveryWitnessFrames(12);
	const targetDirectoryPath = targetFile.path.split('/').slice(0, -1).join('/');
	await act(async (): Promise<void> => {
		harness.pierreTreePath('Sources')?.click();
		await Promise.resolve();
	});
	await advanceBridgeReviewRecoveryWitnessFrames(2);
	await act(async (): Promise<void> => {
		harness.pierreTreePath(targetDirectoryPath)?.click();
		await Promise.resolve();
	});
	await advanceBridgeReviewRecoveryWitnessFrames(2);
	const targetTreeRow = harness.pierreTreePath(targetFile.path);
	if (targetTreeRow === null) {
		throw new Error(`Pending-hydration selection tree target is missing: ${targetFile.path}`);
	}
	await act(async (): Promise<void> => {
		targetTreeRow.click();
		await Promise.resolve();
	});
		await advanceBridgeReviewRecoveryWitnessUntil({
			failureMessage: 'Pending-hydration selection did not commit and land within six frames.',
			isSatisfied: (): boolean => {
				const selectedScrollOwner = harness.codeScrollOwner();
				return (
					harness.selectedItemCommandCount() === 2 &&
					selectedScrollOwner !== null &&
					selectedScrollOwner.scrollTop > selectedScrollOwner.clientHeight
				);
			},
			maximumFrameCount: 6,
		});
		await advanceBridgeReviewRecoveryWitnessFrames(3);
		const scrollOwner = harness.codeScrollOwner();
	if (scrollOwner === null) {
		throw new Error('Pending-hydration selection witness has no CodeView scroll owner.');
	}
		return { harness, scrollOwner, targetFile };
}

async function advanceBridgeReviewRecoveryWitnessUntil(props: {
	readonly failureMessage: string;
	readonly isSatisfied: () => boolean;
	readonly maximumFrameCount: number;
}): Promise<void> {
	if (props.isSatisfied()) return;
	for (let frameIndex = 0; frameIndex < props.maximumFrameCount; frameIndex += 1) {
		// oxlint-disable-next-line no-await-in-loop -- Each frame is an act-wrapped render boundary.
		await advanceBridgeReviewRecoveryWitnessFrames(1);
		if (props.isSatisfied()) return;
	}
	throw new Error(props.failureMessage);
}
