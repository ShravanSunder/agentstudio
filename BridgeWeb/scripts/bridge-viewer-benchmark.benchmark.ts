import { execFile } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdir, writeFile } from 'node:fs/promises';
import { arch, cpus, platform, totalmem } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

import { describe, expect, test } from 'vitest';

import { materializeBridgeCodeViewItem } from '../src/review-viewer/code-view/bridge-code-view-materialization.js';
import type { BridgeReviewProjectionWorkloadId } from '../src/review-viewer/models/review-projection-models.js';
import {
	buildBridgeReviewProjection,
	buildBridgeReviewProjectionFromInput,
	makeBridgeReviewProjectionInput,
} from '../src/review-viewer/navigation/review-projection.js';
import {
	makeBridgeViewerBenchmarkWorkload,
	type BridgeViewerBenchmarkWorkload,
} from '../src/review-viewer/test-support/bridge-viewer-benchmark-workloads.js';
import { prepareBridgePresortedTreeInput } from '../src/review-viewer/trees/bridge-trees-controller.js';
import { buildBridgeMarkdownRenderWorkerSuccessResponse } from '../src/review-viewer/workers/markdown/bridge-markdown-render-worker-renderer.js';
import type { BridgeMarkdownRenderWorkerRequest } from '../src/review-viewer/workers/markdown/bridge-markdown-render-worker-rpc.js';

interface BridgeViewerBenchmarkArtifact {
	readonly schemaVersion: 1;
	readonly workloadId: Exclude<BridgeReviewProjectionWorkloadId, 'interactive'>;
	readonly runner: 'vitest-node';
	readonly viewport: BenchmarkViewport;
	readonly git: GitIdentity;
	readonly machine: MachineIdentity;
	readonly createdAtUnixMilliseconds: number;
	readonly workload: BenchmarkWorkloadSummary;
	readonly warmupRun: BenchmarkRun;
	readonly keptRuns: readonly BenchmarkRun[];
	readonly summary: BenchmarkSummary;
	readonly checksum: string;
	readonly notes: readonly string[];
}

interface BenchmarkViewport {
	readonly width: number;
	readonly height: number;
	readonly rowHeight: number;
	readonly overscanRows: number;
}

interface BenchmarkRun {
	readonly iteration: number;
	readonly runKind: 'warmup' | 'kept';
	readonly metrics: Readonly<Record<string, number>>;
	readonly positionChecksum: string;
}

interface BenchmarkSummary {
	readonly averages: Readonly<Record<string, number>>;
	readonly medians: Readonly<Record<string, number>>;
	readonly keptRunCount: number;
}

interface BenchmarkWorkloadSummary {
	readonly expectedDiffRows: number;
	readonly expectedItemCount: number;
	readonly expectedPathCount: number;
	readonly fixtureClass: string;
}

interface GitIdentity {
	readonly branch: string;
	readonly commit: string;
	readonly worktreeHash: string;
}

interface MachineIdentity {
	readonly arch: string;
	readonly cpuCount: number;
	readonly nodeVersion: string;
	readonly platform: string;
	readonly totalMemoryBytes: number;
}

const execFileAsync = promisify(execFile);
const repoRootPath = fileURLToPath(new URL('../../', import.meta.url));
const proofRootPath = join(repoRootPath, 'tmp/bridge-viewer-benchmark');
const viewport: BenchmarkViewport = {
	width: 1_440,
	height: 1_000,
	rowHeight: 24,
	overscanRows: 10,
};
const keptRunCount = 3;

describe('bridge viewer benchmark', () => {
	test('writes large tree and large diff artifacts', { timeout: 120_000 }, async () => {
		const git = await readGitIdentity();
		const runDirectoryPath = join(proofRootPath, timestampSlug(new Date()));
		await mkdir(runDirectoryPath, { recursive: true });

		const artifacts = [
			await runWorkloadBenchmark('bridge_viewer_large_tree_v1', git),
			await runWorkloadBenchmark('bridge_viewer_large_diff_scroll_v1', git),
		];
		for (const artifact of artifacts) {
			expect(artifact.keptRuns).toHaveLength(keptRunCount);
			expect(artifact.checksum).toMatch(/^[a-f0-9]{64}$/u);
			expect(Object.values(artifact.summary.averages).every(Number.isFinite)).toBe(true);
		}
		await Promise.all(
			artifacts.map(
				(artifact: BridgeViewerBenchmarkArtifact): Promise<void> =>
					writeArtifact(runDirectoryPath, artifact),
			),
		);
		await writeFile(
			join(proofRootPath, 'latest.json'),
			`${JSON.stringify(
				{
					schemaVersion: 1,
					runDirectory: runDirectoryPath,
					artifacts: artifacts.map((artifact: BridgeViewerBenchmarkArtifact): string =>
						artifactFileName(artifact.workloadId),
					),
				},
				null,
				'\t',
			)}\n`,
			'utf8',
		);
	});
});

async function runWorkloadBenchmark(
	workloadId: Exclude<BridgeReviewProjectionWorkloadId, 'interactive'>,
	git: GitIdentity,
): Promise<BridgeViewerBenchmarkArtifact> {
	const workload = makeBridgeViewerBenchmarkWorkload(workloadId);
	const warmupRun = await runBenchmarkIteration({ workload, iteration: 0, runKind: 'warmup' });
	const keptRuns: BenchmarkRun[] = [];
	for (let index = 0; index < keptRunCount; index += 1) {
		// eslint-disable-next-line no-await-in-loop -- Benchmark samples must run sequentially so runs do not contend with each other.
		keptRuns.push(await runBenchmarkIteration({ workload, iteration: index + 1, runKind: 'kept' }));
	}
	const summary = summarizeRuns(keptRuns);
	const checksum = checksumObject({ workloadId, warmupRun, keptRuns, summary });

	return {
		schemaVersion: 1,
		workloadId,
		runner: 'vitest-node',
		viewport,
		git,
		machine: readMachineIdentity(),
		createdAtUnixMilliseconds: Date.now(),
		workload: {
			expectedDiffRows: workload.metadata.expectedDiffRows,
			expectedItemCount: workload.metadata.expectedItemCount,
			expectedPathCount: workload.metadata.expectedPathCount,
			fixtureClass: workload.metadata.fixtureClass,
		},
		warmupRun,
		keptRuns,
		summary,
		checksum,
		notes: [
			'Node benchmark uses deterministic Pierre input preparation, CodeView item materialization, and markdown worker rendering.',
			'The scroll trace is a deterministic scroll-budget checksum; packaged WKWebView visual proof remains the runtime gate for actual browser painting and scrolling.',
		],
	};
}

interface RunBenchmarkIterationProps {
	readonly workload: BridgeViewerBenchmarkWorkload;
	readonly iteration: number;
	readonly runKind: 'warmup' | 'kept';
}

async function runBenchmarkIteration(props: RunBenchmarkIterationProps): Promise<BenchmarkRun> {
	const metrics =
		props.workload.workloadId === 'bridge_viewer_large_tree_v1'
			? runLargeTreeIteration(props.workload)
			: await runLargeDiffIteration(props.workload);
	return {
		iteration: props.iteration,
		runKind: props.runKind,
		metrics,
		positionChecksum: checksumObject(metrics),
	};
}

function runLargeTreeIteration(
	workload: BridgeViewerBenchmarkWorkload,
): Readonly<Record<string, number>> {
	const prepareStart = performance.now();
	const preparedInput = prepareBridgePresortedTreeInput(workload.treePaths);
	const prepareInputMilliseconds = elapsedSince(prepareStart);

	const projectionInputStart = performance.now();
	const projectionInput = makeBridgeReviewProjectionInput(workload.reviewPackage);
	const projectionInputMilliseconds = elapsedSince(projectionInputStart);

	const projectionFilterStart = performance.now();
	const docsProjection = buildBridgeReviewProjectionFromInput({
		projectionInput,
		request: { mode: { kind: 'plansAndSpecs' }, facets: [] },
	});
	const projectionFilterMilliseconds = elapsedSince(projectionFilterStart);

	return {
		docsProjectionItemCount: docsProjection.orderedItemIds.length,
		docsProjectionPathCount: docsProjection.orderedPaths.length,
		estimatedVisibleRows:
			Math.ceil(viewport.height / viewport.rowHeight) + viewport.overscanRows * 2,
		prepareInputMilliseconds,
		preparedRootCount: Object.keys(preparedInput).length,
		projectionFilterMilliseconds,
		projectionInputMilliseconds,
		treePathCount: workload.treePaths.length,
	};
}

async function runLargeDiffIteration(
	workload: BridgeViewerBenchmarkWorkload,
): Promise<Readonly<Record<string, number>>> {
	const largeDiff = workload.largeDiff;
	const largeMarkdown = workload.largeMarkdown;
	const diffItem = Object.values(workload.reviewPackage.itemsById).find(
		(item): boolean => item.contentRoles.base !== null && item.contentRoles.head !== null,
	);
	if (largeDiff === undefined || largeMarkdown === undefined || diffItem === undefined) {
		throw new Error('large diff benchmark workload is missing content');
	}
	const baseHandle = diffItem.contentRoles.base;
	const headHandle = diffItem.contentRoles.head;
	if (
		baseHandle === null ||
		baseHandle === undefined ||
		headHandle === null ||
		headHandle === undefined
	) {
		throw new Error('large diff benchmark workload is missing base/head handles');
	}

	const projectionStart = performance.now();
	const projection = buildBridgeReviewProjection({
		reviewPackage: workload.reviewPackage,
		request: { mode: { kind: 'normalReview' }, facets: [] },
	});
	const projectionBuildMilliseconds = elapsedSince(projectionStart);

	const materializeStart = performance.now();
	const materializationLineSampleCount = 8_000;
	const materializedItem = materializeBridgeCodeViewItem({
		item: diffItem,
		resources: {
			base: {
				handle: baseHandle,
				readText: (): string => firstLines(largeDiff.baseText, materializationLineSampleCount),
			},
			head: {
				handle: headHandle,
				readText: (): string => firstLines(largeDiff.headText, materializationLineSampleCount),
			},
		},
	});
	const materializeDiffMilliseconds = elapsedSince(materializeStart);
	if (materializedItem === null) {
		throw new Error('large diff benchmark failed to materialize CodeView item');
	}

	const markdownStart = performance.now();
	const markdownResponse = await buildBridgeMarkdownRenderWorkerSuccessResponse({
		request: markdownBenchmarkRequest({
			workload,
			markdownText: largeMarkdown.markdownText,
		}),
	});
	const markdownRenderWallMilliseconds = elapsedSince(markdownStart);

	const scrollStart = performance.now();
	const scroll = deterministicScrollTrace(largeDiff.lineCount);
	const scrollTraceMilliseconds = elapsedSince(scrollStart);

	return {
		diffLineCount: largeDiff.lineCount,
		markdownFencedBlockCount: largeMarkdown.fencedBlockCount,
		markdownInputBytes: markdownResponse.metrics.inputBytes,
		markdownLineCount: largeMarkdown.lineCount,
		markdownRenderMilliseconds: markdownResponse.metrics.durationMilliseconds,
		markdownRenderWallMilliseconds,
		markdownRenderedOutputBytes: markdownResponse.metrics.outputBytes,
		materializeDiffMilliseconds,
		materializedLineSampleCount: materializationLineSampleCount,
		projectionBuildMilliseconds,
		scrollDistancePixels: scroll.targetScrollTop,
		scrollSteps: scroll.steps,
		scrollTraceMilliseconds,
		virtualItemCount: projection.orderedItemIds.length,
	};
}

function markdownBenchmarkRequest(props: {
	readonly workload: BridgeViewerBenchmarkWorkload;
	readonly markdownText: string;
}): BridgeMarkdownRenderWorkerRequest {
	return {
		schemaVersion: 1,
		method: 'markdown.render',
		requestId: `${props.workload.workloadId}-markdown-benchmark`,
		packageId: props.workload.reviewPackage.packageId,
		reviewGeneration: props.workload.reviewPackage.reviewGeneration,
		revision: props.workload.reviewPackage.revision,
		itemId: 'benchmark-markdown-plan',
		itemVersion: 1,
		contentCacheKey: `${props.workload.workloadId}:markdown`,
		contentHash: checksumObject(props.markdownText),
		markdownText: props.markdownText,
		sourcePath: 'docs/plans/benchmark-plan.md',
	};
}

function firstLines(text: string, lineCount: number): string {
	let currentLine = 0;
	for (let index = 0; index < text.length; index += 1) {
		if (text[index] === '\n') {
			currentLine += 1;
		}
		if (currentLine >= lineCount) {
			return text.slice(0, index);
		}
	}
	return text;
}

interface DeterministicScrollTrace {
	readonly steps: number;
	readonly targetScrollTop: number;
}

function deterministicScrollTrace(lineCount: number): DeterministicScrollTrace {
	const steps = 120;
	const targetScrollTop = lineCount * 22;
	let checksum = 0;
	for (let step = 0; step <= steps; step += 1) {
		const scrollTop = Math.round((targetScrollTop * step) / steps);
		checksum = (checksum + scrollTop * (step + 1)) % 1_000_000_007;
	}
	if (checksum === 0) {
		throw new Error('deterministic scroll checksum must not be empty');
	}
	return { steps, targetScrollTop };
}

function summarizeRuns(runs: readonly BenchmarkRun[]): BenchmarkSummary {
	const metricNames = Object.keys(runs[0]?.metrics ?? {});
	return {
		averages: Object.fromEntries(
			metricNames.map((metricName: string): [string, number] => [
				metricName,
				average(runs.map((run: BenchmarkRun): number => run.metrics[metricName] ?? 0)),
			]),
		),
		medians: Object.fromEntries(
			metricNames.map((metricName: string): [string, number] => [
				metricName,
				median(runs.map((run: BenchmarkRun): number => run.metrics[metricName] ?? 0)),
			]),
		),
		keptRunCount: runs.length,
	};
}

function average(values: readonly number[]): number {
	return values.reduce((total: number, value: number): number => total + value, 0) / values.length;
}

function median(values: readonly number[]): number {
	const sorted = [...values].toSorted((left: number, right: number): number => left - right);
	const middleIndex = Math.floor(sorted.length / 2);
	return sorted[middleIndex] ?? 0;
}

async function writeArtifact(
	runDirectoryPath: string,
	artifact: BridgeViewerBenchmarkArtifact,
): Promise<void> {
	await writeFile(
		join(runDirectoryPath, artifactFileName(artifact.workloadId)),
		`${JSON.stringify(artifact, null, '\t')}\n`,
		'utf8',
	);
}

function artifactFileName(workloadId: BridgeViewerBenchmarkArtifact['workloadId']): string {
	return `${workloadId}.json`;
}

function elapsedSince(startMilliseconds: number): number {
	return Math.max(0, performance.now() - startMilliseconds);
}

function checksumObject(value: unknown): string {
	return createHash('sha256').update(JSON.stringify(value)).digest('hex');
}

async function readGitIdentity(): Promise<GitIdentity> {
	return {
		commit: await execGit(['rev-parse', 'HEAD']),
		branch: await execGit(['rev-parse', '--abbrev-ref', 'HEAD']),
		worktreeHash: checksumObject(repoRootPath),
	};
}

async function execGit(args: readonly string[]): Promise<string> {
	const { stdout } = await execFileAsync('git', args, { cwd: repoRootPath });
	return stdout.trim();
}

function readMachineIdentity(): MachineIdentity {
	return {
		arch: arch(),
		cpuCount: cpus().length,
		nodeVersion: process.version,
		platform: platform(),
		totalMemoryBytes: totalmem(),
	};
}

function timestampSlug(date: Date): string {
	return date.toISOString().replaceAll(/[:.]/gu, '-');
}
