import type { RenderFileResult } from '@pierre/diffs';
import { WorkerPoolManager, type FileRendererInstance } from '@pierre/diffs/worker';
import { afterEach, describe, expect, test, vi } from 'vitest';

import {
	bridgePierreContentDescriptorFileSchema,
	createBridgePierreContentDescriptorFile,
	replaceBridgePierreContentDescriptorFileContents,
} from './bridge-pierre-worker-content-descriptor.js';

describe('Bridge Pierre worker content descriptor files', () => {
	afterEach(() => {
		vi.unstubAllGlobals();
	});

	test('round trips a descriptor-backed file request with only line skeleton content on the main side', () => {
		const file = createBridgePierreContentDescriptorFile({
			cacheKey: 'item-source:head',
			contentHash: 'sha256:abc123',
			contentHashAlgorithm: 'sha256',
			generation: 7,
			lineCount: 3,
			maxBytes: 2048,
			name: 'Sources/Example.swift',
			resourceUrl:
				'agentstudio://resource/review/content/handle-item-source-head?generation=7&revision=2',
		});

		const parsedFile = bridgePierreContentDescriptorFileSchema.parse(file);
		const hydratedFile = replaceBridgePierreContentDescriptorFileContents({
			file,
			text: 'struct Example {}\nlet value = 1\n',
		});

		expect(parsedFile.contents).toBe('\n\n\n');
		expect(parsedFile.bridgeContentDescriptor).toEqual({
			contentHash: 'sha256:abc123',
			contentHashAlgorithm: 'sha256',
			generation: 7,
			maxBytes: 2048,
			resourceUrl:
				'agentstudio://resource/review/content/handle-item-source-head?generation=7&revision=2',
		});
		expect(hydratedFile).toEqual({
			cacheKey: 'pierre-content:sha256:sha256:abc123',
			contents: 'struct Example {}\nlet value = 1\n',
			name: 'Sources/Example.swift',
		});
	});

	test('normalizes unsupported descriptor languages to plaintext before Pierre highlighting', () => {
		const file = createBridgePierreContentDescriptorFile({
			cacheKey: 'item-gitignore:head',
			contentHash: 'sha256:def456',
			contentHashAlgorithm: 'sha256',
			generation: 9,
			lang: 'gitignore',
			lineCount: 2,
			maxBytes: 1024,
			name: '.gitignore',
			resourceUrl:
				'agentstudio://resource/review/content/handle-item-gitignore-head?generation=9&revision=1',
		});

		expect(file.lang).toBe('text');
	});

	test('preserves supported descriptor languages used by modified review files', () => {
		expect(
			createBridgePierreContentDescriptorFile({
				cacheKey: 'item-package-json:head',
				contentHash: 'sha256:json',
				contentHashAlgorithm: 'sha256',
				generation: 1,
				lang: 'json',
				lineCount: 1,
				maxBytes: 1024,
				name: 'package.json',
				resourceUrl:
					'agentstudio://resource/review/content/handle-item-package-json-head?generation=1',
			}).lang,
		).toBe('json');
		expect(
			createBridgePierreContentDescriptorFile({
				cacheKey: 'item-release-yml:head',
				contentHash: 'sha256:yml',
				contentHashAlgorithm: 'sha256',
				generation: 1,
				lang: 'yml',
				lineCount: 1,
				maxBytes: 1024,
				name: '.github/workflows/release.yml',
				resourceUrl:
					'agentstudio://resource/review/content/handle-item-release-yml-head?generation=1',
			}).lang,
		).toBe('yml');
		expect(
			createBridgePierreContentDescriptorFile({
				cacheKey: 'item-mise-toml:head',
				contentHash: 'sha256:toml',
				contentHashAlgorithm: 'sha256',
				generation: 1,
				lang: 'toml',
				lineCount: 1,
				maxBytes: 1024,
				name: '.mise.toml',
				resourceUrl:
					'agentstudio://resource/review/content/handle-item-mise-toml-head?generation=1',
			}).lang,
		).toBe('toml');
	});

	test('uses content-addressed cache keys so metadata-only retouches hit Pierre manager cache', () => {
		vi.stubGlobal('requestAnimationFrame', (callback: FrameRequestCallback): number => {
			callback(0);
			return 1;
		});
		vi.stubGlobal('cancelAnimationFrame', (_frameId: number): void => {});
		const initialFile = createBridgePierreContentDescriptorFile({
			cacheKey: 'item-source:head:generation-7:revision-2',
			contentHash: 'sha256:abc123',
			contentHashAlgorithm: 'sha256',
			generation: 7,
			lineCount: 3,
			maxBytes: 2048,
			name: 'Sources/Example.swift',
			resourceUrl:
				'agentstudio://resource/review/content/handle-item-source-head?generation=7&revision=2',
		});
		const retouchedFile = createBridgePierreContentDescriptorFile({
			cacheKey: 'item-source:head:generation-7:revision-3',
			contentHash: 'sha256:abc123',
			contentHashAlgorithm: 'sha256',
			generation: 7,
			lineCount: 3,
			maxBytes: 2048,
			name: 'Sources/Example.swift',
			resourceUrl:
				'agentstudio://resource/review/content/handle-item-source-head?generation=7&revision=3',
		});
		const workerPoolManager = new WorkerPoolManager(
			{
				poolSize: 0,
				totalASTLRUCacheSize: 4,
				workerFactory: (): Worker => {
					throw new Error('worker should not be constructed for cache lookup test');
				},
			},
			{},
		);
		const cachedRenderResult = {
			result: { code: [], themeStyles: '', baseThemeType: undefined },
			options: workerPoolManager.getFileRenderOptions(),
		} satisfies RenderFileResult;

		workerPoolManager.inspectCaches().fileCache.set(initialFile.cacheKey, cachedRenderResult);

		expect(initialFile.cacheKey).toBe('pierre-content:sha256:sha256:abc123');
		expect(retouchedFile.cacheKey).toBe(initialFile.cacheKey);
		expect(workerPoolManager.getFileResultCache(retouchedFile)).toBe(cachedRenderResult);
		expect(workerPoolManager.getStats().fileCacheSize).toBe(1);
	});

	test('rehighlights descriptor content after the Pierre AST LRU evicts its cache entry', () => {
		vi.stubGlobal('requestAnimationFrame', (callback: FrameRequestCallback): number => {
			callback(0);
			return 1;
		});
		vi.stubGlobal('cancelAnimationFrame', (_frameId: number): void => {});
		const firstFile = createBridgePierreContentDescriptorFile({
			cacheKey: 'item-source-a:head:generation-7:revision-2',
			contentHash: 'sha256:first-content',
			contentHashAlgorithm: 'sha256',
			generation: 7,
			lineCount: 3,
			maxBytes: 2048,
			name: 'Sources/First.swift',
			resourceUrl:
				'agentstudio://resource/review/content/handle-item-source-a-head?generation=7&revision=2',
		});
		const secondFile = createBridgePierreContentDescriptorFile({
			cacheKey: 'item-source-b:head:generation-7:revision-2',
			contentHash: 'sha256:second-content',
			contentHashAlgorithm: 'sha256',
			generation: 7,
			lineCount: 3,
			maxBytes: 2048,
			name: 'Sources/Second.swift',
			resourceUrl:
				'agentstudio://resource/review/content/handle-item-source-b-head?generation=7&revision=2',
		});
		const workerPoolManager = new WorkerPoolManager(
			{
				poolSize: 0,
				totalASTLRUCacheSize: 1,
				workerFactory: (): Worker => {
					throw new Error('worker should not be constructed for cache eviction test');
				},
			},
			{},
		);
		const highlightSpy = vi.spyOn(workerPoolManager, 'highlightFileAST');
		const firstRendererInstance = makeFileRendererInstance('first-renderer');

		workerPoolManager.highlightFileAST(firstRendererInstance, firstFile);
		expect(highlightSpy).toHaveBeenCalledTimes(1);
		expect(workerPoolManager.getStats().queuedTasks).toBe(1);

		workerPoolManager.cleanUpTasks(firstRendererInstance);
		workerPoolManager
			.inspectCaches()
			.fileCache.set(firstFile.cacheKey, cachedRenderFileResultFor(workerPoolManager));
		workerPoolManager
			.inspectCaches()
			.fileCache.set(secondFile.cacheKey, cachedRenderFileResultFor(workerPoolManager));

		expect(workerPoolManager.getStats().fileCacheSize).toBe(1);
		expect(workerPoolManager.getFileResultCache(firstFile)).toBeUndefined();
		expect(workerPoolManager.getFileResultCache(secondFile)).toBeDefined();

		workerPoolManager.highlightFileAST(makeFileRendererInstance('first-renderer-again'), firstFile);

		expect(highlightSpy).toHaveBeenCalledTimes(2);
		expect(workerPoolManager.getStats()).toMatchObject({
			fileCacheSize: 1,
			queuedTasks: 1,
		});
	});
});

function makeFileRendererInstance(id: string): FileRendererInstance {
	return {
		__id: id,
		onHighlightSuccess: (): void => {},
		onHighlightError: (): void => {},
	};
}

function cachedRenderFileResultFor(workerPoolManager: WorkerPoolManager): RenderFileResult {
	return {
		result: { code: [], themeStyles: '', baseThemeType: undefined },
		options: workerPoolManager.getFileRenderOptions(),
	};
}
