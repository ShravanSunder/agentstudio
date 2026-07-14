import { createHash } from 'node:crypto';

import {
	bridgeProductContentIdentityFromDescriptor,
	type BridgeProductFileContentDescriptor,
	type BridgeProductFileContentIdentity,
} from '../../src/core/comm-worker/bridge-product-content-contracts.js';
import {
	BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES,
	bridgeProductIdentifierSchema,
} from '../../src/core/comm-worker/bridge-product-contract-primitives.js';
import type { BridgeProductFileSourceIdentity } from '../../src/core/comm-worker/bridge-product-file-contracts.js';
import {
	BRIDGE_PRODUCT_MAXIMUM_FILE_METADATA_TREE_WINDOW_ROW_COUNT,
	bridgeProductFileMetadataEventSchema,
	bridgeProductFileSourceConfigurationSchema,
	type BridgeProductSubscriptionEvent,
} from '../../src/core/comm-worker/bridge-product-subscription-contracts.js';
import type { BridgeProductDevContentPayload } from './bridge-product-dev-content-producer.js';
import {
	deriveBridgeProductDevFilePrefix,
	type BridgeProductDevFilePrefix,
} from './bridge-product-dev-file-prefix.js';
import type {
	WorktreeFileDescriptor,
	WorktreeTreeRowMetadata,
} from './bridge-worktree-dev-file-fixture-contracts.js';
import type { BridgeWorktreeDevProvider } from './bridge-worktree-dev-provider.js';

const bridgeProductDevRepoId = '00000000-0000-4000-8000-000000000001';
const bridgeProductDevWorktreeId = '00000000-0000-4000-8000-000000000002';
export const BRIDGE_PRODUCT_DEV_FILE_MAXIMUM_LINES = 10_000;

type BridgeProductFileEvent = BridgeProductSubscriptionEvent<'file.metadata'>;
type BridgeProductFileDescriptorReadyEvent = Extract<
	BridgeProductFileEvent,
	{ readonly eventKind: 'file.descriptorReady' }
>;
type BridgeProductFileTreeWindowEvent = Extract<
	BridgeProductFileEvent,
	{ readonly eventKind: 'file.treeWindow' }
>;
type BridgeProductFileTreeRow = BridgeProductFileTreeWindowEvent['rows'][number];

function parseFileDescriptorReadyEvent(value: unknown): BridgeProductFileDescriptorReadyEvent {
	const event = bridgeProductFileMetadataEventSchema.parse(value);
	if (event.eventKind !== 'file.descriptorReady') {
		throw new Error('Bridge product dev File adapter produced the wrong event kind.');
	}
	return event;
}

export interface BridgeProductDevFileSourceSnapshot {
	readonly configuration: ReturnType<typeof bridgeProductFileSourceConfigurationSchema.parse>;
	readonly identity: BridgeProductFileSourceIdentity;
	readonly treeEvents: readonly BridgeProductFileEvent[];
}

export interface BridgeProductDevFileContent {
	readonly bytes: Uint8Array;
	readonly descriptor: BridgeProductFileContentDescriptor;
	readonly endOfSource: boolean;
	readonly identity: BridgeProductFileContentIdentity;
}

export class BridgeProductDevFileAdapter {
	readonly #contentByDescriptorId = new Map<string, BridgeProductDevFileContent>();
	readonly #provider: BridgeWorktreeDevProvider;
	#sourceSnapshot: Promise<BridgeProductDevFileSourceSnapshot> | null = null;

	constructor(provider: BridgeWorktreeDevProvider) {
		this.#provider = provider;
	}

	loadSource(): Promise<BridgeProductDevFileSourceSnapshot> {
		this.#sourceSnapshot ??= this.#loadSource();
		return this.#sourceSnapshot;
	}

	async loadDescriptor(path: string): Promise<BridgeProductFileDescriptorReadyEvent> {
		const sourceSnapshot = await this.loadSource();
		let legacyFrame: Awaited<ReturnType<BridgeWorktreeDevProvider['loadWorktreeFileDescriptor']>>;
		try {
			legacyFrame = await this.#provider.loadWorktreeFileDescriptor({
				path,
				sourceCursor: sourceSnapshot.identity.sourceCursor,
				subscriptionGeneration: sourceSnapshot.identity.subscriptionGeneration,
			});
		} catch (error: unknown) {
			return unavailableDescriptorEventForKnownFile({ error, path, sourceSnapshot });
		}
		return await this.#descriptorEvent(legacyFrame.descriptor, sourceSnapshot);
	}

	loadContent(
		descriptor: BridgeProductFileContentDescriptor,
		signal?: AbortSignal,
	): Promise<BridgeProductDevContentPayload | null> {
		if (signal?.aborted === true) {
			return Promise.reject(
				new DOMException('Bridge product File content was cancelled.', 'AbortError'),
			);
		}
		const content = this.#contentByDescriptorId.get(descriptor.descriptorId);
		return Promise.resolve(
			content !== undefined && JSON.stringify(content.descriptor) === JSON.stringify(descriptor)
				? content
				: null,
		);
	}

	async #loadSource(): Promise<BridgeProductDevFileSourceSnapshot> {
		const surface = await this.#provider.loadWorktreeFileSurface();
		const identity: BridgeProductFileSourceIdentity = {
			repoId: bridgeProductDevRepoId,
			rootRevisionToken: surface.source.rootRevisionToken ?? null,
			sourceCursor: surface.source.sourceCursor,
			sourceId: bridgeProductIdentifierSchema.parse(surface.source.sourceId),
			subscriptionGeneration: surface.source.subscriptionGeneration,
			worktreeId: bridgeProductDevWorktreeId,
		};
		const configuration = bridgeProductFileSourceConfigurationSchema.parse({
			cwdScope: null,
			freshness: 'live',
			includeStatuses: true,
			repoId: identity.repoId,
			rootPathToken: surface.provenance.worktreeRootToken,
			worktreeId: identity.worktreeId,
		});
		const rowWindows = surface.frames.flatMap((frame) => {
			if (frame.frameKind === 'worktree.snapshot') {
				return [{ lineage: frame.metadataLineage, rows: frame.treeRows, startIndex: 0 }];
			}
			if (frame.frameKind === 'worktree.treeWindow') {
				return [
					{
						lineage: frame.metadataLineage,
						rows: frame.rows,
						startIndex: frame.treeSizeFacts?.windowStartIndex ?? 0,
					},
				];
			}
			return [];
		});
		const totalRowCount = surface.treeSizeFacts.pathCount ?? null;
		const treeEvents = rowWindows.flatMap((window, windowIndex): BridgeProductFileEvent[] => {
			const rowChunks = chunkRows(window.rows);
			return rowChunks.map((rows, chunkIndex) =>
				bridgeProductFileMetadataEventSchema.parse({
					eventKind: 'file.treeWindow',
					finalWindow: windowIndex === rowWindows.length - 1 && chunkIndex === rowChunks.length - 1,
					lineage: window.lineage,
					pathScope: [],
					rows: rows.map(productTreeRow),
					source: identity,
					startIndex:
						window.startIndex +
						chunkIndex * BRIDGE_PRODUCT_MAXIMUM_FILE_METADATA_TREE_WINDOW_ROW_COUNT,
					totalRowCount,
				}),
			);
		});
		return { configuration, identity, treeEvents };
	}

	async #descriptorEvent(
		descriptor: WorktreeFileDescriptor,
		sourceSnapshot: BridgeProductDevFileSourceSnapshot,
	): Promise<BridgeProductFileDescriptorReadyEvent> {
		const source = sourceSnapshot.identity;
		if (descriptor.isBinary || descriptor.virtualizedExtentKind === 'unavailable') {
			return parseFileDescriptorReadyEvent({
				availability: descriptor.isBinary
					? { availabilityKind: 'binary' }
					: {
							availabilityKind: 'unavailable',
							reason: descriptor.unavailableReason ?? 'unreadable',
						},
				encoding: null,
				endsMidLine: false,
				endsWithNewline: false,
				estimatedContentHeightPixels: null,
				eventKind: 'file.descriptorReady',
				fileExtension: descriptor.fileExtension ?? null,
				fileId: descriptor.fileId,
				language: descriptor.language ?? null,
				modifiedAtUnixMilliseconds: descriptor.modifiedAtUnixMilliseconds ?? null,
				path: descriptor.path,
				payloadByteCount: 0,
				payloadLineCount: 0,
				rowId: productRowId(descriptor.path),
				sizeBytes: descriptor.sizeBytes,
				source,
				totalLineCount: null,
				truncationKind: 'none',
				virtualizedExtentKind: 'unavailable',
			});
		}

		let contentText: string;
		try {
			contentText = await this.#provider.loadWorktreeFileContent({
				descriptorId: descriptor.contentHandle,
				sourceCursor: source.sourceCursor,
				subscriptionGeneration: source.subscriptionGeneration,
			});
		} catch (error: unknown) {
			return unavailableDescriptorEventForKnownFile({
				error,
				path: descriptor.path,
				sourceSnapshot,
			});
		}
		const sourceBytes = new TextEncoder().encode(contentText);
		const prefix = deriveBridgeProductDevFilePrefix(sourceBytes, {
			maximumBytes: BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES,
			maximumLines: BRIDGE_PRODUCT_DEV_FILE_MAXIMUM_LINES,
		});
		return this.#availableDescriptorEvent({ descriptor, prefix, source, sourceBytes });
	}

	#availableDescriptorEvent(props: {
		readonly descriptor: WorktreeFileDescriptor;
		readonly prefix: BridgeProductDevFilePrefix;
		readonly source: BridgeProductFileSourceIdentity;
		readonly sourceBytes: Uint8Array;
	}): BridgeProductFileDescriptorReadyEvent {
		const contentDescriptor: BridgeProductFileContentDescriptor = {
			contentKind: 'file.content',
			declaredByteLength: props.prefix.bytes.byteLength,
			descriptorId: props.descriptor.contentHandle,
			encoding: 'utf-8',
			expectedSha256: props.prefix.sha256,
			fileId: props.descriptor.fileId,
			maximumBytes: BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES,
			source: props.source,
			window: {
				kind: 'prefix',
				maximumBytes: BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES,
				maximumLines: BRIDGE_PRODUCT_DEV_FILE_MAXIMUM_LINES,
				startByte: 0,
			},
		};
		this.#contentByDescriptorId.set(contentDescriptor.descriptorId, {
			bytes: props.prefix.bytes,
			descriptor: contentDescriptor,
			endOfSource: props.prefix.didReachEnd,
			identity: bridgeProductContentIdentityFromDescriptor(contentDescriptor),
		});
		return parseFileDescriptorReadyEvent({
			availability: { availabilityKind: 'available', contentDescriptor },
			encoding: 'utf-8',
			endsMidLine: props.prefix.endsMidLine,
			endsWithNewline: props.prefix.endsWithNewline,
			estimatedContentHeightPixels: null,
			eventKind: 'file.descriptorReady',
			fileExtension: props.descriptor.fileExtension ?? null,
			fileId: props.descriptor.fileId,
			language: props.descriptor.language ?? null,
			modifiedAtUnixMilliseconds: props.descriptor.modifiedAtUnixMilliseconds ?? null,
			path: props.descriptor.path,
			payloadByteCount: props.prefix.bytes.byteLength,
			payloadLineCount: props.prefix.payloadLineCount,
			rowId: productRowId(props.descriptor.path),
			sizeBytes: props.sourceBytes.byteLength,
			source: props.source,
			totalLineCount: props.prefix.didReachEnd ? props.prefix.payloadLineCount : null,
			truncationKind: props.prefix.truncationKind,
			virtualizedExtentKind: props.prefix.didReachEnd ? 'exactLineCount' : 'previewBounded',
		});
	}
}

function unavailableDescriptorEventForKnownFile(props: {
	readonly error: unknown;
	readonly path: string;
	readonly sourceSnapshot: BridgeProductDevFileSourceSnapshot;
}): BridgeProductFileDescriptorReadyEvent {
	const reason = itemScopedUnavailableReason(props.error);
	const row = fileTreeRowForPath(props.sourceSnapshot.treeEvents, props.path);
	if (reason === null || row?.fileId === null || row?.fileId === undefined || row.isDirectory) {
		throw props.error;
	}
	return parseFileDescriptorReadyEvent({
		availability: { availabilityKind: 'unavailable', reason },
		encoding: null,
		endsMidLine: false,
		endsWithNewline: false,
		estimatedContentHeightPixels: null,
		eventKind: 'file.descriptorReady',
		fileExtension: null,
		fileId: row.fileId,
		language: null,
		modifiedAtUnixMilliseconds: null,
		path: row.path,
		payloadByteCount: 0,
		payloadLineCount: 0,
		rowId: row.rowId,
		sizeBytes: row.sizeBytes ?? 0,
		source: props.sourceSnapshot.identity,
		totalLineCount: null,
		truncationKind: 'none',
		virtualizedExtentKind: 'unavailable',
	});
}

function fileTreeRowForPath(
	events: readonly BridgeProductFileEvent[],
	path: string,
): BridgeProductFileTreeRow | null {
	for (const event of events) {
		if (event.eventKind !== 'file.treeWindow') continue;
		const row = event.rows.find((candidate): boolean => candidate.path === path);
		if (row !== undefined) return row;
	}
	return null;
}

function itemScopedUnavailableReason(error: unknown): 'outside_scope' | 'unreadable' | null {
	if (!(error instanceof Error)) return 'unreadable';
	if (
		error.name === 'AbortError' ||
		error.message.startsWith('Rejected stale Bridge worktree file descriptor') ||
		error.message.startsWith('Rejected stale Bridge worktree file content')
	) {
		return null;
	}
	return error.message.includes('escapes root') ? 'outside_scope' : 'unreadable';
}

function chunkRows(
	rows: readonly WorktreeTreeRowMetadata[],
): readonly (readonly WorktreeTreeRowMetadata[])[] {
	if (rows.length === 0) return [[]];
	const chunks: WorktreeTreeRowMetadata[][] = [];
	for (
		let startIndex = 0;
		startIndex < rows.length;
		startIndex += BRIDGE_PRODUCT_MAXIMUM_FILE_METADATA_TREE_WINDOW_ROW_COUNT
	) {
		chunks.push(
			rows.slice(
				startIndex,
				startIndex + BRIDGE_PRODUCT_MAXIMUM_FILE_METADATA_TREE_WINDOW_ROW_COUNT,
			),
		);
	}
	return chunks;
}

function productTreeRow(row: WorktreeTreeRowMetadata): {
	readonly changeStatus: string | null;
	readonly depth: number;
	readonly fileId: string | null;
	readonly isDirectory: boolean;
	readonly lineCount: number | null;
	readonly name: string;
	readonly parentPath: string | null;
	readonly path: string;
	readonly rowId: string;
	readonly sizeBytes: number | null;
} {
	return {
		changeStatus: row.changeStatus ?? null,
		depth: row.depth,
		fileId: row.fileId ?? null,
		isDirectory: row.isDirectory,
		lineCount: row.lineCount ?? null,
		name: row.name,
		parentPath: row.parentPath,
		path: row.path,
		rowId: productRowId(row.path),
		sizeBytes: row.sizeBytes ?? null,
	};
}

function productRowId(path: string): string {
	return `dev-row-${createHash('sha256').update(path).digest('hex').slice(0, 24)}`;
}
