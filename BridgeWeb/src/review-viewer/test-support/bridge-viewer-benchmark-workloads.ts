import { createHash } from 'node:crypto';

import { makeBridgeReviewPackage } from '../../foundation/review-package/bridge-review-package-test-support.js';
import type {
	BridgeContentHandle,
	BridgeFileChangeKind,
	BridgeFileClass,
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package.js';
import type { BridgeReviewProjectionWorkloadId } from '../models/review-projection-models.js';

export interface BridgeViewerBenchmarkWorkload {
	readonly workloadId: BridgeReviewProjectionWorkloadId;
	readonly reviewPackage: BridgeReviewPackage;
	readonly treePaths: readonly string[];
	readonly metadata: BridgeViewerBenchmarkWorkloadMetadata;
	readonly largeDiff?: BridgeViewerLargeDiffWorkload;
	readonly largeMarkdown?: BridgeViewerLargeMarkdownWorkload;
}

export interface BridgeViewerBenchmarkWorkloadMetadata {
	readonly expectedDiffRows: number;
	readonly expectedItemCount: number;
	readonly expectedPathCount: number;
	readonly fixtureClass: 'medium_review' | 'large_tree' | 'large_diff';
}

export interface BridgeViewerLargeDiffWorkload {
	readonly baseText: string;
	readonly headText: string;
	readonly contentChecksum: string;
	readonly lineCount: number;
}

export interface BridgeViewerLargeMarkdownWorkload {
	readonly markdownText: string;
	readonly contentChecksum: string;
	readonly fencedBlockCount: number;
	readonly lineCount: number;
}

const fileClasses: readonly BridgeFileClass[] = [
	'source',
	'test',
	'docs',
	'generated',
	'binary',
	'large',
	'config',
];
const changeKinds: readonly BridgeFileChangeKind[] = [
	'added',
	'modified',
	'deleted',
	'renamed',
	'copied',
];

export function makeBridgeViewerBenchmarkWorkload(
	workloadId: BridgeReviewProjectionWorkloadId,
): BridgeViewerBenchmarkWorkload {
	switch (workloadId) {
		case 'bridge_viewer_medium_review_v1':
			return makeMediumReviewWorkload();
		case 'bridge_viewer_large_tree_v1':
			return makeLargeTreeWorkload();
		case 'bridge_viewer_large_diff_scroll_v1':
			return makeLargeDiffScrollWorkload();
		case 'interactive':
			return makeMediumReviewWorkload();
	}
	return assertNever(workloadId);
}

function makeMediumReviewWorkload(): BridgeViewerBenchmarkWorkload {
	const itemCount = 1_000;
	const treePaths = Array.from({ length: itemCount }, (_value: unknown, index: number): string =>
		pathForIndex(index),
	);
	return {
		workloadId: 'bridge_viewer_medium_review_v1',
		reviewPackage: makeReviewPackage({
			packageId: 'bridge-viewer-medium-review-v1',
			reviewGeneration: 338,
			revision: 1,
			treePaths,
		}),
		treePaths,
		metadata: {
			expectedDiffRows: 0,
			expectedItemCount: itemCount,
			expectedPathCount: itemCount,
			fixtureClass: 'medium_review',
		},
	};
}

function makeLargeTreeWorkload(): BridgeViewerBenchmarkWorkload {
	const itemCount = 90_000;
	const treePaths = Array.from({ length: itemCount }, (_value: unknown, index: number): string =>
		pathForIndex(index),
	);
	return {
		workloadId: 'bridge_viewer_large_tree_v1',
		reviewPackage: makeReviewPackage({
			packageId: 'bridge-viewer-large-tree-v1',
			reviewGeneration: 338,
			revision: 1,
			treePaths,
		}),
		treePaths,
		metadata: {
			expectedDiffRows: 0,
			expectedItemCount: itemCount,
			expectedPathCount: itemCount,
			fixtureClass: 'large_tree',
		},
	};
}

function makeLargeDiffScrollWorkload(): BridgeViewerBenchmarkWorkload {
	const itemCount = 25;
	const lineCount = 100_000;
	const treePaths = Array.from(
		{ length: itemCount },
		(_value: unknown, index: number): string =>
			`packages/render/src/large-diff-${index.toString().padStart(3, '0')}.ts`,
	);
	const baseText = largeDiffText('base', lineCount);
	const headText = largeDiffText('head', lineCount);
	const largeMarkdown = largeMarkdownText();
	const contentChecksum = createHash('sha256')
		.update(baseText)
		.update('\n')
		.update(headText)
		.update('\n')
		.update(largeMarkdown)
		.digest('hex');

	return {
		workloadId: 'bridge_viewer_large_diff_scroll_v1',
		reviewPackage: makeReviewPackage({
			packageId: 'bridge-viewer-large-diff-scroll-v1',
			reviewGeneration: 338,
			revision: 1,
			treePaths,
			sizeBytes: baseText.length + headText.length,
		}),
		treePaths,
		metadata: {
			expectedDiffRows: lineCount,
			expectedItemCount: itemCount,
			expectedPathCount: itemCount,
			fixtureClass: 'large_diff',
		},
		largeDiff: {
			baseText,
			headText,
			contentChecksum,
			lineCount,
		},
		largeMarkdown: {
			markdownText: largeMarkdown,
			contentChecksum: createHash('sha256').update(largeMarkdown).digest('hex'),
			fencedBlockCount: 64,
			lineCount: countLines(largeMarkdown),
		},
	};
}

interface MakeReviewPackageProps {
	readonly packageId: string;
	readonly reviewGeneration: number;
	readonly revision: number;
	readonly treePaths: readonly string[];
	readonly sizeBytes?: number;
}

function makeReviewPackage(props: MakeReviewPackageProps): BridgeReviewPackage {
	const basePackage = makeBridgeReviewPackage();
	const orderedItemIds = props.treePaths.map(
		(_path: string, index: number): string => `benchmark-item-${index.toString().padStart(5, '0')}`,
	);
	const itemsById = Object.fromEntries(
		props.treePaths.map((path: string, index: number): [string, BridgeReviewItemDescriptor] => {
			const itemId = orderedItemIds[index];
			if (itemId === undefined) {
				throw new Error(`Missing benchmark item id for path index ${index}`);
			}
			return [
				itemId,
				makeReviewItem({
					index,
					itemId,
					path,
					reviewGeneration: props.reviewGeneration,
					sizeBytes: props.sizeBytes ?? 512 + (index % 8_192),
				}),
			];
		}),
	);
	return {
		...basePackage,
		packageId: props.packageId,
		reviewGeneration: props.reviewGeneration,
		revision: props.revision,
		orderedItemIds,
		itemsById,
		summary: {
			filesChanged: orderedItemIds.length,
			additions: orderedItemIds.length * 3,
			deletions: orderedItemIds.length,
			visibleFileCount: orderedItemIds.length,
			hiddenFileCount: 0,
		},
		filterState: {
			...basePackage.filterState,
			showBinaryFiles: true,
			showLargeFiles: true,
		},
		generatedAtUnixMilliseconds: 1_781_555_000_000,
	};
}

interface MakeReviewItemProps {
	readonly index: number;
	readonly itemId: string;
	readonly path: string;
	readonly reviewGeneration: number;
	readonly sizeBytes: number;
}

function makeReviewItem(props: MakeReviewItemProps): BridgeReviewItemDescriptor {
	const fileClass = fileClasses[props.index % fileClasses.length] ?? 'unknown';
	const changeKind = changeKinds[props.index % changeKinds.length] ?? 'modified';
	const language = languageForPath(props.path, fileClass);
	const extension = extensionForPath(props.path);
	const base =
		changeKind === 'added' ? null : makeContentHandle(props, 'base', language, fileClass);
	const head =
		changeKind === 'deleted' ? null : makeContentHandle(props, 'head', language, fileClass);
	return {
		itemId: props.itemId,
		itemKind: 'diff',
		itemVersion: 1,
		basePath: changeKind === 'added' ? null : props.path,
		headPath: changeKind === 'deleted' ? null : props.path,
		changeKind,
		fileClass,
		language,
		extension,
		sizeBytes: props.sizeBytes,
		baseContentHash: base?.contentHash ?? null,
		headContentHash: head?.contentHash ?? null,
		contentHashAlgorithm: 'sha256',
		additions: 3 + (props.index % 17),
		deletions: 1 + (props.index % 11),
		isHiddenByDefault: fileClass === 'generated' || fileClass === 'binary',
		hiddenReason:
			fileClass === 'generated' || fileClass === 'binary' ? `benchmark-${fileClass}` : null,
		reviewPriority: props.index % 13 === 0 ? 'high' : props.index % 7 === 0 ? 'low' : 'normal',
		contentRoles: { base, head, diff: null, file: null },
		cacheKey: `${base?.cacheKey ?? 'none'}|${head?.cacheKey ?? 'none'}`,
		provenance: {
			paneIds: [`pane-${props.index % 4}`],
			agentSessionIds: [`session-${props.index % 8}`],
			promptIds: [`prompt-${props.index % 16}`],
			operationIds: [`operation-${props.index % 32}`],
			sourceKinds: ['benchmark'],
		},
		annotationSummary: {
			threadCount: props.index % 5,
			unresolvedThreadCount: props.index % 3,
			commentCount: props.index % 7,
		},
		reviewState: props.index % 19 === 0 ? 'viewed' : 'unreviewed',
		collapsed: false,
	};
}

function makeContentHandle(
	props: MakeReviewItemProps,
	role: 'base' | 'head',
	language: string | null,
	fileClass: BridgeFileClass,
): BridgeContentHandle {
	const handleId = `benchmark-${props.itemId}-${role}`;
	return {
		handleId,
		itemId: props.itemId,
		role,
		endpointId: role === 'base' ? 'endpoint-base' : 'endpoint-head',
		reviewGeneration: props.reviewGeneration,
		contentHash: createHash('sha256').update(`${props.path}:${role}`).digest('hex'),
		contentHashAlgorithm: 'sha256',
		cacheKey: `${props.itemId}:${role}`,
		mimeType: mimeTypeForLanguage(language, fileClass),
		language,
		sizeBytes: props.sizeBytes,
		isBinary: fileClass === 'binary',
	};
}

function pathForIndex(index: number): string {
	const fileNumber = index.toString().padStart(5, '0');
	if (index < 30_000) {
		return `apps/app-${Math.floor(index / 1_000)
			.toString()
			.padStart(
				3,
				'0',
			)}/src/module-${(index % 1_000).toString().padStart(3, '0')}/file-${fileNumber}.ts`;
	}
	if (index < 45_000) {
		return `docs/plans/area-${Math.floor((index - 30_000) / 500)
			.toString()
			.padStart(3, '0')}/plan-${fileNumber}.md`;
	}
	if (index < 60_000) {
		return `packages/pkg-${Math.floor((index - 45_000) / 500)
			.toString()
			.padStart(3, '0')}/Tests/File${fileNumber}Tests.swift`;
	}
	if (index < 80_000) {
		return `packages/pkg-${Math.floor((index - 60_000) / 500)
			.toString()
			.padStart(3, '0')}/Sources/File${fileNumber}.swift`;
	}
	return `vendor/generated/pkg-${Math.floor((index - 80_000) / 112)
		.toString()
		.padStart(3, '0')}/file-${fileNumber}.ts`;
}

function extensionForPath(path: string): string | null {
	const match = /\.([^./]+)$/u.exec(path);
	return match?.[1] ?? null;
}

function languageForPath(path: string, fileClass: BridgeFileClass): string | null {
	if (fileClass === 'binary') {
		return null;
	}
	const extension = extensionForPath(path);
	switch (extension) {
		case null:
			return 'text';
		case 'md':
			return 'markdown';
		case 'swift':
			return 'swift';
		case 'ts':
		case 'tsx':
			return 'typescript';
		default:
			return 'text';
	}
}

function mimeTypeForLanguage(language: string | null, fileClass: BridgeFileClass): string {
	if (fileClass === 'binary') {
		return 'application/octet-stream';
	}
	switch (language) {
		case null:
			return 'text/plain';
		case 'markdown':
			return 'text/markdown';
		case 'swift':
			return 'text/x-swift';
		case 'typescript':
			return 'text/typescript';
		default:
			return 'text/plain';
	}
}

function largeDiffText(side: 'base' | 'head', lineCount: number): string {
	return Array.from({ length: lineCount }, (_value: unknown, index: number): string => {
		const paddedIndex = index.toString().padStart(6, '0');
		const value = side === 'base' ? index % 97 : (index + 3) % 101;
		return `export const ${side}Value${paddedIndex} = ${value};`;
	}).join('\n');
}

function largeMarkdownText(): string {
	return Array.from({ length: 64 }, (_value: unknown, sectionIndex: number): string => {
		const paddedSection = sectionIndex.toString().padStart(2, '0');
		const bodyLines = Array.from(
			{ length: 32 },
			(_bodyValue: unknown, lineIndex: number): string => {
				const paddedLine = lineIndex.toString().padStart(2, '0');
				return `- Review note ${paddedSection}.${paddedLine}: validate generated package behavior before approving.`;
			},
		).join('\n');
		const codeLines = Array.from(
			{ length: 48 },
			(_codeValue: unknown, lineIndex: number): string =>
				`export const benchmarkPlan${paddedSection}_${lineIndex.toString().padStart(2, '0')} = ${lineIndex + sectionIndex};`,
		).join('\n');
		return `## Plan Section ${paddedSection}\n\n${bodyLines}\n\n\`\`\`ts\n${codeLines}\n\`\`\``;
	}).join('\n\n');
}

function countLines(text: string): number {
	return text.length === 0 ? 0 : text.split('\n').length;
}

function assertNever(value: never): never {
	throw new Error(`Unhandled benchmark workload id: ${String(value)}`);
}
