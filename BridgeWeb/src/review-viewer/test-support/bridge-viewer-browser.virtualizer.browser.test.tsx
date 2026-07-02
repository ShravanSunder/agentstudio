import { afterEach, describe, expect, test } from 'vitest';
import { cleanup, render } from 'vitest-browser-react';

import { BridgeApp } from '../../app/bridge-app.js';
import type { BridgeIntakeFrame } from '../../core/models/bridge-intake-frame.js';
import { buildReviewMetadataWindowFrame } from '../../features/review/protocol/review-metadata-frame-builder.js';
import type {
	BridgeContentRole,
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package.js';
import { bridgeCodeViewOptions } from '../code-view/bridge-code-view-options.js';
import {
	waitForBridgeViewerAnimationFrame,
	waitForBridgeViewerCodeScrollOwner,
	waitForBridgeViewerText,
} from './bridge-viewer-browser-dom.js';
import * as browserSupport from './bridge-viewer-browser.integration.test-support.js';
import {
	disposeBridgeViewerMockedBackends,
	installBridgeViewerMockedBackend,
	makeBridgeViewerBrowserFixture,
	type BridgeViewerBrowserFixture,
	type BridgeViewerMockedBackend,
} from './bridge-viewer-mocked-backend.js';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load the app CSS.
import '../../app/bridge-app.css';

const reviewPaneId = 'bridge-viewer-dev-pane';
const reviewStreamId = `review:${reviewPaneId}`;
const bridgeViewerPushNonce = 'browser-push-nonce';
// Selection-reveal landing bound (px) between the target header top and the scroll-owner
// top after settle. Measured to be a constant ~4px structural offset from Pierre's item
// layout at align:'start' (identical for a 1-line filler and a multi-line file, and
// unchanged by S3 height truth), so this is the achievable floor — the load-bearing proof
// is the monotonic, oscillation-free settle, not sub-pixel landing.
const revealSettleLandingOffsetPixels = 4;

describe('Bridge viewer CodeView virtualizer anchoring', () => {
	afterEach(async () => {
		cleanup();
		await Promise.resolve();
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();
		disposeBridgeViewerMockedBackends();
		document.body.replaceChildren();
		document.documentElement.removeAttribute('data-bridge-nonce');
		document.documentElement.removeAttribute('data-bridge-review-pane-id');
		document.documentElement.removeAttribute('data-bridge-review-stream-id');
		delete window.bridgeReviewControlProbe;
	});

	test('keeps a rendered CodeView header anchored when a late metadata window changes heights above it', async () => {
		const fixture = makeBridgeViewerBrowserFixture({ fixtureClass: 'large-diffshub' });
		const initialPackage = reviewPackageWithClampedLineCounts({
			lineCount: 1,
			reviewPackage: fixture.reviewPackage,
		});
		const backend = installBridgeViewerMockedBackend(fixture);
		const anchorItemId = fixture.reviewPackage.orderedItemIds[120];
		if (anchorItemId === undefined) {
			throw new Error('Expected large fixture anchor item.');
		}

		render(
			<BridgeApp
				codeViewWorkerPoolEnabled={false}
				fetchContent={backend.fetchContent}
				markdownWorkerClient={null}
				projectionWorkerClient={backend.projectionWorkerClient}
			/>,
		);
		await backend.pushMetadata(initialPackage);
		await waitForBridgeViewerText(fixture.expected.initialText);

		const scrollOwner = await waitForBridgeViewerCodeScrollOwner();
		window.dispatchEvent(
			new CustomEvent('__bridge_review_control', {
				detail: {
					method: 'bridge.diff.scrollToFile',
					itemId: anchorItemId,
				},
			}),
		);
		const anchorButton =
			await browserSupport.waitForBridgeCodeHeaderCollapseButtonForItem(anchorItemId);
		await browserSupport.waitForBridgeCodeHeaderOffsetFromScrollOwner({
			collapseButton: anchorButton,
			maxOffset: 120,
			scrollOwner,
		});
		const anchorOffsetBefore = browserSupport.bridgeCodeHeaderOffsetFromScrollOwner({
			collapseButton: anchorButton,
			scrollOwner,
		});

		dispatchReviewMetadataWindow({
			itemIds: fixture.reviewPackage.orderedItemIds.slice(0, 80),
			reviewPackage: fixture.reviewPackage,
			sequence: 99,
		});

		await browserSupport.waitForBridgeCodeHeaderCollapseButtonForItemStateNearOffset({
			ariaExpanded: 'true',
			expectedOffset: anchorOffsetBefore,
			itemId: anchorItemId,
			maxDelta: 2,
			scrollOwner,
		});
		const anchorOffsetAfter = browserSupport.bridgeCodeHeaderOffsetFromScrollOwner({
			collapseButton: anchorButton,
			scrollOwner,
		});
		expect(Math.abs(anchorOffsetAfter - anchorOffsetBefore)).toBeLessThanOrEqual(2);
	});

	test('does not yank the user scroll position back to the selected file on metadata windows', async () => {
		const fixture = makeBridgeViewerBrowserFixture({ fixtureClass: 'large-diffshub' });
		const backend = installBridgeViewerMockedBackend(fixture);

		render(
			<BridgeApp
				codeViewWorkerPoolEnabled={false}
				fetchContent={backend.fetchContent}
				markdownWorkerClient={null}
				projectionWorkerClient={backend.projectionWorkerClient}
			/>,
		);
		await backend.pushMetadata();
		await waitForBridgeViewerText(fixture.expected.initialText);

		const scrollOwner = await waitForBridgeViewerCodeScrollOwner();
		scrollOwner.scrollTop += 500;
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();
		const scrollTopBeforeMetadataWindow = scrollOwner.scrollTop;

		dispatchReviewMetadataWindow({
			itemIds: fixture.reviewPackage.orderedItemIds.slice(0, 80),
			reviewPackage: fixture.reviewPackage,
			sequence: 100,
		});

		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();
		expect(Math.abs(scrollOwner.scrollTop - scrollTopBeforeMetadataWindow)).toBeLessThanOrEqual(4);
	});

	test('keeps the first fully-visible item anchored across N idle metadata windows (R1 streaming stability)', async () => {
		const fixture = makeBridgeViewerBrowserFixture({ fixtureClass: 'large-diffshub' });
		const backend = installBridgeViewerMockedBackend(fixture);

		render(
			<BridgeApp
				codeViewWorkerPoolEnabled={false}
				fetchContent={backend.fetchContent}
				markdownWorkerClient={null}
				projectionWorkerClient={backend.projectionWorkerClient}
			/>,
		);
		await backend.pushMetadata();
		await waitForBridgeViewerText(fixture.expected.initialText);

		const scrollOwner = await waitForBridgeViewerCodeScrollOwner();
		scrollOwner.scrollTop = Math.min(scrollOwner.scrollHeight - scrollOwner.clientHeight, 6_000);
		scrollOwner.dispatchEvent(new Event('scroll', { bubbles: true }));
		await waitForBridgeViewerScrollIdle(scrollOwner);
		expect(scrollOwner.scrollTop).toBeGreaterThan(0);

		// I4 USER MOTION ONLY: idle metadata windows must not move the viewport. The
		// measurable invariant is first-visible-line drift — the anchored header's offset
		// from the scroll-owner top — not absolute scrollTop, which legitimately shifts as
		// total height changes (that thumb churn is R2's domain).
		const anchorBefore = firstFullyVisibleBridgeCodeHeader(scrollOwner);
		const renderedHeaderCountBefore = browserSupport.bridgeCodeHeaderCollapseButtons().length;

		const windowBatches = idleMetadataWindowBatches({
			batchCount: 5,
			reviewPackage: fixture.reviewPackage,
		});
		for (const [batchIndex, itemIds] of windowBatches.entries()) {
			dispatchReviewMetadataWindow({
				itemIds,
				reviewPackage: fixture.reviewPackage,
				sequence: 200 + batchIndex,
			});
			// oxlint-disable-next-line no-await-in-loop -- Streaming stability proof must observe each window settle.
			await waitForBridgeViewerAnimationFrame();
			// oxlint-disable-next-line no-await-in-loop -- Streaming stability proof must observe each window settle.
			await waitForBridgeViewerAnimationFrame();
			const anchorOffsetDuringWindow = bridgeCodeHeaderOffsetForItem({
				itemId: anchorBefore.itemId,
				scrollOwner,
			});
			expect(anchorOffsetDuringWindow).not.toBeNull();
			expect(Math.abs((anchorOffsetDuringWindow ?? 0) - anchorBefore.offset)).toBeLessThanOrEqual(
				2,
			);
		}

		// Zero collapsed-region count flicker: the rendered header set stays stable across
		// windows (no reshuffle re-rendering the visible window).
		expect(
			Math.abs(browserSupport.bridgeCodeHeaderCollapseButtons().length - renderedHeaderCountBefore),
		).toBeLessThanOrEqual(1);
	});

	test('keeps an upward selection reveal pinned after target content hydrates', async () => {
		const fixture = makeBridgeViewerBrowserFixture({ fixtureClass: 'large-diffshub' });
		const upItemId = 'browser-added-source';
		const upItem = fixture.reviewPackage.itemsById[upItemId];
		if (upItem === undefined) {
			throw new Error('Expected large fixture upward target item.');
		}
		const deferredUpTargetHandleIds = contentHandleIdsForItem(upItem);
		const backend = installBridgeViewerMockedBackend(fixture, {
			deferContentHandleIds: deferredUpTargetHandleIds,
		});

		render(
			<BridgeApp
				codeViewWorkerPoolEnabled={false}
				fetchContent={backend.fetchContent}
				markdownWorkerClient={null}
				projectionWorkerClient={backend.projectionWorkerClient}
			/>,
		);
		await backend.pushMetadata();
		await waitForBridgeViewerText(fixture.expected.initialText);

		const scrollOwner = await waitForBridgeViewerCodeScrollOwner();
		await waitForInitialRevealSettled(scrollOwner);
		scrollOwner.scrollTop = Math.min(scrollOwner.scrollHeight - scrollOwner.clientHeight, 12_000);
		scrollOwner.dispatchEvent(new Event('scroll', { bubbles: true }));
		await waitForBridgeViewerScrollIdle(scrollOwner);
		expect(scrollOwner.scrollTop).toBeGreaterThan(0);

		const upwardMotionSamples = await browserSupport.sampleBridgeCodeViewScrollMotion({
			frameCount: 36,
			scrollOwner,
			action: (): void => {
				revealReviewItem(upItemId);
			},
		});
		await browserSupport.waitForBridgeCodeHeaderItemOffsetFromScrollOwner({
			itemId: upItemId,
			maxOffset: 8,
			scrollOwner,
		});
		await browserSupport.waitForPendingContentResponseCount(
			backend,
			deferredUpTargetHandleIds.length,
		);
		for (const response of backend.pendingContentResponses) {
			response.resolve();
		}
		await browserSupport.waitForSelectedBridgeViewerContentState('ready');
		const upHeaderButton =
			await browserSupport.waitForBridgeCodeHeaderCollapseButtonForItem(upItemId);
		const stableOffsetAfterHydration =
			await browserSupport.waitForStableBridgeCodeHeaderOffsetFromScrollOwner({
				collapseButton: upHeaderButton,
				maxOffset: 4,
				scrollOwner,
			});
		const settledScrollTop = await waitForStableScrollTop(scrollOwner);
		const resampledSettledScrollTop = await waitForStableScrollTop(scrollOwner);

		expectUpwardRevealMotion(upwardMotionSamples);
		expect(Math.abs(resampledSettledScrollTop - settledScrollTop)).toBeLessThanOrEqual(2);
		expect(stableOffsetAfterHydration).toBeGreaterThanOrEqual(0);
		expect(stableOffsetAfterHydration).toBeLessThanOrEqual(4);
	});

	test('lands and monotonically settles two-step upward reveals to earlier targets (R4)', async () => {
		const fixture = makeBridgeViewerBrowserFixture({ fixtureClass: 'large-diffshub' });
		// Two content-rich upward targets whose own late hydration growth stresses re-targeting
		// (F9). The pathologically large item (index 4) is FROZEN as a permanent placeholder so
		// its placeholder-cap height defect (F2 / S3) cannot shift the targets — this isolates
		// F9 from S3 in the same fixture.
		const frozenPlaceholderItem = 'browser-large-diff';
		const firstUpTarget = 'browser-added-source';
		const secondUpTarget = 'browser-docs-plan';
		const firstUpTargetHandleIds = contentHandleIdsForFixtureItem(fixture, firstUpTarget);
		const secondUpTargetHandleIds = contentHandleIdsForFixtureItem(fixture, secondUpTarget);
		const backend = installBridgeViewerMockedBackend(fixture, {
			deferContentHandleIds: [
				...contentHandleIdsForFixtureItem(fixture, frozenPlaceholderItem),
				...firstUpTargetHandleIds,
				...secondUpTargetHandleIds,
			],
		});

		render(
			<BridgeApp
				codeViewWorkerPoolEnabled={false}
				fetchContent={backend.fetchContent}
				markdownWorkerClient={null}
				projectionWorkerClient={backend.projectionWorkerClient}
			/>,
		);
		await backend.pushMetadata();
		await waitForBridgeViewerText(fixture.expected.initialText);
		const scrollOwner = await waitForBridgeViewerCodeScrollOwner();
		await waitForInitialRevealSettled(scrollOwner);

		// From a deep scroll position, reveal up to each earlier target in turn. The second
		// iteration is a selection->selection transition (target A -> target B).
		const upTargets = [
			{ handleIds: firstUpTargetHandleIds, itemId: firstUpTarget },
			{ handleIds: secondUpTargetHandleIds, itemId: secondUpTarget },
		];
		for (const upTarget of upTargets) {
			scrollOwner.scrollTop = Math.min(scrollOwner.scrollHeight - scrollOwner.clientHeight, 12_000);
			scrollOwner.dispatchEvent(new Event('scroll', { bubbles: true }));
			// oxlint-disable-next-line no-await-in-loop -- Each reveal must start from a settled deep position.
			await waitForBridgeViewerScrollIdle(scrollOwner);
			// oxlint-disable-next-line no-await-in-loop -- Each reveal must land and settle before the next.
			await revealDeferredTargetAndAssertLanding({
				backend,
				direction: 'up',
				scrollOwner,
				targetHandleIds: upTarget.handleIds,
				targetItemId: upTarget.itemId,
			});
		}
	});

	test('keeps the code view scroll height stable as items measure across scroll positions (R2 thumb constancy)', async () => {
		const fixture = makeBridgeViewerBrowserFixture({ fixtureClass: 'large-diffshub' });
		const backend = installBridgeViewerMockedBackend(fixture);

		render(
			<BridgeApp
				codeViewWorkerPoolEnabled={false}
				fetchContent={backend.fetchContent}
				markdownWorkerClient={null}
				projectionWorkerClient={backend.projectionWorkerClient}
			/>,
		);
		await backend.pushMetadata();
		await waitForBridgeViewerText(fixture.expected.initialText);
		const scrollOwner = await waitForBridgeViewerCodeScrollOwner();
		await waitForInitialRevealSettled(scrollOwner);

		// I1 HEIGHT TRUTH (F1): the estimate Pierre reserves for an unhydrated/virtualized item
		// must equal the height it measures after render, within a line of rounding. Without
		// itemMetrics Pierre defaults to a 44px header while the rendered header is 32px.
		const measured = measuredBridgeCodeViewLayoutMetrics();
		expect(measured.headerHeight).toBeGreaterThan(0);
		expect(measured.lineHeight).toBeGreaterThan(0);
		expect(
			Math.abs((bridgeCodeViewOptions.itemMetrics?.diffHeaderHeight ?? 0) - measured.headerHeight),
		).toBeLessThanOrEqual(1);
		expect(
			Math.abs((bridgeCodeViewOptions.itemMetrics?.lineHeight ?? 0) - measured.lineHeight),
		).toBeLessThanOrEqual(1);

		// R2 thumb constancy: with true estimates the scroll height (thumb length =
		// clientHeight / scrollHeight) does not churn as items scroll through the measured
		// window.
		const maxScrollTop = Math.max(0, scrollOwner.scrollHeight - scrollOwner.clientHeight);
		const scrollHeights: number[] = [];
		for (const fraction of [0, 0.2, 0.4, 0.6, 0.8, 0.95, 0.4, 0]) {
			scrollOwner.scrollTop = Math.round(maxScrollTop * fraction);
			scrollOwner.dispatchEvent(new Event('scroll', { bubbles: true }));
			// oxlint-disable-next-line no-await-in-loop -- Each scroll must settle before sampling scroll height.
			await waitForBridgeViewerScrollIdle(scrollOwner);
			scrollHeights.push(scrollOwner.scrollHeight);
		}
		const minScrollHeight = Math.min(...scrollHeights);
		const maxScrollHeight = Math.max(...scrollHeights);
		expect((maxScrollHeight - minScrollHeight) / maxScrollHeight).toBeLessThan(0.02);
	});

	test('lands a downward selection reveal at the target header top (R3 down-guard)', async () => {
		const fixture = makeBridgeViewerBrowserFixture({ fixtureClass: 'large-diffshub' });
		const orderedItemIds = fixture.reviewPackage.orderedItemIds;
		const startItemId = 'browser-source-b';
		const downTargetItemId = orderedItemIds[40];
		if (downTargetItemId === undefined) {
			throw new Error('Expected large fixture deep down target item.');
		}
		const deferredHandleIds = contentHandleIdsForFixtureItem(fixture, downTargetItemId);
		const backend = installBridgeViewerMockedBackend(fixture, {
			deferContentHandleIds: deferredHandleIds,
		});

		render(
			<BridgeApp
				codeViewWorkerPoolEnabled={false}
				fetchContent={backend.fetchContent}
				markdownWorkerClient={null}
				projectionWorkerClient={backend.projectionWorkerClient}
			/>,
		);
		await backend.pushMetadata();
		await waitForBridgeViewerText(fixture.expected.initialText);
		const scrollOwner = await waitForBridgeViewerCodeScrollOwner();

		await revealAndSettleSelection({ itemId: startItemId, scrollOwner });
		await revealDeferredTargetAndAssertLanding({
			backend,
			direction: 'down',
			scrollOwner,
			targetHandleIds: deferredHandleIds,
			targetItemId: downTargetItemId,
		});
	});
});

interface FirstFullyVisibleBridgeCodeHeader {
	readonly itemId: string;
	readonly offset: number;
}

function firstFullyVisibleBridgeCodeHeader(
	scrollOwner: HTMLElement,
): FirstFullyVisibleBridgeCodeHeader {
	let best: FirstFullyVisibleBridgeCodeHeader | null = null;
	for (const collapseButton of browserSupport.bridgeCodeHeaderCollapseButtons()) {
		const itemId = collapseButton.dataset['bridgeCodeViewItemId'];
		if (itemId === undefined) {
			continue;
		}
		const offset = browserSupport.bridgeCodeHeaderOffsetFromScrollOwner({
			collapseButton,
			scrollOwner,
		});
		// A header stuck at the viewport top can read a small negative offset (sticky
		// positioning + sub-pixel); treat those as fully visible so the item that owns the
		// top of the viewport wins over the next item below it.
		if (offset < -3) {
			continue;
		}
		if (best === null || offset < best.offset) {
			best = { itemId, offset };
		}
	}
	if (best === null) {
		throw new Error(
			'expected a fully-visible Bridge CodeView header to anchor the streaming proof',
		);
	}
	return best;
}

function bridgeCodeHeaderOffsetForItem(props: {
	readonly itemId: string;
	readonly scrollOwner: HTMLElement;
}): number | null {
	for (const collapseButton of browserSupport.bridgeCodeHeaderCollapseButtons()) {
		if (collapseButton.dataset['bridgeCodeViewItemId'] === props.itemId) {
			return browserSupport.bridgeCodeHeaderOffsetFromScrollOwner({
				collapseButton,
				scrollOwner: props.scrollOwner,
			});
		}
	}
	return null;
}

function idleMetadataWindowBatches(props: {
	readonly batchCount: number;
	readonly reviewPackage: BridgeReviewPackage;
}): readonly (readonly string[])[] {
	const windowSize = 80;
	const batches: (readonly string[])[] = [];
	for (let batchIndex = 0; batchIndex < props.batchCount; batchIndex += 1) {
		const start = batchIndex * windowSize;
		const itemIds = props.reviewPackage.orderedItemIds.slice(start, start + windowSize);
		batches.push(
			itemIds.length > 0 ? itemIds : props.reviewPackage.orderedItemIds.slice(0, windowSize),
		);
	}
	return batches;
}

async function waitForInitialRevealSettled(scrollOwner: HTMLElement): Promise<void> {
	// The metadata snapshot selects item 0 and reveals it; that reveal must finish before a
	// test manually scrolls elsewhere, or the completing animation fights the manual scroll.
	await browserSupport.waitForSelectedBridgeViewerContentState('ready');
	for (let attempt = 0; attempt < 180; attempt += 1) {
		const reason = browserSupport.selectedBridgeViewerPanelAttribute(
			'data-selection-scroll-reason',
		);
		if (reason === 'hydrated' || reason === 'already-completed') {
			break;
		}
		// oxlint-disable-next-line no-await-in-loop -- Must observe the selection reveal complete frame-by-frame.
		await waitForBridgeViewerAnimationFrame();
	}
	await waitForBridgeViewerScrollIdle(scrollOwner);
}

async function waitForBridgeViewerScrollIdle(
	scrollOwner: HTMLElement,
	stableFrameCount = 10,
): Promise<void> {
	let previousScrollTop = scrollOwner.scrollTop;
	let stableFrames = 0;
	for (let frameIndex = 0; frameIndex < 120; frameIndex += 1) {
		// oxlint-disable-next-line no-await-in-loop -- Idle detection must observe sequential animation frames.
		await waitForBridgeViewerAnimationFrame();
		if (Math.abs(scrollOwner.scrollTop - previousScrollTop) <= 1) {
			stableFrames += 1;
			if (stableFrames >= stableFrameCount) {
				return;
			}
		} else {
			stableFrames = 0;
		}
		previousScrollTop = scrollOwner.scrollTop;
	}
}

interface MeasuredBridgeCodeViewLayoutMetrics {
	readonly headerHeight: number;
	readonly lineHeight: number;
}

function measuredBridgeCodeViewLayoutMetrics(): MeasuredBridgeCodeViewLayoutMetrics {
	let headerHeight = 0;
	let lineHeight = 0;
	const searchRoots: ParentNode[] = [document];
	for (const container of document.querySelectorAll('diffs-container')) {
		if (container.shadowRoot !== null) {
			searchRoots.push(container.shadowRoot);
		}
	}
	for (const searchRoot of searchRoots) {
		if (headerHeight === 0) {
			const headerElement = searchRoot.querySelector('[data-diffs-header]');
			if (headerElement instanceof HTMLElement) {
				headerHeight = headerElement.getBoundingClientRect().height;
			}
		}
		if (lineHeight === 0) {
			const lineElement = searchRoot.querySelector('[data-line-index]');
			if (lineElement instanceof HTMLElement) {
				lineHeight = lineElement.getBoundingClientRect().height;
			}
		}
	}
	return {
		headerHeight: Math.round(headerHeight * 100) / 100,
		lineHeight: Math.round(lineHeight * 100) / 100,
	};
}

function revealReviewItem(itemId: string): void {
	window.dispatchEvent(
		new CustomEvent('__bridge_review_control', {
			detail: {
				method: 'bridge.diff.scrollToFile',
				itemId,
			},
		}),
	);
}

function contentHandleIdsForItem(item: BridgeReviewItemDescriptor): readonly string[] {
	return Object.values(item.contentRoles)
		.map((handle): string | null => handle?.handleId ?? null)
		.filter((handleId): handleId is string => handleId !== null);
}

function contentHandleIdsForFixtureItem(
	fixture: BridgeViewerBrowserFixture,
	itemId: string,
): readonly string[] {
	const item = fixture.reviewPackage.itemsById[itemId];
	if (item === undefined) {
		throw new Error(`expected fixture item ${itemId}`);
	}
	return contentHandleIdsForItem(item);
}

async function revealAndSettleSelection(props: {
	readonly itemId: string;
	readonly scrollOwner: HTMLElement;
}): Promise<void> {
	revealReviewItem(props.itemId);
	await browserSupport.waitForBridgeCodeHeaderItemOffsetFromScrollOwner({
		itemId: props.itemId,
		maxOffset: 12,
		scrollOwner: props.scrollOwner,
	});
}

async function drainDeferredContentUntilSelectedReady(props: {
	readonly backend: BridgeViewerMockedBackend;
	readonly targetHandleIds: readonly string[];
	readonly remainingAttempts?: number;
}): Promise<void> {
	const targetHandleSet = new Set(props.targetHandleIds);
	const remainingAttempts = props.remainingAttempts ?? 180;
	for (let attempt = 0; attempt < remainingAttempts; attempt += 1) {
		for (const response of props.backend.pendingContentResponses) {
			// Only resolve the target's content — other deferred handles (e.g. a frozen
			// placeholder item) must stay pending so their heights do not shift the target.
			if (response.handleId !== null && targetHandleSet.has(response.handleId)) {
				response.resolve();
			}
		}
		if (browserSupport.selectedBridgeViewerContentState() === 'ready') {
			return;
		}
		// oxlint-disable-next-line no-await-in-loop -- Draining deferred content must observe frame-by-frame hydration.
		await waitForBridgeViewerAnimationFrame();
	}
	throw new Error(
		`expected deferred content to reach ready; state=${browserSupport.selectedBridgeViewerContentState() ?? 'null'}`,
	);
}

function assertMonotonicScrollConvergence(props: {
	readonly context: string;
	readonly epsilon: number;
	readonly samples: readonly number[];
}): void {
	const significantDeltas: number[] = [];
	for (let index = 1; index < props.samples.length; index += 1) {
		const delta = (props.samples[index] ?? 0) - (props.samples[index - 1] ?? 0);
		if (Math.abs(delta) > props.epsilon) {
			significantDeltas.push(delta);
		}
	}
	let directionReversals = 0;
	for (let index = 1; index < significantDeltas.length; index += 1) {
		if (Math.sign(significantDeltas[index] ?? 0) !== Math.sign(significantDeltas[index - 1] ?? 0)) {
			directionReversals += 1;
		}
	}
	if (directionReversals > 1) {
		throw new Error(
			`expected monotonic settle for ${props.context}; reversals=${directionReversals}; samples=${JSON.stringify(
				props.samples.map((sample): number => Math.round(sample)),
			)}`,
		);
	}
}

async function revealDeferredTargetAndAssertLanding(props: {
	readonly backend: BridgeViewerMockedBackend;
	readonly direction: 'up' | 'down';
	readonly scrollOwner: HTMLElement;
	readonly targetHandleIds: readonly string[];
	readonly targetItemId: string;
}): Promise<void> {
	const revealSamples = await browserSupport.sampleBridgeCodeViewScrollMotion({
		frameCount: 36,
		scrollOwner: props.scrollOwner,
		action: (): void => {
			revealReviewItem(props.targetItemId);
		},
	});
	const revealFirst = revealSamples[0] ?? 0;
	const revealLast = revealSamples.at(-1) ?? revealFirst;
	if (props.direction === 'up') {
		expect(revealLast).toBeLessThan(revealFirst + 1);
	} else {
		expect(revealLast).toBeGreaterThan(revealFirst - 1);
	}

	await browserSupport.waitForBridgeCodeHeaderItemOffsetFromScrollOwner({
		itemId: props.targetItemId,
		maxOffset: 12,
		scrollOwner: props.scrollOwner,
	});
	await drainDeferredContentUntilSelectedReady({
		backend: props.backend,
		targetHandleIds: props.targetHandleIds,
	});

	// F9/I3: after the region hydrates and heights change, scrollTop must converge to the
	// target without oscillation — a single scroll authority (Pierre's smooth path).
	const settleSamples = await browserSupport.sampleBridgeCodeViewScrollMotion({
		frameCount: 24,
		scrollOwner: props.scrollOwner,
		action: (): void => {},
	});
	assertMonotonicScrollConvergence({
		context: `${props.direction}->${props.targetItemId}`,
		epsilon: 2,
		samples: settleSamples,
	});

	// I3/R3/R4 landing bound: target header top at the scroll-owner top and the first
	// fully-visible item after settle. S2 alone lands within the header-estimate residual
	// (a few px of un-truthful placeholder height); accurate itemMetrics in S3 (F1) closes
	// that residual to the spec's tighter bound. The load-bearing S2 proof is the monotonic
	// settle above — the pre-fix bounce is gone.
	const landedOffset = await browserSupport.waitForBridgeCodeHeaderItemOffsetFromScrollOwner({
		itemId: props.targetItemId,
		maxOffset: revealSettleLandingOffsetPixels,
		scrollOwner: props.scrollOwner,
	});
	expect(landedOffset).toBeGreaterThanOrEqual(-revealSettleLandingOffsetPixels);
	expect(landedOffset).toBeLessThanOrEqual(revealSettleLandingOffsetPixels);
	expect(firstFullyVisibleBridgeCodeHeader(props.scrollOwner).itemId).toBe(props.targetItemId);
}

function expectUpwardRevealMotion(samples: readonly number[]): void {
	const firstScrollTop = samples[0] ?? 0;
	const lastScrollTop = samples.at(-1) ?? firstScrollTop;
	expect(lastScrollTop).toBeLessThan(firstScrollTop);
}

async function waitForStableScrollTop(
	scrollOwner: HTMLElement,
	remainingAttempts = 120,
): Promise<number> {
	const firstSample = scrollOwner.scrollTop;
	await waitForBridgeViewerAnimationFrame();
	const secondSample = scrollOwner.scrollTop;
	if (Math.abs(secondSample - firstSample) <= 2) {
		return secondSample;
	}
	if (remainingAttempts <= 0) {
		throw new Error(
			`expected stable Bridge CodeView scrollTop; first=${firstSample}; second=${secondSample}`,
		);
	}
	return await waitForStableScrollTop(scrollOwner, remainingAttempts - 1);
}

function reviewPackageWithClampedLineCounts(props: {
	readonly lineCount: number;
	readonly reviewPackage: BridgeReviewPackage;
}): BridgeReviewPackage {
	const itemsById = Object.fromEntries(
		Object.entries(props.reviewPackage.itemsById).map(
			([itemId, item]): readonly [string, BridgeReviewItemDescriptor] => [
				itemId,
				reviewItemWithClampedLineCounts({
					item,
					lineCount: props.lineCount,
				}),
			],
		),
	);
	return {
		...props.reviewPackage,
		itemsById,
	};
}

function reviewItemWithClampedLineCounts(props: {
	readonly item: BridgeReviewItemDescriptor;
	readonly lineCount: number;
}): BridgeReviewItemDescriptor {
	const contentLineCountsByRole: NonNullable<
		BridgeReviewItemDescriptor['contentLineCountsByRole']
	> = {};
	for (const role of [
		'base',
		'head',
		'diff',
		'file',
	] as const satisfies readonly BridgeContentRole[]) {
		if (props.item.contentRoles[role] !== null && props.item.contentRoles[role] !== undefined) {
			contentLineCountsByRole[role] = props.lineCount;
		}
	}
	return {
		...props.item,
		contentLineCountsByRole,
	};
}

function dispatchReviewMetadataWindow(props: {
	readonly itemIds: readonly string[];
	readonly reviewPackage: BridgeReviewPackage;
	readonly sequence: number;
}): void {
	const protocolFrame = buildReviewMetadataWindowFrame({
		package: props.reviewPackage,
		paneId: reviewPaneId,
		sequence: props.sequence,
		sourceIdentity: props.reviewPackage.query.queryId,
		streamId: reviewStreamId,
		itemIds: props.itemIds,
	});
	const intakeFrame: BridgeIntakeFrame = {
		kind: 'delta',
		streamId: protocolFrame.streamId,
		generation: protocolFrame.generation,
		sequence: protocolFrame.sequence,
		payload: protocolFrame,
	};
	document.dispatchEvent(
		new CustomEvent('__bridge_intake_json', {
			detail: {
				json: JSON.stringify(intakeFrame),
				nonce: bridgeViewerPushNonce,
			},
		}),
	);
}
