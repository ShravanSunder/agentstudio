import { describe, expect, test } from 'vitest';

import {
	extractBridgeViewerBrowserBenchmarkMetrics,
	verifyBridgeViewerBrowserBenchmarkMetrics,
	type BridgeViewerBrowserBenchmarkMetric,
} from './bridge-viewer-browser-benchmark-runner.ts';

describe('bridge viewer browser benchmark runner', () => {
	test('extracts metric envelopes from noisy Vitest Browser Mode output', () => {
		const metric = makeMetric({ scenarioId: 'cold-package-push' });
		const output = [
			'stdout | src/review-viewer/test-support/bridge-viewer.browser.benchmark.tsx',
			JSON.stringify(metric),
			'not json',
		].join('\n');

		expect(extractBridgeViewerBrowserBenchmarkMetrics(output)).toEqual([metric]);
	});

	test('rejects missing required scenarios', () => {
		expect(() =>
			verifyBridgeViewerBrowserBenchmarkMetrics([makeMetric({ scenarioId: 'cold-package-push' })]),
		).toThrow(/missing browser benchmark scenario/);
	});

	test('rejects worker-backed scenario without packaged worker mode', () => {
		expect(() =>
			verifyBridgeViewerBrowserBenchmarkMetrics(
				requiredScenarioIds.map(
					(scenarioId): BridgeViewerBrowserBenchmarkMetric =>
						makeMetric({
							scenarioId,
							codeViewWorkerPoolEnabled: false,
						}),
				),
			),
		).toThrow(/CodeView worker mode drifted from scenario contract/);
	});

	test('rejects reported p95 values that do not match raw samples', () => {
		expect(() =>
			verifyBridgeViewerBrowserBenchmarkMetrics(
				requiredScenarioIds.map(
					(scenarioId): BridgeViewerBrowserBenchmarkMetric =>
						makeMetric({
							scenarioId,
							codeViewWorkerPoolEnabled: scenarioRequiresCodeViewWorker(scenarioId),
							...(scenarioId === 'cold-package-push'
								? {
										samples: [5_000, 6_000],
										p50DurationMilliseconds: 10,
										p95DurationMilliseconds: 12,
									}
								: {}),
						}),
				),
			),
		).toThrow(/reported p50 .* does not match samples p50/);
	});

	test('rejects scenario contract drift', () => {
		expect(() =>
			verifyBridgeViewerBrowserBenchmarkMetrics(
				requiredScenarioIds.map(
					(scenarioId): BridgeViewerBrowserBenchmarkMetric =>
						makeMetric({
							scenarioId,
							codeViewWorkerPoolEnabled: scenarioRequiresCodeViewWorker(scenarioId),
							...(scenarioId === 'medium-streaming-append-delta'
								? { fixtureClass: 'small-mixed', deliveryMode: 'full-load' }
								: {}),
						}),
				),
			),
		).toThrow(/fixture class drifted from scenario contract/);
	});

	test('rejects large fixture rows below the Node PR class scale floor', () => {
		expect(() =>
			verifyBridgeViewerBrowserBenchmarkMetrics(
				requiredScenarioIds.map(
					(scenarioId): BridgeViewerBrowserBenchmarkMetric =>
						makeMetric({
							scenarioId,
							codeViewWorkerPoolEnabled: scenarioRequiresCodeViewWorker(scenarioId),
							...(scenarioId === 'large-cold-package-push' ? { itemCount: 2_000 } : {}),
						}),
				),
			),
		).toThrow(/item count .* below scenario floor/);
	});

	test('rejects content URLs outside the Bridge resource lane', () => {
		expect(() =>
			verifyBridgeViewerBrowserBenchmarkMetrics(
				requiredScenarioIds.map(
					(scenarioId): BridgeViewerBrowserBenchmarkMetric =>
						makeMetric({
							scenarioId,
							codeViewWorkerPoolEnabled: scenarioRequiresCodeViewWorker(scenarioId),
							...(scenarioId === 'warm-added-file'
								? {
										contentUrls: [
											'agentstudio://resource/content/handle-browser-added-source-head?generation=1',
											'https://example.test/not-bridge',
										],
										contentUrlsScopedToBridgeResource: false,
									}
								: {}),
						}),
				),
			),
		).toThrow(/content URLs escaped Bridge resource lane/);
	});

	test('accepts complete scenario rows with budgets and ledgers', () => {
		expect(() =>
			verifyBridgeViewerBrowserBenchmarkMetrics(
				requiredScenarioIds.map(
					(scenarioId): BridgeViewerBrowserBenchmarkMetric =>
						makeMetric({
							scenarioId,
							codeViewWorkerPoolEnabled: scenarioRequiresCodeViewWorker(scenarioId),
						}),
				),
			),
		).not.toThrow();
	});
});

const requiredScenarioIds = [
	'cold-package-push',
	'warm-tree-select',
	'warm-added-file',
	'warm-hunk-expand',
	'warm-search-expand-matches',
	'warm-filter-switch',
	'warm-projection-chip-switch',
	'medium-streaming-append-delta',
	'large-cold-package-push',
	'large-semantic-select',
	'worker-backed-cold-package-push',
	'warm-markdown-preview',
	'failure-content-unavailable',
	'stale-generation-drop',
	'scroll-ownership',
] as const;

function makeMetric(props: {
	readonly scenarioId: string;
	readonly codeViewWorkerPoolEnabled?: boolean;
	readonly fixtureClass?: BridgeViewerBrowserBenchmarkMetric['fixtureClass'];
	readonly deliveryMode?: BridgeViewerBrowserBenchmarkMetric['deliveryMode'];
	readonly contentUrls?: readonly string[];
	readonly contentUrlsScopedToBridgeResource?: boolean;
	readonly samples?: readonly number[];
	readonly p50DurationMilliseconds?: number;
	readonly p95DurationMilliseconds?: number;
	readonly itemCount?: number;
}): BridgeViewerBrowserBenchmarkMetric {
	const scenarioContract = scenarioContracts[props.scenarioId];
	if (scenarioContract === undefined) {
		throw new Error(`missing unit-test scenario contract: ${props.scenarioId}`);
	}
	const contentUrls = [
		...(props.contentUrls ??
			Array.from(
				{ length: scenarioContract.minimumContentUrlCount },
				(_value, index): string =>
					`agentstudio://resource/content/handle-browser-source-${index}-head?generation=1`,
			)),
	];
	const samples = [...(props.samples ?? [10, 12])];
	return {
		metric: scenarioContract.metric,
		scenarioId: props.scenarioId,
		fixtureId: 'browser-mode-small-mixed',
		fixtureClass: props.fixtureClass ?? scenarioContract.fixtureClass,
		deliveryMode: props.deliveryMode ?? scenarioContract.deliveryMode,
		itemCount:
			props.itemCount ?? (scenarioContract.fixtureClass === 'large-diffshub' ? 3_420 : 100),
		pathCount: 100,
		diffLineCount: 500,
		packageBytes: 20_000,
		fixtureChecksum: 'fixture:checksum',
		backendLatencyProfile: scenarioContract.backendLatencyProfile,
		workerModes: {
			codeViewWorkerPoolEnabled:
				props.codeViewWorkerPoolEnabled ?? scenarioContract.codeViewWorkerPoolEnabled,
			projectionWorkerClient: 'mocked',
			markdownWorkerClient: scenarioContract.markdownWorkerClient,
		},
		viewport: {
			width: 1_728,
			height: 972,
			deviceScaleFactor: 2,
		},
		runtime: {
			userAgent: 'Vitest Browser',
			language: 'en-US',
		},
		correctnessAssertion: 'visible behavior and mocked Bridge ledger passed',
		sampleCount: samples.length,
		samples,
		p50DurationMilliseconds: props.p50DurationMilliseconds ?? 10,
		p95DurationMilliseconds: props.p95DurationMilliseconds ?? 12,
		budgetMilliseconds: 1_000,
		requests: {
			contentUrls,
			contentUrlCount: contentUrls.length,
			contentUrlsScopedToBridgeResource: props.contentUrlsScopedToBridgeResource ?? true,
			projectionRequestCount: 1,
			commandCount: scenarioContract.minimumCommandCount,
			pushRecordCount: scenarioContract.minimumPushRecordCount,
		},
	};
}

interface UnitTestScenarioContract {
	readonly metric: string;
	readonly fixtureClass: BridgeViewerBrowserBenchmarkMetric['fixtureClass'];
	readonly deliveryMode: BridgeViewerBrowserBenchmarkMetric['deliveryMode'];
	readonly codeViewWorkerPoolEnabled: boolean;
	readonly markdownWorkerClient: BridgeViewerBrowserBenchmarkMetric['workerModes']['markdownWorkerClient'];
	readonly backendLatencyProfile: BridgeViewerBrowserBenchmarkMetric['backendLatencyProfile'];
	readonly minimumContentUrlCount: number;
	readonly minimumCommandCount: number;
	readonly minimumPushRecordCount: number;
}

const scenarioContracts: Readonly<Record<string, UnitTestScenarioContract>> = {
	'cold-package-push': makeScenarioContract({
		metric: 'bridge.viewer.browser.cold_package_push.interactive_ms',
	}),
	'warm-tree-select': makeScenarioContract({
		metric: 'bridge.viewer.browser.warm_tree_select.visible_ms',
		minimumContentUrlCount: 2,
		minimumCommandCount: 1,
	}),
	'warm-added-file': makeScenarioContract({
		metric: 'bridge.viewer.browser.warm_added_file.visible_ms',
		minimumContentUrlCount: 2,
		minimumCommandCount: 1,
	}),
	'warm-hunk-expand': makeScenarioContract({
		metric: 'bridge.viewer.browser.warm_hunk_expand.visible_ms',
		minimumContentUrlCount: 2,
		minimumCommandCount: 1,
	}),
	'warm-search-expand-matches': makeScenarioContract({
		metric: 'bridge.viewer.browser.warm_search.expand_matches_ms',
	}),
	'warm-filter-switch': makeScenarioContract({
		metric: 'bridge.viewer.browser.warm_filter_switch.visible_ms',
	}),
	'warm-projection-chip-switch': makeScenarioContract({
		metric: 'bridge.viewer.browser.warm_projection_chip_switch.visible_ms',
	}),
	'medium-streaming-append-delta': makeScenarioContract({
		metric: 'bridge.viewer.browser.medium_streaming_append_delta.visible_ms',
		fixtureClass: 'medium-agentstudio',
		deliveryMode: 'streaming-append',
		minimumPushRecordCount: 2,
	}),
	'large-cold-package-push': makeScenarioContract({
		metric: 'bridge.viewer.browser.large_cold_package_push.interactive_ms',
		fixtureClass: 'large-diffshub',
	}),
	'large-semantic-select': makeScenarioContract({
		metric: 'bridge.viewer.browser.large_semantic_select.visible_ms',
		fixtureClass: 'large-diffshub',
		codeViewWorkerPoolEnabled: true,
		minimumContentUrlCount: 2,
		minimumCommandCount: 1,
	}),
	'worker-backed-cold-package-push': makeScenarioContract({
		metric: 'bridge.viewer.browser.worker_backed_cold_package_push.interactive_ms',
		codeViewWorkerPoolEnabled: true,
	}),
	'warm-markdown-preview': makeScenarioContract({
		metric: 'bridge.viewer.browser.warm_markdown_preview.visible_ms',
		markdownWorkerClient: 'mocked',
		minimumContentUrlCount: 2,
		minimumCommandCount: 1,
	}),
	'failure-content-unavailable': makeScenarioContract({
		metric: 'bridge.viewer.browser.failure_content_unavailable.visible_ms',
		backendLatencyProfile: 'small',
		minimumContentUrlCount: 2,
		minimumCommandCount: 1,
	}),
	'stale-generation-drop': makeScenarioContract({
		metric: 'bridge.viewer.browser.stale_generation_drop.visible_ms',
		markdownWorkerClient: 'mocked',
		minimumContentUrlCount: 2,
		minimumCommandCount: 1,
	}),
	'scroll-ownership': makeScenarioContract({
		metric: 'bridge.viewer.browser.warm_scroll_ownership.visible_ms',
		minimumContentUrlCount: 2,
		minimumCommandCount: 1,
	}),
};

function makeScenarioContract(
	props: Pick<UnitTestScenarioContract, 'metric'> &
		Partial<Omit<UnitTestScenarioContract, 'metric'>>,
): UnitTestScenarioContract {
	return {
		metric: props.metric,
		fixtureClass: props.fixtureClass ?? 'small-mixed',
		deliveryMode: props.deliveryMode ?? 'full-load',
		codeViewWorkerPoolEnabled: props.codeViewWorkerPoolEnabled ?? false,
		markdownWorkerClient: props.markdownWorkerClient ?? 'disabled',
		backendLatencyProfile: props.backendLatencyProfile ?? 'zero',
		minimumContentUrlCount: props.minimumContentUrlCount ?? 1,
		minimumCommandCount: props.minimumCommandCount ?? 0,
		minimumPushRecordCount: props.minimumPushRecordCount ?? 1,
	};
}

function scenarioRequiresCodeViewWorker(scenarioId: string): boolean {
	return scenarioContracts[scenarioId]?.codeViewWorkerPoolEnabled ?? false;
}
