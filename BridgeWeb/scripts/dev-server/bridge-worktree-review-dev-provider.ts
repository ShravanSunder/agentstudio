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
	readonly reviewGeneration?: number;
	readonly revision?: number;
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

export interface BridgeWorktreeReviewIdentityRotationRequest {
	readonly reason?: 'authorityChanged' | 'providerRestart' | 'sourceChanged' | 'subscriptionReset';
}

export interface BridgeWorktreeReviewIdentityRotationResult {
	readonly generation: number;
	readonly reason: NonNullable<BridgeWorktreeReviewIdentityRotationRequest['reason']>;
	readonly revokedPackageIds: readonly string[];
	readonly streamId: string;
}

export interface BridgeWorktreeReviewDevProvider {
	readonly dispose: () => void;
	readonly loadReviewContent: (request: BridgeWorktreeReviewContentRequest) => Promise<string>;
	readonly loadReviewMetadata: (
		request?: BridgeWorktreeReviewMetadataRequest,
	) => Promise<BridgeWorktreeReviewDevMetadataResult>;
	readonly rotateIdentity: (
		request?: BridgeWorktreeReviewIdentityRotationRequest,
	) => BridgeWorktreeReviewIdentityRotationResult;
}

export interface CreateBridgeWorktreeReviewDevProviderOptions {
	readonly identityRotation?: BridgeWorktreeReviewIdentityRotationOptions;
	readonly loadSnapshot?: (props: {
		readonly baseRef: string;
		readonly worktreeRoot: string;
	}) => Promise<BridgeWorktreeReviewDevSnapshot>;
}

export interface BridgeWorktreeReviewIdentityRotationOptions {
	readonly clearInterval?: (handle: BridgeWorktreeReviewIdentityRotationTimerHandle) => void;
	readonly intervalMilliseconds?: number;
	readonly setInterval?: (
		callback: () => void,
		intervalMilliseconds: number,
	) => BridgeWorktreeReviewIdentityRotationTimerHandle;
}

type BridgeWorktreeReviewIdentityRotationTimerHandle = number | ReturnType<typeof setInterval>;
type BridgeWorktreeReviewMetadataIdentityKey = `${string}:generation-${number}:revision-${number}`;
type BridgeWorktreeReviewContentHashRole = 'base' | 'diff' | 'file' | 'head';
type BridgeWorktreeChangedFileHashMetadata = BridgeWorktreeChangedFile & {
	readonly contentHashAlgorithm?: string;
	readonly newContentHash?: string | null;
	readonly oldContentHash?: string | null;
};

const initialWorktreeReviewGeneration = 1;
const initialWorktreeReviewRevision = 1;
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
	const metadataResultsByIdentityKey = new Map<
		BridgeWorktreeReviewMetadataIdentityKey,
		BridgeWorktreeReviewDevMetadataResult
	>();
	let currentMetadataResult: BridgeWorktreeReviewDevMetadataResult | null = null;
	let currentGeneration = initialWorktreeReviewGeneration;
	let currentRevision = 0;
	let streamOrdinal = 1;
	let identityRotationTimer: BridgeWorktreeReviewIdentityRotationTimerHandle | null = null;
	const currentStreamId = (): string =>
		streamOrdinal === 1
			? 'review:bridge-worktree-review-dev-pane'
			: `review:bridge-worktree-review-dev-pane:${streamOrdinal}`;
	const rotateIdentity = (
		request: BridgeWorktreeReviewIdentityRotationRequest = {},
	): BridgeWorktreeReviewIdentityRotationResult => {
		const revokedPackageIds = [...metadataResultsByPackageId.keys()];
		metadataResultsByPackageId.clear();
		metadataResultsByIdentityKey.clear();
		currentMetadataResult = null;
		currentGeneration += 1;
		currentRevision = 0;
		streamOrdinal += 1;
		return {
			generation: currentGeneration,
			reason: request.reason ?? 'authorityChanged',
			revokedPackageIds,
			streamId: currentStreamId(),
		};
	};
	const rotationSetInterval = options.identityRotation?.setInterval ?? setInterval;
	const rotationClearInterval = options.identityRotation?.clearInterval ?? clearInterval;
	if (options.identityRotation?.intervalMilliseconds !== undefined) {
		identityRotationTimer = rotationSetInterval(() => {
			rotateIdentity({ reason: 'authorityChanged' });
		}, options.identityRotation.intervalMilliseconds);
	}
	const loadReviewMetadata = async (
		request: BridgeWorktreeReviewMetadataRequest = {},
	): Promise<BridgeWorktreeReviewDevMetadataResult> => {
		if (currentMetadataResult !== null && request.forceRefresh !== true) {
			return currentMetadataResult;
		}
		currentRevision += 1;
		currentMetadataResult = await createReviewMetadataResult({
			baseRef: config.baseRef,
			loadSnapshot,
			metadataResultsByIdentityKey,
			metadataResultsByPackageId,
			paneId: 'bridge-worktree-review-dev-pane',
			reviewGeneration: currentGeneration,
			revision: currentRevision,
			streamId: currentStreamId(),
			worktreeRoot: config.worktreeRoot,
		});
		return currentMetadataResult;
	};
	return {
		dispose: (): void => {
			if (identityRotationTimer === null) {
				return;
			}
			rotationClearInterval(identityRotationTimer);
			identityRotationTimer = null;
		},
		loadReviewMetadata,
		rotateIdentity,
		loadReviewContent: async (request: BridgeWorktreeReviewContentRequest): Promise<string> => {
			let metadataResult = metadataResultsByIdentityKey.get(
				metadataIdentityKey({
					generation: request.generation,
					packageId: request.packageId,
					revision: request.revision,
				}),
			);
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
	readonly metadataResultsByIdentityKey: Map<
		BridgeWorktreeReviewMetadataIdentityKey,
		BridgeWorktreeReviewDevMetadataResult
	>;
	readonly metadataResultsByPackageId: Map<string, BridgeWorktreeReviewDevMetadataResult>;
	readonly paneId: string;
	readonly reviewGeneration: number;
	readonly revision: number;
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
		reviewGeneration: props.reviewGeneration,
		revision: props.revision,
		snapshot,
		streamId: props.streamId,
	});
	props.metadataResultsByPackageId.set(result.metadataFrame.comparison.packageId, result);
	props.metadataResultsByIdentityKey.set(
		metadataIdentityKey({
			generation: result.metadataFrame.comparison.generation,
			packageId: result.metadataFrame.comparison.packageId,
			revision: result.metadataFrame.comparison.revision,
		}),
		result,
	);
	return result;
}

export function createBridgeWorktreeReviewDevMetadata(
	props: CreateBridgeWorktreeReviewDevMetadataProps,
): BridgeWorktreeReviewDevMetadataResult {
	const packageId = `worktree-review-${props.snapshot.fingerprint.slice(0, 12)}`;
	const reviewGeneration = props.reviewGeneration ?? initialWorktreeReviewGeneration;
	const revision = props.revision ?? initialWorktreeReviewRevision;
	const contentByHandleId = new Map<string, string>();
	const items = props.snapshot.changedFiles.map(
		(changedFile): BridgeReviewItemDescriptor =>
			reviewItemForChangedFile({
				changedFile,
				contentByHandleId,
				packageId,
				reviewGeneration,
				revision,
			}),
	);
	assertUniqueItemIds(items);
	const itemsById = Object.fromEntries(
		items.map((item): readonly [string, BridgeReviewItemDescriptor] => [item.itemId, item]),
	);
	const reviewPackage = bridgeReviewPackageSchema.parse({
		packageId,
		schemaVersion: 1,
		reviewGeneration,
		revision,
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
	readonly reviewGeneration: number;
	readonly revision: number;
}): BridgeReviewItemDescriptor {
	const itemId = itemIdForChangedFile(props.changedFile);
	const extension = extensionForPath(props.changedFile.path);
	const language = languageForExtension(extension);
	const fileClass = fileClassForPath(props.changedFile.path);
	const contentHashes = contentHashesForChangedFile(props.changedFile);
	const base =
		props.changedFile.baseContent === null
			? null
			: makeContentHandle({
					content: props.changedFile.baseContent,
					contentByHandleId: props.contentByHandleId,
					endpointId: worktreeReviewBaseEndpointId,
					itemId,
					language,
					contentHash: bridgeWorktreeReviewDevContentHashForRole(props.changedFile, 'base'),
					contentHashAlgorithm: contentHashes.algorithm,
					reviewGeneration: props.reviewGeneration,
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
					contentHash: bridgeWorktreeReviewDevContentHashForRole(props.changedFile, 'head'),
					contentHashAlgorithm: contentHashes.algorithm,
					reviewGeneration: props.reviewGeneration,
					role: 'head',
				});
	const contentLineCountsByRole = contentLineCountsByRoleForChangedFile(props.changedFile);
	return {
		itemId,
		itemKind: 'diff',
		itemVersion: 1,
		basePath: props.changedFile.baseContent === null ? null : props.changedFile.basePath,
		headPath: props.changedFile.headContent === null ? null : props.changedFile.headPath,
		changeKind: props.changedFile.changeKind,
		fileClass,
		language,
		extension,
		sizeBytes: byteLength(props.changedFile.headContent ?? props.changedFile.baseContent ?? ''),
		baseContentHash: contentHashes.oldContentHash,
		headContentHash: contentHashes.newContentHash,
		contentHashAlgorithm: contentHashes.algorithm,
		additions: props.changedFile.additions,
		deletions: props.changedFile.deletions,
		isHiddenByDefault: false,
		hiddenReason: null,
		reviewPriority: 'normal',
		contentRoles: {
			base,
			head,
			diff: null,
			file: null,
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
		lineCounts.head = renderLineCount(changedFile.headContent);
	}
	return Object.keys(lineCounts).length === 0 ? undefined : lineCounts;
}

function makeContentHandle(props: {
	readonly content: string;
	readonly contentByHandleId: Map<string, string>;
	readonly contentHash: string;
	readonly contentHashAlgorithm: string;
	readonly endpointId: string;
	readonly itemId: string;
	readonly language: string;
	readonly reviewGeneration: number;
	readonly role: 'base' | 'head';
}): BridgeContentHandle {
	const handleId = `handle-${hashText(
		`${props.endpointId}:${props.itemId}:${props.role}:${props.contentHash}`,
	)}`;
	props.contentByHandleId.set(handleId, props.content);
	return {
		handleId,
		itemId: props.itemId,
		role: props.role,
		endpointId: props.endpointId,
		reviewGeneration: props.reviewGeneration,
		resourceUrl: `agentstudio://resource/review/content/${handleId}?generation=${props.reviewGeneration}`,
		contentHash: props.contentHash,
		contentHashAlgorithm: props.contentHashAlgorithm,
		cacheKey: `${props.endpointId}:${props.itemId}:${props.role}:${props.contentHash}`,
		mimeType: mimeTypeForLanguage(props.language),
		language: props.language,
		sizeBytes: byteLength(props.content),
		isBinary: false,
	};
}

function contentHashesForChangedFile(changedFile: BridgeWorktreeChangedFile): {
	readonly algorithm: string;
	readonly newContentHash: string | null;
	readonly oldContentHash: string | null;
} {
	const metadata = changedFile as BridgeWorktreeChangedFileHashMetadata;
	const oldContentHash =
		metadata.oldContentHash ??
		(changedFile.baseContent === null ? null : gitBlobSha1(changedFile.baseContent));
	const newContentHash =
		metadata.newContentHash ??
		(changedFile.headContent === null ? null : gitBlobSha1(changedFile.headContent));
	return {
		algorithm: metadata.contentHashAlgorithm ?? 'git-blob-sha1',
		newContentHash,
		oldContentHash,
	};
}

export function bridgeWorktreeReviewDevContentHashForRole(
	changedFile: BridgeWorktreeChangedFile,
	role: BridgeWorktreeReviewContentHashRole,
): string {
	const contentHashes = contentHashesForChangedFile(changedFile);
	switch (role) {
		case 'base':
			return contentHashes.oldContentHash ?? 'missing-base';
		case 'head':
		case 'file':
			return contentHashes.newContentHash ?? contentHashes.oldContentHash ?? 'unknown';
		case 'diff':
			return `${contentHashes.oldContentHash ?? 'none'}...${contentHashes.newContentHash ?? 'none'}`;
	}
	const exhaustiveRole: never = role;
	void exhaustiveRole;
	throw new Error('Unhandled Bridge worktree review content hash role');
}

function metadataIdentityKey(props: {
	readonly generation: number;
	readonly packageId: string;
	readonly revision: number;
}): BridgeWorktreeReviewMetadataIdentityKey {
	return `${props.packageId}:generation-${props.generation}:revision-${props.revision}`;
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

function gitBlobSha1(content: string): string {
	return createHash('sha1')
		.update(
			Buffer.concat([Buffer.from(`blob ${Buffer.byteLength(content)}\0`), Buffer.from(content)]),
		)
		.digest('hex');
}
