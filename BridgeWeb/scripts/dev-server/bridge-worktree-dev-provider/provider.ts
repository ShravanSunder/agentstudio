import type {
	WorktreeFileDescriptor,
	WorktreeFileInvalidatedFrame,
	WorktreeFileProtocolFrame,
	WorktreeFileSurfaceSourceIdentity,
	WorktreeTreeRowMetadata,
	WorktreeTreeVirtualizedSizeFacts,
} from '../bridge-worktree-dev-file-fixture-contracts.js';
import type { BridgeWorktreeDevProviderConfig, BridgeWorktreeDevScenarioName } from './config.ts';
import { hydrateBridgeWorktreeDevContentWindow } from './content.ts';
import {
	bridgeWorktreeDevRootTokenForPath,
	byteLength,
	extensionForPath,
	hashText,
	languageForExtension,
	renderLineCount,
	resolveAllowedWorktreeRoot,
} from './files.ts';
import {
	loadBridgeWorktreeDevMetadataSnapshot,
	type BridgeWorktreeChangedFileMetadata,
	type BridgeWorktreeDevMetadataSnapshot,
} from './metadata.ts';
import {
	BRIDGE_WORKTREE_DEV_MAXIMUM_CONTENT_BYTES,
	defaultBridgeWorktreeDevPorts,
	type BridgeWorktreeDevPorts,
} from './ports.ts';

const worktreeFileSubscriptionGeneration = 1;
const worktreeFileProtocol = 'worktree-file';
const worktreeFilePaneId = 'bridge-worktree-dev-pane';
const worktreeFileSourceId = 'dev-worktree-source';
const worktreeFileStreamId = `${worktreeFileProtocol}:${worktreeFilePaneId}`;
const worktreeFileSourceCursor = `cursor-generation-${worktreeFileSubscriptionGeneration}`;
const worktreeFileRowHeightPixels = 24;
const worktreeFileTreeWindowRowLimit = 200;
export const BRIDGE_WORKTREE_DEV_RETAINED_PROVIDER_STATE_LIMIT = 4;
export const BRIDGE_WORKTREE_DEV_RETAINED_CONTENT_BODY_LIMIT = 8;
export const BRIDGE_WORKTREE_DEV_RETAINED_CONTENT_BYTE_LIMIT = 32 * 1024 * 1024;

export interface BridgeWorktreeDevProviderWorktreeFileContentRequest {
	readonly descriptorId: string;
	readonly signal?: AbortSignal | undefined;
	readonly sourceCursor: string;
	readonly subscriptionGeneration: number;
}

export interface BridgeWorktreeDevProviderWorktreeFileDescriptorRequest {
	readonly maximumBytes?: number;
	readonly path: string;
	readonly signal?: AbortSignal | undefined;
	readonly sourceCursor: string;
	readonly subscriptionGeneration: number;
}

export interface BridgeWorktreeDevProviderWorktreeFileSurface {
	readonly frames: readonly WorktreeFileProtocolFrame[];
	readonly provenance: BridgeWorktreeDevProviderProvenance;
	readonly source: WorktreeFileSurfaceSourceIdentity;
	readonly treeSizeFacts: WorktreeTreeVirtualizedSizeFacts;
}

export interface BridgeWorktreeDevProviderProvenance {
	readonly baseRef: string;
	readonly scenarioName: BridgeWorktreeDevScenarioName;
	readonly worktreeRootToken: string;
}

export interface BridgeWorktreeDevProvider {
	readonly diagnostics?: (() => BridgeWorktreeDevProviderDiagnostics) | undefined;
	readonly loadWorktreeFileDescriptor: (
		request: BridgeWorktreeDevProviderWorktreeFileDescriptorRequest,
	) => Promise<
		Extract<WorktreeFileProtocolFrame, { readonly frameKind: 'worktree.fileDescriptor' }>
	>;
	readonly loadWorktreeFileContent: (
		request: BridgeWorktreeDevProviderWorktreeFileContentRequest,
	) => Promise<string>;
	readonly loadWorktreeFileSurface: () => Promise<BridgeWorktreeDevProviderWorktreeFileSurface>;
}

export interface BridgeWorktreeDevProviderDiagnostics {
	readonly retainedContentBodyCount: number;
	readonly retainedContentByteCount: number;
	readonly retainedProviderStateCount: number;
}

export interface CreateBridgeWorktreeDevProviderOptions {
	readonly ports?: BridgeWorktreeDevPorts;
	readonly signal?: AbortSignal | undefined;
}

interface ContentLocator {
	readonly changedFile: BridgeWorktreeChangedFileMetadata;
	readonly expectedSha256: string;
	readonly maximumBytes: number;
	readonly worktreeRoot: string;
}

interface ProviderState {
	readonly changedFileByPath: ReadonlyMap<string, BridgeWorktreeChangedFileMetadata>;
	readonly currentFilePaths: ReadonlySet<string>;
	readonly fingerprint: string;
	readonly revision: number;
	readonly worktreeFileDescriptorById: Map<string, WorktreeFileDescriptor>;
	readonly worktreeFileDescriptorByPath: Map<string, WorktreeFileDescriptor>;
	readonly worktreeFileDescriptorSequenceByPath: Map<string, number>;
	readonly worktreeFileSurface: BridgeWorktreeDevProviderWorktreeFileSurface;
	readonly worktreeRoot: string;
}

interface RetainedContentBody {
	readonly byteLength: number;
	readonly text: string;
}

export async function createBridgeWorktreeDevProvider(
	config: BridgeWorktreeDevProviderConfig,
	options: CreateBridgeWorktreeDevProviderOptions = {},
): Promise<BridgeWorktreeDevProvider> {
	const parsedConfig = validateProviderConfig(config);
	const ports = options.ports ?? defaultBridgeWorktreeDevPorts;
	const worktreeRoot = await resolveAllowedWorktreeRoot(
		parsedConfig.worktreeRoot,
		ports,
		options.signal,
	);
	const worktreeRootToken = await bridgeWorktreeDevRootTokenForPath(
		worktreeRoot,
		ports,
		options.signal,
	);
	let state: ProviderState | null = null;
	const retainedStatesByFingerprint = new Map<string, ProviderState>();
	const contentLocatorByDescriptorId = new Map<string, ContentLocator>();
	const retainedContentByDescriptorId = new Map<string, RetainedContentBody>();
	let retainedContentByteCount = 0;

	const retainContent = (descriptorId: string, text: string): void => {
		const byteCount = byteLength(text);
		const previous = retainedContentByDescriptorId.get(descriptorId);
		if (previous !== undefined) retainedContentByteCount -= previous.byteLength;
		retainedContentByDescriptorId.delete(descriptorId);
		retainedContentByDescriptorId.set(descriptorId, { byteLength: byteCount, text });
		retainedContentByteCount += byteCount;
		while (
			retainedContentByDescriptorId.size > BRIDGE_WORKTREE_DEV_RETAINED_CONTENT_BODY_LIMIT ||
			retainedContentByteCount > BRIDGE_WORKTREE_DEV_RETAINED_CONTENT_BYTE_LIMIT
		) {
			const oldestDescriptorId = retainedContentByDescriptorId.keys().next().value;
			if (oldestDescriptorId === undefined) break;
			const removed = retainedContentByDescriptorId.get(oldestDescriptorId);
			retainedContentByDescriptorId.delete(oldestDescriptorId);
			retainedContentByteCount -= removed?.byteLength ?? 0;
		}
	};

	const loadCurrentState = async (): Promise<ProviderState> => {
		const snapshot = await loadBridgeWorktreeDevMetadataSnapshot({
			baseRef: parsedConfig.baseRef,
			ports,
			signal: options.signal,
			worktreeRoot,
		});
		const previousState = state;
		const revision =
			previousState === null
				? 1
				: previousState.fingerprint === snapshot.fingerprint
					? previousState.revision
					: previousState.revision + 1;
		const currentState = makeProviderState({
			config: parsedConfig,
			previousState,
			revision,
			snapshot,
			worktreeRoot,
			worktreeRootToken,
		});
		state = currentState;
		retainProviderState(retainedStatesByFingerprint, currentState);
		return currentState;
	};

	return {
		diagnostics: () => ({
			retainedContentBodyCount: retainedContentByDescriptorId.size,
			retainedContentByteCount,
			retainedProviderStateCount: retainedStatesByFingerprint.size,
		}),
		loadWorktreeFileDescriptor: async (request) => {
			const demandSignal = combinedSignal(options.signal, request.signal);
			throwIfAborted(demandSignal);
			const currentState = state ?? (await loadCurrentState());
			const acceptedState =
				providerStateForDescriptorRequest(currentState, request, retainedStatesByFingerprint) ??
				providerStateForDescriptorRequest(
					await loadCurrentState(),
					request,
					retainedStatesByFingerprint,
				);
			if (acceptedState === null) {
				rejectStaleDescriptorRequest(request, currentState.worktreeFileSurface.source);
				throw new Error('Unknown Bridge worktree file descriptor path');
			}
			const descriptor =
				acceptedState.worktreeFileDescriptorByPath.get(request.path) ??
				(await materializeDescriptor({
					contentLocatorByDescriptorId,
					maximumBytes: request.maximumBytes ?? BRIDGE_WORKTREE_DEV_MAXIMUM_CONTENT_BYTES,
					ports,
					request,
					retainContent,
					signal: demandSignal,
					state: acceptedState,
				}));
			if (descriptor === null) throw new Error('Unknown Bridge worktree file descriptor path');
			return {
				descriptor,
				frameKind: 'worktree.fileDescriptor',
				generation: acceptedState.worktreeFileSurface.source.subscriptionGeneration,
				kind: 'delta',
				sequence: acceptedState.worktreeFileDescriptorSequenceByPath.get(request.path) ?? 1,
				streamId: worktreeFileStreamId,
			};
		},
		loadWorktreeFileContent: async (request) => {
			const demandSignal = combinedSignal(options.signal, request.signal);
			throwIfAborted(demandSignal);
			const currentState = state ?? (await loadCurrentState());
			const acceptedState =
				providerStateForContentRequest(currentState, request, retainedStatesByFingerprint) ??
				providerStateForContentRequest(
					await loadCurrentState(),
					request,
					retainedStatesByFingerprint,
				);
			if (acceptedState === null) {
				rejectStaleContentRequest(request, currentState.worktreeFileSurface.source);
				throw new Error(`Unknown Bridge worktree file content descriptor: ${request.descriptorId}`);
			}
			const retainedContent = retainedContentByDescriptorId.get(request.descriptorId);
			if (retainedContent !== undefined) return retainedContent.text;
			const locator = contentLocatorByDescriptorId.get(request.descriptorId);
			if (locator === undefined) {
				throw new Error(`Unknown Bridge worktree file content descriptor: ${request.descriptorId}`);
			}
			const window = await hydrateBridgeWorktreeDevContentWindow({
				baseRef: parsedConfig.baseRef,
				changedFile: locator.changedFile,
				maximumBytes: locator.maximumBytes,
				ports,
				role: 'head',
				signal: demandSignal,
				startByte: 0,
				worktreeRoot: locator.worktreeRoot,
			});
			if (window.sha256 !== locator.expectedSha256) {
				throw new Error('Bridge worktree content changed after descriptor admission');
			}
			const text = decodeUtf8OrNull(window.bytes);
			if (text === null) {
				throw new Error('Bridge worktree content changed to unsupported encoding after admission');
			}
			retainContent(request.descriptorId, text);
			return text;
		},
		loadWorktreeFileSurface: async () => (await loadCurrentState()).worktreeFileSurface,
	};
}

async function materializeDescriptor(props: {
	readonly contentLocatorByDescriptorId: Map<string, ContentLocator>;
	readonly maximumBytes: number;
	readonly ports: BridgeWorktreeDevPorts;
	readonly request: BridgeWorktreeDevProviderWorktreeFileDescriptorRequest;
	readonly retainContent: (descriptorId: string, text: string) => void;
	readonly signal?: AbortSignal | undefined;
	readonly state: ProviderState;
}): Promise<WorktreeFileDescriptor | null> {
	const changedFile =
		props.state.changedFileByPath.get(props.request.path) ??
		metadataForUnchangedCurrentFile(props.request.path);
	if (changedFile.headPath === null) {
		const descriptor = unavailableDescriptor(changedFile, props.state.worktreeFileSurface.source);
		rememberDescriptor(props.state, descriptor, props.request.path);
		return descriptor;
	}
	if (!props.state.currentFilePaths.has(props.request.path)) return null;
	const window = await hydrateBridgeWorktreeDevContentWindow({
		baseRef: props.state.worktreeFileSurface.provenance.baseRef,
		changedFile,
		maximumBytes: props.maximumBytes,
		ports: props.ports,
		role: 'head',
		signal: props.signal,
		startByte: 0,
		worktreeRoot: props.state.worktreeRoot,
	});
	const text = decodeUtf8OrNull(window.bytes);
	if (window.bytes.includes(0) || text === null) {
		const descriptor = unavailableDescriptor(changedFile, props.state.worktreeFileSurface.source, {
			isBinary: window.bytes.includes(0),
			unavailableReason: text === null ? 'unsupported_encoding' : null,
		});
		rememberDescriptor(props.state, descriptor, props.request.path);
		return descriptor;
	}
	const descriptor = availableDescriptor({
		changedFile,
		contentSha256: window.sha256,
		endOfSource: window.endOfSource,
		sourceIdentity: props.state.worktreeFileSurface.source,
		text,
		totalByteLength: window.totalByteLength,
	});
	props.contentLocatorByDescriptorId.set(descriptor.contentHandle, {
		changedFile,
		expectedSha256: window.sha256,
		maximumBytes: props.maximumBytes,
		worktreeRoot: props.state.worktreeRoot,
	});
	props.retainContent(descriptor.contentHandle, text);
	rememberDescriptor(props.state, descriptor, props.request.path);
	return descriptor;
}

function rememberDescriptor(
	state: ProviderState,
	descriptor: WorktreeFileDescriptor,
	path: string,
): void {
	state.worktreeFileDescriptorByPath.set(path, descriptor);
	state.worktreeFileDescriptorById.set(descriptor.contentHandle, descriptor);
	state.worktreeFileDescriptorSequenceByPath.set(path, nextDemandFrameSequence(state));
}

function makeProviderState(props: {
	readonly config: BridgeWorktreeDevProviderConfig;
	readonly previousState: ProviderState | null;
	readonly revision: number;
	readonly snapshot: BridgeWorktreeDevMetadataSnapshot;
	readonly worktreeRoot: string;
	readonly worktreeRootToken: string;
}): ProviderState {
	const sourceIdentity: WorktreeFileSurfaceSourceIdentity = {
		repoId: 'dev-worktree-repo',
		rootRevisionToken: props.snapshot.fingerprint,
		sourceCursor: worktreeFileSourceCursor,
		sourceId: worktreeFileSourceId,
		subscriptionGeneration: worktreeFileSubscriptionGeneration,
		worktreeId: 'dev-worktree',
	};
	const treeRows = worktreeTreeRowsForCurrentFiles(props.snapshot);
	const renderedTreeRowCount = countFlattenedRows(props.snapshot.currentFilePaths);
	const initialTreeRows = treeRows.slice(0, worktreeFileTreeWindowRowLimit);
	const treeSizeFacts = exactTreeSizeFacts(renderedTreeRowCount, initialTreeRows.length, 0);
	const surfaceFrames = worktreeFileSurfaceFramesForTreeRows({
		initialTreeRows,
		renderedTreeRowCount,
		revision: props.revision,
		sourceIdentity,
		treeRows,
		treeSizeFacts,
	});
	const currentFilePaths = new Set(props.snapshot.currentFilePaths);
	const changedFileByPath = new Map(props.snapshot.changedFiles.map((file) => [file.path, file]));
	const invalidations = invalidationFrames({
		changedFileByPath,
		currentFilePaths,
		previousState: props.previousState,
		sequenceStart: surfaceFrames.length,
		sourceIdentity,
	});
	return {
		changedFileByPath,
		currentFilePaths,
		fingerprint: props.snapshot.fingerprint,
		revision: props.revision,
		worktreeFileDescriptorById: new Map(),
		worktreeFileDescriptorByPath: new Map(),
		worktreeFileDescriptorSequenceByPath: new Map(),
		worktreeFileSurface: {
			frames: [...surfaceFrames, ...invalidations],
			provenance: {
				baseRef: props.config.baseRef,
				scenarioName: props.config.scenarioName,
				worktreeRootToken: props.worktreeRootToken,
			},
			source: sourceIdentity,
			treeSizeFacts,
		},
		worktreeRoot: props.worktreeRoot,
	};
}

function worktreeFileSurfaceFramesForTreeRows(props: {
	readonly initialTreeRows: readonly WorktreeTreeRowMetadata[];
	readonly renderedTreeRowCount: number;
	readonly revision: number;
	readonly sourceIdentity: WorktreeFileSurfaceSourceIdentity;
	readonly treeRows: readonly WorktreeTreeRowMetadata[];
	readonly treeSizeFacts: WorktreeTreeVirtualizedSizeFacts;
}): readonly WorktreeFileProtocolFrame[] {
	const snapshotFrame = {
		frameKind: 'worktree.snapshot',
		generation: props.sourceIdentity.subscriptionGeneration,
		kind: 'snapshot',
		metadataLineage: { lane: 'foreground', loadedBy: 'startup_window' },
		sequence: 0,
		source: props.sourceIdentity,
		streamId: worktreeFileStreamId,
		treeRows: [...props.initialTreeRows],
		treeSizeFacts: props.treeSizeFacts,
	} satisfies Extract<WorktreeFileProtocolFrame, { readonly frameKind: 'worktree.snapshot' }>;
	return [
		snapshotFrame,
		...worktreeFileTreeWindowFrames({
			renderedTreeRowCount: props.renderedTreeRowCount,
			revision: props.revision,
			sourceIdentity: props.sourceIdentity,
			treeRows: props.treeRows,
		}),
	];
}

function worktreeFileTreeWindowFrames(props: {
	readonly renderedTreeRowCount: number;
	readonly revision: number;
	readonly sourceIdentity: WorktreeFileSurfaceSourceIdentity;
	readonly treeRows: readonly WorktreeTreeRowMetadata[];
}): readonly Extract<WorktreeFileProtocolFrame, { readonly frameKind: 'worktree.treeWindow' }>[] {
	const frames: Extract<
		WorktreeFileProtocolFrame,
		{ readonly frameKind: 'worktree.treeWindow' }
	>[] = [];
	for (
		let windowStartIndex = worktreeFileTreeWindowRowLimit;
		windowStartIndex < props.treeRows.length;
		windowStartIndex += worktreeFileTreeWindowRowLimit
	) {
		const rows = props.treeRows.slice(
			windowStartIndex,
			windowStartIndex + worktreeFileTreeWindowRowLimit,
		);
		frames.push({
			frameKind: 'worktree.treeWindow',
			generation: props.sourceIdentity.subscriptionGeneration,
			kind: 'delta',
			metadataLineage: { lane: 'idle', loadedBy: 'idle' },
			projectionIdentity: {
				filterKey: 'all',
				groupKey: 'none',
				pathScope: [],
				sortKey: 'path',
				source: props.sourceIdentity,
				treeWindowKey: `dev-tree-window-${props.revision}-${windowStartIndex}`,
			},
			rows,
			sequence: frames.length + 1,
			streamId: worktreeFileStreamId,
			treeSizeFacts: exactTreeSizeFacts(props.renderedTreeRowCount, rows.length, windowStartIndex),
		});
	}
	return frames;
}

function invalidationFrames(props: {
	readonly changedFileByPath: ReadonlyMap<string, BridgeWorktreeChangedFileMetadata>;
	readonly currentFilePaths: ReadonlySet<string>;
	readonly previousState: ProviderState | null;
	readonly sequenceStart: number;
	readonly sourceIdentity: WorktreeFileSurfaceSourceIdentity;
}): readonly WorktreeFileInvalidatedFrame[] {
	if (props.previousState === null) return [];
	const frames: WorktreeFileInvalidatedFrame[] = [];
	for (const descriptor of props.previousState.worktreeFileDescriptorByPath.values()) {
		const latestChange = props.changedFileByPath.get(descriptor.path);
		const previousChange = props.previousState.changedFileByPath.get(descriptor.path);
		const removed = !props.currentFilePaths.has(descriptor.path);
		const changed =
			latestChange !== undefined &&
			JSON.stringify(latestChange) !== JSON.stringify(previousChange ?? null);
		if (!removed && !changed) continue;
		frames.push({
			frameKind: 'worktree.fileInvalidated',
			generation: props.sourceIdentity.subscriptionGeneration,
			invalidation: {
				contentHandleIds: [descriptor.contentHandle],
				fileId: descriptor.fileId,
				path: descriptor.path,
				reason: removed ? 'filesystemEvent' : 'contentChanged',
			},
			kind: 'delta',
			sequence: props.sequenceStart + frames.length,
			streamId: worktreeFileStreamId,
		});
	}
	return frames;
}

function worktreeTreeRowsForCurrentFiles(
	snapshot: BridgeWorktreeDevMetadataSnapshot,
): WorktreeTreeRowMetadata[] {
	const changedFilesByPath = new Map(snapshot.changedFiles.map((file) => [file.path, file]));
	const rowsByPath = new Map<string, WorktreeTreeRowMetadata>();
	for (const currentFilePath of snapshot.currentFilePaths) {
		const parts = currentFilePath.split('/').filter((part) => part.length > 0);
		let parentPath: string | null = null;
		for (const [partIndex, part] of parts.entries()) {
			const path = parts.slice(0, partIndex + 1).join('/');
			if (rowsByPath.has(path)) {
				parentPath = path;
				continue;
			}
			const isDirectory = partIndex < parts.length - 1;
			const changedFile = changedFilesByPath.get(currentFilePath);
			rowsByPath.set(path, {
				depth: partIndex,
				isDirectory,
				name: part,
				parentPath,
				path,
				rowId: `row:${path}`,
				...(isDirectory
					? {}
					: {
							fileId: `dev-file-id-${hashText(currentFilePath).slice(0, 16)}`,
							...(changedFile === undefined
								? {}
								: {
										changeStatus: changedFile.changeKind,
										sizeBytes: changedFile.headFileMetadata?.sizeBytes,
									}),
						}),
			});
			parentPath = path;
		}
	}
	return [...rowsByPath.values()];
}

function availableDescriptor(props: {
	readonly changedFile: BridgeWorktreeChangedFileMetadata;
	readonly contentSha256: string;
	readonly endOfSource: boolean;
	readonly sourceIdentity: WorktreeFileSurfaceSourceIdentity;
	readonly text: string;
	readonly totalByteLength: number;
}): WorktreeFileDescriptor {
	const pathHash = hashText(props.changedFile.path).slice(0, 16);
	const descriptorId = `dev-file-${pathHash}-${props.contentSha256.slice(0, 16)}`;
	const extension = extensionForPath(props.changedFile.path);
	return {
		contentHandle: descriptorId,
		contentHash: `sha256:${props.contentSha256}`,
		fileExtension: extension,
		fileId: `dev-file-id-${pathHash}`,
		isBinary: false,
		unavailableReason: null,
		language: languageForExtension(extension),
		lineCount: props.endOfSource ? renderLineCount(props.text) : undefined,
		modifiedAtUnixMilliseconds: props.changedFile.headFileMetadata?.modifiedAtUnixMilliseconds,
		path: props.changedFile.path,
		sizeBytes: props.totalByteLength,
		sourceIdentity: props.sourceIdentity,
		virtualizedExtentKind: props.endOfSource ? 'exactLineCount' : 'previewBounded',
	};
}

function unavailableDescriptor(
	changedFile: BridgeWorktreeChangedFileMetadata,
	sourceIdentity: WorktreeFileSurfaceSourceIdentity,
	availability: {
		readonly isBinary: boolean;
		readonly unavailableReason: 'unreadable' | 'unsupported_encoding' | null;
	} = { isBinary: false, unavailableReason: 'unreadable' },
): WorktreeFileDescriptor {
	const pathHash = hashText(changedFile.path).slice(0, 16);
	const descriptorId = `dev-file-unavailable-${pathHash}`;
	const extension = extensionForPath(changedFile.path);
	return {
		contentHandle: descriptorId,
		fileExtension: extension,
		fileId: `dev-file-id-${pathHash}`,
		isBinary: availability.isBinary,
		unavailableReason: availability.unavailableReason,
		language: languageForExtension(extension),
		path: changedFile.path,
		sizeBytes: 0,
		sourceIdentity,
		virtualizedExtentKind: 'unavailable',
	};
}

function providerStateForDescriptorRequest(
	state: ProviderState,
	request: BridgeWorktreeDevProviderWorktreeFileDescriptorRequest,
	retainedStates: ReadonlyMap<string, ProviderState>,
): ProviderState | null {
	if (!providerStateMatchesRequest(state, request)) return null;
	if (state.currentFilePaths.has(request.path) || state.changedFileByPath.has(request.path))
		return state;
	return (
		[...retainedStates.values()].find(
			(candidate) =>
				providerStateMatchesRequest(candidate, request) &&
				(candidate.currentFilePaths.has(request.path) ||
					candidate.changedFileByPath.has(request.path)),
		) ?? null
	);
}

function providerStateForContentRequest(
	state: ProviderState,
	request: BridgeWorktreeDevProviderWorktreeFileContentRequest,
	retainedStates: ReadonlyMap<string, ProviderState>,
): ProviderState | null {
	if (!providerStateMatchesRequest(state, request)) return null;
	if (state.worktreeFileDescriptorById.has(request.descriptorId)) return state;
	return (
		[...retainedStates.values()].find(
			(candidate) =>
				providerStateMatchesRequest(candidate, request) &&
				candidate.worktreeFileDescriptorById.has(request.descriptorId),
		) ?? null
	);
}

function providerStateMatchesRequest(
	state: ProviderState,
	request: { readonly sourceCursor: string; readonly subscriptionGeneration: number },
): boolean {
	return (
		request.sourceCursor === state.worktreeFileSurface.source.sourceCursor &&
		request.subscriptionGeneration === state.worktreeFileSurface.source.subscriptionGeneration
	);
}

function rejectStaleDescriptorRequest(
	request: BridgeWorktreeDevProviderWorktreeFileDescriptorRequest,
	source: WorktreeFileSurfaceSourceIdentity,
): void {
	if (request.subscriptionGeneration !== source.subscriptionGeneration) {
		throw new Error(
			`Rejected stale Bridge worktree file descriptor generation: ${request.subscriptionGeneration}`,
		);
	}
	if (request.sourceCursor !== source.sourceCursor) {
		throw new Error(
			`Rejected stale Bridge worktree file descriptor cursor: ${request.sourceCursor}`,
		);
	}
}

function rejectStaleContentRequest(
	request: BridgeWorktreeDevProviderWorktreeFileContentRequest,
	source: WorktreeFileSurfaceSourceIdentity,
): void {
	if (request.subscriptionGeneration !== source.subscriptionGeneration) {
		throw new Error(
			`Rejected stale Bridge worktree file content generation: ${request.subscriptionGeneration}`,
		);
	}
	if (request.sourceCursor !== source.sourceCursor) {
		throw new Error(`Rejected stale Bridge worktree file content cursor: ${request.sourceCursor}`);
	}
}

function retainProviderState(
	retainedStates: Map<string, ProviderState>,
	state: ProviderState,
): void {
	retainedStates.set(state.fingerprint, state);
	while (retainedStates.size > BRIDGE_WORKTREE_DEV_RETAINED_PROVIDER_STATE_LIMIT) {
		const oldestFingerprint = retainedStates.keys().next().value;
		if (oldestFingerprint === undefined) return;
		retainedStates.delete(oldestFingerprint);
	}
}

function nextDemandFrameSequence(state: ProviderState): number {
	return (
		Math.max(
			...state.worktreeFileSurface.frames.map((frame) => frame.sequence),
			...state.worktreeFileDescriptorSequenceByPath.values(),
		) + 1
	);
}

function exactTreeSizeFacts(
	renderedTreeRowCount: number,
	windowRowCount: number,
	windowStartIndex: number,
): WorktreeTreeVirtualizedSizeFacts {
	return {
		estimatedTotalHeightPixels: renderedTreeRowCount * worktreeFileRowHeightPixels,
		extentKind: 'exactPathCount',
		pathCount: renderedTreeRowCount,
		rowHeightPixels: worktreeFileRowHeightPixels,
		windowRowCount,
		windowStartIndex,
	};
}

function countFlattenedRows(paths: readonly string[]): number {
	const rowPaths = new Set<string>();
	for (const path of paths) {
		const parts = path.split('/').filter((part) => part.length > 0);
		for (let partIndex = 0; partIndex < parts.length; partIndex += 1) {
			rowPaths.add(parts.slice(0, partIndex + 1).join('/'));
		}
	}
	return rowPaths.size;
}

function metadataForUnchangedCurrentFile(path: string): BridgeWorktreeChangedFileMetadata {
	return {
		additions: 0,
		basePath: path,
		changeKind: 'modified',
		deletions: 0,
		headFileMetadata: null,
		headPath: path,
		path,
	};
}

function decodeUtf8OrNull(bytes: Uint8Array): string | null {
	try {
		return new TextDecoder('utf-8', { fatal: true }).decode(bytes);
	} catch {
		return null;
	}
}

function combinedSignal(
	providerSignal: AbortSignal | undefined,
	requestSignal: AbortSignal | undefined,
): AbortSignal | undefined {
	if (providerSignal === undefined) return requestSignal;
	if (requestSignal === undefined) return providerSignal;
	return AbortSignal.any([providerSignal, requestSignal]);
}

function throwIfAborted(signal: AbortSignal | undefined): void {
	if (signal?.aborted !== true) return;
	const error = new Error('Bridge worktree provider demand was cancelled');
	error.name = 'AbortError';
	throw error;
}

function validateProviderConfig(
	config: BridgeWorktreeDevProviderConfig,
): BridgeWorktreeDevProviderConfig {
	if (
		config.baseRef.length === 0 ||
		config.scenarioName !== 'current-worktree' ||
		config.worktreeRoot.length === 0
	) {
		throw new Error('Invalid Bridge worktree dev provider config');
	}
	return config;
}
