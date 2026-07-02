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
} from './bridge-viewer-mocked-backend.js';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load the app CSS.
import '../../app/bridge-app.css';

const reviewPaneId = 'bridge-viewer-dev-pane';
const reviewStreamId = `review:${reviewPaneId}`;
const bridgeViewerPushNonce = 'browser-push-nonce';

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
		scrollOwner.scrollTop = Math.min(scrollOwner.scrollHeight - scrollOwner.clientHeight, 12_000);
		scrollOwner.dispatchEvent(new Event('scroll', { bubbles: true }));
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();
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
});

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
