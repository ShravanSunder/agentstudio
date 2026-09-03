import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { describe, expect, test } from 'vitest';

import {
	type ArchitectureViolation,
	checkBridgeWebArchitecture,
} from './check-bridgeweb-architecture.ts';

describe('BridgeWeb architecture checker', () => {
	test('reports every TypeScript and TSX file over one thousand lines', async () => {
		await withFixtureTree(
			{
				'src/app/large-controller.ts': generatedLineSource(1001),
				'src/app/large-controller.unit.test.ts': generatedLineSource(1001),
				'vite.config.ts': generatedLineSource(1001),
				'src/app/large-view.tsx': generatedLineSource(1001),
				'src/app/limit.ts': generatedLineSource(1000),
				'node_modules/package/large.ts': generatedLineSource(1001),
			},
			async (packageRootPath: string): Promise<void> => {
				const report = await checkBridgeWebArchitecture({ packageRootPath });

				expect(report.ok).toBe(false);
				expect(report.violations).toEqual(
					expect.arrayContaining([
						expect.objectContaining({
							ruleId: 'max-file-lines',
							relativePath: 'src/app/large-controller.ts',
						}),
						expect.objectContaining({
							ruleId: 'max-file-lines',
							relativePath: 'src/app/large-controller.unit.test.ts',
						}),
						expect.objectContaining({
							ruleId: 'max-file-lines',
							relativePath: 'src/app/large-view.tsx',
						}),
						expect.objectContaining({
							ruleId: 'max-file-lines',
							relativePath: 'vite.config.ts',
						}),
					]),
				);
				expect(report.violations).not.toContainEqual(
					expect.objectContaining({
						ruleId: 'max-file-lines',
						relativePath: 'src/app/limit.ts',
					}),
				);
				expect(report.violations).not.toContainEqual(
					expect.objectContaining({
						ruleId: 'max-file-lines',
						relativePath: 'node_modules/package/large.ts',
					}),
				);
			},
		);
	});

	test('reports private Pierre imports and misplaced Trees runtime imports', async () => {
		await withFixtureTree(
			{
				'src/review-viewer/code-view/bad-private-parser.ts': `
					import { parseDiffFromFile } from '@pierre/diffs/dist/parseDiffFromFile';
					export const value = parseDiffFromFile;
				`,
				'src/review-viewer/shell/bad-tree-import.ts': `
					import { prepareFileTreeInput } from '@pierre/trees';
					import type { FileTreeNode } from '@pierre/trees/dist/model/publicTypes';
					export const value = prepareFileTreeInput([]);
				`,
			},
			async (packageRootPath: string): Promise<void> => {
				const report = await checkBridgeWebArchitecture({ packageRootPath });

				expect(report.ok).toBe(false);
				expect(report.violations).toEqual(
					expect.arrayContaining([
						expect.objectContaining({
							relativePath: 'src/review-viewer/code-view/bad-private-parser.ts',
							ruleId: 'no-private-pierre-imports',
						}),
					]),
				);
				expect(report.violations.map(ruleIdForViolation)).toEqual(
					expect.arrayContaining(['no-private-pierre-imports', 'pierre-trees-import-boundary']),
				);
			},
		);
	});

	test('keeps endpoint adapters and environment detection out of shared product runtime sources', async () => {
		await withFixtureTree(
			{
				'src/core/comm-worker/bridge-product-transport.ts': `
					import { executeAgentStudioBridgeProductRequest } from './bridge-product-agent-studio-request-executor.js';
					import { executeHttpBridgeProductRequest } from './bridge-product-http-request-executor.js';
					export const execute = import.meta.env.DEV
						? executeHttpBridgeProductRequest
						: executeAgentStudioBridgeProductRequest;
					export const computedImportMetaMode = import.meta['env'].DEV;
					export const computedProcessMode = process['env'].NODE_ENV;
					export const call = (props) =>
						props.executeProductRequest('command', { method: 'GET', headers: {} });
				`,
				'src/core/comm-worker/bridge-comm-worker-packaged-entry.ts': `
					import { executeAgentStudioBridgeProductRequest } from './bridge-product-agent-studio-request-executor.js';
					export const execute = executeAgentStudioBridgeProductRequest;
				`,
				'src/core/comm-worker/bridge-comm-worker-vite-entry.ts': `
					import { executeHttpBridgeProductRequest } from './bridge-product-http-request-executor.js';
					export const execute = executeHttpBridgeProductRequest;
				`,
				'src/core/comm-worker/bridge-comm-worker-runtime-protocol.ts': `
					import { executeHttpBridgeProductRequest } from './bridge-product-http-request-executor.js';
					export const execute = executeHttpBridgeProductRequest;
				`,
				'src/core/comm-worker/bridge-worker-runtime.ts': `
					export const transportOrigin = globalThis.location.origin;
					export const computedTransportOrigin = globalThis['location']['origin'];
				`,
				'src/file-viewer/file-product-runtime.ts': `
					export const endpoint = '/__bridge-product/content';
				`,
				'src/app/bridge-app-file-viewer-mode.tsx': `
					export const transportOrigin = window.location.origin;
				`,
			},
			async (packageRootPath: string): Promise<void> => {
				const report = await checkBridgeWebArchitecture({ packageRootPath });
				const endpointViolations = report.violations.filter(
					(violation): boolean => violation.ruleId === 'product-endpoint-boundary',
				);

				expect(endpointViolations).toHaveLength(11);
				expect(endpointViolations).toEqual(
					expect.arrayContaining([
						expect.objectContaining({
							relativePath: 'src/core/comm-worker/bridge-product-transport.ts',
						}),
						expect.objectContaining({
							relativePath: 'src/core/comm-worker/bridge-product-transport.ts',
						}),
						expect.objectContaining({
							relativePath: 'src/core/comm-worker/bridge-product-transport.ts',
						}),
						expect.objectContaining({
							relativePath: 'src/core/comm-worker/bridge-comm-worker-runtime-protocol.ts',
						}),
						expect.objectContaining({
							relativePath: 'src/core/comm-worker/bridge-worker-runtime.ts',
						}),
						expect.objectContaining({
							relativePath: 'src/file-viewer/file-product-runtime.ts',
						}),
						expect.objectContaining({
							relativePath: 'src/app/bridge-app-file-viewer-mode.tsx',
						}),
					]),
				);
			},
		);
	});

	test('covers every comm-worker runtime and qualified fetch while allowing worker script loading', async () => {
		await withFixtureTree(
			{
				'src/core/comm-worker/bridge-pane-runtime-environment.ts': `
					export const transportOrigin = globalThis.location.origin;
					export const productEndpoint = '/__bridge-product/content';
				`,
				'src/core/comm-worker/bridge-product-runtime-fetches.ts': `
					export const first = globalThis.fetch('/one');
					export const second = self['fetch']('/two');
					export const third = window.fetch('/three');
				`,
				'src/core/comm-worker/bridge-pane-comm-worker-session.ts': `
					export const loadWorkerScript = (workerScriptUrl: string) => fetch(workerScriptUrl);
				`,
			},
			async (packageRootPath: string): Promise<void> => {
				const report = await checkBridgeWebArchitecture({ packageRootPath });
				const endpointViolations = report.violations.filter(
					(violation): boolean => violation.ruleId === 'product-endpoint-boundary',
				);

				expect(endpointViolations).toHaveLength(5);
				expect(endpointViolations).toEqual(
					expect.arrayContaining([
						expect.objectContaining({
							relativePath: 'src/core/comm-worker/bridge-pane-runtime-environment.ts',
						}),
						expect.objectContaining({
							relativePath: 'src/core/comm-worker/bridge-product-runtime-fetches.ts',
						}),
					]),
				);
				expect(endpointViolations).not.toContainEqual(
					expect.objectContaining({
						relativePath: 'src/core/comm-worker/bridge-pane-comm-worker-session.ts',
					}),
				);
			},
		);
	});

	test('ignores Pierre strings in assertions while still reporting real imports', async () => {
		await withFixtureTree(
			{
				'src/review-viewer/dependencies/source-structure.guard.unit.test.ts': `
					import { expect, test } from 'vitest';

					test('guards source boundaries', () => {
						const source = 'import type { FileTreeNode } from "forbidden";';

						expect(source).not.toContain('@pierre/diffs/dist/');
						expect(source).not.toContain('@pierre/trees/dist/model/publicTypes');
					});
				`,
				'src/review-viewer/shell/bad-private-import.ts': `
					import type { FileTreeNode } from '@pierre/trees/dist/model/publicTypes';
					export type Value = FileTreeNode;
				`,
			},
			async (packageRootPath: string): Promise<void> => {
				const report = await checkBridgeWebArchitecture({ packageRootPath });

				expect(report.ok).toBe(false);
				expect(report.violations).not.toEqual(
					expect.arrayContaining([
						expect.objectContaining({
							relativePath: 'src/review-viewer/dependencies/source-structure.guard.unit.test.ts',
						}),
					]),
				);
				expect(report.violations).toEqual(
					expect.arrayContaining([
						expect.objectContaining({
							ruleId: 'no-private-pierre-imports',
							relativePath: 'src/review-viewer/shell/bad-private-import.ts',
						}),
					]),
				);
			},
		);
	});

	test('allows public Pierre imports in their owning viewer slices and tests', async () => {
		await withFixtureTree(
			{
				'src/core/comm-worker/bridge-worker-review-pierre-job-planner.ts': `
					import { parseDiffFromFile } from '@pierre/diffs';
					export const value = parseDiffFromFile;
				`,
				'src/review-viewer/trees/tree-controller.ts': `
					import { preparePresortedFileTreeInput } from '@pierre/trees';
					export const value = preparePresortedFileTreeInput([]);
				`,
				'src/file-viewer/file-tree-panel.tsx': `
					import { FileTree } from '@pierre/trees/react';
					export const value = FileTree;
				`,
				'src/app/bridge-viewer-tree-theme.ts': `
					import { themeToTreeStyles } from '@pierre/trees';
					export const value = themeToTreeStyles;
				`,
				'src/review-viewer/code-view/code-view-controller.ts': `
					import { CodeView } from '@pierre/diffs/react';
					export const value = CodeView;
				`,
				'src/file-viewer/file-code-panel.tsx': `
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
				'src/core/models/bad-aliased-worktree-import.ts': `
					import type { WorktreeFileDescriptor } from '@/features/worktree-file/models/worktree-file-protocol-models.js';
					export type Value = WorktreeFileDescriptor;
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
						relativePath: 'src/core/models/bad-aliased-worktree-import.ts',
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

	test('reports a TypeScript development server that reintroduces live product authority', async () => {
		await withFixtureTree(
			{
				'scripts/dev-server/rogue-live-product-provider.ts': `
					import type { BridgeReviewPackage } from '../../src/foundation/review-package/bridge-review-package.js';
					export interface RogueLiveProductProvider {
						readonly loadReviewPackage: () => Promise<BridgeReviewPackage>;
						readonly loadContent: () => Promise<string>;
					}
					export const reviewContentEndpoint = '/__bridge-product/content';
				`,
			},
			async (packageRootPath: string): Promise<void> => {
				const report = await checkBridgeWebArchitecture({ packageRootPath });

				expect(report.ok).toBe(false);
				expect(report.violations).toEqual([
					expect.objectContaining({
						ruleId: 'no-typescript-live-product-authority',
						relativePath: 'scripts/dev-server/rogue-live-product-provider.ts',
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

	test('allows only owned comm-worker and diagnostic message boundaries', async () => {
		await withFixtureTree(
			{
				'src/core/comm-worker/bridge-comm-worker-client.ts': `
					const worker = new Worker(new URL('./bridge-comm-worker.js', import.meta.url));
					worker.postMessage({ kind: 'client' });
				`,
				'src/core/comm-worker/bridge-comm-worker-entry.ts': `
					self.postMessage({ kind: 'entry' });
				`,
				'src/core/comm-worker/bridge-comm-worker-runtime-protocol.ts': `
					const port = { postMessage: (_message: unknown): void => undefined };
					port.postMessage({ kind: 'runtime' });
				`,
				'src/core/comm-worker/bridge-comm-worker-task-boundary.ts': `
					const port = { postMessage: (_message: unknown): void => undefined };
					port.postMessage({ kind: 'task-boundary' });
				`,
				'src/core/comm-worker/bridge-product-session-contracts.ts': `
					const port = { postMessage: (_message: unknown): void => undefined };
					port.postMessage({ kind: 'product-session' });
				`,
				'src/app/diagnostics/bridge-product-stream-webkit-feasibility-worker-entry.ts': `
					self.postMessage({ kind: 'product-stream-feasibility' });
				`,
				'src/app/diagnostics/bridge-product-stream-webkit-feasibility-probe.ts': `
					const worker = { postMessage: (_message: unknown): void => undefined };
					worker.postMessage({ kind: 'product-stream-probe' });
				`,
				'src/core/comm-worker/unowned-message-boundary.ts': `
					const port = { postMessage: (_message: unknown): void => undefined };
					port.postMessage({ kind: 'unowned-comm-message' });
				`,
				'src/app/diagnostics/unowned-diagnostic-message-boundary.ts': `
					const worker = { postMessage: (_message: unknown): void => undefined };
					worker.postMessage({ kind: 'unowned-diagnostic-message' });
				`,
			},
			async (packageRootPath: string): Promise<void> => {
				const report = await checkBridgeWebArchitecture({ packageRootPath });

				expect(report.ok).toBe(false);
				expect(report.violations).toHaveLength(3);
				expect(report.violations).toEqual(
					expect.arrayContaining([
						expect.objectContaining({
							ruleId: 'worker-boundary',
							relativePath: 'src/core/comm-worker/bridge-comm-worker-client.ts',
							message: expect.stringContaining('Worker construction'),
						}),
						expect.objectContaining({
							ruleId: 'worker-boundary',
							relativePath: 'src/core/comm-worker/unowned-message-boundary.ts',
							message: expect.stringContaining('postMessage usage'),
						}),
						expect.objectContaining({
							ruleId: 'worker-boundary',
							relativePath: 'src/app/diagnostics/unowned-diagnostic-message-boundary.ts',
							message: expect.stringContaining('postMessage usage'),
						}),
					]),
				);
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
				'src/file-viewer/bridge-file-viewer-shell.tsx': `
					import { createMarkdownExit } from 'markdown-exit';
					import { codeToHtml } from 'shiki';
					export const values = [createMarkdownExit, codeToHtml];
				`,
				'src/app/markdown/worker/bridge-markdown-render-worker-client.ts': `
					import { createMarkdownExit } from 'markdown-exit';
					export const value = createMarkdownExit;
				`,
				'src/app/markdown/worker/bridge-markdown-render-worker-renderer.ts': `
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
						relativePath: 'src/app/markdown/worker/bridge-markdown-render-worker-client.ts',
					}),
					expect.objectContaining({
						ruleId: 'markdown-render-worker-boundary',
						relativePath: 'src/file-viewer/bridge-file-viewer-shell.tsx',
					}),
					expect.objectContaining({
						ruleId: 'markdown-render-worker-boundary',
						relativePath: 'src/file-viewer/bridge-file-viewer-shell.tsx',
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

function generatedLineSource(lineCount: number): string {
	return Array.from(
		{ length: lineCount },
		(_value: undefined, index: number): string => `export const value${index} = ${index};`,
	).join('\n');
}
