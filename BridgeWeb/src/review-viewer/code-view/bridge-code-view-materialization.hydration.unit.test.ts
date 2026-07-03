import { describe, expect, expectTypeOf, test } from 'vitest';

import type { BridgeContentResource } from '../../foundation/content/content-resource-loader.js';
import { buildBridgeReviewProjection } from '../navigation/review-projection.js';
import { makeBridgeViewerProjectionFixture } from '../test-support/review-viewer-fixtures.js';
import { bridgePierreContentDescriptorFileSchema } from '../workers/pierre/bridge-pierre-worker-content-descriptor.js';
import {
	createBridgeCodeViewInitialItems,
	materializeBridgeCodeViewItem,
	type BridgeCodeViewDiffItem,
	type BridgeCodeViewItem,
} from './bridge-code-view-materialization.js';

describe('Bridge CodeView hydrated materialization', () => {
	test('keeps full text for descriptor probe requests before worker fetch is proven', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const item = reviewPackage.itemsById['source-high'];
		const headHandle = item?.contentRoles.head;
		if (item === undefined || headHandle === null || headHandle === undefined) {
			throw new Error('expected source fixture with head handle');
		}

		const materialized = materializeBridgeCodeViewItem({
			item,
			presentation: { kind: 'file', version: 'head' },
			resources: {
				head: makeContentResource(headHandle, 'let value = 2\n'),
			},
		});

		if (materialized?.type !== 'file') {
			throw new Error('expected file materialization');
		}
		const parsedFile = bridgePierreContentDescriptorFileSchema.parse(materialized.file);
		expect(parsedFile.contents).toBe('let value = 2\n');
		expect(parsedFile.bridgeContentDescriptor).toMatchObject({
			contentHash: headHandle.contentHash,
			generation: headHandle.reviewGeneration,
			resourceUrl: headHandle.resourceUrl,
		});
	});

	test('keeps plaintext fallback content with descriptor metadata after worker fetch is proven', () => {
		const previousDocument = globalThis.document;
		Object.defineProperty(globalThis, 'document', {
			configurable: true,
			value: {
				documentElement: {
					dataset: {
						bridgePierreWorkerContentFetchProbeResult: 'success',
					},
				},
			},
		});
		try {
			const reviewPackage = makeBridgeViewerProjectionFixture();
			const item = reviewPackage.itemsById['source-high'];
			const headHandle = item?.contentRoles.head;
			if (item === undefined || headHandle === null || headHandle === undefined) {
				throw new Error('expected source fixture with head handle');
			}

			const materialized = materializeBridgeCodeViewItem({
				item: {
					...item,
					contentLineCountsByRole: {
						head: 2,
					},
				},
				presentation: { kind: 'file', version: 'head' },
				resources: {
					head: makeContentResource(headHandle, 'let value = 2\n'),
				},
			});

			if (materialized?.type !== 'file') {
				throw new Error('expected file materialization');
			}
			const parsedFile = bridgePierreContentDescriptorFileSchema.parse(materialized.file);
			expect(parsedFile.contents).toBe('let value = 2\n');
			expect(parsedFile.bridgeContentDescriptor).toMatchObject({
				contentHash: headHandle.contentHash,
				generation: headHandle.reviewGeneration,
				resourceUrl: headHandle.resourceUrl,
			});
		} finally {
			Object.defineProperty(globalThis, 'document', {
				configurable: true,
				value: previousDocument,
			});
		}
	});

	test('keeps plaintext JSON fallback content after descriptor fetch is proven', () => {
		const previousDocument = globalThis.document;
		Object.defineProperty(globalThis, 'document', {
			configurable: true,
			value: {
				documentElement: {
					dataset: {
						bridgePierreWorkerContentFetchProbeResult: 'success',
					},
				},
			},
		});
		try {
			const reviewPackage = makeBridgeViewerProjectionFixture();
			const item = reviewPackage.itemsById['source-high'];
			const headHandle = item?.contentRoles.head;
			if (item === undefined || headHandle === null || headHandle === undefined) {
				throw new Error('expected source fixture with head handle');
			}
			const jsonText = '{\n\t"scripts": {\n\t\t"test": "vitest run"\n\t}\n}\n';

			const materialized = materializeBridgeCodeViewItem({
				item: {
					...item,
					headPath: 'BridgeWeb/package.json',
					language: 'json',
					extension: 'json',
					contentLineCountsByRole: {
						head: 5,
					},
				},
				presentation: { kind: 'file', version: 'head' },
				resources: {
					head: makeContentResource(
						{
							...headHandle,
							language: 'json',
							mimeType: 'application/json',
							sizeBytes: jsonText.length,
						},
						jsonText,
					),
				},
			});

			if (materialized?.type !== 'file') {
				throw new Error('expected file materialization');
			}
			const parsedFile = bridgePierreContentDescriptorFileSchema.parse(materialized.file);
			expect(parsedFile.contents).toBe(jsonText);
			expect(parsedFile.lang).toBe('json');
			expect(parsedFile.bridgeContentDescriptor.resourceUrl).toBe(headHandle.resourceUrl);
		} finally {
			Object.defineProperty(globalThis, 'document', {
				configurable: true,
				value: previousDocument,
			});
		}
	});

	test('carries text language on deleted txt diffs so the empty head side cannot erase fallback rendering', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const item = reviewPackage.itemsById['deleted-source'];
		const baseHandle = item?.contentRoles.base;
		if (item === undefined || baseHandle === null || baseHandle === undefined) {
			throw new Error('expected deleted fixture with base handle');
		}

		const materialized = materializeBridgeCodeViewItem({
			item: {
				...item,
				basePath: '.agent_sidecar/firewall-allowlist-extra.repo.txt',
				fileClass: 'config',
				language: 'text',
				extension: 'txt',
			},
			resources: {
				base: makeContentResource(
					{
						...baseHandle,
						language: 'text',
						mimeType: 'text/plain',
					},
					'127.0.0.1\nlocalhost\n',
				),
			},
		});

		if (materialized?.type !== 'diff') {
			throw new Error('expected deleted text diff materialization');
		}
		expect(materialized.fileDiff.lang).toBe('text');
		expect(materialized.fileDiff.deletionLines).toEqual(['127.0.0.1\n', 'localhost\n']);
	});

	test('keeps a diff placeholder as a diff when only one role is loaded', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const item = reviewPackage.itemsById['docs-plan'];
		const headHandle = item?.contentRoles.head;
		if (item === undefined || headHandle === null || headHandle === undefined) {
			throw new Error('expected docs fixture with head handle');
		}

		const materialized = materializeBridgeCodeViewItem({
			item: { ...item, itemVersion: 7 },
			resources: {
				head: makeContentResource(headHandle, '# Plan\n\nText body.'),
			},
		});

		if (materialized?.type !== 'diff') {
			throw new Error('expected diff materialization');
		}

		expect(materialized).toMatchObject({
			id: 'docs-plan',
			type: 'diff',
			version: 23,
			fileDiff: {
				name: 'docs/plans/2026-bridge-plan.md',
				deletionLines: [],
				additionLines: expect.arrayContaining(['# Plan\n', '\n', 'Text body.']),
			},
			bridgeMetadata: {
				contentState: 'hydrated',
				contentRoles: ['head'],
				itemId: 'docs-plan',
			},
		});
		expectTypeOf(materialized).toMatchTypeOf<BridgeCodeViewDiffItem>();
	});

	test('keeps unloaded diff side extents when partially hydrating visible content', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const item = reviewPackage.itemsById['source-high'];
		const headHandle = item?.contentRoles.head;
		if (item === undefined || headHandle === null || headHandle === undefined) {
			throw new Error('expected source fixture with head handle');
		}

		const materialized = materializeBridgeCodeViewItem({
			item: {
				...item,
				contentLineCountsByRole: {
					base: 17,
					head: 19,
				},
			},
			resources: {
				head: makeContentResource(headHandle, 'let value = 2\n'),
			},
		});

		if (materialized?.type !== 'diff') {
			throw new Error('expected diff materialization');
		}

		expect(materialized.fileDiff.deletionLines).toContain('Loading content...\n');
		expect(materialized.fileDiff.deletionLines).toHaveLength(17);
		expect(materialized.fileDiff.additionLines).toContain('let value = 2\n');
		expect(materialized.bridgeMetadata).toMatchObject({
			contentState: 'hydrated',
			contentRoles: ['head'],
			itemId: 'source-high',
			lineCount: 19,
		});
	});

	test('uses a newer CodeView render version when hydrating generation zero', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const originalItem = reviewPackage.itemsById['source-high'];
		if (originalItem === undefined) {
			throw new Error('expected source fixture item');
		}
		const generationZeroPackage = {
			...reviewPackage,
			itemsById: {
				...reviewPackage.itemsById,
				'source-high': {
					...originalItem,
					itemVersion: 0,
				},
			},
		};
		const projection = buildBridgeReviewProjection({
			reviewPackage: generationZeroPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});
		const placeholder = createBridgeCodeViewInitialItems({
			reviewPackage: generationZeroPackage,
			projection,
		}).find((item: BridgeCodeViewItem): boolean => item.id === 'source-high');
		const item = generationZeroPackage.itemsById['source-high'];
		const baseHandle = item?.contentRoles.base;
		const headHandle = item?.contentRoles.head;
		if (
			placeholder === undefined ||
			item === undefined ||
			baseHandle === null ||
			baseHandle === undefined ||
			headHandle === null ||
			headHandle === undefined
		) {
			throw new Error('expected source fixture with base and head handles');
		}

		const materialized = materializeBridgeCodeViewItem({
			item: { ...item, itemVersion: 0 },
			resources: {
				base: makeContentResource(baseHandle, 'let value = 1\n'),
				head: makeContentResource(headHandle, 'let value = 2\n'),
			},
		});

		if (materialized?.type !== 'diff') {
			throw new Error('expected diff materialization');
		}
		if (placeholder.version === undefined || materialized.version === undefined) {
			throw new Error('expected CodeView render versions');
		}

		expect(placeholder.version).toBe(0);
		expect(materialized.version).toBe(2);
		expect(materialized.version).toBeGreaterThan(placeholder.version);
	});

	test('hydrates an added new file as a one-sided CodeView diff with full content', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const item = reviewPackage.itemsById['hidden-binary'];
		const headHandle = item?.contentRoles.head;
		if (item === undefined || headHandle === null || headHandle === undefined) {
			throw new Error('expected added fixture with head handle');
		}
		const sourceText = [
			'export function renderAddedFile(): string {',
			"\treturn 'new file content';",
			'}',
			'',
		].join('\n');

		const materialized = materializeBridgeCodeViewItem({
			item: {
				...item,
				headPath: 'Sources/NewFeature/AddedFile.ts',
				fileClass: 'source',
				extension: 'ts',
				language: 'typescript',
				isHiddenByDefault: false,
				hiddenReason: null,
			},
			resources: {
				head: makeContentResource(
					{
						...headHandle,
						isBinary: false,
						mimeType: 'text/typescript',
						language: 'typescript',
					},
					sourceText,
				),
			},
		});

		if (materialized?.type !== 'diff') {
			throw new Error('expected added diff materialization');
		}

		expect(materialized).toMatchObject({
			type: 'diff',
			fileDiff: {
				name: 'Sources/NewFeature/AddedFile.ts',
				deletionLines: [],
				additionLines: expect.arrayContaining([
					'export function renderAddedFile(): string {\n',
					"\treturn 'new file content';\n",
					'}\n',
				]),
			},
			bridgeMetadata: {
				contentState: 'hydrated',
				contentRoles: ['head'],
			},
		});
		expectTypeOf(materialized).toMatchTypeOf<BridgeCodeViewDiffItem>();
	});

	test('keeps an added file-target presentation as a one-sided diff so added backgrounds can render', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const item = reviewPackage.itemsById['hidden-binary'];
		const headHandle = item?.contentRoles.head;
		if (item === undefined || headHandle === null || headHandle === undefined) {
			throw new Error('expected added fixture with head handle');
		}
		const sourceText = [
			'export function renderAddedFile(): string {',
			"\treturn 'new file content';",
			'}',
			'',
		].join('\n');

		const materialized = materializeBridgeCodeViewItem({
			item: {
				...item,
				headPath: 'Sources/NewFeature/AddedFile.ts',
				fileClass: 'source',
				extension: 'ts',
				language: 'typescript',
				isHiddenByDefault: false,
				hiddenReason: null,
			},
			presentation: { kind: 'file', version: 'current' },
			resources: {
				head: makeContentResource(
					{
						...headHandle,
						isBinary: false,
						mimeType: 'text/typescript',
						language: 'typescript',
					},
					sourceText,
				),
			},
		});

		if (materialized?.type !== 'diff') {
			throw new Error('expected added file target to remain diff materialization');
		}

		expect(materialized.fileDiff.type).toBe('new');
		expect(materialized.fileDiff.hunks).toEqual([
			expect.objectContaining({
				additionLines: 3,
				deletionLines: 0,
				hunkContent: [
					expect.objectContaining({
						type: 'change',
						additions: 3,
						deletions: 0,
					}),
				],
			}),
		]);
		expect(materialized.fileDiff.additionLines).toEqual([
			'export function renderAddedFile(): string {\n',
			"\treturn 'new file content';\n",
			'}\n',
		]);
	});

	test('hydrates a modified item as a diff when base and head roles are loaded', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const item = reviewPackage.itemsById['source-high'];
		const baseHandle = item?.contentRoles.base;
		const headHandle = item?.contentRoles.head;
		if (
			item === undefined ||
			baseHandle === null ||
			baseHandle === undefined ||
			headHandle === null ||
			headHandle === undefined
		) {
			throw new Error('expected source fixture with base and head handles');
		}

		const materialized = materializeBridgeCodeViewItem({
			item: { ...item, itemVersion: 9 },
			resources: {
				base: makeContentResource(baseHandle, 'let value = 1\n'),
				head: makeContentResource(headHandle, 'let value = 2\n'),
			},
		});

		if (materialized?.type !== 'diff') {
			throw new Error('expected diff materialization');
		}

		expect(materialized.fileDiff.name).toBe('Sources/App/Core.swift');
		expect(materialized.version).toBe(29);
		expect(materialized.fileDiff.deletionLines).toContain('let value = 1\n');
		expect(materialized.fileDiff.additionLines).toContain('let value = 2\n');
		expect(materialized.bridgeMetadata).toMatchObject({
			contentState: 'hydrated',
			contentRoles: ['base', 'head'],
			itemId: 'source-high',
		});
		expectTypeOf(materialized).toMatchTypeOf<BridgeCodeViewDiffItem>();
	});

	test('bounds oversized diff body materialization while keeping selected content visible', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const item = reviewPackage.itemsById['source-high'];
		const baseHandle = item?.contentRoles.base;
		const headHandle = item?.contentRoles.head;
		if (
			item === undefined ||
			baseHandle === null ||
			baseHandle === undefined ||
			headHandle === null ||
			headHandle === undefined
		) {
			throw new Error('expected source fixture with base and head handles');
		}
		const baseText = makeGeneratedLines('base', 50_000);
		const headText = makeGeneratedLines('head', 50_000);

		const materialized = materializeBridgeCodeViewItem({
			item: {
				...item,
				additions: 50_000,
				deletions: 50_000,
				itemVersion: 12,
			},
			resources: {
				base: makeContentResource({ ...baseHandle, sizeBytes: baseText.length }, baseText),
				head: makeContentResource({ ...headHandle, sizeBytes: headText.length }, headText),
			},
		});

		if (materialized?.type !== 'diff') {
			throw new Error('expected oversized content to remain a diff item');
		}

		expect(materialized.bridgeMetadata.contentState).toBe('windowed');
		expect(materialized.bridgeMetadata.cacheKey).toContain(':window:1500');
		expect(materialized.fileDiff.additionLines).toContain(
			"export const generatedLine0000 = 'head';\n",
		);
		expect(materialized.fileDiff.additionLines).not.toContain(
			"export const generatedLine5000 = 'head';\n",
		);
		expect(materialized.fileDiff.additionLines.length).toBeLessThan(3_000);
		expectTypeOf(materialized).toMatchTypeOf<BridgeCodeViewDiffItem>();
	});

	test('renders a review file target as a Pierre file item from the requested head version', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const item = reviewPackage.itemsById['source-high'];
		const baseHandle = item?.contentRoles.base;
		const headHandle = item?.contentRoles.head;
		if (
			item === undefined ||
			baseHandle === null ||
			baseHandle === undefined ||
			headHandle === null ||
			headHandle === undefined
		) {
			throw new Error('expected source fixture with base and head handles');
		}

		const itemWithStreamedLineCounts = {
			...item,
			contentLineCountsByRole: {
				head: 37,
			},
		};
		const materialized = materializeBridgeCodeViewItem({
			item: { ...itemWithStreamedLineCounts, itemVersion: 11 },
			presentation: { kind: 'file', version: 'current' },
			resources: {
				base: makeContentResource(baseHandle, 'let value = 1\n'),
				head: makeContentResource(headHandle, 'let value = 2\n'),
			},
		});

		if (materialized?.type !== 'file') {
			throw new Error('expected file presentation materialization');
		}

		expect(materialized).toMatchObject({
			id: 'source-high',
			type: 'file',
			version: 35,
			file: {
				name: 'Sources/App/Core.swift',
				contents: 'let value = 2\n',
				cacheKey: headHandle.cacheKey,
			},
			bridgeMetadata: {
				contentState: 'hydrated',
				contentRoles: ['head'],
				itemId: 'source-high',
				lineCount: 37,
			},
		});
	});

	test('renders a review file target as a Pierre file item from the requested base version', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const item = reviewPackage.itemsById['source-high'];
		const baseHandle = item?.contentRoles.base;
		const headHandle = item?.contentRoles.head;
		if (
			item === undefined ||
			baseHandle === null ||
			baseHandle === undefined ||
			headHandle === null ||
			headHandle === undefined
		) {
			throw new Error('expected source fixture with base and head handles');
		}

		const materialized = materializeBridgeCodeViewItem({
			item,
			presentation: { kind: 'file', version: 'base' },
			resources: {
				base: makeContentResource(baseHandle, 'let value = 1\n'),
				head: makeContentResource(headHandle, 'let value = 2\n'),
			},
		});

		if (materialized?.type !== 'file') {
			throw new Error('expected file presentation materialization');
		}

		expect(materialized.file.contents).toBe('let value = 1\n');
		expect(materialized.bridgeMetadata.contentRoles).toEqual(['base']);
	});
});

function makeContentResource(
	handle: BridgeContentResource['handle'],
	text: string,
): BridgeContentResource {
	return { handle, readText: (): string => text };
}

function makeGeneratedLines(label: 'base' | 'head', lineCount: number): string {
	return Array.from({ length: lineCount }, (_value: unknown, index: number): string => {
		const paddedIndex = index.toString().padStart(4, '0');
		return `export const generatedLine${paddedIndex} = '${label}';`;
	}).join('\n');
}
