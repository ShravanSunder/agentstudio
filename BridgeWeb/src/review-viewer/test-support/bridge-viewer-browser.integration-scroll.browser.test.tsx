import { afterEach, describe, expect, test } from 'vitest';
import { cleanup } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load the app CSS.
import '../../app/bridge-app.css';
import { reviewPackageForBridgeAppDevFixtureScenario } from '../../app/bridge-app-dev-fixture.js';
import { createBridgePierrePortableBlobWorkerFactory } from '../workers/pierre/bridge-pierre-dev-worker-factory.js';
import {
	bridgeViewerRenderedTextContent,
	bridgeViewerVisibleCodeTextContent,
	setBridgeViewerSearchText,
	waitForBridgeViewerAnimationFrame,
	waitForBridgeViewerCodeScrollOwner,
	waitForBridgeViewerText,
	waitForBridgeViewerTreeItemButton,
} from './bridge-viewer-browser-dom.js';
import * as browserSupport from './bridge-viewer-browser.integration.test-support.js';
import * as virtualizerSupport from './bridge-viewer-browser.virtualizer.test-support.js';
import {
	disposeBridgeViewerMockedBackends,
	installBridgeViewerMockedBackend,
	makeBridgeViewerBrowserFixture,
} from './bridge-viewer-mocked-backend.js';

describe('Bridge viewer Browser Mode large fixture scroll integration', () => {
	afterEach(async () => {
		cleanup();
		await Promise.resolve();
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();
		disposeBridgeViewerMockedBackends();
		document.body.replaceChildren();
		document.documentElement.removeAttribute('data-bridge-review-pane-id');
		document.documentElement.removeAttribute('data-bridge-review-stream-id');
		delete window.bridgeReviewControlProbe;
	});

	test('large fixture search reveals added files and renders their fetched content', async () => {
		const fixture = makeBridgeViewerBrowserFixture({ fixtureClass: 'large-diffshub' });
		const backend = installBridgeViewerMockedBackend(fixture);
		const workerFactory = createBridgePierrePortableBlobWorkerFactory();

		try {
			browserSupport.renderBridgeViewerAppWithMockedBackend({
				backend,
				codeViewWorkerFactory: workerFactory.workerFactory,
				codeViewWorkerPoolEnabled: true,
			});
			await backend.pushMetadata(
				reviewPackageForBridgeAppDevFixtureScenario({
					fixture,
					scenario: 'scroll',
				}),
			);
			await browserSupport.waitForSelectedBridgeViewerDisplayPath(fixture.expected.largePath);
			await browserSupport.waitForSelectedBridgeViewerContentState('ready');
			await browserSupport.waitForBridgeViewerTextWithDiagnostics(fixture.expected.largeText);

			setBridgeViewerSearchText('NewPanel');
			const addedButton = await waitForBridgeViewerTreeItemButton(fixture.expected.addedPath);
			addedButton.click();
			await waitForBridgeViewerText(fixture.expected.addedText);
			const codeScroll = await waitForBridgeViewerCodeScrollOwner();
			const selectedItemId = browserSupport.bridgeReviewFixtureItemIdForPath(
				fixture,
				fixture.expected.addedPath,
			);
			const selectedHeaderOffset =
				await browserSupport.waitForBridgeCodeHeaderItemOffsetFromScrollOwner({
					itemId: selectedItemId,
					maxOffset: 8,
					scrollOwner: codeScroll,
				});

			expect(bridgeViewerRenderedTextContent()).toContain(fixture.expected.addedText);
			expect(bridgeViewerVisibleCodeTextContent(codeScroll)).toContain(fixture.expected.addedText);
			expect(selectedHeaderOffset).toBeGreaterThanOrEqual(0);
			expect(selectedHeaderOffset).toBeLessThanOrEqual(8);
			expect(
				backend.requestedUrls.some((url: string): boolean =>
					url.includes(fixture.expected.addedHeadHandleId),
				),
			).toBe(true);
		} finally {
			await browserSupport.cleanupBridgeViewerReactTreeBeforeExternalWorkerRevoke();
			workerFactory.revoke();
			backend.dispose();
		}
	});

	test('large fixture file selection keeps the target header pinned after content hydration', async () => {
		const fixture = makeBridgeViewerBrowserFixture({ fixtureClass: 'large-diffshub' });
		const backend = installBridgeViewerMockedBackend(fixture, {
			deferContentHandleIds: [fixture.expected.addedHeadHandleId],
		});
		const workerFactory = createBridgePierrePortableBlobWorkerFactory();

		try {
			browserSupport.renderBridgeViewerAppWithMockedBackend({
				backend,
				codeViewWorkerFactory: workerFactory.workerFactory,
				codeViewWorkerPoolEnabled: true,
			});
			await backend.pushMetadata(
				reviewPackageForBridgeAppDevFixtureScenario({
					fixture,
					scenario: 'scroll',
				}),
			);
			try {
				await browserSupport.waitForSelectedBridgeViewerDisplayPath(fixture.expected.largePath);
			} catch (error: unknown) {
				throw new Error(
					[
						error instanceof Error ? error.message : String(error),
						`requestedUrls=${JSON.stringify(backend.requestedUrls.slice(0, 8))}`,
					].join('\n'),
					{ cause: error },
				);
			}
			await browserSupport.waitForSelectedBridgeViewerContentState('ready');
			await browserSupport.waitForBridgeViewerTextWithDiagnostics(fixture.expected.largeText);

			setBridgeViewerSearchText('NewPanel');
			const addedButton = await waitForBridgeViewerTreeItemButton(fixture.expected.addedPath);
			const codeScroll = await waitForBridgeViewerCodeScrollOwner();
			const selectedItemId = browserSupport.bridgeReviewFixtureItemIdForPath(
				fixture,
				fixture.expected.addedPath,
			);

			addedButton.click();
			await browserSupport.waitForSelectedBridgeViewerDisplayPath(fixture.expected.addedPath);
			await browserSupport.waitForPendingContentResponseCount(backend, 1);
			expect(backend.pendingContentResponses.map((response) => response.handleId)).toEqual([
				fixture.expected.addedHeadHandleId,
			]);
			const selectedHeaderButton =
				await browserSupport.waitForBridgeCodeHeaderCollapseButtonForItem(selectedItemId);
			const offsetBeforeHydration =
				await browserSupport.waitForBridgeCodeHeaderOffsetFromScrollOwner({
					collapseButton: selectedHeaderButton,
					maxOffset: 8,
					scrollOwner: codeScroll,
				});

			backend.pendingContentResponses[0]?.resolve();
			await browserSupport.waitForSelectedBridgeViewerContentState('ready');
			await browserSupport.waitForBridgeViewerTextWithDiagnostics(fixture.expected.addedText);
			const hydratedSelectedHeaderButton =
				await browserSupport.waitForBridgeCodeHeaderCollapseButtonForItem(selectedItemId);
			const stableOffsetAfterHydration =
				await browserSupport.waitForStableBridgeCodeHeaderOffsetFromScrollOwner({
					collapseButton: hydratedSelectedHeaderButton,
					maxOffset: 8,
					scrollOwner: codeScroll,
				});

			expect(offsetBeforeHydration).toBeLessThanOrEqual(8);
			expect(stableOffsetAfterHydration).toBeGreaterThanOrEqual(0);
			expect(stableOffsetAfterHydration).toBeLessThanOrEqual(4);
		} finally {
			await browserSupport.cleanupBridgeViewerReactTreeBeforeExternalWorkerRevoke();
			workerFactory.revoke();
			backend.dispose();
		}
	});

	test('large fixture deep tree selection scrolls the selected file body into the CodeView viewport', async () => {
		const fixture = makeBridgeViewerBrowserFixture({ fixtureClass: 'large-diffshub' });
		const backend = installBridgeViewerMockedBackend(fixture);
		const workerFactory = createBridgePierrePortableBlobWorkerFactory();
		const deepPath = 'Sources/AgentStudio/source/module-24/file-292.ts';
		const deepExpectedText = "export const fillerbrowser-filler-large-diffshub-292 = 'head';";

		try {
			browserSupport.renderBridgeViewerAppWithMockedBackend({
				backend,
				codeViewWorkerFactory: workerFactory.workerFactory,
				codeViewWorkerPoolEnabled: true,
			});
			await backend.pushMetadata(
				reviewPackageForBridgeAppDevFixtureScenario({
					fixture,
					scenario: 'scroll',
				}),
			);
			await browserSupport.waitForSelectedBridgeViewerDisplayPath(fixture.expected.largePath);
			await browserSupport.waitForSelectedBridgeViewerContentState('ready');
			await browserSupport.waitForBridgeViewerTextWithDiagnostics(fixture.expected.largeText);

			const codeScroll = await waitForBridgeViewerCodeScrollOwner();
			const scrollTopBeforeClick = codeScroll.scrollTop;
			const selectedItemId = browserSupport.bridgeReviewFixtureItemIdForPath(fixture, deepPath);

			const motionSamples = await browserSupport.sampleBridgeCodeViewScrollMotion({
				frameCount: 24,
				scrollOwner: codeScroll,
				action: (): void => {
					window.dispatchEvent(
						new CustomEvent('__bridge_review_control', {
							detail: {
								method: 'bridge.fileTree.revealPath',
								path: deepPath,
							},
						}),
					);
				},
			});
			await browserSupport.waitForSelectedBridgeViewerDisplayPath(deepPath);
			await browserSupport.waitForSelectedBridgeViewerContentState('ready');
			await browserSupport.waitForBridgeViewerTextWithDiagnostics(deepExpectedText);
			expect(
				backend.requestedUrls.some((url: string): boolean =>
					url.includes(`${selectedItemId}-head`),
				),
			).toBe(true);
			await browserSupport.waitForBridgeViewerVisibleCodeTextWithDiagnostics(
				codeScroll,
				deepExpectedText,
			);
			const selectedHeaderButton =
				await browserSupport.waitForBridgeCodeHeaderCollapseButtonForItem(selectedItemId);
			const selectedHeaderOffset =
				await browserSupport.waitForBridgeCodeHeaderOffsetFromScrollOwner({
					collapseButton: selectedHeaderButton,
					maxOffset: 8,
					scrollOwner: codeScroll,
				});
			await browserSupport.waitForStableBridgeViewerVisibleCodeTextWithDiagnostics(
				codeScroll,
				deepExpectedText,
			);

			expect(bridgeViewerVisibleCodeTextContent(codeScroll)).toContain(deepExpectedText);
			expect(selectedHeaderOffset).toBeGreaterThanOrEqual(-20);
			expect(codeScroll.scrollTop).not.toBe(scrollTopBeforeClick);
			const motionSummary = browserSupport.summarizeBridgeCodeViewScrollMotion(motionSamples);
			expect(browserSupport.isBridgeCodeViewIntentionalRevealMotionSample(motionSamples)).toBe(
				true,
			);
			expect(motionSummary.largeFrameDeltaCount).toBeLessThanOrEqual(1);
		} finally {
			await browserSupport.cleanupBridgeViewerReactTreeBeforeExternalWorkerRevoke();
			workerFactory.revoke();
			backend.dispose();
		}
	});

	test('large fixture mid-scroll hydration keeps off-screen content from shifting the visible item', async () => {
		const fixture = makeBridgeViewerBrowserFixture({ fixtureClass: 'large-diffshub' });
		const targetItemId = 'browser-hunked-diff';
		const aboveViewportItemIds = ['browser-source-b', 'browser-added-source', 'browser-docs-plan'];
		const deferredHandleIds = aboveViewportItemIds.flatMap((itemId): readonly string[] =>
			virtualizerSupport.contentHandleIdsForFixtureItem(fixture, itemId),
		);
		const targetItem = fixture.reviewPackage.itemsById[targetItemId];
		const targetPath = targetItem?.headPath ?? targetItem?.basePath;
		if (targetPath === undefined || targetPath === null) {
			throw new Error('expected large fixture mid-scroll target path.');
		}
		const backend = installBridgeViewerMockedBackend(fixture, {
			deferContentHandleIds: deferredHandleIds,
		});
		const workerFactory = createBridgePierrePortableBlobWorkerFactory();

		try {
			browserSupport.renderBridgeViewerAppWithMockedBackend({
				backend,
				codeViewWorkerFactory: workerFactory.workerFactory,
				codeViewWorkerPoolEnabled: false,
			});
			await backend.pushMetadata();
			await browserSupport.waitForBridgeViewerTextWithDiagnostics(fixture.expected.initialText);

			const codeScroll = await waitForBridgeViewerCodeScrollOwner();
			await virtualizerSupport.waitForInitialRevealSettled(codeScroll);

			// Scroll deep into the filler tail (mid-scroll), then reveal a target that sits right
			// after the deferred items (source-b/added-source/docs-plan); Pierre's overscan mounts
			// them as off-screen-above placeholders with their content genuinely requested, matching
			// the proven pattern in bridge-viewer-browser.virtualizer.browser.test.tsx's "does not
			// chase post-settle non-selected hydration above the selected file".
			codeScroll.scrollTop = Math.min(codeScroll.scrollHeight - codeScroll.clientHeight, 12_000);
			codeScroll.dispatchEvent(new Event('scroll', { bubbles: true }));
			await virtualizerSupport.waitForBridgeViewerScrollIdle(codeScroll);
			expect(codeScroll.scrollTop).toBeGreaterThan(0);

			virtualizerSupport.revealReviewTreePath(targetPath);
			await browserSupport.waitForBridgeCodeHeaderItemOffsetFromScrollOwner({
				itemId: targetItemId,
				maxOffset: 12,
				scrollOwner: codeScroll,
			});
			await browserSupport.waitForSelectedBridgeViewerContentState('ready');
			await virtualizerSupport.waitForBridgeViewerScrollIdle(codeScroll);
			await virtualizerSupport.waitForStableScrollTop(codeScroll);

			const anchorBefore = virtualizerSupport.firstFullyVisibleBridgeCodeHeader(codeScroll);
			for (const itemId of aboveViewportItemIds) {
				virtualizerSupport.resolveDeferredContentForItem({
					backend,
					itemId,
					targetHandleIds: virtualizerSupport.contentHandleIdsForFixtureItem(fixture, itemId),
				});
				// oxlint-disable-next-line no-await-in-loop -- Each hydration must settle before sampling the next one.
				await virtualizerSupport.waitForBridgeViewerScrollIdle(codeScroll);
				const anchorOffset = virtualizerSupport.bridgeCodeHeaderOffsetForItem({
					itemId: anchorBefore.itemId,
					scrollOwner: codeScroll,
				});
				expect(anchorOffset).not.toBeNull();
				expect(Math.abs((anchorOffset ?? 0) - anchorBefore.offset), itemId).toBeLessThanOrEqual(2);
			}

			expect(virtualizerSupport.firstFullyVisibleBridgeCodeHeader(codeScroll).itemId).toBe(
				anchorBefore.itemId,
			);
		} finally {
			await browserSupport.cleanupBridgeViewerReactTreeBeforeExternalWorkerRevoke();
			workerFactory.revoke();
			backend.dispose();
		}
	});
});
