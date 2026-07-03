import { CodeView } from '@pierre/diffs';
import { afterEach, describe, expect, test, vi } from 'vitest';
import { cleanup, render } from 'vitest-browser-react';

import { BridgeApp } from '../../app/bridge-app.js';
import { bridgeCodeViewOptions } from '../code-view/bridge-code-view-options.js';
import {
	waitForBridgeViewerAnimationFrame,
	waitForBridgeViewerCodeScrollOwner,
	waitForBridgeViewerText,
} from './bridge-viewer-browser-dom.js';
import * as browserSupport from './bridge-viewer-browser.integration.test-support.js';
import * as virtualizerSupport from './bridge-viewer-browser.virtualizer.test-support.js';
import {
	disposeBridgeViewerMockedBackends,
	installBridgeViewerMockedBackend,
	makeBridgeViewerBrowserFixture,
} from './bridge-viewer-mocked-backend.js';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load the app CSS.
import '../../app/bridge-app.css';

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
		const initialPackage = virtualizerSupport.reviewPackageWithClampedLineCounts({
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

		virtualizerSupport.dispatchReviewMetadataWindow({
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

		virtualizerSupport.dispatchReviewMetadataWindow({
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
		await virtualizerSupport.waitForBridgeViewerScrollIdle(scrollOwner);
		expect(scrollOwner.scrollTop).toBeGreaterThan(0);

		// I4 USER MOTION ONLY: idle metadata windows must not move the viewport. The
		// measurable invariant is first-visible-line drift — the anchored header's offset
		// from the scroll-owner top — not absolute scrollTop, which legitimately shifts as
		// total height changes (that thumb churn is R2's domain).
		const anchorBefore = virtualizerSupport.firstFullyVisibleBridgeCodeHeader(scrollOwner);
		const renderedHeaderCountBefore = browserSupport.bridgeCodeHeaderCollapseButtons().length;

		const windowBatches = virtualizerSupport.idleMetadataWindowBatches({
			batchCount: 5,
			reviewPackage: fixture.reviewPackage,
		});
		for (const [batchIndex, itemIds] of windowBatches.entries()) {
			virtualizerSupport.dispatchReviewMetadataWindow({
				itemIds,
				reviewPackage: fixture.reviewPackage,
				sequence: 200 + batchIndex,
			});
			// oxlint-disable-next-line no-await-in-loop -- Streaming stability proof must observe each window settle.
			await waitForBridgeViewerAnimationFrame();
			// oxlint-disable-next-line no-await-in-loop -- Streaming stability proof must observe each window settle.
			await waitForBridgeViewerAnimationFrame();
			const anchorOffsetDuringWindow = virtualizerSupport.bridgeCodeHeaderOffsetForItem({
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
		const deferredUpTargetHandleIds = virtualizerSupport.contentHandleIdsForItem(upItem);
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
		await virtualizerSupport.waitForInitialRevealSettled(scrollOwner);
		scrollOwner.scrollTop = Math.min(scrollOwner.scrollHeight - scrollOwner.clientHeight, 12_000);
		scrollOwner.dispatchEvent(new Event('scroll', { bubbles: true }));
		await virtualizerSupport.waitForBridgeViewerScrollIdle(scrollOwner);
		expect(scrollOwner.scrollTop).toBeGreaterThan(0);

		const upwardMotionSamples = await browserSupport.sampleBridgeCodeViewScrollMotion({
			frameCount: 36,
			scrollOwner,
			action: (): void => {
				virtualizerSupport.revealReviewItem(upItemId);
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
		const settledScrollTop = await virtualizerSupport.waitForStableScrollTop(scrollOwner);
		const resampledSettledScrollTop = await virtualizerSupport.waitForStableScrollTop(scrollOwner);

		virtualizerSupport.expectUpwardRevealMotion(upwardMotionSamples);
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
		const firstUpTargetHandleIds = virtualizerSupport.contentHandleIdsForFixtureItem(
			fixture,
			firstUpTarget,
		);
		const secondUpTargetHandleIds = virtualizerSupport.contentHandleIdsForFixtureItem(
			fixture,
			secondUpTarget,
		);
		const backend = installBridgeViewerMockedBackend(fixture, {
			deferContentHandleIds: [
				...virtualizerSupport.contentHandleIdsForFixtureItem(fixture, frozenPlaceholderItem),
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
		await virtualizerSupport.waitForInitialRevealSettled(scrollOwner);

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
			await virtualizerSupport.waitForBridgeViewerScrollIdle(scrollOwner);
			// oxlint-disable-next-line no-await-in-loop -- Each reveal must land and settle before the next.
			await virtualizerSupport.revealDeferredTargetAndAssertLanding({
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
		await virtualizerSupport.waitForInitialRevealSettled(scrollOwner);

		// I1 HEIGHT TRUTH (F1): the estimate Pierre reserves for an unhydrated/virtualized item
		// must equal the height it measures after render, within a line of rounding. Without
		// itemMetrics Pierre defaults to a 44px header while the rendered header is 32px.
		const measured = virtualizerSupport.measuredBridgeCodeViewLayoutMetrics();
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
			await virtualizerSupport.waitForBridgeViewerScrollIdle(scrollOwner);
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
		const deferredHandleIds = virtualizerSupport.contentHandleIdsForFixtureItem(
			fixture,
			downTargetItemId,
		);
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

		await virtualizerSupport.revealAndSettleSelection({ itemId: startItemId, scrollOwner });
		await virtualizerSupport.revealDeferredTargetAndAssertLanding({
			backend,
			direction: 'down',
			scrollOwner,
			targetHandleIds: deferredHandleIds,
			targetItemId: downTargetItemId,
		});
	});

	test('corrects a deep reveal after wrap-heavy above-target estimates land the rendered header low', async () => {
		const fixture = makeBridgeViewerBrowserFixture({ fixtureClass: 'large-diffshub' });
		const orderedItemIds = fixture.reviewPackage.orderedItemIds;
		const targetItemId = orderedItemIds[260];
		if (targetItemId === undefined) {
			throw new Error('Expected large fixture deep correction target item.');
		}
		const wrapHeavyAboveTargetItemIds = orderedItemIds.slice(228, 260);
		const wrapHeavyFixture = virtualizerSupport.fixtureWithWrapHeavyLogicalLines({
			fixture,
			itemIds: wrapHeavyAboveTargetItemIds,
		});
		const backend = installBridgeViewerMockedBackend(wrapHeavyFixture);

		render(
			<BridgeApp
				codeViewWorkerPoolEnabled={false}
				fetchContent={backend.fetchContent}
				markdownWorkerClient={null}
				projectionWorkerClient={backend.projectionWorkerClient}
			/>,
		);
		await backend.pushMetadata(wrapHeavyFixture.reviewPackage);
		await waitForBridgeViewerText(fixture.expected.initialText);

		const scrollOwner = await waitForBridgeViewerCodeScrollOwner();
		await virtualizerSupport.waitForInitialRevealSettled(scrollOwner);

		virtualizerSupport.revealReviewItem(targetItemId);
		await browserSupport.waitForSelectedBridgeViewerContentState('ready');
		const landedOffset = await virtualizerSupport.waitForStableBridgeCodeHeaderItemOffset({
			itemId: targetItemId,
			scrollOwner,
		});

		// 4px is the documented Pierre layout constant at align:start (docs/specs/bridge-viewer-scroll-parity.md R3/R4); app-side correction cannot beat estimate error for unmeasured above-target items.
		expect(landedOffset).toBeGreaterThanOrEqual(
			-virtualizerSupport.revealSettleLandingOffsetPixels,
		);
		expect(landedOffset).toBeLessThanOrEqual(virtualizerSupport.revealSettleLandingOffsetPixels);
		expect(virtualizerSupport.firstFullyVisibleBridgeCodeHeader(scrollOwner).itemId).toBe(
			targetItemId,
		);
	});

	test('keeps an upward tree reveal pinned after above-target content hydrates late', async () => {
		const fixture = makeBridgeViewerBrowserFixture({ fixtureClass: 'large-diffshub' });
		const aboveTargetItemId = 'browser-large-diff';
		const targetItemId = 'browser-hunked-diff';
		const reviewPackage = virtualizerSupport.reviewPackageWithItemLineCounts({
			itemIds: [aboveTargetItemId],
			lineCount: 1,
			reviewPackage: fixture.reviewPackage,
		});
		const targetItem = fixture.reviewPackage.itemsById[targetItemId];
		if (targetItem === undefined) {
			throw new Error('Expected large fixture tree reveal target item.');
		}
		const rawTargetPath = targetItem.headPath ?? targetItem.basePath;
		if (typeof rawTargetPath !== 'string') {
			throw new Error('Expected large fixture tree reveal target path.');
		}
		const targetPath = rawTargetPath;
		const aboveTargetHandleIds = virtualizerSupport.contentHandleIdsForFixtureItem(
			fixture,
			aboveTargetItemId,
		);
		const backend = installBridgeViewerMockedBackend(fixture, {
			deferContentHandleIds: aboveTargetHandleIds,
		});

		render(
			<BridgeApp
				codeViewWorkerPoolEnabled={false}
				fetchContent={backend.fetchContent}
				markdownWorkerClient={null}
				projectionWorkerClient={backend.projectionWorkerClient}
			/>,
		);
		await backend.pushMetadata(reviewPackage);
		await waitForBridgeViewerText(fixture.expected.initialText);

		const scrollOwner = await waitForBridgeViewerCodeScrollOwner();
		await virtualizerSupport.waitForInitialRevealSettled(scrollOwner);
		scrollOwner.scrollTop = Math.min(scrollOwner.scrollHeight - scrollOwner.clientHeight, 12_000);
		scrollOwner.dispatchEvent(new Event('scroll', { bubbles: true }));
		await virtualizerSupport.waitForBridgeViewerScrollIdle(scrollOwner);
		expect(scrollOwner.scrollTop).toBeGreaterThan(0);

		const revealSamples = await virtualizerSupport.sampleTreeRevealLandingFrames({
			frameCount: 44,
			scrollOwner,
			targetItemId,
			targetPath,
		});

		virtualizerSupport.assertTargetHeaderStaysPinnedAfterLanding({
			context: targetItemId,
			samples: revealSamples,
		});
		const scrollHeightBeforeAboveHydration = scrollOwner.scrollHeight;
		for (const response of backend.pendingContentResponses) {
			if (response.handleId !== null && aboveTargetHandleIds.includes(response.handleId)) {
				response.resolve();
			}
		}
		await virtualizerSupport.waitForBridgeCodeScrollHeightChange({
			previousScrollHeight: scrollHeightBeforeAboveHydration,
			scrollOwner,
		});
		await virtualizerSupport.waitForBridgeViewerScrollIdle(scrollOwner);
		const targetOffsetAfterAboveHydration =
			await browserSupport.waitForBridgeCodeHeaderItemOffsetFromScrollOwner({
				itemId: targetItemId,
				maxOffset: virtualizerSupport.revealSettleLandingOffsetPixels,
				scrollOwner,
			});

		expect(targetOffsetAfterAboveHydration).toBeGreaterThanOrEqual(
			-virtualizerSupport.revealSettleLandingOffsetPixels,
		);
		expect(targetOffsetAfterAboveHydration).toBeLessThanOrEqual(
			virtualizerSupport.revealSettleLandingOffsetPixels,
		);
		expect(virtualizerSupport.firstFullyVisibleBridgeCodeHeader(scrollOwner).itemId).toBe(
			targetItemId,
		);
	});

	test('does not chase post-settle non-selected hydration above the selected file', async () => {
		const fixture = makeBridgeViewerBrowserFixture({ fixtureClass: 'large-diffshub' });
		const targetItemId = 'browser-hunked-diff';
		const inRenderWindowAboveTargetItemId = 'browser-docs-plan';
		const aboveTargetItemIds = ['browser-source-b', 'browser-added-source', 'browser-docs-plan'];
		const aboveTargetHandleIds = aboveTargetItemIds.flatMap((itemId): readonly string[] =>
			virtualizerSupport.contentHandleIdsForFixtureItem(fixture, itemId),
		);
		const targetItem = fixture.reviewPackage.itemsById[targetItemId];
		if (targetItem === undefined) {
			throw new Error('Expected large fixture post-settle target item.');
		}
		const rawTargetPath = targetItem.headPath ?? targetItem.basePath;
		if (typeof rawTargetPath !== 'string') {
			throw new Error('Expected large fixture post-settle target path.');
		}
		const targetPath = rawTargetPath;
		const backend = installBridgeViewerMockedBackend(fixture, {
			deferContentHandleIds: aboveTargetHandleIds,
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
		await virtualizerSupport.waitForInitialRevealSettled(scrollOwner);
		scrollOwner.scrollTop = Math.min(scrollOwner.scrollHeight - scrollOwner.clientHeight, 12_000);
		scrollOwner.dispatchEvent(new Event('scroll', { bubbles: true }));
		await virtualizerSupport.waitForBridgeViewerScrollIdle(scrollOwner);
		expect(scrollOwner.scrollTop).toBeGreaterThan(0);

		const revealSamples = await virtualizerSupport.sampleTreeRevealLandingFrames({
			frameCount: 44,
			scrollOwner,
			targetItemId,
			targetPath,
		});
		virtualizerSupport.assertTargetHeaderStaysPinnedAfterLanding({
			context: targetItemId,
			samples: revealSamples,
		});
		await browserSupport.waitForSelectedBridgeViewerContentState('ready');
		const settledScrollTop = await virtualizerSupport.waitForStableScrollTop(scrollOwner);

		// I2/I4 post-settle contract: after the reveal settles, OUR code must issue zero scroll
		// writes. Every app-issued scroll (reveal retarget + hydration re-arm) delegates through
		// the Pierre instance's scrollTo, while Pierre's own top-visible anchor adjusts scroll
		// internally without it — so a spy count of 0 proves the app never chases hydration. The
		// in-render-window item (browser-docs-plan) deliberately breaks F2/I1 height truth and
		// Pierre's anchor legitimately tracks it (vendor behavior, not our writer), so its pixel
		// motion is expected; only the genuinely off-screen items stay pixel-stable.
		const appScrollWriteSpy = vi.spyOn(CodeView.prototype, 'scrollTo');
		try {
			for (const aboveTargetItemId of aboveTargetItemIds) {
				const scrollHeightBeforeHydration = scrollOwner.scrollHeight;
				// oxlint-disable-next-line no-await-in-loop -- Each above-target hydration must settle before sampling the next one.
				const samples = await browserSupport.sampleBridgeCodeViewScrollMotion({
					frameCount: aboveTargetItemId === inRenderWindowAboveTargetItemId ? 24 : 12,
					scrollOwner,
					action: (): void => {
						virtualizerSupport.resolveDeferredContentForItem({
							backend,
							itemId: aboveTargetItemId,
							targetHandleIds: virtualizerSupport.contentHandleIdsForFixtureItem(
								fixture,
								aboveTargetItemId,
							),
						});
					},
				});
				if (aboveTargetItemId === inRenderWindowAboveTargetItemId) {
					// oxlint-disable-next-line no-await-in-loop -- The in-render-window hydration must land before the spy is asserted.
					await virtualizerSupport.waitForBridgeCodeScrollHeightChange({
						previousScrollHeight: scrollHeightBeforeHydration,
						scrollOwner,
					});
					// oxlint-disable-next-line no-await-in-loop -- Let Pierre's anchor settle before the next sample.
					await virtualizerSupport.waitForBridgeViewerScrollIdle(scrollOwner);
					continue;
				}
				const largestScrollDelta = Math.max(
					...samples.map((sample: number): number => Math.abs(sample - settledScrollTop)),
				);
				expect(largestScrollDelta, aboveTargetItemId).toBeLessThanOrEqual(2);
			}
			expect(appScrollWriteSpy, 'app-issued scroll writes after settle').not.toHaveBeenCalled();
		} finally {
			appScrollWriteSpy.mockRestore();
		}
		expect(virtualizerSupport.firstFullyVisibleBridgeCodeHeader(scrollOwner).itemId).toBe(
			targetItemId,
		);
	});
});
