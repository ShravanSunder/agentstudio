import { createHash } from 'node:crypto';
import { extname } from 'node:path';

import type { ReviewMetadataSnapshotFrame } from '../../src/features/review/models/review-protocol-models.js';
import type { ReviewMetadataWindowFrame } from '../../src/features/review/models/review-protocol-models.js';
import {
	buildReviewMetadataSnapshotFrame,
	buildReviewMetadataWindowFrame,
} from '../../src/features/review/protocol/review-metadata-frame-builder.js';
import { bridgeReviewPackageSchema } from '../../src/foundation/review-package/bridge-review-package-schema.js';
import type {
	BridgeContentHandle,
	BridgeFileClass,
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../../src/foundation/review-package/bridge-review-package.js';
import {
	loadBridgeWorktreeDevSnapshot,
	type BridgeWorktreeChangedFile,
	type BridgeWorktreeDevProviderConfig,
} from './bridge-worktree-dev-provider.js';

export interface BridgeWorktreeReviewDevSnapshot {
	readonly changedFiles: readonly BridgeWorktreeChangedFile[];
	readonly fingerprint: string;
}

export interface CreateBridgeWorktreeReviewDevMetadataProps {
	readonly baseRef: string;
	readonly snapshot: BridgeWorktreeReviewDevSnapshot;
	readonly paneId: string;
	readonly streamId: string;
}

export interface BridgeWorktreeReviewDevMetadataResult {
	readonly contentByHandleId: ReadonlyMap<string, string>;
	readonly metadataFrame: ReviewMetadataSnapshotFrame;
	readonly metadataWindowFrames: readonly ReviewMetadataWindowFrame[];
	readonly reviewMetadataSource: BridgeReviewPackage;
}

export interface BridgeWorktreeReviewContentRequest {
	readonly generation: number;
	readonly handleId: string;
	readonly packageId: string;
	readonly revision: number;
}

export interface BridgeWorktreeReviewMetadataRequest {
	readonly forceRefresh?: boolean;
}

export interface BridgeWorktreeReviewDevProvider {
	readonly loadReviewContent: (request: BridgeWorktreeReviewContentRequest) => Promise<string>;
	readonly loadReviewMetadata: (
		request?: BridgeWorktreeReviewMetadataRequest,
	) => Promise<BridgeWorktreeReviewDevMetadataResult>;
}

export interface CreateBridgeWorktreeReviewDevProviderOptions {
	readonly loadSnapshot?: (props: {
		readonly baseRef: string;
		readonly worktreeRoot: string;
	}) => Promise<BridgeWorktreeReviewDevSnapshot>;
}

const worktreeReviewGeneration = 1;
const worktreeReviewRevision = 1;
const worktreeReviewRepoId = 'dev-worktree-repo';
const worktreeReviewWorktreeId = 'dev-worktree';
const worktreeReviewBaseEndpointId = 'baseline-local-default';
const worktreeReviewHeadEndpointId = 'working-tree';
const worktreeReviewMetadataWindowSize = 80;

export function createBridgeWorktreeReviewDevProvider(
	config: BridgeWorktreeDevProviderConfig,
	options: CreateBridgeWorktreeReviewDevProviderOptions = {},
): BridgeWorktreeReviewDevProvider {
	const loadSnapshot = options.loadSnapshot ?? loadBridgeWorktreeDevSnapshot;
	const metadataResultsByPackageId = new Map<string, BridgeWorktreeReviewDevMetadataResult>();
	let currentMetadataResult: BridgeWorktreeReviewDevMetadataResult | null = null;
	const loadReviewMetadata = async (
		request: BridgeWorktreeReviewMetadataRequest = {},
	): Promise<BridgeWorktreeReviewDevMetadataResult> => {
		if (currentMetadataResult !== null && request.forceRefresh !== true) {
			return currentMetadataResult;
		}
		currentMetadataResult = await createReviewMetadataResult({
			baseRef: config.baseRef,
			loadSnapshot,
			metadataResultsByPackageId,
			paneId: 'bridge-worktree-review-dev-pane',
			streamId: 'review:bridge-worktree-review-dev-pane',
			worktreeRoot: config.worktreeRoot,
		});
		return currentMetadataResult;
	};
	return {
		loadReviewMetadata,
		loadReviewContent: async (request: BridgeWorktreeReviewContentRequest): Promise<string> => {
			let metadataResult = metadataResultsByPackageId.get(request.packageId);
			if (metadataResult === undefined) {
				metadataResult = await loadReviewMetadata();
			}
			if (
				metadataResult.metadataFrame.comparison.packageId !== request.packageId ||
				metadataResult.metadataFrame.comparison.generation !== request.generation ||
				metadataResult.metadataFrame.comparison.revision !== request.revision
			) {
				throw new Error(
					`Bridge worktree review content request does not match loaded metadata: ${request.packageId}`,
				);
			}
			const content = metadataResult.contentByHandleId.get(request.handleId);
			if (content === undefined) {
				throw new Error(`Unknown Bridge worktree review content handle: ${request.handleId}`);
			}
			return content;
		},
	};
}

async function createReviewMetadataResult(props: {
	readonly baseRef: string;
	readonly loadSnapshot: NonNullable<CreateBridgeWorktreeReviewDevProviderOptions['loadSnapshot']>;
	readonly metadataResultsByPackageId: Map<string, BridgeWorktreeReviewDevMetadataResult>;
	readonly paneId: string;
	readonly streamId: string;
	readonly worktreeRoot: string;
}): Promise<BridgeWorktreeReviewDevMetadataResult> {
	const snapshot = await props.loadSnapshot({
		baseRef: props.baseRef,
		worktreeRoot: props.worktreeRoot,
	});
	const result = createBridgeWorktreeReviewDevMetadata({
		baseRef: props.baseRef,
		paneId: props.paneId,
		snapshot,
		streamId: props.streamId,
	});
	props.metadataResultsByPackageId.set(result.metadataFrame.comparison.packageId, result);
	return result;
}

export function createBridgeWorktreeReviewDevMetadata(
	props: CreateBridgeWorktreeReviewDevMetadataProps,
): BridgeWorktreeReviewDevMetadataResult {
	const packageId = `worktree-review-${props.snapshot.fingerprint.slice(0, 12)}`;
	const contentByHandleId = new Map<string, string>();
	const items = props.snapshot.changedFiles.map(
		(changedFile): BridgeReviewItemDescriptor =>
			reviewItemForChangedFile({
				changedFile,
				contentByHandleId,
				packageId,
			}),
	);
	assertUniqueItemIds(items);
	const itemsById = Object.fromEntries(
		items.map((item): readonly [string, BridgeReviewItemDescriptor] => [item.itemId, item]),
	);
	const reviewPackage = bridgeReviewPackageSchema.parse({
		packageId,
		schemaVersion: 1,
		reviewGeneration: worktreeReviewGeneration,
		revision: worktreeReviewRevision,
		query: {
			queryId: 'dev-current-worktree-review',
			queryKind: 'compare',
			repoId: worktreeReviewRepoId,
			worktreeId: worktreeReviewWorktreeId,
			baseEndpointId: worktreeReviewBaseEndpointId,
			headEndpointId: worktreeReviewHeadEndpointId,
			comparisonSemantics: 'workingTreeDelta',
			pathScope: [],
			fileTarget: null,
			viewFilter: emptyReviewViewFilter(),
			grouping: { kind: 'flat', label: null },
			provenanceFilter: emptyReviewProvenanceFilter(),
		},
		baseEndpoint: {
			endpointId: worktreeReviewBaseEndpointId,
			kind: 'gitRef',
			repoId: worktreeReviewRepoId,
			worktreeId: worktreeReviewWorktreeId,
			label: 'Default',
			createdAtUnixMilliseconds: 1,
			contentSetHash: `sha256:${props.baseRef}`,
			providerIdentity: props.baseRef,
		},
		headEndpoint: {
			endpointId: worktreeReviewHeadEndpointId,
			kind: 'workingTree',
			repoId: worktreeReviewRepoId,
			worktreeId: worktreeReviewWorktreeId,
			label: 'Working tree',
			createdAtUnixMilliseconds: 2,
			contentSetHash: `sha256:${props.snapshot.fingerprint}`,
			providerIdentity: 'working-tree',
		},
		orderedItemIds: items.map((item) => item.itemId),
		itemsById,
		groups: [],
		summary: {
			filesChanged: items.length,
			additions: sumItems(items, (item): number => item.additions),
			deletions: sumItems(items, (item): number => item.deletions),
			visibleFileCount: items.filter((item) => !item.isHiddenByDefault).length,
			hiddenFileCount: items.filter((item) => item.isHiddenByDefault).length,
		},
		filterState: emptyReviewViewFilter(),
		generatedAtUnixMilliseconds: 3,
	});
	const metadataFrame = buildReviewMetadataSnapshotFrame({
		package: reviewPackage,
		paneId: props.paneId,
		sourceIdentity: reviewPackage.query.queryId,
		streamId: props.streamId,
		sequence: reviewPackage.revision,
		selectedItemId: reviewPackage.orderedItemIds[0] ?? null,
		visibleItemIds: reviewPackage.orderedItemIds.slice(0, worktreeReviewMetadataWindowSize),
	});
	const metadataWindowFrames = reviewPackage.orderedItemIds
		.slice(worktreeReviewMetadataWindowSize)
		.reduce<ReviewMetadataWindowFrame[]>((frames, _itemId, offset, remainingItemIds) => {
			if (offset % worktreeReviewMetadataWindowSize !== 0) {
				return frames;
			}
			frames.push(
				buildReviewMetadataWindowFrame({
					package: reviewPackage,
					paneId: props.paneId,
					sourceIdentity: reviewPackage.query.queryId,
					streamId: props.streamId,
					sequence: reviewPackage.revision + frames.length + 1,
					itemIds: remainingItemIds.slice(offset, offset + worktreeReviewMetadataWindowSize),
				}),
			);
			return frames;
		}, []);
	return {
		contentByHandleId,
		metadataFrame,
		metadataWindowFrames,
		reviewMetadataSource: reviewPackage,
	};
}

function reviewItemForChangedFile(props: {
	readonly changedFile: BridgeWorktreeChangedFile;
	readonly contentByHandleId: Map<string, string>;
	readonly packageId: string;
}): BridgeReviewItemDescriptor {
	const itemId = itemIdForChangedFile(props.changedFile);
	const extension = extensionForPath(props.changedFile.path);
	const language = languageForExtension(extension);
	const fileClass = fileClassForPath(props.changedFile.path);
	const base =
		props.changedFile.baseContent === null
			? null
			: makeContentHandle({
					content: props.changedFile.baseContent,
					contentByHandleId: props.contentByHandleId,
					endpointId: worktreeReviewBaseEndpointId,
					itemId,
					language,
					packageId: props.packageId,
					role: 'base',
				});
	const head =
		props.changedFile.headContent === null
			? null
			: makeContentHandle({
					content: props.changedFile.headContent,
					contentByHandleId: props.contentByHandleId,
					endpointId: worktreeReviewHeadEndpointId,
					itemId,
					language,
					packageId: props.packageId,
					role: props.changedFile.baseContent === null ? 'file' : 'head',
				});
	const contentLineCountsByRole = contentLineCountsByRoleForChangedFile(props.changedFile);
	const contentHashAlgorithm = 'sha256';
	return {
		itemId,
		itemKind: props.changedFile.baseContent === null ? 'file' : 'diff',
		itemVersion: 1,
		basePath: props.changedFile.baseContent === null ? null : props.changedFile.basePath,
		headPath: props.changedFile.headContent === null ? null : props.changedFile.headPath,
		changeKind: props.changedFile.changeKind,
		fileClass,
		language,
		extension,
		sizeBytes: byteLength(props.changedFile.headContent ?? props.changedFile.baseContent ?? ''),
		baseContentHash: base?.contentHash ?? null,
		headContentHash: head?.contentHash ?? null,
		contentHashAlgorithm,
		additions: props.changedFile.additions,
		deletions: props.changedFile.deletions,
		isHiddenByDefault: false,
		hiddenReason: null,
		reviewPriority: 'normal',
		contentRoles: {
			base,
			head: head?.role === 'head' ? head : null,
			diff: null,
			file: head?.role === 'file' ? head : null,
		},
		contentLineCountsByRole,
		cacheKey: `${base?.cacheKey ?? 'none'}|${head?.cacheKey ?? 'none'}`,
		provenance: {
			paneIds: [],
			agentSessionIds: [],
			promptIds: [],
			operationIds: [],
			sourceKinds: ['worktree'],
		},
		annotationSummary: { threadCount: 0, unresolvedThreadCount: 0, commentCount: 0 },
		reviewState: 'unreviewed',
		collapsed: false,
	};
}

function contentLineCountsByRoleForChangedFile(
	changedFile: BridgeWorktreeChangedFile,
): BridgeReviewItemDescriptor['contentLineCountsByRole'] {
	const lineCounts: NonNullable<BridgeReviewItemDescriptor['contentLineCountsByRole']> = {};
	if (changedFile.baseContent !== null) {
		lineCounts.base = renderLineCount(changedFile.baseContent);
	}
	if (changedFile.headContent !== null) {
		if (changedFile.baseContent === null) {
			lineCounts.file = renderLineCount(changedFile.headContent);
		} else {
			lineCounts.head = renderLineCount(changedFile.headContent);
		}
	}
	return Object.keys(lineCounts).length === 0 ? undefined : lineCounts;
}

function makeContentHandle(props: {
	readonly content: string;
	readonly contentByHandleId: Map<string, string>;
	readonly endpointId: string;
	readonly itemId: string;
	readonly language: string;
	readonly packageId: string;
	readonly role: 'base' | 'head' | 'file';
}): BridgeContentHandle {
	const handleId = `${props.itemId}-${props.role}`;
	const contentHash = `sha256:${hashText(props.content)}`;
	props.contentByHandleId.set(handleId, props.content);
	return {
		handleId,
		itemId: props.itemId,
		role: props.role,
		endpointId: props.endpointId,
		reviewGeneration: worktreeReviewGeneration,
		resourceUrl: `agentstudio://resource/review/content/${handleId}?generation=${worktreeReviewGeneration}&revision=${worktreeReviewRevision}&cursor=${props.packageId}`,
		contentHash,
		contentHashAlgorithm: 'sha256',
		cacheKey: `${handleId}:${contentHash}`,
		mimeType: mimeTypeForLanguage(props.language),
		language: props.language,
		sizeBytes: byteLength(props.content),
		isBinary: false,
	};
}

function renderLineCount(content: string): number {
	if (content.length === 0) {
		return 0;
	}
	const renderedContent = content.endsWith('\n') ? content.slice(0, -1) : content;
	return renderedContent.split('\n').length;
}

function emptyReviewViewFilter(): BridgeReviewPackage['filterState'] {
	return {
		includedPathGlobs: [],
		excludedPathGlobs: [],
		includedFileClasses: [],
		excludedFileClasses: [],
		includedExtensions: [],
		excludedExtensions: [],
		changeKinds: [],
		reviewStates: [],
		showHiddenFiles: false,
		showBinaryFiles: false,
		showLargeFiles: false,
	};
}

function emptyReviewProvenanceFilter(): BridgeReviewPackage['query']['provenanceFilter'] {
	return {
		paneIds: [],
		agentSessionIds: [],
		promptIds: [],
		operationIds: [],
		createdAfterUnixMilliseconds: null,
		createdBeforeUnixMilliseconds: null,
		sourceKinds: [],
	};
}

function sumItems(
	items: readonly BridgeReviewItemDescriptor[],
	value: (item: BridgeReviewItemDescriptor) => number,
): number {
	return items.reduce((total, item): number => total + value(item), 0);
}

function assertUniqueItemIds(items: readonly BridgeReviewItemDescriptor[]): void {
	const seenIds = new Set<string>();
	for (const item of items) {
		if (seenIds.has(item.itemId)) {
			throw new Error(`Duplicate Bridge worktree review item id: ${item.itemId}`);
		}
		seenIds.add(item.itemId);
	}
}

function itemIdForChangedFile(changedFile: BridgeWorktreeChangedFile): string {
	const identity = [
		changedFile.basePath ?? '',
		changedFile.headPath ?? '',
		changedFile.path,
		changedFile.changeKind,
	].join('\0');
	return `worktree-review-${hashText(identity).slice(0, 12)}-${slugForPath(changedFile.path)}`;
}

function slugForPath(path: string): string {
	return path
		.replace(/[^a-zA-Z0-9]+/gu, '-')
		.replace(/^-+|-+$/gu, '')
		.toLowerCase();
}

function extensionForPath(path: string): string | null {
	const extension = extname(path).replace(/^\./u, '').toLowerCase();
	return extension.length === 0 ? null : extension;
}

function languageForExtension(extension: string | null): string {
	if (extension === null) {
		return 'text';
	}
	switch (extension) {
		case 'js':
		case 'jsx':
			return 'javascript';
		case 'md':
		case 'mdx':
			return 'markdown';
		case 'ts':
		case 'tsx':
			return 'typescript';
		default:
			return extension;
	}
}

function mimeTypeForLanguage(language: string): string {
	switch (language) {
		case 'markdown':
			return 'text/markdown';
		case 'typescript':
			return 'text/typescript';
		default:
			return 'text/plain';
	}
}

function fileClassForPath(path: string): BridgeFileClass {
	if (/(\b|\/)(test|tests|__tests__)(\/|$)|\.(?:test|spec)\./u.test(path)) {
		return 'test';
	}
	if (/\.(?:md|mdx|rst|txt)$/u.test(path) || path.startsWith('docs/')) {
		return 'docs';
	}
	if (/(?:^|\/)(?:package\.json|pnpm-lock\.yaml|vite\.config\.ts|\.github\/)/u.test(path)) {
		return 'config';
	}
	return 'source';
}

function byteLength(value: string): number {
	return new TextEncoder().encode(value).byteLength;
}

function hashText(value: string): string {
	return createHash('sha256').update(value).digest('hex');
}
