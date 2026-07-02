import { afterEach, describe, expect, test } from 'vitest';
import { cleanup, render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load the app CSS.
import '../../app/bridge-app.css';
import { reviewPackageForBridgeAppDevFixtureScenario } from '../../app/bridge-app-dev-fixture.js';
import { BridgeApp } from '../../app/bridge-app.js';
import type { BridgeTelemetrySample } from '../../foundation/telemetry/bridge-telemetry-event.js';
import { createBridgePierrePortableBlobWorkerFactory } from '../workers/pierre/bridge-pierre-dev-worker-factory.js';
import {
	bridgeViewerCodeTextContent,
	bridgeViewerRenderedTextContent,
	bridgeViewerVisibleCodeTextContent,
	bridgeViewerVisibleTreeTextContent,
	collapseBridgeViewerTreeFolder,
	requireBridgeViewerHTMLElement,
	setBridgeViewerSearchText,
	waitForBridgeViewerAnimationFrame,
	waitForBridgeViewerCodeHeaderCollapseButton,
	waitForBridgeViewerCodeScrollOwner,
	waitForBridgeViewerElement,
	waitForBridgeViewerHunkExpandButton,
	waitForBridgeViewerText,
	waitForBridgeViewerTreeItemAbsent,
	waitForBridgeViewerTreeItemButton,
	waitForBridgeViewerTreeScrollOwner,
} from './bridge-viewer-browser-dom.js';
import * as browserSupport from './bridge-viewer-browser.integration.test-support.js';
import {
	disposeBridgeViewerMockedBackends,
	installBridgeViewerMockedBackend,
	makeBridgeViewerBrowserFixture,
	makeBridgeViewerContentUnavailableFixture,
} from './bridge-viewer-mocked-backend.js';
describe('Bridge viewer Browser Mode mocked backend', () => {
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

	test('mounts the real viewer from a mocked Bridge metadata push', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
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
		await waitForBridgeViewerElement('[data-testid="review-viewer-shell"]');
		await waitForBridgeViewerText(fixture.expected.initialPath);
		await waitForBridgeViewerText(fixture.expected.initialText);
		await browserSupport.waitForBridgeViewerRenderedCodeGeometry();

		expect(backend.projectionRequests).toEqual([
			expect.objectContaining({
				method: 'reviewProjection.build',
				workloadId: 'interactive',
			}),
		]);
		expect(
			backend.requestedUrls.some((url: string): boolean => url.includes('browser-source-a')),
		).toBe(true);

		backend.dispose();
	});

	test('renders Review tree content inside the resizable right rail', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
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
		await waitForBridgeViewerElement('[data-testid="review-viewer-shell"]');
		await waitForBridgeViewerElement('[data-testid="bridge-review-resizable-rail"]');
		await waitForBridgeViewerTreeItemButton(fixture.expected.initialPath);

		const railSlot = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-review-resizable-rail"]'),
		);
		const sidebar = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-review-sidebar"]'),
		);
		const railScroll = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-review-rail-scroll"]'),
		);
		const treeSlot = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-review-rail-tree-slot"]'),
		);
		const treeText = bridgeViewerVisibleTreeTextContent(railScroll);

		expect(Math.round(railSlot.getBoundingClientRect().width)).toBeGreaterThanOrEqual(240);
		expect(Math.round(railSlot.getBoundingClientRect().height)).toBeGreaterThan(300);
		expect(Math.round(sidebar.getBoundingClientRect().height)).toBeGreaterThan(300);
		expect(Math.round(railScroll.getBoundingClientRect().height)).toBeGreaterThan(250);
		expect(Math.round(treeSlot.getBoundingClientRect().height)).toBeGreaterThan(250);
		expect(treeText).toContain('Alpha');

		backend.dispose();
	});

	test('emits review startup timing telemetry from mocked metadata push to selected content ready', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
		const backend = installBridgeViewerMockedBackend(fixture, {
			telemetryConfig: {
				enabledScopes: ['web'],
				maxSamplesPerBatch: 64,
				maxEncodedBatchBytes: 262_144,
				minimumFlushIntervalMilliseconds: 0,
				rpcMethodName: 'system.bridgeTelemetry',
				scenario: 'mocked_review_startup_timing_v1',
			},
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
		await waitForBridgeViewerElement('[data-testid="review-viewer-shell"]');
		await browserSupport.waitForSelectedBridgeViewerContentState('ready');
		await browserSupport.waitForBridgeViewerTextWithDiagnostics(fixture.expected.initialText);
		await browserSupport.waitForBridgeViewerRenderedCodeGeometry();

		const samples = await browserSupport.waitForBridgeTelemetrySamples(backend, [
			'performance.bridge.web.intake_frame',
			'performance.bridge.web.review_metadata_apply',
			'performance.bridge.web.projection_input_build',
			'performance.bridge.web.projection_store_apply',
			'performance.bridge.web.projection_total',
			'performance.bridge.web.selected_content_ready',
			'performance.bridge.web.review_ready',
		]);

		expect(browserSupport.sampleNames(samples)).toEqual(
			expect.arrayContaining([
				'performance.bridge.web.intake_frame',
				'performance.bridge.web.review_metadata_apply',
				'performance.bridge.web.projection_input_build',
				'performance.bridge.web.projection_store_apply',
				'performance.bridge.web.projection_total',
				'performance.bridge.web.selected_content_ready',
				'performance.bridge.web.review_ready',
			]),
		);
		expect(
			samples.find(
				(sample: BridgeTelemetrySample): boolean =>
					sample.name === 'performance.bridge.web.review_metadata_apply',
			),
		).toEqual(
			expect.objectContaining({
				durationMilliseconds: expect.any(Number),
				stringAttributes: expect.objectContaining({
					'agentstudio.bridge.phase': 'review_metadata_apply',
					'agentstudio.bridge.priority': 'hot',
					'agentstudio.bridge.slice': 'review_metadata',
					'agentstudio.bridge.transport': 'intake',
				}),
				numericAttributes: expect.objectContaining({
					'agentstudio.bridge.review.item_count': expect.any(Number),
				}),
			}),
		);
		expect(
			samples.find(
				(sample: BridgeTelemetrySample): boolean =>
					sample.name === 'performance.bridge.web.selected_content_ready',
			),
		).toEqual(
			expect.objectContaining({
				durationMilliseconds: expect.any(Number),
				stringAttributes: expect.objectContaining({
					'agentstudio.bridge.phase': 'selected_content_ready',
					'agentstudio.bridge.transport': 'content',
				}),
			}),
		);

		backend.dispose();
	});

	test(
		'default packaged Pierre worker path hydrates the initial selected content after worker readiness',
		{
			timeout: 12_000,
		},
		async () => {
			const fixture = makeBridgeViewerBrowserFixture();
			const backend = installBridgeViewerMockedBackend(fixture);
			const uninstallPackagedWorkerFetchMock =
				browserSupport.installPierrePackagedWorkerFetchMock();

			try {
				render(
					<BridgeApp
						codeViewWorkerPoolEnabled={true}
						fetchContent={backend.fetchContent}
						markdownWorkerClient={null}
						projectionWorkerClient={backend.projectionWorkerClient}
					/>,
				);
				await backend.pushMetadata();
				await waitForBridgeViewerElement('[data-testid="review-viewer-shell"]');
				await waitForBridgeViewerText(fixture.expected.initialText);
				await browserSupport.waitForBridgeViewerRenderedCodeGeometry();

				expect(
					document.querySelector('[data-testid="bridge-pierre-worker-pool-failed"]'),
				).toBeNull();
				await browserSupport.waitForBridgeViewerSelectorAbsent(
					'[data-testid="bridge-pierre-worker-pool-loading"]',
				);
				expect(
					backend.requestedUrls.some((url: string): boolean => url.includes('browser-source-a')),
				).toBe(true);
			} finally {
				uninstallPackagedWorkerFetchMock();
				backend.dispose();
			}
		},
	);

	test('clicking a tree row fetches and renders the newly selected file', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
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

		const secondButton = await waitForBridgeViewerTreeItemButton(fixture.expected.secondPath);
		secondButton.click();
		await waitForBridgeViewerText(fixture.expected.secondText);
		await waitForBridgeViewerAnimationFrame();

		expect(
			backend.requestedUrls.some((url: string): boolean => url.includes('browser-source-b-head')),
		).toBe(true);
		expect(
			backend.commandDetails.some((detail: unknown): boolean =>
				browserSupport.isBridgeCommandForItem(detail, 'review.markFileViewed', 'browser-source-b'),
			),
		).toBe(true);

		backend.dispose();
	});

	test('starts clicked Review foreground content demand before selected path commit', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
		const backend = installBridgeViewerMockedBackend(fixture, {
			deferContentHandleIds: [fixture.expected.secondHeadHandleId],
		});
		const selectedPathsAtSecondContentRequest: string[] = [];
		const fetchContent: typeof backend.fetchContent = async (input, init): Promise<Response> => {
			const url = browserSupport.bridgeViewerFetchInputUrl(input);
			if (url.includes(fixture.expected.secondHeadHandleId)) {
				selectedPathsAtSecondContentRequest.push(
					browserSupport.selectedBridgeViewerDisplayPath() ?? 'missing',
				);
			}
			return await backend.fetchContent(input, init);
		};

		render(
			<BridgeApp
				codeViewWorkerPoolEnabled={false}
				fetchContent={fetchContent}
				markdownWorkerClient={null}
				projectionWorkerClient={backend.projectionWorkerClient}
			/>,
		);
		await backend.pushMetadata();
		await waitForBridgeViewerText(fixture.expected.initialText);
		expect(browserSupport.selectedBridgeViewerDisplayPath()).toBe(fixture.expected.initialPath);

		const secondButton = await waitForBridgeViewerTreeItemButton(fixture.expected.secondPath);
		secondButton.click();
		await browserSupport.waitForPendingContentResponseCount(backend, 1);

		expect(selectedPathsAtSecondContentRequest).toEqual([fixture.expected.initialPath]);

		backend.pendingContentResponses[0]?.resolve();
		await waitForBridgeViewerText(fixture.expected.secondText);
		backend.dispose();
	});

	test('stale content responses cannot overwrite newer selected content', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
		const backend = installBridgeViewerMockedBackend(fixture, {
			deferContentHandleIds: [fixture.expected.secondHeadHandleId],
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

		const secondButton = await waitForBridgeViewerTreeItemButton(fixture.expected.secondPath);
		secondButton.click();
		await browserSupport.waitForPendingContentResponseCount(backend, 1);

		const addedButton = await waitForBridgeViewerTreeItemButton(fixture.expected.addedPath);
		addedButton.click();
		await waitForBridgeViewerText(fixture.expected.addedText);

		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();

		expect(bridgeViewerCodeTextContent()).toContain(fixture.expected.addedText);
		expect(browserSupport.selectedBridgeViewerDisplayPath()).toBe(fixture.expected.addedPath);
		expect(browserSupport.selectedBridgeViewerContentState()).toBe('ready');
		const pendingStaleResponse = backend.pendingContentResponses[0] ?? null;
		if (pendingStaleResponse !== null) {
			expect(pendingStaleResponse.handleId).toBe(fixture.expected.secondHeadHandleId);
			pendingStaleResponse.resolve();
			await waitForBridgeViewerAnimationFrame();
			await waitForBridgeViewerAnimationFrame();
			expect(bridgeViewerCodeTextContent()).toContain(fixture.expected.addedText);
			expect(browserSupport.selectedBridgeViewerDisplayPath()).toBe(fixture.expected.addedPath);
			expect(browserSupport.selectedBridgeViewerContentState()).toBe('ready');
		}
		expect(
			backend.requestedUrls.some((url: string): boolean =>
				url.includes(fixture.expected.secondHeadHandleId),
			),
		).toBe(true);

		backend.dispose();
	});

	test('added files render full fetched content instead of placeholder rows', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
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

		const addedButton = await waitForBridgeViewerTreeItemButton(fixture.expected.addedPath);
		addedButton.click();
		await waitForBridgeViewerText(fixture.expected.addedText);

		expect(bridgeViewerRenderedTextContent()).toContain(fixture.expected.addedText);
		expect(
			backend.requestedUrls.some((url: string): boolean =>
				url.includes('browser-added-source-head'),
			),
		).toBe(true);

		backend.dispose();
	});

	test('visible added files hydrate without requiring file selection', async () => {
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
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();

		await waitForBridgeViewerText(fixture.expected.addedText);
		expect(bridgeViewerRenderedTextContent()).toContain(fixture.expected.addedText);
		expect(
			backend.requestedUrls.some((url: string): boolean =>
				url.includes(fixture.expected.addedHeadHandleId),
			),
		).toBe(true);

		const addedButton = await waitForBridgeViewerTreeItemButton(fixture.expected.addedPath);
		addedButton.click();
		await waitForBridgeViewerText(fixture.expected.addedText);

		expect(
			backend.requestedUrls.some((url: string): boolean =>
				url.includes(fixture.expected.addedHeadHandleId),
			),
		).toBe(true);

		backend.dispose();
	});

	test('collapsed unchanged hunk separators expand additional context', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
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

		const hunkedButton = await waitForBridgeViewerTreeItemButton(fixture.expected.hunkPath);
		hunkedButton.click();
		const expandButton = await waitForBridgeViewerHunkExpandButton();

		expect(bridgeViewerCodeTextContent()).not.toContain(fixture.expected.hunkExpandedText);

		expandButton.click();
		await waitForBridgeViewerText(fixture.expected.hunkExpandedText);

		backend.dispose();
	});

	test('CodeView file headers collapse and expand file content through Pierre items', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
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

		const selectedItemId = browserSupport.bridgeReviewFixtureItemIdForPath(
			fixture,
			fixture.expected.initialPath,
		);
		const collapseButton =
			await browserSupport.waitForBridgeCodeHeaderCollapseButtonForItem(selectedItemId);
		expect(collapseButton.getAttribute('aria-expanded')).toBe('true');
		collapseButton.click();

		await browserSupport.waitForBridgeCodeHeaderCollapseButtonForItemState({
			ariaExpanded: 'false',
			itemId: selectedItemId,
		});
		expect(bridgeViewerCodeTextContent()).not.toContain(fixture.expected.initialText);

		const collapsedButton = await browserSupport.waitForBridgeCodeHeaderCollapseButtonForItemState({
			ariaExpanded: 'false',
			itemId: selectedItemId,
		});
		collapsedButton.click();
		await waitForBridgeViewerText(fixture.expected.initialText);

		await browserSupport.waitForBridgeCodeHeaderCollapseButtonForItemState({
			ariaExpanded: 'true',
			itemId: selectedItemId,
		});

		backend.dispose();
	});

	test('CodeView file header collapse preserves mid-viewport header position', async () => {
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
		scrollOwner.scrollTop = 0;
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();
		// Wait for item hydration to stop changing the layout before capturing the baseline.
		// A preceding test can leak async hydration work that keeps growing header positions
		// after this test mounts (pre-existing; flagged to the content/harness owner). Without
		// this the baseline offset is captured mid-hydration and the test measures hydration
		// timing instead of its actual intent: collapse stability from a settled layout.
		await browserSupport.waitForStableBridgeCodeViewLayout(scrollOwner);

		const collapseButton =
			await browserSupport.waitForVisibleBridgeCodeHeaderCollapseButtonInOffsetRange({
				maxOffset: 480,
				minOffset: 120,
				scrollOwner,
			});
		const itemId = browserSupport.requireBridgeCodeHeaderCollapseButtonItemId(collapseButton);
		const beforeOffset = browserSupport.bridgeCodeHeaderOffsetFromScrollOwner({
			collapseButton,
			scrollOwner,
		});

		collapseButton.click();
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();
		const collapsedButton =
			await browserSupport.waitForBridgeCodeHeaderCollapseButtonForItemStateNearOffset({
				ariaExpanded: 'false',
				expectedOffset: beforeOffset,
				itemId,
				maxDelta: 2,
				scrollOwner,
			});

		const afterCollapseOffset = browserSupport.bridgeCodeHeaderOffsetFromScrollOwner({
			collapseButton: collapsedButton,
			scrollOwner,
		});
		expect(Math.abs(afterCollapseOffset - beforeOffset)).toBeLessThanOrEqual(2);

		collapsedButton.click();
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();
		const expandedButton =
			await browserSupport.waitForBridgeCodeHeaderCollapseButtonForItemStateNearOffset({
				ariaExpanded: 'true',
				expectedOffset: beforeOffset,
				itemId,
				maxDelta: 2,
				scrollOwner,
			});

		const afterExpandOffset = browserSupport.bridgeCodeHeaderOffsetFromScrollOwner({
			collapseButton: expandedButton,
			scrollOwner,
		});
		expect(Math.abs(afterExpandOffset - beforeOffset)).toBeLessThanOrEqual(2);

		backend.dispose();
	});

	test('review chrome controls expose pointer affordances instead of inert default cursors', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
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

		const collapseButton = await waitForBridgeViewerCodeHeaderCollapseButton();
		const treeButton = await waitForBridgeViewerTreeItemButton(fixture.expected.initialPath);
		const searchButton = requireBridgeViewerHTMLElement(
			document.querySelector('button[data-testid="bridge-review-search-toggle"]'),
		);
		const statusFilterButton = requireBridgeViewerHTMLElement(
			document.querySelector('button[data-testid="bridge-review-facet-menu-control"]'),
		);

		expect(getComputedStyle(collapseButton).cursor).toBe('pointer');
		expect(getComputedStyle(treeButton).cursor).toBe('pointer');
		expect(getComputedStyle(searchButton).cursor).toBe('pointer');
		expect(getComputedStyle(statusFilterButton).cursor).toBe('pointer');
		expect(getComputedStyle(collapseButton).userSelect).toBe('none');
		expect(getComputedStyle(treeButton).userSelect).toBe('none');

		backend.dispose();
	});

	test('content fetch failure records the request and renders unavailable state', async () => {
		const fixture = makeBridgeViewerContentUnavailableFixture();
		const backend = installBridgeViewerMockedBackend(fixture, {
			contentFailures: [fixture.expected.secondHeadHandleId],
			latencyProfile: 'small',
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

		const secondButton = await waitForBridgeViewerTreeItemButton(fixture.expected.secondPath);
		const requestedFailureHandleCountBeforeClick = browserSupport.requestedContentUrlCount(
			backend,
			fixture.expected.secondHeadHandleId,
		);
		secondButton.click();
		await browserSupport.waitForRequestedContentUrlCountGreaterThan(
			backend,
			fixture.expected.secondHeadHandleId,
			requestedFailureHandleCountBeforeClick,
		);
		await browserSupport.waitForBridgeViewerSelectedContentState('failed');
		const unavailableElement = await waitForBridgeViewerElement(
			'[data-testid="bridge-review-content-unavailable"]',
		);
		expect(unavailableElement.textContent ?? '').toContain('Content unavailable');

		expect(
			backend.requestedUrls.some((url: string): boolean =>
				url.includes(fixture.expected.secondHeadHandleId),
			),
		).toBe(true);
		expect(
			backend.commandDetails.some((detail: unknown): boolean =>
				browserSupport.isBridgeCommandForItem(detail, 'review.markFileViewed', 'browser-source-b'),
			),
		).toBe(true);

		backend.dispose();
	});

	test('projection worker failure renders a typed projection error instead of hanging', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
		const backend = installBridgeViewerMockedBackend(fixture, {
			projectionFailure: true,
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
		await waitForBridgeViewerText('Review projection unavailable');

		expect(backend.projectionRequests).toHaveLength(1);
		expect(bridgeViewerRenderedTextContent()).not.toContain('Projecting review');

		backend.dispose();
	});

	test('CodeView and right rail keep independent scroll ownership', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
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
		await waitForBridgeViewerElement('[data-testid="review-viewer-shell"]');

		const largeButton = await waitForBridgeViewerTreeItemButton(fixture.expected.largePath);
		largeButton.click();
		await waitForBridgeViewerText(fixture.expected.largeText);
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();

		const codeScroll = await waitForBridgeViewerCodeScrollOwner();
		const railScroll = await waitForBridgeViewerTreeScrollOwner();
		const shell = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="review-viewer-shell"]'),
		);
		const documentScrollBefore = document.scrollingElement?.scrollTop ?? 0;
		const codeTextBefore = bridgeViewerVisibleCodeTextContent(codeScroll);
		const treeTextBefore = bridgeViewerVisibleTreeTextContent(railScroll);

		codeScroll.scrollTop = Math.max(1, codeScroll.scrollHeight - codeScroll.clientHeight);
		codeScroll.dispatchEvent(new Event('scroll', { bubbles: true }));
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();
		railScroll.scrollTop = Math.max(1, railScroll.scrollHeight - railScroll.clientHeight);
		railScroll.dispatchEvent(new Event('scroll', { bubbles: true }));
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();

		expect(codeScroll.scrollHeight).toBeGreaterThan(codeScroll.clientHeight);
		expect(codeScroll.scrollTop).toBeGreaterThan(0);
		expect(bridgeViewerVisibleCodeTextContent(codeScroll)).not.toBe(codeTextBefore);
		expect(railScroll.dataset['fileTreeVirtualizedScroll']).toBe('true');
		expect(railScroll.scrollTop).toBeGreaterThan(0);
		expect(bridgeViewerVisibleTreeTextContent(railScroll)).not.toBe(treeTextBefore);
		expect(shell.scrollTop).toBe(0);
		expect(document.scrollingElement?.scrollTop ?? 0).toBe(documentScrollBefore);

		backend.dispose();
	});

	test('CodeView scrollbars stay compact like the DiffsHub review surface', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
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
		await waitForBridgeViewerElement('[data-testid="review-viewer-shell"]');

		const largeButton = await waitForBridgeViewerTreeItemButton(fixture.expected.largePath);
		largeButton.click();
		await waitForBridgeViewerText(fixture.expected.largeText);
		const codeScroll = await waitForBridgeViewerCodeScrollOwner();
		const codeScrollStyle = getComputedStyle(codeScroll);

		expect(codeScrollStyle.scrollbarWidth).toBe('thin');
		expect(codeScrollStyle.scrollbarColor).toContain('rgba(205, 214, 244, 0.24)');

		backend.dispose();
	});

	test('search expands nested tree matches without losing selected CodeView content', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
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
		await collapseBridgeViewerTreeFolder('Sources/BridgeViewer');
		await waitForBridgeViewerTreeItemAbsent(fixture.expected.searchPath);

		setBridgeViewerSearchText(fixture.expected.searchText);
		const matchedButton = await waitForBridgeViewerTreeItemButton(fixture.expected.searchPath);

		expect(matchedButton.textContent ?? '').toContain(fixture.expected.searchText);
		expect(bridgeViewerRenderedTextContent()).toContain(fixture.expected.initialText);
		expect(backend.projectionRequests).toHaveLength(1);

		backend.dispose();
	});

	test('large fixture search reveals added files and renders their fetched content', async () => {
		const fixture = makeBridgeViewerBrowserFixture({ fixtureClass: 'large-diffshub' });
		const backend = installBridgeViewerMockedBackend(fixture);
		const workerFactory = createBridgePierrePortableBlobWorkerFactory();

		try {
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
			try {
				await browserSupport.waitForSelectedBridgeViewerDisplayPath(fixture.expected.largePath);
			} catch (error: unknown) {
				throw new Error(
					[
						error instanceof Error ? error.message : String(error),
						`requestedUrls=${JSON.stringify(backend.requestedUrls.slice(0, 8))}`,
					].join('\n'),
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
});
