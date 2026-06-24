import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { describe, expect, test } from 'vitest';

import {
	type ArchitectureViolation,
	checkBridgeWebArchitecture,
} from './check-bridgeweb-architecture.ts';

describe('BridgeWeb architecture checker', () => {
	test('reports private Pierre imports and misplaced Trees runtime imports', async () => {
		await withFixtureTree(
			{
				'src/review-viewer/shell/bad-tree-import.ts': `
					import { prepareFileTreeInput } from '@pierre/trees';
					import type { FileTreeNode } from '@pierre/trees/dist/model/publicTypes';
					export const value = prepareFileTreeInput([]);
				`,
			},
			async (packageRootPath: string): Promise<void> => {
				const report = await checkBridgeWebArchitecture({ packageRootPath });

				expect(report.ok).toBe(false);
				expect(report.violations.map(ruleIdForViolation)).toEqual(
					expect.arrayContaining(['no-private-pierre-imports', 'pierre-trees-import-boundary']),
				);
			},
		);
	});

	test('allows public Pierre imports in their owning viewer slices and tests', async () => {
		await withFixtureTree(
			{
				'src/review-viewer/trees/tree-controller.ts': `
					import { preparePresortedFileTreeInput } from '@pierre/trees';
					export const value = preparePresortedFileTreeInput([]);
				`,
				'src/review-viewer/code-view/code-view-controller.ts': `
					import { CodeView } from '@pierre/diffs/react';
					export const value = CodeView;
				`,
				'src/review-viewer/workers/pierre/pierre-worker-pool.ts': `
					import { WorkerPoolManager } from '@pierre/diffs/worker';
					export const value = WorkerPoolManager;
				`,
				'src/review-viewer/dependencies/public-package-exports.unit.test.ts': `
					import { FileTree } from '@pierre/trees/react';
					import { File } from '@pierre/diffs/react';
					export const values = [FileTree, File];
				`,
				'src/review-viewer/test-support/bridge-viewer.browser.benchmark.tsx': `
					import portableWorkerSource from '@pierre/diffs/worker/worker-portable.js?raw';
					export const value = portableWorkerSource;
				`,
				'src/review-viewer/test-support/example.browser.test.tsx': `
					const worker = new Worker(new URL('./fixture-worker.js', import.meta.url));
					worker.postMessage({ ok: true });
				`,
			},
			async (packageRootPath: string): Promise<void> => {
				const report = await checkBridgeWebArchitecture({ packageRootPath });

				expect(report).toEqual({ ok: true, violations: [] });
			},
		);
	});

	test('reports query-suffixed Pierre worker imports outside the worker owner', async () => {
		await withFixtureTree(
			{
				'src/review-viewer/shell/bad-worker-import.ts': `
					import portableWorkerSource from '@pierre/diffs/worker/worker-portable.js?raw';
					export const value = portableWorkerSource;
				`,
			},
			async (packageRootPath: string): Promise<void> => {
				const report = await checkBridgeWebArchitecture({ packageRootPath });

				expect(report.ok).toBe(false);
				expect(report.violations).toEqual([
					expect.objectContaining({
						ruleId: 'pierre-worker-import-boundary',
						relativePath: 'src/review-viewer/shell/bad-worker-import.ts',
					}),
				]);
			},
		);
	});

	test('reports effectful review-viewer state and raw loaded file bodies', async () => {
		await withFixtureTree(
			{
				'src/review-viewer/state/review-viewer-store.ts': `
					import { createBridgeRpcClient } from '../../bridge/bridge-rpc-client.js';
					import { WorkerPoolManager } from '@pierre/diffs/worker';
					const loadedFileBody = 'raw file text';
					const worker = new Worker(new URL('./worker.js', import.meta.url));
					const telemetry = { record: () => undefined };
					export const state = { createBridgeRpcClient, loadedFileBody, WorkerPoolManager };
					fetch('agentstudio://resource/content/handle?generation=1');
					worker.postMessage({ ok: true });
					telemetry.record('store-action');
				`,
			},
			async (packageRootPath: string): Promise<void> => {
				const report = await checkBridgeWebArchitecture({ packageRootPath });

				expect(report.ok).toBe(false);
				expect(report.violations.map(ruleIdForViolation)).toEqual(
					expect.arrayContaining([
						'review-viewer-state-has-effects',
						'no-raw-file-bodies-in-state',
						'worker-boundary',
						'telemetry-boundary',
					]),
				);
			},
		);
	});

	test('reports generic core imports of app protocol and viewer modules', async () => {
		await withFixtureTree(
			{
				'src/core/demand/bad-review-policy-import.ts': `
					import { mapReviewDemandStimulusToIntents } from '../../features/review/demand/review-demand-policy.js';
					export const value = mapReviewDemandStimulusToIntents;
				`,
				'src/core/resources/bad-worktree-import.ts': `
					import type { WorktreeFileDescriptor } from '../../features/worktree-file/models/worktree-file-protocol-models.js';
					export type Value = WorktreeFileDescriptor;
				`,
				'src/core/intake/bad-viewer-import.ts': `
					import { createBridgeReviewViewerStore } from '../../review-viewer/state/review-viewer-store.js';
					export const value = createBridgeReviewViewerStore;
				`,
				'src/core/models/bad-legacy-package-import.ts': `
					import type { BridgeReviewPackage } from '../../foundation/review-package/bridge-review-package.js';
					export type Value = BridgeReviewPackage;
				`,
			},
			async (packageRootPath: string): Promise<void> => {
				const report = await checkBridgeWebArchitecture({ packageRootPath });

				expect(report.ok).toBe(false);
				expect(report.violations).toEqual([
					expect.objectContaining({
						ruleId: 'core-imports-app-protocol',
						relativePath: 'src/core/demand/bad-review-policy-import.ts',
					}),
					expect.objectContaining({
						ruleId: 'core-imports-app-protocol',
						relativePath: 'src/core/intake/bad-viewer-import.ts',
					}),
					expect.objectContaining({
						ruleId: 'core-imports-app-protocol',
						relativePath: 'src/core/models/bad-legacy-package-import.ts',
					}),
					expect.objectContaining({
						ruleId: 'core-imports-app-protocol',
						relativePath: 'src/core/resources/bad-worktree-import.ts',
					}),
				]);
			},
		);
	});

	test('reports raw bodies and runtime handles in Worktree/File state', async () => {
		await withFixtureTree(
			{
				'src/features/worktree-file/state/worktree-file-state.ts': `
					export interface WorktreeFileSurfaceState {
						readonly selectedContentText: string;
						readonly contentPromise: Promise<string>;
						readonly abortController: AbortController;
						readonly workerHandle: Worker;
						readonly pierreInstance: object;
					}
				`,
			},
			async (packageRootPath: string): Promise<void> => {
				const report = await checkBridgeWebArchitecture({ packageRootPath });

				expect(report.ok).toBe(false);
				expect(report.violations).toEqual([
					expect.objectContaining({
						ruleId: 'no-raw-file-bodies-in-state',
						relativePath: 'src/features/worktree-file/state/worktree-file-state.ts',
					}),
				]);
			},
		);
	});

	test('reports Worktree dev Review-package scaffolding', async () => {
		await withFixtureTree(
			{
				'src/app/bridge-app-dev-worktree.ts': `
					import { dispatchBridgeDevHostAdmittedEnvelope } from '../bridge/bridge-dev-host-push-carrier.js';
					import { buildReviewSnapshotFrame } from '../features/review/protocol/review-snapshot-frame-builder.js';
					import { bridgeReviewPackageSchema } from '../foundation/review-package/bridge-review-package-schema.js';
					const worktreePackageEndpoint = '/__bridge-worktree/package';
					export const pushPackage = (): void => {
						dispatchBridgeDevHostAdmittedEnvelope(buildReviewSnapshotFrame(bridgeReviewPackageSchema));
					};
					export const endpoint = worktreePackageEndpoint;
				`,
				'scripts/dev-server/bridge-worktree-dev-provider.ts': `
					import type { BridgeReviewPackage } from '../../src/foundation/review-package/bridge-review-package.js';
					export interface BridgeWorktreeDevProvider {
						readonly loadReviewPackage: () => Promise<BridgeReviewPackage>;
						readonly loadContent: () => Promise<string>;
					}
					export const reviewContentEndpoint = '/__bridge-worktree/content/';
				`,
			},
			async (packageRootPath: string): Promise<void> => {
				const report = await checkBridgeWebArchitecture({ packageRootPath });

				expect(report.ok).toBe(false);
				expect(report.violations).toEqual([
					expect.objectContaining({
						ruleId: 'worktree-dev-review-package-scaffolding',
						relativePath: 'scripts/dev-server/bridge-worktree-dev-provider.ts',
					}),
					expect.objectContaining({
						ruleId: 'worktree-dev-review-package-scaffolding',
						relativePath: 'src/app/bridge-app-dev-worktree.ts',
					}),
				]);
			},
		);
	});

	test('reports vague review-viewer runtime and workers/rpc folders', async () => {
		await withFixtureTree(
			{
				'src/review-viewer/runtime/review-content-loader.ts': `
					export const value = 'content';
				`,
				'src/review-viewer/workers/rpc/review-projection-worker-client.ts': `
					export const value = 'projection';
				`,
				'src/review-viewer/content/review-content-loader.ts': `
					export const content = 'content';
				`,
				'src/review-viewer/projections/use-review-projection-coordinator.ts': `
					export const projection = 'projection';
				`,
				'src/review-viewer/workers/projection/review-projection-worker-client.ts': `
					export const projectionWorker = 'projection-worker';
				`,
				'src/review-viewer/workers/shared-rpc/shared-worker-rpc.ts': `
					export const sharedRpc = 'shared-rpc';
				`,
			},
			async (packageRootPath: string): Promise<void> => {
				const report = await checkBridgeWebArchitecture({ packageRootPath });

				expect(report.ok).toBe(false);
				expect(report.violations).toEqual([
					expect.objectContaining({
						ruleId: 'review-viewer-folder-boundary',
						relativePath: 'src/review-viewer/runtime/review-content-loader.ts',
					}),
					expect.objectContaining({
						ruleId: 'review-viewer-folder-boundary',
						relativePath: 'src/review-viewer/workers/rpc/review-projection-worker-client.ts',
					}),
				]);
			},
		);
	});

	test('reports Worker and postMessage usage outside worker lanes', async () => {
		await withFixtureTree(
			{
				'src/review-viewer/shell/bad-worker.ts': `
					const worker = new Worker(new URL('./worker.js', import.meta.url));
					worker.postMessage({ ok: true });
				`,
				'src/review-viewer/workers/projection/projection-worker-client.ts': `
					const worker = new Worker(new URL('./projection-worker.js', import.meta.url));
					worker.postMessage({ ok: true });
				`,
			},
			async (packageRootPath: string): Promise<void> => {
				const report = await checkBridgeWebArchitecture({ packageRootPath });

				expect(report.ok).toBe(false);
				expect(report.violations).toEqual([
					expect.objectContaining({
						ruleId: 'worker-boundary',
						relativePath: 'src/review-viewer/shell/bad-worker.ts',
					}),
					expect.objectContaining({
						ruleId: 'worker-boundary',
						relativePath: 'src/review-viewer/shell/bad-worker.ts',
					}),
				]);
			},
		);
	});

	test('reports content loading imports from review-viewer shell files', async () => {
		await withFixtureTree(
			{
				'src/review-viewer/shell/review-viewer-shell.tsx': `
					import { loadBridgeContentResource } from '../../foundation/content/content-resource-loader.js';
					export const value = loadBridgeContentResource;
				`,
				'src/review-viewer/content/review-content-loader.ts': `
					import { loadBridgeContentResource } from '../../foundation/content/content-resource-loader.js';
					export const value = loadBridgeContentResource;
				`,
			},
			async (packageRootPath: string): Promise<void> => {
				const report = await checkBridgeWebArchitecture({ packageRootPath });

				expect(report.ok).toBe(false);
				expect(report.violations).toEqual([
					expect.objectContaining({
						ruleId: 'review-viewer-shell-has-content-effects',
						relativePath: 'src/review-viewer/shell/review-viewer-shell.tsx',
					}),
				]);
			},
		);
	});

	test('reports markdown and Shiki rendering imports outside the markdown worker renderer', async () => {
		await withFixtureTree(
			{
				'src/review-viewer/markdown/bridge-markdown-preview.tsx': `
					import { createMarkdownExit } from 'markdown-exit';
					import { codeToHtml } from 'shiki';
					export const values = [createMarkdownExit, codeToHtml];
				`,
				'src/review-viewer/workers/markdown/bridge-markdown-render-worker-client.ts': `
					import { createMarkdownExit } from 'markdown-exit';
					export const value = createMarkdownExit;
				`,
				'src/review-viewer/workers/markdown/bridge-markdown-render-worker-renderer.ts': `
					import { fromAsyncCodeToHtml } from '@shikijs/markdown-exit/core';
					export const value = fromAsyncCodeToHtml;
				`,
			},
			async (packageRootPath: string): Promise<void> => {
				const report = await checkBridgeWebArchitecture({ packageRootPath });

				expect(report.ok).toBe(false);
				expect(report.violations).toEqual([
					expect.objectContaining({
						ruleId: 'markdown-render-worker-boundary',
						relativePath: 'src/review-viewer/markdown/bridge-markdown-preview.tsx',
					}),
					expect.objectContaining({
						ruleId: 'markdown-render-worker-boundary',
						relativePath: 'src/review-viewer/markdown/bridge-markdown-preview.tsx',
					}),
					expect.objectContaining({
						ruleId: 'markdown-render-worker-boundary',
						relativePath:
							'src/review-viewer/workers/markdown/bridge-markdown-render-worker-client.ts',
					}),
				]);
			},
		);
	});
});

async function withFixtureTree(
	files: Record<string, string>,
	runTest: (packageRootPath: string) => Promise<void>,
): Promise<void> {
	const packageRootPath = await mkdtemp(join(tmpdir(), 'bridgeweb-architecture-'));

	try {
		await Promise.all(
			Object.entries(files).map(async ([relativePath, content]) => {
				const filePath = join(packageRootPath, relativePath);
				await mkdir(join(filePath, '..'), { recursive: true });
				await writeFile(filePath, content, 'utf8');
			}),
		);
		await runTest(packageRootPath);
	} finally {
		await rm(packageRootPath, { force: true, recursive: true });
	}
}

function ruleIdForViolation(violation: ArchitectureViolation): string {
	return violation.ruleId;
}
