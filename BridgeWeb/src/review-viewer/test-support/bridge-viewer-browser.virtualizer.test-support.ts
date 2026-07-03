import { expect } from 'vitest';

import type { BridgeIntakeFrame } from '../../core/models/bridge-intake-frame.js';
import { buildReviewMetadataWindowFrame } from '../../features/review/protocol/review-metadata-frame-builder.js';
import type {
	BridgeContentRole,
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package.js';
import { waitForBridgeViewerAnimationFrame } from './bridge-viewer-browser-dom.js';
import * as browserSupport from './bridge-viewer-browser.integration.test-support.js';
import type {
	BridgeViewerBrowserFixture,
	BridgeViewerMockedBackend,
} from './bridge-viewer-mocked-backend.js';

const reviewPaneId = 'bridge-viewer-dev-pane';
const reviewStreamId = `review:${reviewPaneId}`;
const bridgeViewerPushNonce = 'browser-push-nonce';
// Selection-reveal landing bound (px) between the target header top and the scroll-owner
// top after settle. Measured to be a constant ~4px structural offset from Pierre's item
// layout at align:'start' (identical for a 1-line filler and a multi-line file, and
// unchanged by S3 height truth), so this is the achievable floor -- the load-bearing proof
// is the monotonic, oscillation-free settle, not sub-pixel landing.
export const revealSettleLandingOffsetPixels = 4;

export interface FirstFullyVisibleBridgeCodeHeader {
	readonly itemId: string;
	readonly offset: number;
}

export interface TreeRevealLandingFrameSample {
	readonly frameIndex: number;
	readonly headerOffset: number | null;
	readonly scrollTop: number;
}

export function firstFullyVisibleBridgeCodeHeader(
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

export function bridgeCodeHeaderOffsetForItem(props: {
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

export function idleMetadataWindowBatches(props: {
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

export async function waitForInitialRevealSettled(scrollOwner: HTMLElement): Promise<void> {
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

export async function waitForBridgeViewerScrollIdle(
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

export async function waitForBridgeCodeScrollHeightChange(props: {
	readonly previousScrollHeight: number;
	readonly scrollOwner: HTMLElement;
}): Promise<void> {
	for (let frameIndex = 0; frameIndex < 120; frameIndex += 1) {
		// oxlint-disable-next-line no-await-in-loop -- Late hydration proof must observe the layout shift frame.
		await waitForBridgeViewerAnimationFrame();
		if (props.scrollOwner.scrollHeight !== props.previousScrollHeight) {
			return;
		}
	}
	throw new Error(
		`expected late above-target hydration to change CodeView scroll height; previous=${props.previousScrollHeight}; current=${props.scrollOwner.scrollHeight}`,
	);
}

export interface MeasuredBridgeCodeViewLayoutMetrics {
	readonly headerHeight: number;
	readonly lineHeight: number;
}

export function measuredBridgeCodeViewLayoutMetrics(): MeasuredBridgeCodeViewLayoutMetrics {
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

export function revealReviewItem(itemId: string): void {
	window.dispatchEvent(
		new CustomEvent('__bridge_review_control', {
			detail: {
				method: 'bridge.diff.scrollToFile',
				itemId,
			},
		}),
	);
}

export function revealReviewTreePath(path: string): void {
	window.dispatchEvent(
		new CustomEvent('__bridge_review_control', {
			detail: {
				method: 'bridge.fileTree.revealPath',
				path,
			},
		}),
	);
}

export function contentHandleIdsForItem(item: BridgeReviewItemDescriptor): readonly string[] {
	return Object.values(item.contentRoles)
		.map((handle): string | null => handle?.handleId ?? null)
		.filter((handleId): handleId is string => handleId !== null);
}

export function contentHandleIdsForFixtureItem(
	fixture: BridgeViewerBrowserFixture,
	itemId: string,
): readonly string[] {
	const item = fixture.reviewPackage.itemsById[itemId];
	if (item === undefined) {
		throw new Error(`expected fixture item ${itemId}`);
	}
	return contentHandleIdsForItem(item);
}

export async function revealAndSettleSelection(props: {
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

export async function sampleTreeRevealLandingFrames(props: {
	readonly frameCount: number;
	readonly scrollOwner: HTMLElement;
	readonly targetItemId: string;
	readonly targetPath: string;
}): Promise<readonly TreeRevealLandingFrameSample[]> {
	const samples: TreeRevealLandingFrameSample[] = [
		{
			frameIndex: 0,
			headerOffset: bridgeCodeHeaderOffsetForItem({
				itemId: props.targetItemId,
				scrollOwner: props.scrollOwner,
			}),
			scrollTop: props.scrollOwner.scrollTop,
		},
	];
	revealReviewTreePath(props.targetPath);
	for (let frameIndex = 1; frameIndex <= props.frameCount; frameIndex += 1) {
		// oxlint-disable-next-line no-await-in-loop -- Post-landing drift proof must sample sequential browser frames.
		await waitForBridgeViewerAnimationFrame();
		samples.push({
			frameIndex,
			headerOffset: bridgeCodeHeaderOffsetForItem({
				itemId: props.targetItemId,
				scrollOwner: props.scrollOwner,
			}),
			scrollTop: props.scrollOwner.scrollTop,
		});
	}
	return samples;
}

export function assertTargetHeaderStaysPinnedAfterLanding(props: {
	readonly context: string;
	readonly samples: readonly TreeRevealLandingFrameSample[];
}): void {
	const landingFrame = props.samples.find(
		(sample): boolean =>
			sample.headerOffset !== null &&
			Math.abs(sample.headerOffset) <= revealSettleLandingOffsetPixels,
	);
	if (landingFrame === undefined) {
		throw new Error(
			`expected instant reveal to land ${props.context}; samples=${JSON.stringify(
				props.samples.map(
					(sample): Record<string, number | null> => ({
						frameIndex: sample.frameIndex,
						headerOffset: sample.headerOffset === null ? null : Math.round(sample.headerOffset),
						scrollTop: Math.round(sample.scrollTop),
					}),
				),
			)}`,
		);
	}
	const postLandingSamples = props.samples.filter(
		(sample): boolean => sample.frameIndex > landingFrame.frameIndex,
	);
	const unpinnedSample = postLandingSamples.find(
		(sample): boolean =>
			sample.headerOffset === null ||
			Math.abs(sample.headerOffset) > revealSettleLandingOffsetPixels,
	);
	if (unpinnedSample !== undefined) {
		throw new Error(
			`expected target header to stay pinned for ${props.context}; samples=${JSON.stringify(
				props.samples.map(
					(sample): Record<string, number | null> => ({
						frameIndex: sample.frameIndex,
						headerOffset: sample.headerOffset === null ? null : Math.round(sample.headerOffset),
						scrollTop: Math.round(sample.scrollTop),
					}),
				),
			)}`,
		);
	}
}

export async function drainDeferredContentUntilSelectedReady(props: {
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

export function resolveDeferredContentForItem(props: {
	readonly backend: BridgeViewerMockedBackend;
	readonly itemId: string;
	readonly targetHandleIds: readonly string[];
}): void {
	const targetHandleSet = new Set(props.targetHandleIds);
	let didResolve = false;
	for (const response of props.backend.pendingContentResponses) {
		if (response.handleId !== null && targetHandleSet.has(response.handleId)) {
			response.resolve();
			didResolve = true;
		}
	}
	if (!didResolve) {
		throw new Error(`expected pending deferred content for ${props.itemId}`);
	}
}

export function assertMonotonicScrollConvergence(props: {
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

export async function revealDeferredTargetAndAssertLanding(props: {
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

export function expectUpwardRevealMotion(samples: readonly number[]): void {
	const firstScrollTop = samples[0] ?? 0;
	const lastScrollTop = samples.at(-1) ?? firstScrollTop;
	expect(lastScrollTop).toBeLessThan(firstScrollTop);
}

export async function waitForStableScrollTop(
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

export async function waitForStableBridgeCodeHeaderItemOffset(props: {
	readonly itemId: string;
	readonly scrollOwner: HTMLElement;
	readonly remainingAttempts?: number;
}): Promise<number> {
	const firstOffset = bridgeCodeHeaderOffsetForItem({
		itemId: props.itemId,
		scrollOwner: props.scrollOwner,
	});
	await waitForBridgeViewerAnimationFrame();
	const secondOffset = bridgeCodeHeaderOffsetForItem({
		itemId: props.itemId,
		scrollOwner: props.scrollOwner,
	});
	if (firstOffset !== null && secondOffset !== null && Math.abs(secondOffset - firstOffset) <= 1) {
		return secondOffset;
	}
	const remainingAttempts = props.remainingAttempts ?? 120;
	if (remainingAttempts <= 0) {
		throw new Error(
			`expected stable Bridge CodeView header offset for ${props.itemId}; first=${firstOffset ?? 'missing'}; second=${secondOffset ?? 'missing'}`,
		);
	}
	return await waitForStableBridgeCodeHeaderItemOffset({
		itemId: props.itemId,
		remainingAttempts: remainingAttempts - 1,
		scrollOwner: props.scrollOwner,
	});
}

export function fixtureWithWrapHeavyLogicalLines(props: {
	readonly fixture: BridgeViewerBrowserFixture;
	readonly itemIds: readonly string[];
}): BridgeViewerBrowserFixture {
	const contentByHandleId = new Map(props.fixture.contentByHandleId);
	const targetItemIds = new Set(props.itemIds);
	const itemsById = Object.fromEntries(
		Object.entries(props.fixture.reviewPackage.itemsById).map(
			([itemId, item]): readonly [string, BridgeReviewItemDescriptor] => {
				if (!targetItemIds.has(itemId)) {
					return [itemId, item];
				}
				return [
					itemId,
					reviewItemWithWrapHeavyLogicalLines({
						contentByHandleId,
						item,
					}),
				];
			},
		),
	);
	return {
		...props.fixture,
		contentByHandleId,
		reviewPackage: {
			...props.fixture.reviewPackage,
			itemsById,
		},
	};
}

export function reviewItemWithWrapHeavyLogicalLines(props: {
	readonly contentByHandleId: Map<string, string>;
	readonly item: BridgeReviewItemDescriptor;
}): BridgeReviewItemDescriptor {
	const contentRoles = { ...props.item.contentRoles };
	const contentLineCountsByRole: NonNullable<
		BridgeReviewItemDescriptor['contentLineCountsByRole']
	> = {
		...props.item.contentLineCountsByRole,
	};
	for (const role of [
		'base',
		'head',
		'diff',
		'file',
	] as const satisfies readonly BridgeContentRole[]) {
		const handle = props.item.contentRoles[role];
		if (handle === null || handle === undefined) {
			continue;
		}
		const content = wrapHeavyLogicalLineForReviewRole({
			itemId: props.item.itemId,
			role,
		});
		props.contentByHandleId.set(handle.handleId, content);
		contentRoles[role] = {
			...handle,
			sizeBytes: new TextEncoder().encode(content).byteLength,
		};
		contentLineCountsByRole[role] = 1;
	}
	return {
		...props.item,
		contentRoles,
		contentLineCountsByRole,
	};
}

export function wrapHeavyLogicalLineForReviewRole(props: {
	readonly itemId: string;
	readonly role: BridgeContentRole;
}): string {
	const repeatedTokens = Array.from({ length: 220 }, (_value: unknown, index: number): string => {
		const tokenIndex = index.toString().padStart(3, '0');
		return `${props.role}_${props.itemId}_wrapped_token_${tokenIndex}`;
	});
	return `export const ${props.role}Wrapped${props.itemId.replaceAll('-', '_')} = '${repeatedTokens.join(' ')}';\n`;
}

export function reviewPackageWithClampedLineCounts(props: {
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

export function reviewPackageWithItemLineCounts(props: {
	readonly itemIds: readonly string[];
	readonly lineCount: number;
	readonly reviewPackage: BridgeReviewPackage;
}): BridgeReviewPackage {
	const itemIds = new Set(props.itemIds);
	const itemsById = Object.fromEntries(
		Object.entries(props.reviewPackage.itemsById).map(
			([itemId, item]): readonly [string, BridgeReviewItemDescriptor] => [
				itemId,
				itemIds.has(itemId)
					? reviewItemWithClampedLineCounts({
							item,
							lineCount: props.lineCount,
						})
					: item,
			],
		),
	);
	return {
		...props.reviewPackage,
		itemsById,
	};
}

export function reviewItemWithClampedLineCounts(props: {
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

export function dispatchReviewMetadataWindow(props: {
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
