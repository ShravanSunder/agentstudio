import { act } from 'react';
import { afterEach, describe, expect, test } from 'vitest';
import { cleanup } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load the app CSS.
import '../../app/bridge-app.css';
import type { BridgeTelemetrySample } from '../../foundation/telemetry/bridge-telemetry-event.js';
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
	makeBridgeViewerContentRevisionFixture,
	makeBridgeViewerContentUnavailableFixture,
} from './bridge-viewer-mocked-backend-retouch-fixtures.js';
import {
	disposeBridgeViewerMockedBackends,
	installBridgeViewerMockedBackend,
	makeBridgeViewerBrowserFixture,
} from './bridge-viewer-mocked-backend.js';
describe('Bridge viewer Browser Mode mocked backend', () => {
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

	test('mounts the real viewer from a mocked Bridge metadata push', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
		const backend = installBridgeViewerMockedBackend(fixture);

		browserSupport.renderBridgeViewerAppWithMockedBackend({ backend });
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

		browserSupport.renderBridgeViewerAppWithMockedBackend({ backend });
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

	test('selected CodeView file header sits flush below the viewer toolbar after tree click', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
		const backend = installBridgeViewerMockedBackend(fixture);

		browserSupport.renderBridgeViewerAppWithMockedBackend({ backend });
		await backend.pushMetadata();
		await waitForBridgeViewerElement('[data-testid="review-viewer-shell"]');
		const secondButton = await waitForBridgeViewerTreeItemButton(fixture.expected.secondPath);
		secondButton.click();
		await waitForBridgeViewerText(fixture.expected.secondText);
		await browserSupport.waitForBridgeViewerRenderedCodeGeometry();
		await waitForBridgeViewerAnimationFrame();

		const codeScroll = await waitForBridgeViewerCodeScrollOwner();
		const selectedHeader = await browserSupport.waitForBridgeCodeViewHeaderForPath(
			fixture.expected.secondPath,
		);
		const headerTopGap = Math.round(
			selectedHeader.getBoundingClientRect().top - codeScroll.getBoundingClientRect().top,
		);

		expect(headerTopGap).toBe(0);

		backend.dispose();
	});

	test('CodeView scroll owner extends to the review rail resize boundary', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
		const backend = installBridgeViewerMockedBackend(fixture);

		browserSupport.renderBridgeViewerAppWithMockedBackend({ backend });
		await backend.pushMetadata();
		await waitForBridgeViewerElement('[data-testid="review-viewer-shell"]');
		await waitForBridgeViewerText(fixture.expected.initialText);
		await browserSupport.waitForBridgeViewerRenderedCodeGeometry();

		const codeScroll = await waitForBridgeViewerCodeScrollOwner();
		const resizeHandle = requireBridgeViewerHTMLElement(
			document.querySelector('#bridge-review-rail-resize-handle'),
		);
		const horizontalGapToRail = Math.round(
			resizeHandle.getBoundingClientRect().left - codeScroll.getBoundingClientRect().right,
		);

		expect(horizontalGapToRail).toBe(0);

		backend.dispose();
	});

	test(
		'keeps descriptor-backed JSON body text visible when worker content fetch falls back',
		{
			timeout: 12_000,
		},
		async () => {
			const fixture = makeJsonInitialBridgeViewerFixture();
			const backend = installBridgeViewerMockedBackend(fixture);
			const uninstallPackagedWorkerFetchMock =
				browserSupport.installPierrePackagedWorkerFetchMock();

			try {
				browserSupport.renderBridgeViewerAppWithMockedBackend({
					backend,
					codeViewWorkerPoolEnabled: true,
				});
				await backend.pushMetadata();
				await waitForBridgeViewerElement('[data-testid="review-viewer-shell"]');
				await waitForBridgeViewerText(fixture.expected.initialPath);
				await waitForBridgeViewerText(fixture.expected.initialText);
				await browserSupport.waitForBridgeViewerRenderedCodeGeometry();

				const renderedCodeText = bridgeViewerRenderedTextContent();
				expect(renderedCodeText).toContain(fixture.expected.initialText);
				expect(renderedCodeText).not.toMatch(/^\s*$/u);
			} finally {
				uninstallPackagedWorkerFetchMock();
				backend.dispose();
			}
		},
	);

	test('hydrates explicit added file targets as full-file content rows with visible styling', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
		const backend = installBridgeViewerMockedBackend(fixture);

		browserSupport.renderBridgeViewerAppWithMockedBackend({ backend });
		await backend.pushMetadata();
		await waitForBridgeViewerElement('[data-testid="review-viewer-shell"]');
		const addedButton = await waitForBridgeViewerTreeItemButton(fixture.expected.addedPath);
		addedButton.click();
		await waitForBridgeViewerText(fixture.expected.addedText);
		await browserSupport.waitForBridgeViewerRenderedCodeGeometry();

		// Scope to the added file's own body (`renderAddedPanel`) rather than the first line in DOM
		// order, which belongs to the initial modified file's diff.
		const addedContentLine = await waitForBridgeCodeViewShadowElement({
			matchText: 'renderAddedPanel',
			selector: '[data-line][data-line-type]',
		});
		const backgroundColor = getComputedStyle(addedContentLine).backgroundColor;

		expect(addedContentLine.textContent).toContain('renderAddedPanel');
		// Pierre renders a one-sided diff's added lines as `change-addition` (its only added-line
		// type; `LineTypes` has no bare `addition`). That is the green DiffsHub addition styling,
		// backed by `--diffs-addition-base`, so it satisfies the whole-file green-rows requirement.
		expect(addedContentLine.getAttribute('data-line-type')).toBe('change-addition');
		expect(backgroundColor).not.toBe('rgba(0, 0, 0, 0)');
		expect(backgroundColor).not.toBe('transparent');
		expect(
			browserSupport.selectedBridgeViewerPanelAttribute('data-selected-materialized-item-type'),
		).toBe('diff');
		expect(
			Number(
				browserSupport.selectedBridgeViewerPanelAttribute(
					'data-selected-materialized-addition-line-count',
				) ?? '0',
			),
		).toBeGreaterThan(0);
		expect(
			browserSupport.selectedBridgeViewerPanelAttribute(
				'data-selected-materialized-model-content-state',
			),
		).toBe('hydrated');

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
				endpointUrl: 'agentstudio://telemetry/batch',
				scenario: 'mocked_review_startup_timing_v1',
			},
		});

		browserSupport.renderBridgeViewerAppWithMockedBackend({ backend });
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
				browserSupport.renderBridgeViewerAppWithMockedBackend({
					backend,
					codeViewWorkerPoolEnabled: true,
				});
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

		browserSupport.renderBridgeViewerAppWithMockedBackend({ backend });
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

	test('starts clicked Review foreground content demand after selected path commit', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
		// Deferring both selected handles keeps speculative hydration out of
		// the assertion. The request for Beta.ts must observe Beta.ts already
		// selected, proving click paint was not held behind foreground demand.
		const backend = installBridgeViewerMockedBackend(fixture, {
			deferContentHandleIds: [
				fixture.expected.initialHeadHandleId,
				fixture.expected.secondHeadHandleId,
			],
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

		browserSupport.renderBridgeViewerAppWithMockedBackend({ backend, fetchContent });
		await backend.pushMetadata();
		// The initial file's content is deferred, so its text never renders;
		// the selection itself (independent of content readiness) is the
		// signal that the initial demand has committed.
		await pollWithinAct({
			getValue: browserSupport.selectedBridgeViewerDisplayPath,
			isSatisfied: (displayPath) => displayPath === fixture.expected.initialPath,
		});
		await pollWithinAct({
			getValue: () => backend.pendingContentResponses.length,
			isSatisfied: (pendingCount) => pendingCount >= 1,
		});

		const secondButton = await waitForBridgeViewerTreeItemButton(fixture.expected.secondPath);
		await actClick(secondButton);
		await pollWithinAct({
			getValue: browserSupport.selectedBridgeViewerDisplayPath,
			isSatisfied: (displayPath) => displayPath === fixture.expected.secondPath,
		});
		// Selecting Beta.ts aborts Alpha.ts's still-in-flight foreground load,
		// which removes its pending response from the backend — so the pending
		// count dips back to 0 before Beta.ts's own request lands.
		await pollWithinAct({
			getValue: () =>
				backend.pendingContentResponses.some(
					(pendingResponse) => pendingResponse.handleId === fixture.expected.secondHeadHandleId,
				),
			isSatisfied: (didRequestSecondContent) => didRequestSecondContent,
		});

		expect(selectedPathsAtSecondContentRequest).toEqual([fixture.expected.secondPath]);
		const pendingSecondContentResponse = backend.pendingContentResponses.find(
			(pendingResponse) => pendingResponse.handleId === fixture.expected.secondHeadHandleId,
		);
		expect(pendingSecondContentResponse).toBeDefined();

		await actUpdate((): void => pendingSecondContentResponse?.resolve());
		await pollWithinAct({
			getValue: browserSupport.selectedBridgeViewerContentState,
			isSatisfied: (contentState) => contentState === 'ready',
		});
		await pollWithinAct({
			getValue: bridgeViewerRenderedTextContent,
			isSatisfied: (renderedText) => renderedText.includes(fixture.expected.secondText),
		});
		backend.dispose();
	});

	test('a bare revision bump keeps selected content while a contentHash change reloads it', async () => {
		const fixture = makeBridgeViewerContentRevisionFixture();
		const backend = installBridgeViewerMockedBackend(fixture);

		browserSupport.renderBridgeViewerAppWithMockedBackend({ backend });
		await backend.pushMetadata();
		await waitForBridgeViewerText(fixture.expected.initialText);
		expect(browserSupport.selectedBridgeViewerContentState()).toBe('ready');

		const initialHeadFetchCount = (): number =>
			backend.requestedUrls.filter((url: string): boolean =>
				url.includes(fixture.initialHeadHandleId),
			).length;
		const fetchCountBeforeChurn = initialHeadFetchCount();
		expect(fetchCountBeforeChurn).toBeGreaterThan(0);

		// Benign revision churn (extent facts, path/summary/tree updates streamed continuously in a
		// busy multi-worktree workspace) bumps the package revision without changing content. The
		// content-addressed gate must keep the loaded content and must NOT re-arm a fetch.
		await backend.pushMetadata(fixture.bareRevisionPackage);
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();
		expect(bridgeViewerCodeTextContent()).toContain(fixture.expected.initialText);
		expect(browserSupport.selectedBridgeViewerContentState()).toBe('ready');
		expect(initialHeadFetchCount()).toBe(fetchCountBeforeChurn);

		// A genuine contentHash change for the selected file must invalidate the loaded content and
		// reload the fresher body — the one case that survives content-addressing.
		await backend.pushMetadata(fixture.revisedContentPackage);
		await waitForBridgeViewerText(fixture.revisedInitialText);
		expect(bridgeViewerCodeTextContent()).toContain(fixture.revisedInitialText);
		expect(bridgeViewerCodeTextContent()).not.toContain(fixture.expected.initialText);
		expect(browserSupport.selectedBridgeViewerContentState()).toBe('ready');

		backend.dispose();
	});

	test('added files render full fetched content instead of placeholder rows', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
		const backend = installBridgeViewerMockedBackend(fixture);

		browserSupport.renderBridgeViewerAppWithMockedBackend({ backend });
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

		browserSupport.renderBridgeViewerAppWithMockedBackend({ backend });
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

		browserSupport.renderBridgeViewerAppWithMockedBackend({ backend });
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

		browserSupport.renderBridgeViewerAppWithMockedBackend({ backend });
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

		browserSupport.renderBridgeViewerAppWithMockedBackend({ backend });
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

		browserSupport.renderBridgeViewerAppWithMockedBackend({ backend });
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
		// A selected modified diff now renders whichever side loads as ready (partial content), so
		// failing only the head would leave the base readable. Fail both sides so the item has no
		// loadable content and the genuine unavailable/failed path this test proves is exercised.
		const secondBaseHandleId =
			fixture.reviewPackage.itemsById['browser-source-b']?.contentRoles.base?.handleId;
		if (secondBaseHandleId === undefined) {
			throw new Error('expected content-unavailable fixture second item base handle');
		}
		const backend = installBridgeViewerMockedBackend(fixture, {
			contentFailures: [fixture.expected.secondHeadHandleId, secondBaseHandleId],
			latencyProfile: 'small',
		});

		browserSupport.renderBridgeViewerAppWithMockedBackend({ backend });
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

		browserSupport.renderBridgeViewerAppWithMockedBackend({ backend });
		await backend.pushMetadata();
		await waitForBridgeViewerText('Review projection unavailable');

		expect(backend.projectionRequests).toHaveLength(1);
		expect(bridgeViewerRenderedTextContent()).not.toContain('Projecting review');

		backend.dispose();
	});

	test('CodeView and right rail keep independent scroll ownership', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
		const backend = installBridgeViewerMockedBackend(fixture);

		browserSupport.renderBridgeViewerAppWithMockedBackend({ backend });
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

		browserSupport.renderBridgeViewerAppWithMockedBackend({ backend });
		await backend.pushMetadata();
		await waitForBridgeViewerElement('[data-testid="review-viewer-shell"]');

		const largeButton = await waitForBridgeViewerTreeItemButton(fixture.expected.largePath);
		largeButton.click();
		await waitForBridgeViewerText(fixture.expected.largeText);
		const codeScroll = await waitForBridgeViewerCodeScrollOwner();
		const codeScrollStyle = getComputedStyle(codeScroll);
		const codeScrollbarStyle = getComputedStyle(codeScroll, '::-webkit-scrollbar');

		// The Review CodeView scroll owner uses the shared compact visible scrollbar contract:
		// a thin overlay scrollbar with no reserved gutter.
		expect(codeScrollStyle.scrollbarWidth).toBe('thin');
		expect(codeScrollStyle.scrollbarGutter).toBe('auto');
		expect(codeScrollbarStyle.width).toBe('6px');
		expect(codeScrollbarStyle.height).toBe('6px');

		backend.dispose();
	});

	test('search expands nested tree matches without losing selected CodeView content', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
		const backend = installBridgeViewerMockedBackend(fixture);

		browserSupport.renderBridgeViewerAppWithMockedBackend({ backend });
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
});

function makeJsonInitialBridgeViewerFixture(): ReturnType<typeof makeBridgeViewerBrowserFixture> {
	const fixture = makeBridgeViewerBrowserFixture();
	const initialItem = fixture.reviewPackage.itemsById['browser-source-a'];
	const baseHandle = initialItem?.contentRoles.base ?? null;
	const headHandle = initialItem?.contentRoles.head ?? null;
	if (initialItem === undefined || baseHandle === null || headHandle === null) {
		throw new Error('expected browser JSON fixture initial handles');
	}

	const baseText = '{\n\t"name": "@agentstudio/bridge-web"\n}\n';
	const headText =
		'{\n\t"name": "@agentstudio/bridge-web",\n\t"scripts": {\n\t\t"test": "vitest run"\n\t}\n}\n';
	const jsonBaseHandle = {
		...baseHandle,
		language: 'json',
		mimeType: 'application/json',
		sizeBytes: new TextEncoder().encode(baseText).byteLength,
	};
	const jsonHeadHandle = {
		...headHandle,
		language: 'json',
		mimeType: 'application/json',
		sizeBytes: new TextEncoder().encode(headText).byteLength,
	};
	const jsonItem = {
		...initialItem,
		basePath: 'BridgeWeb/package.json',
		headPath: 'BridgeWeb/package.json',
		fileClass: 'config' as const,
		language: 'json',
		extension: 'json',
		additions: 5,
		deletions: 3,
		contentRoles: {
			...initialItem.contentRoles,
			base: jsonBaseHandle,
			head: jsonHeadHandle,
		},
		contentLineCountsByRole: {
			base: lineCountForBrowserFixtureText(baseText),
			head: lineCountForBrowserFixtureText(headText),
		},
	};
	const contentByHandleId = new Map(fixture.contentByHandleId);
	contentByHandleId.set(jsonBaseHandle.handleId, baseText);
	contentByHandleId.set(jsonHeadHandle.handleId, headText);

	return {
		...fixture,
		contentByHandleId,
		reviewPackage: {
			...fixture.reviewPackage,
			itemsById: {
				...fixture.reviewPackage.itemsById,
				[jsonItem.itemId]: jsonItem,
			},
		},
		expected: {
			...fixture.expected,
			initialPath: 'BridgeWeb/package.json',
			initialText: '"test": "vitest run"',
		},
	};
}

async function waitForBridgeCodeViewShadowElement(props: {
	readonly selector: string;
	readonly matchText?: string | undefined;
	readonly remainingAttempts?: number;
}): Promise<HTMLElement> {
	const remainingAttempts = props.remainingAttempts ?? 180;
	const match = findBridgeCodeViewShadowElement({
		matchText: props.matchText,
		selector: props.selector,
	});
	if (match !== null) {
		return match;
	}
	if (remainingAttempts <= 0) {
		throw new Error(
			`expected Bridge CodeView shadow element ${props.selector}${
				props.matchText === undefined ? '' : ` containing ${props.matchText}`
			}`,
		);
	}
	await waitForBridgeViewerAnimationFrame();
	return await waitForBridgeCodeViewShadowElement({
		matchText: props.matchText,
		remainingAttempts: remainingAttempts - 1,
		selector: props.selector,
	});
}

function findBridgeCodeViewShadowElement(props: {
	readonly selector: string;
	readonly matchText?: string | undefined;
}): HTMLElement | null {
	for (const container of document.querySelectorAll('diffs-container')) {
		for (const match of container.shadowRoot?.querySelectorAll(props.selector) ?? []) {
			if (!(match instanceof HTMLElement)) {
				continue;
			}
			if (props.matchText === undefined || (match.textContent ?? '').includes(props.matchText)) {
				return match;
			}
		}
	}
	return null;
}

function lineCountForBrowserFixtureText(text: string): number {
	return text.length === 0 ? 0 : text.split('\n').length;
}

async function actClick(element: { readonly click: () => void }): Promise<void> {
	await act(async (): Promise<void> => {
		element.click();
		await Promise.resolve();
	});
}

async function actUpdate(update: () => void): Promise<void> {
	await act(async (): Promise<void> => {
		update();
		await Promise.resolve();
	});
}

async function pollWithinAct<TValue>(props: {
	readonly getValue: () => TValue;
	readonly isSatisfied: (value: TValue) => boolean;
	readonly pollIntervalMilliseconds?: number;
	readonly timeoutMilliseconds?: number;
}): Promise<TValue> {
	const timeoutMilliseconds = props.timeoutMilliseconds ?? 5000;
	const pollIntervalMilliseconds = props.pollIntervalMilliseconds ?? 20;
	const deadlineMilliseconds = Date.now() + timeoutMilliseconds;
	for (;;) {
		const value = props.getValue();
		if (props.isSatisfied(value) || Date.now() >= deadlineMilliseconds) {
			return value;
		}
		// oxlint-disable-next-line no-await-in-loop -- Browser React updates must settle between real-timer poll ticks.
		await act(async (): Promise<void> => {
			await new Promise<void>((resolve): void => {
				setTimeout(resolve, pollIntervalMilliseconds);
			});
		});
	}
}
