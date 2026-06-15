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
				'src/review-viewer/workers/shiki/pierre-worker-pool.ts': `
					import { WorkerPoolManager } from '@pierre/diffs/worker';
					export const value = WorkerPoolManager;
				`,
				'src/review-viewer/dependencies/public-package-exports.unit.test.ts': `
					import { FileTree } from '@pierre/trees/react';
					import { File } from '@pierre/diffs/react';
					export const values = [FileTree, File];
				`,
			},
			async (packageRootPath: string): Promise<void> => {
				const report = await checkBridgeWebArchitecture({ packageRootPath });

				expect(report).toEqual({ ok: true, violations: [] });
			},
		);
	});

	test('reports effectful review-viewer state and raw loaded file bodies', async () => {
		await withFixtureTree(
			{
				'src/review-viewer/state/review-viewer-store.ts': `
					import { createBridgeRpcClient } from '../../bridge/bridge-rpc-client.js';
					const loadedFileBody = 'raw file text';
					export const state = { createBridgeRpcClient, loadedFileBody };
					fetch('agentstudio://resource/content/handle?generation=1');
				`,
			},
			async (packageRootPath: string): Promise<void> => {
				const report = await checkBridgeWebArchitecture({ packageRootPath });

				expect(report.ok).toBe(false);
				expect(report.violations.map(ruleIdForViolation)).toEqual(
					expect.arrayContaining([
						'review-viewer-state-has-effects',
						'no-raw-file-bodies-in-state',
					]),
				);
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
				'src/review-viewer/workers/rpc/projection-worker-client.ts': `
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
