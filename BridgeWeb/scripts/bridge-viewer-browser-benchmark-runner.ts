import { spawn } from 'node:child_process';
import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { z } from 'zod';

const packageRootPath = fileURLToPath(new URL('../', import.meta.url));
const repoRootPath = fileURLToPath(new URL('../../', import.meta.url));
const proofRootPath =
	process.env['AGENTSTUDIO_BRIDGE_VIEWER_BROWSER_BENCHMARK_ROOT'] ??
	join(repoRootPath, 'tmp/bridge-viewer-browser-benchmark');

const bridgeViewerBrowserMetricPrefix = 'bridge.viewer.browser.';

const bridgeViewerBrowserWorkerModesSchema = z.object({
	codeViewWorkerPoolEnabled: z.boolean(),
	projectionWorkerClient: z.literal('mocked'),
	markdownWorkerClient: z.enum(['disabled', 'mocked']),
});

export const bridgeViewerBrowserBenchmarkMetricSchema = z.object({
	metric: z.string().startsWith(bridgeViewerBrowserMetricPrefix),
	scenarioId: z.string().min(1),
	fixtureId: z.string().min(1),
	fixtureClass: z.enum(['small-mixed', 'medium-agentstudio', 'large-diffshub']),
	deliveryMode: z.enum(['full-load', 'streaming-append']),
	itemCount: z.number().int().positive(),
	pathCount: z.number().int().positive(),
	diffLineCount: z.number().int().nonnegative(),
	packageBytes: z.number().int().positive(),
	fixtureChecksum: z.string().min(1),
	backendLatencyProfile: z.enum(['zero', 'small', 'slowBounded']),
	workerModes: bridgeViewerBrowserWorkerModesSchema,
	viewport: z.object({
		width: z.number().int().positive(),
		height: z.number().int().positive(),
		deviceScaleFactor: z.number().positive(),
	}),
	runtime: z.object({
		userAgent: z.string().min(1),
		language: z.string().min(1),
	}),
	correctnessAssertion: z.string().min(1),
	sampleCount: z.number().int().positive(),
	samples: z.array(z.number().finite().positive()).nonempty(),
	p50DurationMilliseconds: z.number().finite().positive(),
	p95DurationMilliseconds: z.number().finite().positive(),
	budgetMilliseconds: z.number().finite().positive(),
	requests: z.object({
		contentUrls: z.array(z.string()),
		contentUrlCount: z.number().int().nonnegative(),
		contentUrlsScopedToBridgeResource: z.boolean(),
		projectionRequestCount: z.number().int().positive(),
		commandCount: z.number().int().nonnegative(),
		pushRecordCount: z.number().int().nonnegative(),
	}),
});

export type BridgeViewerBrowserBenchmarkMetric = z.infer<
	typeof bridgeViewerBrowserBenchmarkMetricSchema
>;

interface BridgeViewerBrowserBenchmarkArtifact {
	readonly schemaVersion: 1;
	readonly runner: 'vitest-browser';
	readonly createdAtUnixMilliseconds: number;
	readonly metrics: readonly BridgeViewerBrowserBenchmarkMetric[];
	readonly requiredScenarioIds: readonly BridgeViewerBrowserBenchmarkScenarioId[];
	readonly stdoutLogPath: string;
	readonly stderrLogPath: string;
}

type BridgeViewerBrowserBenchmarkScenarioId = (typeof requiredScenarioIds)[number];

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

const requiredScenarioIdSet: ReadonlySet<string> = new Set(requiredScenarioIds);

const expectedWorkerBackedScenarioId: BridgeViewerBrowserBenchmarkScenarioId =
	'worker-backed-cold-package-push';

interface BridgeViewerBrowserBenchmarkScenarioContract {
	readonly metric: string;
	readonly fixtureClass: BridgeViewerBrowserBenchmarkMetric['fixtureClass'];
	readonly deliveryMode: BridgeViewerBrowserBenchmarkMetric['deliveryMode'];
	readonly codeViewWorkerPoolEnabled: boolean;
	readonly markdownWorkerClient: BridgeViewerBrowserBenchmarkMetric['workerModes']['markdownWorkerClient'];
	readonly backendLatencyProfile: BridgeViewerBrowserBenchmarkMetric['backendLatencyProfile'];
	readonly minimumContentUrlCount: number;
	readonly minimumCommandCount: number;
	readonly minimumPushRecordCount: number;
	readonly minimumItemCount?: number;
}

const scenarioContracts: Readonly<
	Record<BridgeViewerBrowserBenchmarkScenarioId, BridgeViewerBrowserBenchmarkScenarioContract>
> = {
	'cold-package-push': {
		metric: 'bridge.viewer.browser.cold_package_push.interactive_ms',
		fixtureClass: 'small-mixed',
		deliveryMode: 'full-load',
		codeViewWorkerPoolEnabled: false,
		markdownWorkerClient: 'disabled',
		backendLatencyProfile: 'zero',
		minimumContentUrlCount: 1,
		minimumCommandCount: 0,
		minimumPushRecordCount: 1,
	},
	'warm-tree-select': {
		metric: 'bridge.viewer.browser.warm_tree_select.visible_ms',
		fixtureClass: 'small-mixed',
		deliveryMode: 'full-load',
		codeViewWorkerPoolEnabled: false,
		markdownWorkerClient: 'disabled',
		backendLatencyProfile: 'zero',
		minimumContentUrlCount: 2,
		minimumCommandCount: 1,
		minimumPushRecordCount: 1,
	},
	'warm-added-file': {
		metric: 'bridge.viewer.browser.warm_added_file.visible_ms',
		fixtureClass: 'small-mixed',
		deliveryMode: 'full-load',
		codeViewWorkerPoolEnabled: false,
		markdownWorkerClient: 'disabled',
		backendLatencyProfile: 'zero',
		minimumContentUrlCount: 2,
		minimumCommandCount: 1,
		minimumPushRecordCount: 1,
	},
	'warm-hunk-expand': {
		metric: 'bridge.viewer.browser.warm_hunk_expand.visible_ms',
		fixtureClass: 'small-mixed',
		deliveryMode: 'full-load',
		codeViewWorkerPoolEnabled: false,
		markdownWorkerClient: 'disabled',
		backendLatencyProfile: 'zero',
		minimumContentUrlCount: 2,
		minimumCommandCount: 1,
		minimumPushRecordCount: 1,
	},
	'warm-search-expand-matches': {
		metric: 'bridge.viewer.browser.warm_search.expand_matches_ms',
		fixtureClass: 'small-mixed',
		deliveryMode: 'full-load',
		codeViewWorkerPoolEnabled: false,
		markdownWorkerClient: 'disabled',
		backendLatencyProfile: 'zero',
		minimumContentUrlCount: 1,
		minimumCommandCount: 0,
		minimumPushRecordCount: 1,
	},
	'warm-filter-switch': {
		metric: 'bridge.viewer.browser.warm_filter_switch.visible_ms',
		fixtureClass: 'small-mixed',
		deliveryMode: 'full-load',
		codeViewWorkerPoolEnabled: false,
		markdownWorkerClient: 'disabled',
		backendLatencyProfile: 'zero',
		minimumContentUrlCount: 1,
		minimumCommandCount: 0,
		minimumPushRecordCount: 1,
	},
	'warm-projection-chip-switch': {
		metric: 'bridge.viewer.browser.warm_projection_chip_switch.visible_ms',
		fixtureClass: 'small-mixed',
		deliveryMode: 'full-load',
		codeViewWorkerPoolEnabled: false,
		markdownWorkerClient: 'disabled',
		backendLatencyProfile: 'zero',
		minimumContentUrlCount: 1,
		minimumCommandCount: 0,
		minimumPushRecordCount: 1,
	},
	'medium-streaming-append-delta': {
		metric: 'bridge.viewer.browser.medium_streaming_append_delta.visible_ms',
		fixtureClass: 'medium-agentstudio',
		deliveryMode: 'streaming-append',
		codeViewWorkerPoolEnabled: false,
		markdownWorkerClient: 'disabled',
		backendLatencyProfile: 'zero',
		minimumContentUrlCount: 1,
		minimumCommandCount: 0,
		minimumPushRecordCount: 2,
	},
	'large-cold-package-push': {
		metric: 'bridge.viewer.browser.large_cold_package_push.interactive_ms',
		fixtureClass: 'large-diffshub',
		deliveryMode: 'full-load',
		codeViewWorkerPoolEnabled: false,
		markdownWorkerClient: 'disabled',
		backendLatencyProfile: 'zero',
		minimumContentUrlCount: 1,
		minimumCommandCount: 0,
		minimumPushRecordCount: 1,
		minimumItemCount: 3_420,
	},
	'large-semantic-select': {
		metric: 'bridge.viewer.browser.large_semantic_select.visible_ms',
		fixtureClass: 'large-diffshub',
		deliveryMode: 'full-load',
		codeViewWorkerPoolEnabled: true,
		markdownWorkerClient: 'disabled',
		backendLatencyProfile: 'zero',
		minimumContentUrlCount: 2,
		minimumCommandCount: 1,
		minimumPushRecordCount: 1,
		minimumItemCount: 3_420,
	},
	'worker-backed-cold-package-push': {
		metric: 'bridge.viewer.browser.worker_backed_cold_package_push.interactive_ms',
		fixtureClass: 'small-mixed',
		deliveryMode: 'full-load',
		codeViewWorkerPoolEnabled: true,
		markdownWorkerClient: 'disabled',
		backendLatencyProfile: 'zero',
		minimumContentUrlCount: 1,
		minimumCommandCount: 0,
		minimumPushRecordCount: 1,
	},
	'warm-markdown-preview': {
		metric: 'bridge.viewer.browser.warm_markdown_preview.visible_ms',
		fixtureClass: 'small-mixed',
		deliveryMode: 'full-load',
		codeViewWorkerPoolEnabled: false,
		markdownWorkerClient: 'mocked',
		backendLatencyProfile: 'zero',
		minimumContentUrlCount: 2,
		minimumCommandCount: 1,
		minimumPushRecordCount: 1,
	},
	'failure-content-unavailable': {
		metric: 'bridge.viewer.browser.failure_content_unavailable.visible_ms',
		fixtureClass: 'small-mixed',
		deliveryMode: 'full-load',
		codeViewWorkerPoolEnabled: false,
		markdownWorkerClient: 'disabled',
		backendLatencyProfile: 'small',
		minimumContentUrlCount: 2,
		minimumCommandCount: 1,
		minimumPushRecordCount: 1,
	},
	'stale-generation-drop': {
		metric: 'bridge.viewer.browser.stale_generation_drop.visible_ms',
		fixtureClass: 'small-mixed',
		deliveryMode: 'full-load',
		codeViewWorkerPoolEnabled: false,
		markdownWorkerClient: 'mocked',
		backendLatencyProfile: 'zero',
		minimumContentUrlCount: 2,
		minimumCommandCount: 1,
		minimumPushRecordCount: 1,
	},
	'scroll-ownership': {
		metric: 'bridge.viewer.browser.warm_scroll_ownership.visible_ms',
		fixtureClass: 'small-mixed',
		deliveryMode: 'full-load',
		codeViewWorkerPoolEnabled: false,
		markdownWorkerClient: 'disabled',
		backendLatencyProfile: 'zero',
		minimumContentUrlCount: 2,
		minimumCommandCount: 1,
		minimumPushRecordCount: 1,
	},
};

export function extractBridgeViewerBrowserBenchmarkMetrics(
	output: string,
): readonly BridgeViewerBrowserBenchmarkMetric[] {
	const metrics: BridgeViewerBrowserBenchmarkMetric[] = [];
	for (const line of output.split(/\r?\n/u)) {
		const jsonStartIndex = line.indexOf('{');
		const jsonEndIndex = line.lastIndexOf('}');
		if (jsonStartIndex < 0 || jsonEndIndex <= jsonStartIndex) {
			continue;
		}
		const candidate = line.slice(jsonStartIndex, jsonEndIndex + 1);
		try {
			const parsedCandidate: unknown = JSON.parse(candidate);
			const metric = bridgeViewerBrowserBenchmarkMetricSchema.safeParse(parsedCandidate);
			if (metric.success) {
				metrics.push(metric.data);
			}
		} catch {
			continue;
		}
	}
	return metrics;
}

export function verifyBridgeViewerBrowserBenchmarkMetrics(
	metrics: readonly BridgeViewerBrowserBenchmarkMetric[],
): void {
	const metricsByScenarioId = new Map<string, BridgeViewerBrowserBenchmarkMetric>();
	for (const metric of metrics) {
		if (metricsByScenarioId.has(metric.scenarioId)) {
			throw new Error(`duplicate browser benchmark scenario: ${metric.scenarioId}`);
		}
		metricsByScenarioId.set(metric.scenarioId, metric);
		verifyBridgeViewerBrowserBenchmarkMetric(metric);
	}

	for (const scenarioId of requiredScenarioIds) {
		if (!metricsByScenarioId.has(scenarioId)) {
			throw new Error(`missing browser benchmark scenario: ${scenarioId}`);
		}
	}

	const workerBackedMetric = metricsByScenarioId.get(expectedWorkerBackedScenarioId);
	if (workerBackedMetric?.workerModes.codeViewWorkerPoolEnabled !== true) {
		throw new Error(`${expectedWorkerBackedScenarioId}: expected packaged CodeView worker proof`);
	}
}

function verifyBridgeViewerBrowserBenchmarkMetric(
	metric: BridgeViewerBrowserBenchmarkMetric,
): void {
	if (metric.samples.length !== metric.sampleCount) {
		throw new Error(
			`${metric.scenarioId}: sample count expected ${metric.sampleCount}, got ${metric.samples.length}`,
		);
	}
	if (!isBridgeViewerBrowserBenchmarkScenarioId(metric.scenarioId)) {
		throw new Error(`${metric.scenarioId}: unknown browser benchmark scenario`);
	}
	const scenarioContract = scenarioContracts[metric.scenarioId];
	verifyScenarioContract({ metric, scenarioContract });
	const actualP50DurationMilliseconds = percentile(metric.samples, 0.5);
	const actualP95DurationMilliseconds = percentile(metric.samples, 0.95);
	if (!nearlyEqual(metric.p50DurationMilliseconds, actualP50DurationMilliseconds)) {
		throw new Error(
			`${metric.scenarioId}: reported p50 ${metric.p50DurationMilliseconds}ms does not match samples p50 ${actualP50DurationMilliseconds}ms`,
		);
	}
	if (!nearlyEqual(metric.p95DurationMilliseconds, actualP95DurationMilliseconds)) {
		throw new Error(
			`${metric.scenarioId}: reported p95 ${metric.p95DurationMilliseconds}ms does not match samples p95 ${actualP95DurationMilliseconds}ms`,
		);
	}
	if (actualP95DurationMilliseconds > metric.budgetMilliseconds) {
		throw new Error(
			`${metric.scenarioId}: p95 ${actualP95DurationMilliseconds}ms exceeds ${metric.budgetMilliseconds}ms budget`,
		);
	}
	if (!metric.correctnessAssertion.trim()) {
		throw new Error(`${metric.scenarioId}: missing correctness assertion`);
	}
	if (metric.requests.projectionRequestCount <= 0) {
		throw new Error(`${metric.scenarioId}: missing projection request ledger`);
	}
	if (metric.requests.contentUrlCount !== metric.requests.contentUrls.length) {
		throw new Error(`${metric.scenarioId}: content URL count does not match URL ledger`);
	}
	if (!metric.requests.contentUrlsScopedToBridgeResource) {
		throw new Error(`${metric.scenarioId}: content URLs escaped Bridge resource lane`);
	}
	if (metric.requests.contentUrlCount < scenarioContract.minimumContentUrlCount) {
		throw new Error(`${metric.scenarioId}: missing content URL ledger`);
	}
	if (metric.requests.commandCount < scenarioContract.minimumCommandCount) {
		throw new Error(`${metric.scenarioId}: missing command ledger`);
	}
	if (metric.requests.pushRecordCount < scenarioContract.minimumPushRecordCount) {
		throw new Error(`${metric.scenarioId}: missing push ledger`);
	}
	if (
		scenarioContract.minimumItemCount !== undefined &&
		metric.itemCount < scenarioContract.minimumItemCount
	) {
		throw new Error(
			`${metric.scenarioId}: item count ${metric.itemCount} below scenario floor ${scenarioContract.minimumItemCount}`,
		);
	}
}

function verifyScenarioContract(props: {
	readonly metric: BridgeViewerBrowserBenchmarkMetric;
	readonly scenarioContract: BridgeViewerBrowserBenchmarkScenarioContract;
}): void {
	const metric = props.metric;
	const scenarioContract = props.scenarioContract;
	if (metric.metric !== scenarioContract.metric) {
		throw new Error(`${metric.scenarioId}: metric id drifted from scenario contract`);
	}
	if (metric.fixtureClass !== scenarioContract.fixtureClass) {
		throw new Error(`${metric.scenarioId}: fixture class drifted from scenario contract`);
	}
	if (metric.deliveryMode !== scenarioContract.deliveryMode) {
		throw new Error(`${metric.scenarioId}: delivery mode drifted from scenario contract`);
	}
	if (metric.backendLatencyProfile !== scenarioContract.backendLatencyProfile) {
		throw new Error(`${metric.scenarioId}: latency profile drifted from scenario contract`);
	}
	if (metric.workerModes.codeViewWorkerPoolEnabled !== scenarioContract.codeViewWorkerPoolEnabled) {
		throw new Error(`${metric.scenarioId}: CodeView worker mode drifted from scenario contract`);
	}
	if (metric.workerModes.markdownWorkerClient !== scenarioContract.markdownWorkerClient) {
		throw new Error(`${metric.scenarioId}: markdown worker mode drifted from scenario contract`);
	}
}

function percentile(values: readonly number[], percentileValue: number): number {
	const sortedValues = [...values];
	// oxlint-disable-next-line unicorn/no-array-sort -- Sorting a local copy preserves the readonly input for verification.
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

function nearlyEqual(left: number, right: number): boolean {
	return Math.abs(left - right) <= 0.001;
}

function isBridgeViewerBrowserBenchmarkScenarioId(
	value: string,
): value is BridgeViewerBrowserBenchmarkScenarioId {
	return requiredScenarioIdSet.has(value);
}

export async function runBridgeViewerBrowserBenchmark(
	props: {
		readonly now?: Date;
	} = {},
): Promise<BridgeViewerBrowserBenchmarkArtifact> {
	const startedAt = props.now ?? new Date();
	const runDirectoryPath = join(proofRootPath, timestampSlug(startedAt));
	await mkdir(runDirectoryPath, { recursive: true });

	const result = await runVitestBrowserBenchmark();
	const stdoutLogPath = join(runDirectoryPath, 'stdout.log');
	const stderrLogPath = join(runDirectoryPath, 'stderr.log');
	await Promise.all([
		writeFile(stdoutLogPath, result.stdout, 'utf8'),
		writeFile(stderrLogPath, result.stderr, 'utf8'),
	]);

	if (result.exitCode !== 0) {
		throw new Error(`Browser benchmark Vitest run failed with exit ${result.exitCode}`);
	}

	const metrics = extractBridgeViewerBrowserBenchmarkMetrics(`${result.stdout}\n${result.stderr}`);
	verifyBridgeViewerBrowserBenchmarkMetrics(metrics);

	const artifact: BridgeViewerBrowserBenchmarkArtifact = {
		schemaVersion: 1,
		runner: 'vitest-browser',
		createdAtUnixMilliseconds: startedAt.getTime(),
		metrics,
		requiredScenarioIds,
		stdoutLogPath,
		stderrLogPath,
	};
	const artifactPath = join(runDirectoryPath, 'metrics.json');
	const metricsJsonlPath = join(runDirectoryPath, 'metrics.jsonl');
	await Promise.all([
		writeFile(artifactPath, `${JSON.stringify(artifact, null, '\t')}\n`, 'utf8'),
		writeFile(
			metricsJsonlPath,
			`${metrics.map((metric): string => JSON.stringify(metric)).join('\n')}\n`,
			'utf8',
		),
		writeFile(
			join(proofRootPath, 'latest.json'),
			`${JSON.stringify(
				{
					schemaVersion: 1,
					runDirectory: runDirectoryPath,
					artifactPath,
					metricsJsonlPath,
					stdoutLogPath,
					stderrLogPath,
				},
				null,
				'\t',
			)}\n`,
			'utf8',
		),
	]);

	console.log(`Bridge viewer browser benchmark proof verified: ${runDirectoryPath}`);
	return artifact;
}

interface RunVitestBrowserBenchmarkResult {
	readonly exitCode: number;
	readonly stdout: string;
	readonly stderr: string;
}

async function runVitestBrowserBenchmark(): Promise<RunVitestBrowserBenchmarkResult> {
	return await new Promise<RunVitestBrowserBenchmarkResult>((resolve, reject): void => {
		const child = spawn(
			'pnpm',
			[
				'exec',
				'vitest',
				'--config',
				'vitest.browser.config.ts',
				'run',
				'--project',
				'benchmarks-browser',
			],
			{
				cwd: packageRootPath,
				env: process.env,
				stdio: ['ignore', 'pipe', 'pipe'],
			},
		);
		let stdout = '';
		let stderr = '';
		child.stdout.setEncoding('utf8');
		child.stderr.setEncoding('utf8');
		child.stdout.on('data', (chunk: string): void => {
			stdout += chunk;
			process.stdout.write(chunk);
		});
		child.stderr.on('data', (chunk: string): void => {
			stderr += chunk;
			process.stderr.write(chunk);
		});
		child.on('error', (error: Error): void => {
			reject(error);
		});
		child.on('close', (code: number | null): void => {
			resolve({
				exitCode: code ?? 1,
				stdout,
				stderr,
			});
		});
	});
}

function timestampSlug(date: Date): string {
	return date.toISOString().replaceAll(':', '-').replaceAll('.', '-');
}

if (import.meta.url === `file://${process.argv[1]}`) {
	await runBridgeViewerBrowserBenchmark();
}
