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
import type {
	WorktreeFileDescriptor,
	WorktreeTreeRowMetadata,
} from '../../src/features/worktree-file/models/worktree-file-protocol-models.js';
import {
	deriveBridgeProductDevFilePrefix,
	type BridgeProductDevFilePrefix,
} from './bridge-product-dev-file-prefix.js';
import type { BridgeWorktreeDevProvider } from './bridge-worktree-dev-provider.js';

const bridgeProductDevRepoId = '00000000-0000-4000-8000-000000000001';
const bridgeProductDevWorktreeId = '00000000-0000-4000-8000-000000000002';
export const BRIDGE_PRODUCT_DEV_FILE_MAXIMUM_LINES = 10_000;

type BridgeProductFileEvent = BridgeProductSubscriptionEvent<'file.metadata'>;
type BridgeProductFileDescriptorReadyEvent = Extract<
	BridgeProductFileEvent,
	{ readonly eventKind: 'file.descriptorReady' }
>;

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
		const legacyFrame = await this.#provider.loadWorktreeFileDescriptor({
			path,
			sourceCursor: sourceSnapshot.identity.sourceCursor,
			subscriptionGeneration: sourceSnapshot.identity.subscriptionGeneration,
		});
		return await this.#descriptorEvent(legacyFrame.descriptor, sourceSnapshot.identity);
	}

	content(descriptor: BridgeProductFileContentDescriptor): BridgeProductDevFileContent | null {
		const content = this.#contentByDescriptorId.get(descriptor.descriptorId);
		if (content === undefined) return null;
		return JSON.stringify(content.descriptor) === JSON.stringify(descriptor) ? content : null;
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
		source: BridgeProductFileSourceIdentity,
	): Promise<BridgeProductFileDescriptorReadyEvent> {
		if (descriptor.isBinary || descriptor.virtualizedExtentKind === 'unavailable') {
			return parseFileDescriptorReadyEvent({
				availability: descriptor.isBinary
					? { availabilityKind: 'binary' }
					: { availabilityKind: 'unavailable', reason: 'unreadable' },
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

		const contentText = await this.#provider.loadWorktreeFileContent({
			descriptorId: descriptor.contentHandle,
			sourceCursor: source.sourceCursor,
			subscriptionGeneration: source.subscriptionGeneration,
		});
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
