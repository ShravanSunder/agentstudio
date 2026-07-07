import { afterEach, describe, expect, test } from 'vitest';
import { cleanup, render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load the app CSS.
import '../../app/bridge-app.css';
import { reviewPackageForBridgeAppDevFixtureScenario } from '../../app/bridge-app-dev-fixture.js';
import { BridgeApp } from '../../app/bridge-app.js';
import { createBridgePierrePortableBlobWorkerFactory } from '../workers/pierre/bridge-pierre-dev-worker-factory.js';
import {
	waitForBridgeViewerAnimationFrame,
	waitForBridgeViewerTreeScrollOwner,
} from './bridge-viewer-browser-dom.js';
import * as browserSupport from './bridge-viewer-browser.integration.test-support.js';
import {
	disposeBridgeViewerMockedBackends,
	installBridgeViewerMockedBackend,
	makeBridgeViewerBrowserFixture,
} from './bridge-viewer-mocked-backend.js';

declare global {
	interface Window {
		__bridgeReviewSliceInvalidationProbe?: {
			clicks: {
				readonly invalidatedKeyCount: number;
				readonly packageItemCount: number;
				readonly selectedItemCount: number;
				readonly subscriberNotificationCount: number;
				readonly visibleDeltaCount: number;
			}[];
		};
	}
}

describe('Bridge viewer review render slices', () => {
	afterEach(async () => {
		cleanup();
		await Promise.resolve();
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();
		disposeBridgeViewerMockedBackends();
		document.body.replaceChildren();
		document.documentElement.removeAttribute('data-bridge-review-pane-id');
		document.documentElement.removeAttribute('data-bridge-review-stream-id');
		// oxlint-disable-next-line no-underscore-dangle -- Intentional Bridge debug surface name.
		delete window.__bridgeReviewSliceInvalidationProbe;
	});

	test('large package click reports bounded subscriber and invalidated key counts', async () => {
		const fixture = makeBridgeViewerBrowserFixture({ fixtureClass: 'large-diffshub' });
		const backend = installBridgeViewerMockedBackend(fixture);
		const workerFactory = createBridgePierrePortableBlobWorkerFactory();

		try {
			// oxlint-disable-next-line no-underscore-dangle -- Intentional Bridge debug surface name.
			window.__bridgeReviewSliceInvalidationProbe = {
				clicks: [],
			};
			render(
				<BridgeApp
					codeViewWorkerPoolEnabled={true}
					codeViewWorkerFactory={workerFactory.workerFactory}
					fetchContent={backend.fetchContent}
					markdownWorkerClient={null}
					projectionWorkerClient={backend.projectionWorkerClient}
				/>,
			);
			await backend.pushMetadata(
				reviewPackageForBridgeAppDevFixtureScenario({
					fixture,
					scenario: 'scroll',
				}),
			);
			await browserSupport.waitForSelectedBridgeViewerDisplayPath(fixture.expected.largePath);
			await browserSupport.waitForSelectedBridgeViewerContentState('ready');
			await browserSupport.waitForBridgeViewerTextWithDiagnostics(fixture.expected.largeText);

			const railScroll = await waitForBridgeViewerTreeScrollOwner();
			const scrolledButton = await browserSupport.waitForScrolledBridgeViewerFileTreeItemButton({
				scrollOwner: railScroll,
			});
			const scrolledPath = scrolledButton.dataset['itemPath'];
			if (scrolledPath === undefined) {
				throw new Error('expected scrolled Bridge viewer tree file button path');
			}

			scrolledButton.click();
			await browserSupport.waitForSelectedBridgeViewerDisplayPath(scrolledPath);
			await browserSupport.waitForSelectedBridgeViewerContentState('ready');
			// oxlint-disable-next-line no-underscore-dangle -- Intentional Bridge debug surface name.
			const [clickProbe] = window.__bridgeReviewSliceInvalidationProbe.clicks;
			if (clickProbe === undefined) {
				throw new Error('expected Bridge review slice invalidation click probe');
			}

			expect(clickProbe).toMatchObject({
				packageItemCount: fixture.reviewPackage.orderedItemIds.length,
				selectedItemCount: 1,
			});
			expect(clickProbe.invalidatedKeyCount).toBeLessThanOrEqual(
				clickProbe.selectedItemCount + clickProbe.visibleDeltaCount,
			);
			expect(clickProbe.subscriberNotificationCount).toBeLessThanOrEqual(
				clickProbe.selectedItemCount + clickProbe.visibleDeltaCount,
			);
		} finally {
			await browserSupport.cleanupBridgeViewerReactTreeBeforeExternalWorkerRevoke();
			workerFactory.revoke();
			backend.dispose();
		}
	});
});
