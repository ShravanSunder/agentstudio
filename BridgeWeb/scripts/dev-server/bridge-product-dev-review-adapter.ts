import { createHash } from 'node:crypto';
import { extname } from 'node:path';

import type {
	BridgeProductReviewContentDescriptor,
	BridgeProductReviewContentSourceDescriptor,
} from '../../src/core/comm-worker/bridge-product-content-contracts.js';
import { BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES } from '../../src/core/comm-worker/bridge-product-contract-primitives.js';
import {
	bridgeProductReviewMetadataEventSchema,
	type BridgeProductReviewExtentFact,
	type BridgeProductReviewItemMetadata,
	type BridgeProductReviewMetadataEvent,
	type BridgeProductReviewTreeRow,
} from '../../src/core/comm-worker/bridge-product-review-metadata-contracts.js';
import type { BridgeProductDevContentPayload } from './bridge-product-dev-content-producer.js';
import {
	hydrateBridgeWorktreeDevContentWindow,
	loadBridgeWorktreeDevMetadataSnapshot,
	type BridgeWorktreeChangedFileMetadata,
	type BridgeWorktreeDevMetadataSnapshot,
} from './bridge-worktree-dev-provider.js';

const reviewMetadataWindowItemLimit = 64;
const reviewGeneration = 1;
const reviewRevision = 1;
const reviewRepoId = 'dev-worktree-repo';
const reviewWorktreeId = 'dev-worktree';
const reviewBaseEndpointId = 'baseline-local-default';
const reviewHeadEndpointId = 'working-tree';

interface BridgeProductDevReviewContentLocator {
	readonly changedFile: BridgeWorktreeChangedFileMetadata;
	readonly source: BridgeProductReviewContentSourceDescriptor;
}

interface BridgeProductDevReviewMetadataEntry {
	readonly contentSources: readonly BridgeProductReviewContentSourceDescriptor[];
	readonly extentFacts: readonly BridgeProductReviewExtentFact[];
	readonly itemMetadata: BridgeProductReviewItemMetadata;
	readonly treeRow: BridgeProductReviewTreeRow;
}

export interface BridgeProductDevReviewSourceSnapshot {
	readonly cursor: string;
	readonly events: readonly BridgeProductReviewMetadataEvent[];
	readonly generation: number;
	readonly packageId: string;
	readonly revision: number;
	readonly sourceIdentity: string;
}

export interface BridgeProductDevReviewAdapterPort {
	readonly loadContent: (
		descriptor: BridgeProductReviewContentDescriptor,
		signal?: AbortSignal,
	) => Promise<BridgeProductDevContentPayload | null>;
	readonly loadSource: (signal?: AbortSignal) => Promise<BridgeProductDevReviewSourceSnapshot>;
}

export class BridgeProductDevReviewAdapter implements BridgeProductDevReviewAdapterPort {
	readonly #baseRef: string;
	readonly #contentLocatorByDescriptorId = new Map<string, BridgeProductDevReviewContentLocator>();
	#sourceSnapshot: Promise<BridgeProductDevReviewSourceSnapshot> | null = null;
	readonly #worktreeRoot: string;

	constructor(props: { readonly baseRef: string; readonly worktreeRoot: string }) {
		this.#baseRef = props.baseRef;
		this.#worktreeRoot = props.worktreeRoot;
	}

	loadSource(signal?: AbortSignal): Promise<BridgeProductDevReviewSourceSnapshot> {
		this.#sourceSnapshot ??= this.#loadSource(signal);
		return this.#sourceSnapshot;
	}

	async loadContent(
		descriptor: BridgeProductReviewContentDescriptor,
		signal?: AbortSignal,
	): Promise<BridgeProductDevContentPayload | null> {
		const locator = this.#contentLocatorByDescriptorId.get(descriptor.descriptorId);
		if (locator === undefined || !reviewDescriptorMatchesSource(descriptor, locator.source)) {
			return null;
		}
		const window = await hydrateBridgeWorktreeDevContentWindow({
			baseRef: this.#baseRef,
			changedFile: locator.changedFile,
			maximumBytes: descriptor.window.maximumBytes,
			role: locator.source.role === 'base' ? 'base' : 'head',
			signal,
			startByte: descriptor.window.startByte,
			worktreeRoot: this.#worktreeRoot,
		});
		if (descriptor.expectedSha256 !== null && descriptor.expectedSha256 !== window.sha256) {
			throw new Error('Bridge product dev Review content changed after descriptor admission.');
		}
		return {
			bytes: window.bytes,
			descriptor,
			endOfSource: window.endOfSource,
		};
	}

	async #loadSource(signal?: AbortSignal): Promise<BridgeProductDevReviewSourceSnapshot> {
		const snapshot = await loadBridgeWorktreeDevMetadataSnapshot({
			baseRef: this.#baseRef,
			signal,
			worktreeRoot: this.#worktreeRoot,
		});
		const fingerprintPrefix = snapshot.fingerprint.slice(0, 24);
		const packageId = `dev-review-package-${fingerprintPrefix}`;
		const sourceIdentity = `dev-review-source-${fingerprintPrefix}`;
		const cursor = `dev-review-cursor-${fingerprintPrefix}`;
		const events = this.#metadataEvents({ cursor, packageId, snapshot, sourceIdentity });
		return {
			cursor,
			events: [
				bridgeProductReviewMetadataEventSchema.parse({
					eventKind: 'review.sourceAccepted',
					generation: reviewGeneration,
					packageId,
					revision: reviewRevision,
					sourceIdentity,
				}),
				...events,
			],
			generation: reviewGeneration,
			packageId,
			revision: reviewRevision,
			sourceIdentity,
		};
	}

	#metadataEvents(props: {
		readonly cursor: string;
		readonly packageId: string;
		readonly snapshot: BridgeWorktreeDevMetadataSnapshot;
		readonly sourceIdentity: string;
	}): readonly BridgeProductReviewMetadataEvent[] {
		const entries = props.snapshot.changedFiles.map((changedFile) => {
			const contentSources = this.#contentSourcesForChange({
				changedFile,
				packageId: props.packageId,
				sourceIdentity: props.sourceIdentity,
			});
			return {
				contentSources,
				extentFacts: [],
				itemMetadata: reviewItemMetadata(changedFile, contentSources),
				treeRow: reviewTreeRow(changedFile),
			} satisfies BridgeProductDevReviewMetadataEntry;
		});
		const makeEvent = (startIndex: number, count: number): BridgeProductReviewMetadataEvent =>
			this.#metadataWindowEvent({
				entries: entries.slice(startIndex, startIndex + count),
				packageId: props.packageId,
				snapshot: props.snapshot,
				sourceIdentity: props.sourceIdentity,
				startIndex,
			});
		if (entries.length === 0) return [makeEvent(0, 0)];

		const events: BridgeProductReviewMetadataEvent[] = [];
		let startIndex = 0;
		while (startIndex < entries.length) {
			const maximumCount = Math.min(reviewMetadataWindowItemLimit, entries.length - startIndex);
			const event = largestFrameBoundedReviewMetadataEvent({
				cursor: props.cursor,
				makeEvent: (count) => makeEvent(startIndex, count),
				maximumCount,
			});
			events.push(event);
			startIndex += reviewMetadataEventItemCount(event);
		}
		return events;
	}

	#metadataWindowEvent(props: {
		readonly entries: readonly BridgeProductDevReviewMetadataEntry[];
		readonly packageId: string;
		readonly snapshot: BridgeWorktreeDevMetadataSnapshot;
		readonly sourceIdentity: string;
		readonly startIndex: number;
	}): BridgeProductReviewMetadataEvent {
		const contentSources = props.entries.flatMap((entry) => entry.contentSources);
		const itemMetadata = props.entries.map((entry) => entry.itemMetadata);
		const treeRows = props.entries.map((entry) => entry.treeRow);
		const finalWindow =
			props.startIndex + props.entries.length === props.snapshot.changedFiles.length;
		const commonPayload = {
			contentSources,
			extentFacts: props.entries.flatMap((entry) => entry.extentFacts),
			generation: reviewGeneration,
			itemMetadata,
			itemWindow: {
				finalWindow,
				itemCount: itemMetadata.length,
				startIndex: props.startIndex,
				totalItemCount: props.snapshot.changedFiles.length,
			},
			packageId: props.packageId,
			revision: reviewRevision,
			sourceIdentity: props.sourceIdentity,
			summary: reviewSummary(props.snapshot),
			treeRows,
			treeWindow: {
				finalWindow,
				rowCount: treeRows.length,
				startIndex: props.startIndex,
				totalRowCount: props.snapshot.changedFiles.length,
			},
		};
		return bridgeProductReviewMetadataEventSchema.parse(
			props.startIndex === 0
				? {
						...commonPayload,
						baseEndpoint: reviewEndpoint({
							contentSetHash: this.#baseRef,
							endpointId: reviewBaseEndpointId,
							kind: 'gitRef',
							label: 'Default',
						}),
						eventKind: 'review.snapshot',
						headEndpoint: reviewEndpoint({
							contentSetHash: props.snapshot.fingerprint,
							endpointId: reviewHeadEndpointId,
							kind: 'workingTree',
							label: 'Working tree',
						}),
						query: reviewQuery(),
					}
				: { ...commonPayload, eventKind: 'review.window' },
		);
	}

	#contentSourcesForChange(props: {
		readonly changedFile: BridgeWorktreeChangedFileMetadata;
		readonly packageId: string;
		readonly sourceIdentity: string;
	}): readonly BridgeProductReviewContentSourceDescriptor[] {
		const roles = [
			...(props.changedFile.basePath === null ? [] : (['base'] as const)),
			...(props.changedFile.headPath === null ? [] : (['head'] as const)),
		];
		return roles.map((role) => {
			const source = reviewContentSource({ ...props, role });
			this.#contentLocatorByDescriptorId.set(source.descriptorId, {
				changedFile: props.changedFile,
				source,
			});
			return source;
		});
	}
}

function reviewContentSource(props: {
	readonly changedFile: BridgeWorktreeChangedFileMetadata;
	readonly packageId: string;
	readonly role: 'base' | 'head';
	readonly sourceIdentity: string;
}): BridgeProductReviewContentSourceDescriptor {
	const identityHash = hash(`${props.packageId}\0${props.changedFile.path}\0${props.role}`);
	const extension = extname(props.changedFile.path).slice(1).toLowerCase();
	return {
		contentDigest: {
			algorithm: 'dev-metadata-fingerprint',
			authority: 'provisional',
			value: identityHash,
		},
		contentKind: 'review.content',
		descriptorId: `review-descriptor-${identityHash.slice(0, 32)}`,
		encoding: 'utf-8',
		endpointId: props.role === 'base' ? reviewBaseEndpointId : reviewHeadEndpointId,
		handleId: `review-handle-${identityHash.slice(0, 32)}`,
		isBinary: false,
		itemId: itemIdForPath(props.changedFile.path),
		language: languageForExtension(extension),
		mimeType: mimeTypeForExtension(extension),
		packageId: props.packageId,
		reviewGeneration,
		role: props.role,
		sourceIdentity: props.sourceIdentity,
		wholeByteLength:
			props.role === 'head' ? (props.changedFile.headFileMetadata?.sizeBytes ?? null) : null,
	};
}

function reviewItemMetadata(
	changedFile: BridgeWorktreeChangedFileMetadata,
	contentSources: readonly BridgeProductReviewContentSourceDescriptor[],
): BridgeProductReviewItemMetadata {
	const sourcesByRole = new Map(contentSources.map((source) => [source.role, source]));
	const extension = extname(changedFile.path).slice(1).toLowerCase();
	return {
		basePath: changedFile.basePath,
		changeKind: changedFile.changeKind,
		contentDescriptorIdsByRole: Object.fromEntries(
			contentSources.map((source) => [source.role, source.descriptorId]),
		),
		contentHashesByRole: Object.fromEntries(
			contentSources.map((source) => [source.role, source.contentDigest.value]),
		),
		contentRoles: [...sourcesByRole.keys()],
		extension: extension.length === 0 ? null : extension,
		fileClass: fileClassForPath(changedFile.path),
		headPath: changedFile.headPath,
		isHiddenByDefault: false,
		itemId: itemIdForPath(changedFile.path),
		language: languageForExtension(extension),
		mimeTypes: [...new Set(contentSources.map((source) => source.mimeType))],
		provenance: { agentSessionIds: [], operationIds: [], promptIds: [] },
		reviewPriority: 'normal',
		reviewState: 'unreviewed',
	};
}

function reviewTreeRow(changedFile: BridgeWorktreeChangedFileMetadata): BridgeProductReviewTreeRow {
	return {
		depth: Math.max(changedFile.path.split('/').length - 1, 0),
		isDirectory: false,
		itemId: itemIdForPath(changedFile.path),
		path: changedFile.path,
		rowId: `review-row-${hash(changedFile.path).slice(0, 32)}`,
	};
}

function reviewSummary(snapshot: BridgeWorktreeDevMetadataSnapshot): {
	readonly additions: number;
	readonly deletions: number;
	readonly filesChanged: number;
	readonly hiddenFileCount: number;
	readonly visibleFileCount: number;
} {
	return {
		additions: snapshot.changedFiles.reduce((sum, file) => sum + (file.additions ?? 0), 0),
		deletions: snapshot.changedFiles.reduce((sum, file) => sum + (file.deletions ?? 0), 0),
		filesChanged: snapshot.changedFiles.length,
		hiddenFileCount: 0,
		visibleFileCount: snapshot.changedFiles.length,
	};
}

function reviewEndpoint(props: {
	readonly contentSetHash: string;
	readonly endpointId: string;
	readonly kind: 'gitRef' | 'workingTree';
	readonly label: string;
}): object {
	return {
		contentSetHash: `sha256:${hash(props.contentSetHash)}`,
		createdAtUnixMilliseconds: 0,
		endpointId: props.endpointId,
		kind: props.kind,
		label: props.label,
		providerIdentity: `dev:${hash(props.contentSetHash).slice(0, 32)}`,
		repoId: reviewRepoId,
		worktreeId: reviewWorktreeId,
	};
}

function reviewQuery(): object {
	return {
		baseEndpointId: reviewBaseEndpointId,
		comparisonSemantics: 'workingTreeDelta',
		fileTarget: null,
		grouping: { kind: 'folder', label: 'Folders' },
		headEndpointId: reviewHeadEndpointId,
		pathScope: [],
		provenanceFilter: {
			agentSessionIds: [],
			createdAfterUnixMilliseconds: null,
			createdBeforeUnixMilliseconds: null,
			operationIds: [],
			paneIds: [],
			promptIds: [],
			sourceKinds: [],
		},
		queryId: 'dev-current-worktree-review',
		queryKind: 'compare',
		repoId: reviewRepoId,
		viewFilter: {
			changeKinds: [],
			excludedExtensions: [],
			excludedFileClasses: [],
			excludedPathGlobs: [],
			includedExtensions: [],
			includedFileClasses: [],
			includedPathGlobs: [],
			reviewStates: [],
			showBinaryFiles: true,
			showHiddenFiles: true,
			showLargeFiles: true,
		},
		worktreeId: reviewWorktreeId,
	};
}

function reviewDescriptorMatchesSource(
	descriptor: BridgeProductReviewContentDescriptor,
	source: BridgeProductReviewContentSourceDescriptor,
): boolean {
	const {
		declaredByteLength: _declared,
		expectedSha256: _expected,
		maximumBytes: _maximum,
		window: _window,
		...identity
	} = descriptor;
	return JSON.stringify(identity) === JSON.stringify(source);
}

function itemIdForPath(path: string): string {
	return `review-item-${hash(path).slice(0, 32)}`;
}

function hash(value: string): string {
	return createHash('sha256').update(value).digest('hex');
}

function largestFrameBoundedReviewMetadataEvent(props: {
	readonly cursor: string;
	readonly makeEvent: (count: number) => BridgeProductReviewMetadataEvent;
	readonly maximumCount: number;
}): BridgeProductReviewMetadataEvent {
	const maximumEvent = props.makeEvent(props.maximumCount);
	if (reviewMetadataEventFitsMaximumCarrierFrame(props.cursor, maximumEvent)) return maximumEvent;

	let acceptedEvent: BridgeProductReviewMetadataEvent | null = null;
	let lowerCount = 1;
	let upperCount = props.maximumCount - 1;
	while (lowerCount <= upperCount) {
		const candidateCount = Math.floor((lowerCount + upperCount) / 2);
		const candidateEvent = props.makeEvent(candidateCount);
		if (reviewMetadataEventFitsMaximumCarrierFrame(props.cursor, candidateEvent)) {
			acceptedEvent = candidateEvent;
			lowerCount = candidateCount + 1;
		} else {
			upperCount = candidateCount - 1;
		}
	}
	if (acceptedEvent === null) {
		throw new Error('Bridge product dev Review metadata item exceeds the frame policy.');
	}
	return acceptedEvent;
}

function reviewMetadataEventItemCount(event: BridgeProductReviewMetadataEvent): number {
	if (event.eventKind !== 'review.snapshot' && event.eventKind !== 'review.window') {
		throw new Error('Bridge product dev Review metadata window kind is invalid.');
	}
	return event.itemWindow.itemCount;
}

function reviewMetadataEventFitsMaximumCarrierFrame(
	cursor: string,
	event: BridgeProductReviewMetadataEvent,
): boolean {
	const maximumIdentifier = 'x'.repeat(128);
	const maximumSequence = Number.MAX_SAFE_INTEGER;
	const frame = {
		cursor,
		data: { event, subscriptionKind: 'review.metadata' },
		interestRevision: maximumSequence,
		interestSha256: 'f'.repeat(64),
		kind: 'subscription.data',
		metadataStreamId: maximumIdentifier,
		paneSessionId: maximumIdentifier,
		sourceGeneration: event.generation,
		streamSequence: maximumSequence,
		subscriptionId: maximumIdentifier,
		subscriptionKind: 'review.metadata',
		subscriptionSequence: maximumSequence,
		wireVersion: 2,
		workerDerivationEpoch: maximumSequence,
		workerInstanceId: maximumIdentifier,
	};
	return (
		new TextEncoder().encode(JSON.stringify(frame)).byteLength <=
		BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES
	);
}

function languageForExtension(extension: string): string | null {
	return (
		(
			{
				js: 'javascript',
				jsx: 'jsx',
				md: 'markdown',
				tsx: 'tsx',
				ts: 'typescript',
				swift: 'swift',
			} as Readonly<Record<string, string>>
		)[extension] ?? null
	);
}

function mimeTypeForExtension(extension: string): string {
	return extension === 'md' ? 'text/markdown' : 'text/plain';
}

function fileClassForPath(path: string): BridgeProductReviewItemMetadata['fileClass'] {
	const lower = path.toLowerCase();
	if (lower.includes('/test') || lower.includes('.test.') || lower.includes('tests/'))
		return 'test';
	if (lower.endsWith('.md')) return 'docs';
	if (lower.includes('fixture')) return 'fixture';
	if (lower.endsWith('.json') || lower.endsWith('.yaml') || lower.endsWith('.yml')) return 'config';
	return 'source';
}
