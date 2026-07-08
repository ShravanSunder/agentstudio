import { existsSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { z } from 'zod';

const repoRootPath = fileURLToPath(new URL('../../', import.meta.url));
const proofRootPath =
	process.env['AGENTSTUDIO_BRIDGE_VIEWER_BENCHMARK_ROOT'] ??
	join(repoRootPath, 'tmp/bridge-viewer-benchmark');
const latestFilePath = join(proofRootPath, 'latest.json');

const benchmarkMetricSchema = z.record(z.string(), z.number().finite());

const benchmarkRunSchema = z.object({
	iteration: z.number().int().nonnegative(),
	runKind: z.enum(['warmup', 'kept']),
	metrics: benchmarkMetricSchema,
	positionChecksum: z.string().regex(/^[a-f0-9]{64}$/u),
});

const benchmarkArtifactSchema = z.object({
	schemaVersion: z.literal(1),
	workloadId: z.enum(['bridge_viewer_large_tree_v1', 'bridge_viewer_large_diff_scroll_v1']),
	runner: z.literal('vitest-node'),
	viewport: z.object({
		width: z.literal(1_440),
		height: z.literal(1_000),
		rowHeight: z.literal(24),
		overscanRows: z.literal(10),
	}),
	workload: z.object({
		expectedDiffRows: z.number().int().nonnegative(),
		expectedItemCount: z.number().int().positive(),
		expectedPathCount: z.number().int().positive(),
		fixtureClass: z.enum(['large_tree', 'large_diff']),
	}),
	warmupRun: benchmarkRunSchema,
	keptRuns: z.array(benchmarkRunSchema).length(3),
	summary: z.object({
		averages: benchmarkMetricSchema,
		medians: benchmarkMetricSchema,
		keptRunCount: z.literal(3),
	}),
	checksum: z.string().regex(/^[a-f0-9]{64}$/u),
	notes: z.array(z.string()),
});

const latestBenchmarkSchema = z.object({
	schemaVersion: z.literal(1),
	runDirectory: z.string().min(1),
	artifacts: z.array(z.string().min(1)).length(2),
});

type BenchmarkArtifact = z.infer<typeof benchmarkArtifactSchema>;
type BridgeViewerBenchmarkWorkloadId = BenchmarkArtifact['workloadId'];
interface BridgeViewerBenchmarkExpectation {
	readonly expectedPathCount: number;
	readonly expectedDiffRows: number;
	readonly expectedCodeViewCacheIdentityCount?: number;
	readonly expectedMarkdownFencedBlockCount?: number;
	readonly metricBudgets: Readonly<Record<string, number>>;
}

const requiredWorkloadIds = [
	'bridge_viewer_large_tree_v1',
	'bridge_viewer_large_diff_scroll_v1',
] as const satisfies readonly BridgeViewerBenchmarkWorkloadId[];

const requiredWorkloads: Record<BridgeViewerBenchmarkWorkloadId, BridgeViewerBenchmarkExpectation> =
	{
		bridge_viewer_large_tree_v1: {
			expectedPathCount: 90_000,
			expectedDiffRows: 0,
			metricBudgets: {
				prepareInputMilliseconds: 50,
				projectionFilterMilliseconds: 250,
				projectionInputMilliseconds: 2_000,
			},
		},
		bridge_viewer_large_diff_scroll_v1: {
			expectedPathCount: 25,
			expectedDiffRows: 100_000,
			expectedCodeViewCacheIdentityCount: 1,
			expectedMarkdownFencedBlockCount: 64,
			metricBudgets: {
				codeViewCacheIdentityMilliseconds: 5,
				markdownRenderMilliseconds: 10_000,
				markdownRenderWallMilliseconds: 10_000,
				projectionBuildMilliseconds: 25,
				scrollTraceMilliseconds: 5,
			},
		},
	};

if (!existsSync(latestFilePath)) {
	throw new Error(`missing Bridge viewer benchmark proof: ${latestFilePath}`);
}

const latest = latestBenchmarkSchema.parse(JSON.parse(await readFile(latestFilePath, 'utf8')));
if (!existsSync(latest.runDirectory)) {
	throw new Error(`benchmark run directory is missing: ${latest.runDirectory}`);
}

const artifacts = await Promise.all(
	requiredWorkloadIds.map(async (workloadId) => {
		const artifactPath = join(latest.runDirectory, `${workloadId}.json`);
		if (!existsSync(artifactPath)) {
			throw new Error(`missing benchmark artifact: ${artifactPath}`);
		}
		return benchmarkArtifactSchema.parse(JSON.parse(await readFile(artifactPath, 'utf8')));
	}),
);

for (const artifact of artifacts) {
	verifyBenchmarkArtifact(artifact);
}

console.log(`Bridge viewer benchmark proof verified: ${latest.runDirectory}`);

function verifyBenchmarkArtifact(artifact: BenchmarkArtifact): void {
	const expectations = requiredWorkloads[artifact.workloadId];
	if (artifact.workload.expectedPathCount !== expectations.expectedPathCount) {
		throw new Error(
			`${artifact.workloadId}: expectedPathCount expected ${expectations.expectedPathCount}, got ${artifact.workload.expectedPathCount}`,
		);
	}
	if (artifact.workload.expectedDiffRows !== expectations.expectedDiffRows) {
		throw new Error(
			`${artifact.workloadId}: expectedDiffRows expected ${expectations.expectedDiffRows}, got ${artifact.workload.expectedDiffRows}`,
		);
	}
	if (expectations.expectedCodeViewCacheIdentityCount !== undefined) {
		const cacheIdentityCount = artifact.summary.medians['codeViewCacheIdentityCount'];
		if (cacheIdentityCount !== expectations.expectedCodeViewCacheIdentityCount) {
			throw new Error(
				`${artifact.workloadId}: codeViewCacheIdentityCount expected ${expectations.expectedCodeViewCacheIdentityCount}, got ${cacheIdentityCount}`,
			);
		}
	}
	if (expectations.expectedMarkdownFencedBlockCount !== undefined) {
		const fencedBlockCount = artifact.summary.medians['markdownFencedBlockCount'];
		if (fencedBlockCount !== expectations.expectedMarkdownFencedBlockCount) {
			throw new Error(
				`${artifact.workloadId}: markdownFencedBlockCount expected ${expectations.expectedMarkdownFencedBlockCount}, got ${fencedBlockCount}`,
			);
		}
		const renderedOutputBytes = artifact.summary.medians['markdownRenderedOutputBytes'];
		if (renderedOutputBytes === undefined || renderedOutputBytes <= 0) {
			throw new Error(`${artifact.workloadId}: missing rendered markdown output bytes`);
		}
	}
	for (const [metricName, budgetMilliseconds] of Object.entries(expectations.metricBudgets)) {
		const medianValue = artifact.summary.medians[metricName];
		if (medianValue === undefined) {
			throw new Error(`${artifact.workloadId}: missing median metric ${metricName}`);
		}
		if (medianValue > budgetMilliseconds) {
			throw new Error(
				`${artifact.workloadId}: ${metricName} median ${medianValue}ms exceeds ${budgetMilliseconds}ms budget`,
			);
		}
	}
}
