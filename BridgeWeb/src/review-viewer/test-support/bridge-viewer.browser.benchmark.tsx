import pierrePortableWorkerSource from '@pierre/diffs/worker/worker-portable.js?raw';
import { afterEach, expect, test } from 'vitest';
import { cleanup, render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load the app CSS.
import '../../app/bridge-app.css';
import type { BridgeAppControlProbe } from '../../app/bridge-app-control.js';
import { BridgeApp } from '../../app/bridge-app.js';
import type { BridgeMarkdownRenderWorkerClient } from '../workers/markdown/bridge-markdown-render-worker-client.js';
import {
	bridgeViewerVisibleCodeTextContent,
	bridgeViewerVisibleTreeItemPaths,
	bridgeViewerVisibleTreeTextContent,
	clickBridgeViewerFilterMenuOption,
	clickBridgeViewerProjectionMenuOption,
	collapseBridgeViewerTreeFolder,
	expandBridgeViewerTreeFolder,
	requireBridgeViewerHTMLElement,
	setBridgeViewerSearchText,
	waitForBridgeViewerAnimationFrame,
	waitForBridgeViewerAppliedProjectionMode,
	waitForBridgeViewerCodeScrollOwner,
	waitForBridgeViewerElement,
	waitForBridgeViewerHunkExpandButton,
	waitForBridgeViewerText,
	waitForBridgeViewerTreeItemAbsent,
	waitForBridgeViewerTreeItemButton,
	waitForBridgeViewerVisibleTreeItemPath,
	waitForBridgeViewerVisibleTreeItemPathAbsent,
	waitForBridgeViewerTreeScrollOwner,
} from './bridge-viewer-browser-dom.js';
import {
	createDeferredMarkdownWorkerClient,
	createImmediateMarkdownWorkerClient,
	type DeferredMarkdownWorkerPendingRequest,
	markdownResponseForRequest,
} from './bridge-viewer-markdown-worker-test-client.js';
import {
	type BridgeViewerBrowserFixture,
	type BridgeViewerBrowserFixtureClass,
	type BridgeViewerMockedBackend,
	type BridgeViewerMockedBackendDeliveryMode,
	disposeBridgeViewerMockedBackends,
	installBridgeViewerMockedBackend,
	makeBridgeViewerBrowserFixture,
} from './bridge-viewer-mocked-backend.js';

interface BridgeViewerBrowserPerformanceScenario {
	readonly scenarioId: string;
	readonly metric: string;
	readonly budgetMilliseconds: number;
	readonly sampleCount: number;
	readonly latencyProfile: 'zero' | 'small' | 'slowBounded';
	readonly deliveryMode?: BridgeViewerMockedBackendDeliveryMode;
	readonly codeViewWorkerPoolEnabled?: boolean;
	readonly correctnessAssertion: string;
	readonly markdownWorkerClientMode?: 'disabled' | 'mocked';
	readonly run: () => Promise<BridgeViewerBrowserPerformanceSample>;
}

interface BridgeViewerBrowserPerformanceSample {
	readonly durationMilliseconds: number;
	readonly fixture: BridgeViewerBrowserFixture;
	readonly backend: BridgeViewerMockedBackend;
	readonly deliveryMode?: BridgeViewerMockedBackendDeliveryMode;
	readonly codeViewWorkerPoolEnabled?: boolean;
}

const browserPerformanceScenarios: readonly BridgeViewerBrowserPerformanceScenario[] = [
	{
		scenarioId: 'cold-package-push',
		metric: 'bridge.viewer.browser.cold_package_push.interactive_ms',
		budgetMilliseconds: 2_000,
		sampleCount: 6,
		latencyProfile: 'zero',
		correctnessAssertion: 'shell and initial selected content visible after package push',
		run: measureColdPackagePush,
	},
	{
		scenarioId: 'warm-tree-select',
		metric: 'bridge.viewer.browser.warm_tree_select.visible_ms',
		budgetMilliseconds: 1_200,
		sampleCount: 5,
		latencyProfile: 'zero',
		correctnessAssertion: 'selected tree row fetches and renders second CodeView content',
		run: measureWarmTreeSelect,
	},
	{
		scenarioId: 'warm-added-file',
		metric: 'bridge.viewer.browser.warm_added_file.visible_ms',
		budgetMilliseconds: 1_200,
		sampleCount: 5,
		latencyProfile: 'zero',
		correctnessAssertion: 'added file hydrates full fetched source content',
		run: measureWarmAddedFile,
	},
	{
		scenarioId: 'warm-hunk-expand',
		metric: 'bridge.viewer.browser.warm_hunk_expand.visible_ms',
		budgetMilliseconds: 1_200,
		sampleCount: 5,
		latencyProfile: 'zero',
		correctnessAssertion: 'collapsed hunk separator expands unchanged context',
		run: measureWarmHunkExpand,
	},
	{
		scenarioId: 'warm-search-expand-matches',
		metric: 'bridge.viewer.browser.warm_search.expand_matches_ms',
		budgetMilliseconds: 1_200,
		sampleCount: 5,
		latencyProfile: 'zero',
		correctnessAssertion:
			'search opens collapsed matching branch and preserves selected CodeView content',
		run: measureWarmSearchExpandMatches,
	},
	{
		scenarioId: 'warm-filter-switch',
		metric: 'bridge.viewer.browser.warm_filter_switch.visible_ms',
		budgetMilliseconds: 1_200,
		sampleCount: 5,
		latencyProfile: 'zero',
		correctnessAssertion:
			'file-class filter updates tree through projection and preserves selected CodeView content',
		run: measureWarmFilterSwitch,
	},
	{
		scenarioId: 'warm-projection-chip-switch',
		metric: 'bridge.viewer.browser.warm_projection_chip_switch.visible_ms',
		budgetMilliseconds: 1_200,
		sampleCount: 5,
		latencyProfile: 'zero',
		correctnessAssertion: 'projection chip updates visible tree through projection base request',
		run: measureWarmProjectionChipSwitch,
	},
	{
		scenarioId: 'medium-streaming-append-delta',
		metric: 'bridge.viewer.browser.medium_streaming_append_delta.visible_ms',
		budgetMilliseconds: 1_500,
		sampleCount: 4,
		latencyProfile: 'zero',
		deliveryMode: 'streaming-append',
		correctnessAssertion:
			'medium fixture delta append updates the rail through the Bridge push lane',
		run: measureMediumStreamingAppendDelta,
	},
	{
		scenarioId: 'large-cold-package-push',
		metric: 'bridge.viewer.browser.large_cold_package_push.interactive_ms',
		budgetMilliseconds: 3_000,
		sampleCount: 3,
		latencyProfile: 'zero',
		correctnessAssertion:
			'large fixture package push reaches visible content and a virtualized rail scroll surface',
		run: measureLargeColdPackagePush,
	},
	{
		scenarioId: 'large-semantic-select',
		metric: 'bridge.viewer.browser.large_semantic_select.visible_ms',
		budgetMilliseconds: 1_500,
		sampleCount: 3,
		latencyProfile: 'zero',
		codeViewWorkerPoolEnabled: true,
		correctnessAssertion:
			'semantic large-file selection updates active item marker tree row content fetch and visible CodeView file content',
		run: measureLargeSemanticSelect,
	},
	{
		scenarioId: 'worker-backed-cold-package-push',
		metric: 'bridge.viewer.browser.worker_backed_cold_package_push.interactive_ms',
		budgetMilliseconds: 4_000,
		sampleCount: 3,
		latencyProfile: 'zero',
		codeViewWorkerPoolEnabled: true,
		correctnessAssertion:
			'packaged Pierre worker pool loads and CodeView renders visible selected content',
		run: measureWorkerBackedColdPackagePush,
	},
	{
		scenarioId: 'warm-markdown-preview',
		metric: 'bridge.viewer.browser.warm_markdown_preview.visible_ms',
		budgetMilliseconds: 1_500,
		sampleCount: 4,
		latencyProfile: 'zero',
		correctnessAssertion:
			'explicit docs preview command renders sanitized markdown preview through worker client',
		markdownWorkerClientMode: 'mocked',
		run: measureWarmMarkdownPreview,
	},
	{
		scenarioId: 'failure-content-unavailable',
		metric: 'bridge.viewer.browser.failure_content_unavailable.visible_ms',
		budgetMilliseconds: 1_500,
		sampleCount: 4,
		latencyProfile: 'small',
		correctnessAssertion: 'content fetch failure renders typed unavailable state',
		run: measureContentUnavailable,
	},
	{
		scenarioId: 'stale-generation-drop',
		metric: 'bridge.viewer.browser.stale_generation_drop.visible_ms',
		budgetMilliseconds: 1_500,
		sampleCount: 4,
		latencyProfile: 'zero',
		correctnessAssertion:
			'stale markdown worker response is aborted and cannot overwrite selection',
		markdownWorkerClientMode: 'mocked',
		run: measureStaleGenerationDrop,
	},
	{
		scenarioId: 'scroll-ownership',
		metric: 'bridge.viewer.browser.warm_scroll_ownership.visible_ms',
		budgetMilliseconds: 1_500,
		sampleCount: 4,
		latencyProfile: 'zero',
		correctnessAssertion: 'CodeView and right rail scroll independently without body scroll drift',
		run: measureScrollOwnership,
	},
];

afterEach(() => {
	disposeBridgeViewerMockedBackends();
	cleanup();
	document.body.replaceChildren();
	document.documentElement.removeAttribute('data-bridge-nonce');
	delete window.bridgeReviewControlProbe;
});

test(
	'Bridge viewer browser scenarios meet interactive performance budgets',
	{
		timeout: 120_000,
	},
	async () => {
		for (const scenario of browserPerformanceScenarios) {
			const samples: BridgeViewerBrowserPerformanceSample[] = [];
			for (let iterationIndex = 0; iterationIndex < scenario.sampleCount; iterationIndex += 1) {
				// oxlint-disable-next-line no-await-in-loop -- Browser performance samples must run sequentially to avoid overlapping DOM work.
				samples.push(await scenario.run());
			}
			const durationMilliseconds = samples.map(
				(sample: BridgeViewerBrowserPerformanceSample): number => sample.durationMilliseconds,
			);
			const p50DurationMilliseconds = percentile(durationMilliseconds, 0.5);
			const p95DurationMilliseconds = percentile(durationMilliseconds, 0.95);
			const fixture = samples[0]?.fixture ?? null;
			if (fixture === null) {
				throw new Error(`missing fixture metadata for ${scenario.scenarioId}`);
			}
			const sampleBackend = samples[0]?.backend ?? null;
			if (sampleBackend === null) {
				throw new Error(`missing backend metadata for ${scenario.scenarioId}`);
			}
			const sample = samples[0];
			if (sample === undefined) {
				throw new Error(`missing performance sample for ${scenario.scenarioId}`);
			}
			const deliveryMode =
				sample.deliveryMode ?? scenario.deliveryMode ?? fixture.metadata.deliveryMode;
			const codeViewWorkerPoolEnabled =
				sample.codeViewWorkerPoolEnabled ?? scenario.codeViewWorkerPoolEnabled ?? false;
			const metricEnvelope = {
				metric: scenario.metric,
				scenarioId: scenario.scenarioId,
				fixtureId: fixture.metadata.fixtureId,
				fixtureClass: fixture.metadata.fixtureClass,
				deliveryMode,
				itemCount: fixture.metadata.itemCount,
				pathCount: fixture.metadata.pathCount,
				diffLineCount: fixture.metadata.diffLineCount,
				packageBytes: fixture.metadata.packageBytes,
				fixtureChecksum: fixture.metadata.fixtureChecksum,
				backendLatencyProfile: scenario.latencyProfile,
				workerModes: {
					codeViewWorkerPoolEnabled,
					projectionWorkerClient: 'mocked',
					markdownWorkerClient: scenario.markdownWorkerClientMode ?? 'disabled',
				},
				viewport: {
					width: window.innerWidth,
					height: window.innerHeight,
					deviceScaleFactor: window.devicePixelRatio,
				},
				runtime: {
					userAgent: navigator.userAgent,
					language: navigator.language,
				},
				correctnessAssertion: scenario.correctnessAssertion,
				sampleCount: scenario.sampleCount,
				samples: durationMilliseconds,
				p50DurationMilliseconds,
				p95DurationMilliseconds,
				budgetMilliseconds: scenario.budgetMilliseconds,
				requests: {
					contentUrls: [...sampleBackend.requestedUrls],
					contentUrlCount: sampleBackend.requestedUrls.length,
					contentUrlsScopedToBridgeResource: sampleBackend.requestedUrls.every(
						isBridgeContentResourceUrl,
					),
					projectionRequestCount: sampleBackend.projectionRequests.length,
					commandCount: sampleBackend.commandDetails.length,
					pushRecordCount: sampleBackend.pushRecords.length,
				},
			};
			console.info(JSON.stringify(metricEnvelope));
			expect(p50DurationMilliseconds).toBeGreaterThan(0);
			expect(p95DurationMilliseconds).toBeLessThan(scenario.budgetMilliseconds);
		}
	},
);

async function measureColdPackagePush(): Promise<BridgeViewerBrowserPerformanceSample> {
	const fixture = makeBridgeViewerBrowserFixture({ largeItemPlacement: 'after-fillers' });
	const backend = installBridgeViewerMockedBackend(fixture);
	const startedAt = performance.now();

	render(
		<BridgeApp
			codeViewWorkerPoolEnabled={false}
			fetchContent={backend.fetchContent}
			markdownWorkerClient={null}
			projectionWorkerClient={backend.projectionWorkerClient}
		/>,
	);
	await backend.pushPackage();
	await waitForBridgeViewerElement('[data-testid="review-viewer-shell"]');
	await waitForBridgeViewerCodePanelSelection({
		itemId: 'browser-source-a',
		displayPath: fixture.expected.initialPath,
	});
	await waitForBridgeViewerVisibleCodeText(fixture.expected.initialText);

	const durationMilliseconds = performance.now() - startedAt;
	expect(durationMilliseconds).toBeGreaterThan(0);
	expect(backend.projectionRequests).toEqual([
		expect.objectContaining({
			method: 'reviewProjection.build',
			workloadId: 'interactive',
		}),
	]);
	expect(
		backend.requestedUrls.some((url: string): boolean => url.includes('browser-source-a')),
	).toBe(true);

	return finishPerformanceSample({ durationMilliseconds, fixture, backend });
}

async function measureWarmTreeSelect(): Promise<BridgeViewerBrowserPerformanceSample> {
	const { backend, fixture } = await mountInteractiveFixture();
	const secondButton = await waitForBridgeViewerTreeItemButton(fixture.expected.secondPath);
	const beforeAction = snapshotBackendLedgerCounts(backend);
	const startedAt = performance.now();
	secondButton.click();
	await waitForBridgeViewerCodePanelSelection({
		itemId: 'browser-source-b',
		displayPath: fixture.expected.secondPath,
	});
	await waitForBridgeViewerVisibleCodeText(fixture.expected.secondText);
	const durationMilliseconds = performance.now() - startedAt;
	expect(
		backend.requestedUrls.some((url: string): boolean =>
			url.includes(fixture.expected.secondHeadHandleId),
		),
	).toBe(true);
	expect(
		backend.commandDetails.some((detail: unknown): boolean =>
			isBridgeCommandForItem(detail, 'review.markFileViewed', 'browser-source-b'),
		),
	).toBe(true);
	expectBackendCommandLedgerDelta(backend, beforeAction, 'browser-source-b');
	return finishPerformanceSample({ durationMilliseconds, fixture, backend });
}

async function measureWarmAddedFile(): Promise<BridgeViewerBrowserPerformanceSample> {
	const { backend, fixture } = await mountInteractiveFixture();
	const addedButton = await waitForBridgeViewerTreeItemButton(fixture.expected.addedPath);
	const beforeAction = snapshotBackendLedgerCounts(backend);
	const startedAt = performance.now();
	addedButton.click();
	await waitForBridgeViewerCodePanelSelection({
		itemId: 'browser-added-source',
		displayPath: fixture.expected.addedPath,
	});
	await waitForBridgeViewerVisibleCodeText(fixture.expected.addedText);
	const durationMilliseconds = performance.now() - startedAt;
	expect(
		backend.requestedUrls.some((url: string): boolean =>
			url.includes(fixture.expected.addedHeadHandleId),
		),
	).toBe(true);
	expectBackendCommandLedgerDelta(backend, beforeAction, 'browser-added-source');
	return finishPerformanceSample({ durationMilliseconds, fixture, backend });
}

async function measureWarmHunkExpand(): Promise<BridgeViewerBrowserPerformanceSample> {
	const { backend, fixture } = await mountInteractiveFixture();
	const hunkedButton = await waitForBridgeViewerTreeItemButton(fixture.expected.hunkPath);
	hunkedButton.click();
	const expandButton = await waitForBridgeViewerHunkExpandButton();
	const startedAt = performance.now();
	expandButton.click();
	await waitForBridgeViewerText(fixture.expected.hunkExpandedText);
	const durationMilliseconds = performance.now() - startedAt;
	return finishPerformanceSample({ durationMilliseconds, fixture, backend });
}

async function measureWarmSearchExpandMatches(): Promise<BridgeViewerBrowserPerformanceSample> {
	const { backend, fixture } = await mountInteractiveFixture();
	await collapseBridgeViewerTreeFolder('Sources/BridgeViewer');
	await waitForBridgeViewerTreeItemAbsent(fixture.expected.searchPath);
	const startedAt = performance.now();
	setBridgeViewerSearchText(fixture.expected.searchText);
	const matchedButton = await waitForBridgeViewerTreeItemButton(fixture.expected.searchPath);
	const durationMilliseconds = performance.now() - startedAt;
	expect(matchedButton.dataset['itemPath']).toBe(fixture.expected.searchPath);
	expect(document.body.textContent ?? '').not.toContain('Content unavailable');
	await waitForBridgeViewerText(fixture.expected.initialText);
	expect(backend.projectionRequests).toHaveLength(1);
	return finishPerformanceSample({ durationMilliseconds, fixture, backend });
}

async function measureWarmFilterSwitch(): Promise<BridgeViewerBrowserPerformanceSample> {
	const { backend, fixture } = await mountInteractiveFixture();
	const startedAt = performance.now();
	await clickBridgeViewerFilterMenuOption('bridge-review-file-class-menu-control', 'Test');
	const railScroll = await waitForBridgeViewerTreeScrollOwner();
	await waitForBridgeViewerVisibleTreeItemPathAbsent(railScroll, fixture.expected.initialPath);
	await waitForBridgeViewerVisibleTreeItemPath(railScroll, fixture.expected.testFilterPath);
	const testFileButton = await waitForBridgeViewerTreeItemButton(fixture.expected.testFilterPath);
	const visibleTreePaths = bridgeViewerVisibleTreeItemPaths(railScroll);
	expect(testFileButton.dataset['itemPath']).toBe(fixture.expected.testFilterPath);
	expect(visibleTreePaths).toContain(fixture.expected.testFilterPath);
	expect(visibleTreePaths).not.toContain(fixture.expected.initialPath);
	const durationMilliseconds = performance.now() - startedAt;
	expect(document.body.textContent ?? '').not.toContain('Content unavailable');
	await waitForBridgeViewerText(fixture.expected.testFilterText);
	expect(backend.projectionRequests.at(-1)?.projectionRequest.facets).toContainEqual({
		kind: 'fileClass',
		fileClasses: ['test'],
	});
	return finishPerformanceSample({ durationMilliseconds, fixture, backend });
}

async function measureWarmProjectionChipSwitch(): Promise<BridgeViewerBrowserPerformanceSample> {
	const { backend, fixture } = await mountInteractiveFixture();
	const startedAt = performance.now();
	await clickBridgeViewerProjectionMenuOption('Plans/specs');
	const docsButton = await waitForBridgeViewerTreeItemButton(fixture.expected.docsPath);
	expect(docsButton.dataset['itemPath']).toBe(fixture.expected.docsPath);
	expect(backend.projectionRequests.at(-1)?.projectionRequest.mode).toEqual({
		kind: 'plansAndSpecs',
	});
	await waitForBridgeViewerAppliedProjectionMode('plansAndSpecs');
	const railScroll = await waitForBridgeViewerTreeScrollOwner();
	const visibleTreePaths = bridgeViewerVisibleTreeItemPaths(railScroll);
	const durationMilliseconds = performance.now() - startedAt;
	expect(visibleTreePaths).toContain(fixture.expected.docsPath);
	expect(visibleTreePaths).not.toContain(fixture.expected.initialPath);
	return finishPerformanceSample({ durationMilliseconds, fixture, backend });
}

async function measureMediumStreamingAppendDelta(): Promise<BridgeViewerBrowserPerformanceSample> {
	const { backend, fixture } = await mountInteractiveFixture({
		fixtureClass: 'medium-agentstudio',
	});
	const startedAt = performance.now();
	await backend.pushDelta();
	await expandBridgeViewerTreeFolder('streaming/append');
	const appendedButton = await waitForBridgeViewerTreeItemButton(fixture.expected.appendedPath);
	await waitForBridgeViewerText(fixture.expected.initialText);
	const durationMilliseconds = performance.now() - startedAt;
	expect(appendedButton.dataset['itemPath']).toBe(fixture.expected.appendedPath);
	expect(backend.projectionRequests.at(-1)?.revision).toBe(fixture.streamingAppendDelta.revision);
	expect(backend.pushRecords).toContainEqual({
		op: 'merge',
		revision: fixture.streamingAppendDelta.revision,
		reviewGeneration: fixture.streamingAppendDelta.reviewGeneration,
		payloadKind: 'delta',
	});
	return finishPerformanceSample({
		durationMilliseconds,
		fixture,
		backend,
		deliveryMode: 'streaming-append',
	});
}

async function measureLargeColdPackagePush(): Promise<BridgeViewerBrowserPerformanceSample> {
	const fixture = makeBridgeViewerBrowserFixture({ fixtureClass: 'large-diffshub' });
	const backend = installBridgeViewerMockedBackend(fixture);
	const startedAt = performance.now();
	renderBridgeApp({ backend });
	await backend.pushPackage();
	await waitForBridgeViewerElement('[data-testid="review-viewer-shell"]');
	await waitForBridgeViewerText(fixture.expected.initialText);
	const railScroll = await waitForBridgeViewerTreeScrollOwner();
	const durationMilliseconds = performance.now() - startedAt;
	expect(railScroll.scrollHeight).toBeGreaterThan(railScroll.clientHeight);
	expect(fixture.metadata.fixtureClass).toBe('large-diffshub');
	expect(backend.pushRecords).toContainEqual({
		op: 'replace',
		revision: fixture.reviewPackage.revision,
		reviewGeneration: fixture.reviewPackage.reviewGeneration,
		payloadKind: 'package',
	});
	return finishPerformanceSample({ durationMilliseconds, fixture, backend });
}

async function measureLargeSemanticSelect(): Promise<BridgeViewerBrowserPerformanceSample> {
	const uninstallPackagedWorkerFetchMock = installPierrePackagedWorkerFetchMock();
	try {
		const { backend, fixture } = await mountInteractiveFixture({
			fixtureClass: 'large-diffshub',
			codeViewWorkerPoolEnabled: true,
		});
		const beforeAction = snapshotBackendLedgerCounts(backend);
		const startedAt = performance.now();
		window.dispatchEvent(
			new CustomEvent('__bridge_select_review_item', {
				detail: { itemId: 'browser-large-diff' },
			}),
		);
		await waitForBridgeViewerCodePanelSelection({
			itemId: 'browser-large-diff',
			displayPath: fixture.expected.largePath,
		});
		await waitForBridgeViewerVisibleCodeText(fixture.expected.largeText);
		const largeButton = await waitForBridgeViewerTreeItemButton(fixture.expected.largePath);
		const durationMilliseconds = performance.now() - startedAt;
		expect(largeButton.getAttribute('aria-selected')).toBe('true');
		expect(
			backend.requestedUrls.some((url: string): boolean =>
				url.includes(fixture.expected.largeHeadHandleId),
			),
		).toBe(true);
		expectBackendCommandLedgerDelta(backend, beforeAction, 'browser-large-diff');
		expect(document.querySelector('[data-testid="bridge-pierre-worker-pool-failed"]')).toBeNull();
		return finishPerformanceSample({
			durationMilliseconds,
			fixture,
			backend,
			codeViewWorkerPoolEnabled: true,
		});
	} finally {
		uninstallPackagedWorkerFetchMock();
	}
}

async function measureWorkerBackedColdPackagePush(): Promise<BridgeViewerBrowserPerformanceSample> {
	const fixture = makeBridgeViewerBrowserFixture();
	const backend = installBridgeViewerMockedBackend(fixture);
	const uninstallPackagedWorkerFetchMock = installPierrePackagedWorkerFetchMock();
	const startedAt = performance.now();
	try {
		renderBridgeApp({
			backend,
			codeViewWorkerPoolEnabled: true,
		});
		await backend.pushPackage();
		await waitForBridgeViewerElement('[data-testid="review-viewer-shell"]');
		await waitForBridgeViewerText(fixture.expected.initialText);
		const durationMilliseconds = performance.now() - startedAt;
		expect(document.querySelector('[data-testid="bridge-pierre-worker-pool-failed"]')).toBeNull();
		expect(document.querySelector('[data-testid="bridge-pierre-worker-pool-loading"]')).toBeNull();
		expect(backend.pushRecords).toContainEqual({
			op: 'replace',
			revision: fixture.reviewPackage.revision,
			reviewGeneration: fixture.reviewPackage.reviewGeneration,
			payloadKind: 'package',
		});
		return finishPerformanceSample({
			durationMilliseconds,
			fixture,
			backend,
			codeViewWorkerPoolEnabled: true,
		});
	} finally {
		uninstallPackagedWorkerFetchMock();
	}
}

async function measureWarmMarkdownPreview(): Promise<BridgeViewerBrowserPerformanceSample> {
	const markdownWorker = createImmediateMarkdownWorkerClient();
	const { backend, fixture } = await mountInteractiveFixture({
		markdownWorkerClient: markdownWorker.client,
	});
	const docsButton = await waitForBridgeViewerTreeItemButton(fixture.expected.docsPath);
	docsButton.click();
	await waitForBridgeViewerText(fixture.expected.docsMarkdownHeading);
	expect(document.querySelector('[data-testid="bridge-markdown-preview"]')).toBeNull();
	expect(markdownWorker.requests).toHaveLength(0);
	const startedAt = performance.now();
	await showBridgeMarkdownPreview('browser-docs-plan');
	await waitForBridgeViewerElement('[data-testid="bridge-markdown-preview"]');
	const durationMilliseconds = performance.now() - startedAt;
	expect(markdownWorker.requests).toHaveLength(1);
	expect(markdownWorker.requests[0]?.sourcePath).toBe(fixture.expected.docsPath);
	expect(document.querySelector('[data-testid="bridge-markdown-preview"] img')).toBeNull();
	expect(document.querySelector('[data-testid="bridge-markdown-preview"] a[href]')).toBeNull();
	expect(
		document.querySelector(
			'[data-testid="bridge-markdown-preview"] form, [data-testid="bridge-markdown-preview"] input, [data-testid="bridge-markdown-preview"] button, [data-testid="bridge-markdown-preview"] details, [data-testid="bridge-markdown-preview"] dialog, [data-testid="bridge-markdown-preview"] [contenteditable]',
		),
	).toBeNull();
	return finishPerformanceSample({ durationMilliseconds, fixture, backend });
}

async function measureContentUnavailable(): Promise<BridgeViewerBrowserPerformanceSample> {
	const fixture = makeBridgeViewerBrowserFixture();
	const backend = installBridgeViewerMockedBackend(fixture, {
		contentFailures: [fixture.expected.secondHeadHandleId],
		latencyProfile: 'small',
	});
	renderBridgeApp({ backend });
	await backend.pushPackage();
	await waitForBridgeViewerText(fixture.expected.initialText);
	const secondButton = await waitForBridgeViewerTreeItemButton(fixture.expected.secondPath);
	const beforeAction = snapshotBackendLedgerCounts(backend);
	const startedAt = performance.now();
	secondButton.click();
	await waitForBridgeViewerText('Content unavailable');
	const durationMilliseconds = performance.now() - startedAt;
	expectBackendLedgerDelta(backend, beforeAction, {
		contentHandleId: fixture.expected.secondHeadHandleId,
		commandItemId: 'browser-source-b',
	});
	return finishPerformanceSample({ durationMilliseconds, fixture, backend });
}

async function measureStaleGenerationDrop(): Promise<BridgeViewerBrowserPerformanceSample> {
	const markdownWorker = createDeferredMarkdownWorkerClient({
		waitForAnimationFrame: waitForBridgeViewerAnimationFrame,
	});
	const { backend, fixture } = await mountInteractiveFixture({
		markdownWorkerClient: markdownWorker.client,
	});
	const docsButton = await waitForBridgeViewerTreeItemButton(fixture.expected.docsPath);
	docsButton.click();
	await waitForBridgeViewerText(fixture.expected.docsMarkdownHeading);
	const pendingRequest = await startBridgeMarkdownPreviewRender({
		hasPendingRequest: markdownWorker.hasPendingRequest,
		itemId: 'browser-docs-plan',
		waitForPendingRequest: markdownWorker.waitForPendingRequest,
	});
	const secondButton = await waitForBridgeViewerTreeItemButton(fixture.expected.secondPath);
	secondButton.click();
	await waitForBridgeViewerText(fixture.expected.secondText);
	const startedAt = performance.now();
	pendingRequest.resolve(markdownResponseForRequest(pendingRequest.request));
	await waitForBridgeViewerAnimationFrame();
	await waitForBridgeViewerAnimationFrame();
	const durationMilliseconds = performance.now() - startedAt;
	expect(markdownWorker.abortedRequests).toHaveLength(1);
	expect(document.querySelector('[data-testid="bridge-markdown-preview"]')).toBeNull();
	expect(
		backend.commandDetails.some((detail: unknown): boolean =>
			isBridgeCommandForItem(detail, 'review.markFileViewed', 'browser-source-b'),
		),
	).toBe(true);
	return finishPerformanceSample({ durationMilliseconds, fixture, backend });
}

async function startBridgeMarkdownPreviewRender(props: {
	readonly hasPendingRequest: () => boolean;
	readonly itemId: string;
	readonly waitForPendingRequest: () => Promise<DeferredMarkdownWorkerPendingRequest>;
}): Promise<DeferredMarkdownWorkerPendingRequest> {
	for (let attempt = 0; attempt < 20; attempt += 1) {
		if (props.hasPendingRequest()) {
			// oxlint-disable-next-line no-await-in-loop -- Preview startup is a sequential UI state machine.
			return await props.waitForPendingRequest();
		}
		const previousSequence = window.bridgeReviewControlProbe?.sequence ?? -1;
		dispatchBridgeFileViewShowMarkdownPreview(props.itemId);
		// oxlint-disable-next-line no-await-in-loop -- Each command must settle before the next preview command.
		const probe = await waitForBridgeReviewControlProbeAfter(previousSequence);
		if (props.hasPendingRequest()) {
			// oxlint-disable-next-line no-await-in-loop -- Preview startup is a sequential UI state machine.
			return await props.waitForPendingRequest();
		}
		if (
			probe.status === 'pending' &&
			(probe.reason === 'preview_selection_pending' ||
				probe.reason === 'preview_content_pending' ||
				probe.reason === 'preview_render_pending')
		) {
			// oxlint-disable-next-line no-await-in-loop -- Browser preview readiness is observed one animation frame at a time.
			await waitForBridgeViewerAnimationFrame();
			continue;
		}
		throw new Error(`unexpected markdown preview control probe ${JSON.stringify(probe)}`);
	}
	throw new Error('expected markdown preview control to start a worker render');
}

async function showBridgeMarkdownPreview(itemId: string): Promise<BridgeAppControlProbe> {
	for (let attempt = 0; attempt < 20; attempt += 1) {
		const previousSequence = window.bridgeReviewControlProbe?.sequence ?? -1;
		dispatchBridgeFileViewShowMarkdownPreview(itemId);
		// oxlint-disable-next-line no-await-in-loop -- Each command must settle before the next preview command.
		const probe = await waitForBridgeReviewControlProbeAfter(previousSequence);
		if (probe.status === 'accepted') {
			return probe;
		}
		if (
			probe.status === 'pending' &&
			(probe.reason === 'preview_selection_pending' ||
				probe.reason === 'preview_content_pending' ||
				probe.reason === 'preview_render_pending')
		) {
			// oxlint-disable-next-line no-await-in-loop -- Browser preview readiness is observed one animation frame at a time.
			await waitForBridgeViewerAnimationFrame();
			continue;
		}
		throw new Error(`unexpected markdown preview control probe ${JSON.stringify(probe)}`);
	}
	throw new Error('expected markdown preview control to become accepted');
}

function dispatchBridgeFileViewShowMarkdownPreview(itemId: string): void {
	window.dispatchEvent(
		new CustomEvent('__bridge_review_control', {
			detail: {
				method: 'bridge.fileView.showMarkdownPreview',
				itemId,
			},
		}),
	);
}

async function waitForBridgeReviewControlProbeAfter(
	previousSequence: number,
	remainingAttempts = 60,
): Promise<BridgeAppControlProbe> {
	const probe = window.bridgeReviewControlProbe;
	if (probe !== undefined && probe.sequence > previousSequence) {
		return probe;
	}
	if (remainingAttempts <= 0) {
		throw new Error('expected Bridge review control probe');
	}
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	return await waitForBridgeReviewControlProbeAfter(previousSequence, remainingAttempts - 1);
}

async function measureScrollOwnership(): Promise<BridgeViewerBrowserPerformanceSample> {
	const { backend, fixture } = await mountInteractiveFixture();
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
	const codeTextBefore = bridgeViewerVisibleCodeTextContent(codeScroll);
	const treeTextBefore = bridgeViewerVisibleTreeTextContent(railScroll);
	const startedAt = performance.now();
	codeScroll.scrollTop = Math.max(1, codeScroll.scrollHeight - codeScroll.clientHeight);
	codeScroll.dispatchEvent(new Event('scroll', { bubbles: true }));
	await waitForBridgeViewerAnimationFrame();
	await waitForBridgeViewerAnimationFrame();
	railScroll.scrollTop = Math.max(1, railScroll.scrollHeight - railScroll.clientHeight);
	railScroll.dispatchEvent(new Event('scroll', { bubbles: true }));
	await waitForBridgeViewerAnimationFrame();
	await waitForBridgeViewerAnimationFrame();
	const durationMilliseconds = performance.now() - startedAt;
	expect(bridgeViewerVisibleCodeTextContent(codeScroll)).not.toBe(codeTextBefore);
	expect(bridgeViewerVisibleTreeTextContent(railScroll)).not.toBe(treeTextBefore);
	expect(shell.scrollTop).toBe(0);
	return finishPerformanceSample({ durationMilliseconds, fixture, backend });
}

async function mountInteractiveFixture(): Promise<{
	readonly backend: BridgeViewerMockedBackend;
	readonly fixture: BridgeViewerBrowserFixture;
}>;
async function mountInteractiveFixture(props: {
	readonly fixtureClass?: BridgeViewerBrowserFixtureClass;
	readonly codeViewWorkerPoolEnabled?: boolean;
	readonly markdownWorkerClient?: BridgeMarkdownRenderWorkerClient | null;
}): Promise<{
	readonly backend: BridgeViewerMockedBackend;
	readonly fixture: BridgeViewerBrowserFixture;
}>;
async function mountInteractiveFixture(
	props: {
		readonly fixtureClass?: BridgeViewerBrowserFixtureClass;
		readonly codeViewWorkerPoolEnabled?: boolean;
		readonly markdownWorkerClient?: BridgeMarkdownRenderWorkerClient | null;
	} = {},
): Promise<{
	readonly backend: BridgeViewerMockedBackend;
	readonly fixture: BridgeViewerBrowserFixture;
}> {
	const fixture = makeBridgeViewerBrowserFixture(
		props.fixtureClass === undefined ? {} : { fixtureClass: props.fixtureClass },
	);
	const backend = installBridgeViewerMockedBackend(fixture);
	renderBridgeApp({
		backend,
		...(props.codeViewWorkerPoolEnabled === undefined
			? {}
			: { codeViewWorkerPoolEnabled: props.codeViewWorkerPoolEnabled }),
		...(props.markdownWorkerClient === undefined
			? {}
			: { markdownWorkerClient: props.markdownWorkerClient }),
	});
	await backend.pushPackage();
	await waitForBridgeViewerElement('[data-testid="review-viewer-shell"]');
	await waitForBridgeViewerText(fixture.expected.initialText);
	return { backend, fixture };
}

async function waitForBridgeViewerCodePanelSelection(
	props: {
		readonly itemId: string;
		readonly displayPath: string;
	},
	remainingAttempts = 180,
): Promise<void> {
	const panel = document.querySelector('[data-testid="bridge-code-view-panel"]');
	if (
		panel?.getAttribute('data-selected-item-id') === props.itemId &&
		panel.getAttribute('data-selected-display-path') === props.displayPath
	) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error(`expected Bridge CodeView selection ${props.itemId} at ${props.displayPath}`);
	}
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	await waitForBridgeViewerCodePanelSelection(props, remainingAttempts - 1);
}

async function waitForBridgeViewerVisibleCodeText(
	text: string,
	remainingAttempts = 180,
): Promise<void> {
	const codeScrollOwner = await waitForBridgeViewerCodeScrollOwner();
	if (bridgeViewerVisibleCodeTextContent(codeScrollOwner).includes(text)) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error(`expected visible Bridge CodeView text to contain ${text}`);
	}
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	await waitForBridgeViewerVisibleCodeText(text, remainingAttempts - 1);
}

function renderBridgeApp(props: {
	readonly backend: BridgeViewerMockedBackend;
	readonly codeViewWorkerPoolEnabled?: boolean;
	readonly markdownWorkerClient?: BridgeMarkdownRenderWorkerClient | null;
}): void {
	render(
		<BridgeApp
			codeViewWorkerPoolEnabled={props.codeViewWorkerPoolEnabled ?? false}
			fetchContent={props.backend.fetchContent}
			markdownWorkerClient={props.markdownWorkerClient ?? null}
			projectionWorkerClient={props.backend.projectionWorkerClient}
		/>,
	);
}

function finishPerformanceSample(props: {
	readonly durationMilliseconds: number;
	readonly fixture: BridgeViewerBrowserFixture;
	readonly backend: BridgeViewerMockedBackend;
	readonly deliveryMode?: BridgeViewerMockedBackendDeliveryMode;
	readonly codeViewWorkerPoolEnabled?: boolean;
}): BridgeViewerBrowserPerformanceSample {
	expect(props.durationMilliseconds).toBeGreaterThan(0);
	expect(props.backend.projectionRequests.length).toBeGreaterThan(0);
	props.backend.dispose();
	cleanup();
	document.body.replaceChildren();
	document.documentElement.removeAttribute('data-bridge-nonce');
	delete window.bridgeReviewControlProbe;
	return {
		durationMilliseconds: props.durationMilliseconds,
		fixture: props.fixture,
		backend: props.backend,
		...(props.deliveryMode === undefined ? {} : { deliveryMode: props.deliveryMode }),
		...(props.codeViewWorkerPoolEnabled === undefined
			? {}
			: { codeViewWorkerPoolEnabled: props.codeViewWorkerPoolEnabled }),
	};
}

function percentile(values: readonly number[], percentileValue: number): number {
	if (values.length === 0) {
		throw new Error('expected at least one performance sample');
	}
	const sortedValues = [...values];
	// oxlint-disable-next-line unicorn/no-array-sort -- Sorting a local copy preserves the readonly input and supports current WebKit targets.
	sortedValues.sort((left, right): number => left - right);
	const index = Math.min(
		sortedValues.length - 1,
		Math.max(0, Math.ceil(sortedValues.length * percentileValue) - 1),
	);
	const value = sortedValues[index];
	if (value === undefined) {
		throw new Error('expected percentile sample');
	}
	return value;
}

function isBridgeCommandForItem(detail: unknown, method: string, itemId: string): boolean {
	if (!isRecord(detail)) {
		return false;
	}
	const params = detail['params'];
	return detail['method'] === method && isRecord(params) && params['fileId'] === itemId;
}

interface BackendLedgerCounts {
	readonly requestedUrlCount: number;
	readonly commandCount: number;
}

function snapshotBackendLedgerCounts(backend: BridgeViewerMockedBackend): BackendLedgerCounts {
	return {
		requestedUrlCount: backend.requestedUrls.length,
		commandCount: backend.commandDetails.length,
	};
}

function expectBackendLedgerDelta(
	backend: BridgeViewerMockedBackend,
	beforeAction: BackendLedgerCounts,
	props: {
		readonly contentHandleId: string;
		readonly commandItemId: string;
	},
): void {
	const actionUrls = backend.requestedUrls.slice(beforeAction.requestedUrlCount);
	const actionCommands = backend.commandDetails.slice(beforeAction.commandCount);
	expect(actionUrls.some((url: string): boolean => url.includes(props.contentHandleId))).toBe(true);
	expect(
		actionCommands.some((detail: unknown): boolean =>
			isBridgeCommandForItem(detail, 'review.markFileViewed', props.commandItemId),
		),
	).toBe(true);
}

function expectBackendCommandLedgerDelta(
	backend: BridgeViewerMockedBackend,
	beforeAction: BackendLedgerCounts,
	commandItemId: string,
): void {
	const actionCommands = backend.commandDetails.slice(beforeAction.commandCount);
	expect(
		actionCommands.some((detail: unknown): boolean =>
			isBridgeCommandForItem(detail, 'review.markFileViewed', commandItemId),
		),
	).toBe(true);
}

function isBridgeContentResourceUrl(url: string): boolean {
	try {
		const parsedUrl = new URL(url);
		return (
			parsedUrl.protocol === 'agentstudio:' &&
			parsedUrl.hostname === 'resource' &&
			parsedUrl.pathname.startsWith('/content/')
		);
	} catch {
		return false;
	}
}

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === 'object' && value !== null;
}

function installPierrePackagedWorkerFetchMock(): () => void {
	const originalFetch = window.fetch.bind(window);
	window.fetch = async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
		const url = resourceUrlFromFetchInput(input);
		if (url === 'agentstudio://app/workers/pierre-diffs-worker-portable.js') {
			return new Response(pierrePortableWorkerSource, {
				headers: { 'content-type': 'application/javascript' },
			});
		}
		return await originalFetch(input, init);
	};
	return (): void => {
		window.fetch = originalFetch;
	};
}

function resourceUrlFromFetchInput(input: RequestInfo | URL): string {
	if (typeof input === 'string') {
		return input;
	}
	if (input instanceof URL) {
		return input.href;
	}
	return input.url;
}
