import type {
	BridgeAttachedResourceDescriptor,
	BridgeResourceDescriptor,
} from '../../../src/core/models/bridge-resource-descriptor.js';
import { bridgeAttachedResourceDescriptorSchema } from '../../../src/core/models/bridge-resource-descriptor.js';
import type {
	WorktreeFileDescriptor,
	WorktreeFileInvalidatedFrame,
	WorktreeFileProtocolFrame,
	WorktreeFileSurfaceSourceIdentity,
	WorktreeTreeRowMetadata,
	WorktreeTreeVirtualizedSizeFacts,
} from '../../../src/features/worktree-file/models/worktree-file-protocol-models.js';
import {
	worktreeFileInvalidatedFrameSchema,
	worktreeFileProtocolFrameSchema,
} from '../../../src/features/worktree-file/models/worktree-file-protocol-models.js';
import { countFlattenedWorktreeFileTreeRows } from '../../../src/features/worktree-file/models/worktree-file-tree-size.js';
import type { BridgeWorktreeDevProviderConfig, BridgeWorktreeDevScenarioName } from './config.ts';
import { bridgeWorktreeDevProviderConfigSchema } from './config.ts';
import {
	bridgeWorktreeDevRootTokenForPath,
	byteLength,
	extensionForPath,
	hashText,
	languageForExtension,
	loadBridgeWorktreeDevSnapshot,
	mimeTypeForExtension,
	readWorktreeFileText,
	renderLineCount,
	resolveAllowedWorktreeRoot,
	type BridgeWorktreeChangedFile,
	type BridgeWorktreeDevSnapshot,
} from './files.ts';

const worktreeFileSubscriptionGeneration = 1;
const worktreeFileProtocol = 'worktree-file';
const worktreeFilePaneId = 'bridge-worktree-dev-pane';
const worktreeFileSourceId = 'dev-worktree-source';
const worktreeFileStreamId = `${worktreeFileProtocol}:${worktreeFilePaneId}`;
const worktreeFileSourceCursor = `cursor-generation-${worktreeFileSubscriptionGeneration}`;
const worktreeFileRowHeightPixels = 24;
const worktreeFileTreeWindowRowLimit = 200;
const retainedProviderStateLimit = 4;

export interface BridgeWorktreeDevProviderWorktreeFileContentRequest {
	readonly descriptorId: string;
	readonly sourceCursor: string;
	readonly subscriptionGeneration: number;
}

export interface BridgeWorktreeDevProviderWorktreeFileDescriptorRequest {
	readonly path: string;
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

interface ProviderState {
	readonly currentFilePaths: ReadonlySet<string>;
	readonly fingerprint: string;
	readonly revision: number;
	readonly worktreeFileDescriptorByPath: Map<string, WorktreeFileDescriptor>;
	readonly worktreeFileDescriptorSequenceByPath: Map<string, number>;
	readonly worktreeFileContentByDescriptorId: Map<string, string>;
	readonly worktreeFileSurface: BridgeWorktreeDevProviderWorktreeFileSurface;
	readonly worktreeRoot: string;
}

export async function createBridgeWorktreeDevProvider(
	config: BridgeWorktreeDevProviderConfig,
): Promise<BridgeWorktreeDevProvider> {
	const parsedConfig = bridgeWorktreeDevProviderConfigSchema.parse(config);
	const worktreeRoot = await resolveAllowedWorktreeRoot(parsedConfig.worktreeRoot);
	const worktreeRootToken = await bridgeWorktreeDevRootTokenForPath(worktreeRoot);
	let state: ProviderState | null = null;
	const retainedStatesByFingerprint = new Map<string, ProviderState>();

	const loadCurrentState = async (): Promise<ProviderState> => {
		const snapshot = await loadBridgeWorktreeDevSnapshot({
			baseRef: parsedConfig.baseRef,
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
		retainProviderState({
			retainedStatesByFingerprint,
			state: currentState,
		});
		return currentState;
	};

	return {
		loadWorktreeFileDescriptor: async (
			request: BridgeWorktreeDevProviderWorktreeFileDescriptorRequest,
		): Promise<
			Extract<WorktreeFileProtocolFrame, { readonly frameKind: 'worktree.fileDescriptor' }>
		> => {
			const currentState = state ?? (await loadCurrentState());
			const acceptedState =
				providerStateForDescriptorRequest({
					request,
					retainedStatesByFingerprint,
					state: currentState,
				}) ??
				providerStateForDescriptorRequest({
					request,
					retainedStatesByFingerprint,
					state: await loadCurrentState(),
				});
			if (acceptedState !== null) {
				return await descriptorFrameFromAcceptedProviderState({ request, state: acceptedState });
			}
			rejectStaleDescriptorRequest({
				request,
				source: currentState.worktreeFileSurface.source,
			});
			throw new Error(`Unknown Bridge worktree file descriptor path: ${request.path}`);
		},
		loadWorktreeFileContent: async (
			request: BridgeWorktreeDevProviderWorktreeFileContentRequest,
		): Promise<string> => {
			const currentState = state ?? (await loadCurrentState());
			const acceptedState =
				providerStateForContentRequest({
					request,
					retainedStatesByFingerprint,
					state: currentState,
				}) ??
				providerStateForContentRequest({
					request,
					retainedStatesByFingerprint,
					state: await loadCurrentState(),
				});
			if (acceptedState !== null) {
				return contentFromAcceptedProviderState({ request, state: acceptedState });
			}
			rejectStaleContentRequest({
				request,
				source: currentState.worktreeFileSurface.source,
			});
			throw new Error(`Unknown Bridge worktree file content descriptor: ${request.descriptorId}`);
		},
		loadWorktreeFileSurface: async (): Promise<BridgeWorktreeDevProviderWorktreeFileSurface> => {
			const currentState = await loadCurrentState();
			return currentState.worktreeFileSurface;
		},
	};
}

function retainProviderState(props: {
	readonly retainedStatesByFingerprint: Map<string, ProviderState>;
	readonly state: ProviderState;
}): void {
	props.retainedStatesByFingerprint.set(props.state.fingerprint, props.state);
	while (props.retainedStatesByFingerprint.size > retainedProviderStateLimit) {
		const oldestFingerprint = props.retainedStatesByFingerprint.keys().next().value;
		if (oldestFingerprint === undefined) {
			return;
		}
		props.retainedStatesByFingerprint.delete(oldestFingerprint);
	}
}

function providerStateForDescriptorRequest(props: {
	readonly request: BridgeWorktreeDevProviderWorktreeFileDescriptorRequest;
	readonly retainedStatesByFingerprint: ReadonlyMap<string, ProviderState>;
	readonly state: ProviderState | null;
}): ProviderState | null {
	if (props.state === null || !providerStateMatchesDescriptorRequest(props.state, props.request)) {
		return null;
	}
	if (
		props.state.currentFilePaths.has(props.request.path) ||
		props.state.worktreeFileDescriptorByPath.has(props.request.path)
	) {
		return props.state;
	}
	for (const retainedState of props.retainedStatesByFingerprint.values()) {
		if (
			providerStateMatchesDescriptorRequest(retainedState, props.request) &&
			(retainedState.currentFilePaths.has(props.request.path) ||
				retainedState.worktreeFileDescriptorByPath.has(props.request.path))
		) {
			return retainedState;
		}
	}
	return null;
}

function providerStateForContentRequest(props: {
	readonly request: BridgeWorktreeDevProviderWorktreeFileContentRequest;
	readonly retainedStatesByFingerprint: ReadonlyMap<string, ProviderState>;
	readonly state: ProviderState | null;
}): ProviderState | null {
	if (props.state === null || !providerStateMatchesContentRequest(props.state, props.request)) {
		return null;
	}
	if (props.state.worktreeFileContentByDescriptorId.has(props.request.descriptorId)) {
		return props.state;
	}
	for (const retainedState of props.retainedStatesByFingerprint.values()) {
		if (
			providerStateMatchesContentRequest(retainedState, props.request) &&
			retainedState.worktreeFileContentByDescriptorId.has(props.request.descriptorId)
		) {
			return retainedState;
		}
	}
	return null;
}

async function descriptorFrameFromAcceptedProviderState(props: {
	readonly request: BridgeWorktreeDevProviderWorktreeFileDescriptorRequest;
	readonly state: ProviderState;
}): Promise<Extract<WorktreeFileProtocolFrame, { readonly frameKind: 'worktree.fileDescriptor' }>> {
	const descriptor =
		props.state.worktreeFileDescriptorByPath.get(props.request.path) ??
		(await materializeCurrentWorktreeFileDescriptorForDemand(props));
	if (descriptor === null) {
		throw new Error(`Unknown Bridge worktree file descriptor path: ${props.request.path}`);
	}
	return {
		kind: 'delta',
		streamId: worktreeFileStreamId,
		generation: props.state.worktreeFileSurface.source.subscriptionGeneration,
		sequence: props.state.worktreeFileDescriptorSequenceByPath.get(props.request.path) ?? 1,
		frameKind: 'worktree.fileDescriptor',
		descriptor,
	};
}

async function materializeCurrentWorktreeFileDescriptorForDemand(props: {
	readonly request: BridgeWorktreeDevProviderWorktreeFileDescriptorRequest;
	readonly state: ProviderState;
}): Promise<WorktreeFileDescriptor | null> {
	if (!props.state.currentFilePaths.has(props.request.path)) {
		return null;
	}
	const descriptor = await worktreeFileDescriptorForCurrentFile({
		path: props.request.path,
		sourceIdentity: props.state.worktreeFileSurface.source,
		worktreeFileContentByDescriptorId: props.state.worktreeFileContentByDescriptorId,
		worktreeRoot: props.state.worktreeRoot,
	});
	props.state.worktreeFileDescriptorByPath.set(props.request.path, descriptor);
	props.state.worktreeFileDescriptorSequenceByPath.set(
		props.request.path,
		nextDemandFrameSequence(props.state),
	);
	return descriptor;
}

function contentFromAcceptedProviderState(props: {
	readonly request: BridgeWorktreeDevProviderWorktreeFileContentRequest;
	readonly state: ProviderState;
}): string {
	const content = props.state.worktreeFileContentByDescriptorId.get(props.request.descriptorId);
	if (content === undefined) {
		throw new Error(
			`Unknown Bridge worktree file content descriptor: ${props.request.descriptorId}`,
		);
	}
	return content;
}

function providerStateMatchesContentRequest(
	state: ProviderState,
	request: BridgeWorktreeDevProviderWorktreeFileContentRequest,
): boolean {
	return (
		request.subscriptionGeneration === state.worktreeFileSurface.source.subscriptionGeneration &&
		request.sourceCursor === state.worktreeFileSurface.source.sourceCursor
	);
}

function providerStateMatchesDescriptorRequest(
	state: ProviderState,
	request: BridgeWorktreeDevProviderWorktreeFileDescriptorRequest,
): boolean {
	return (
		request.subscriptionGeneration === state.worktreeFileSurface.source.subscriptionGeneration &&
		request.sourceCursor === state.worktreeFileSurface.source.sourceCursor
	);
}

function rejectStaleContentRequest(props: {
	readonly request: BridgeWorktreeDevProviderWorktreeFileContentRequest;
	readonly source: WorktreeFileSurfaceSourceIdentity;
}): void {
	if (props.request.subscriptionGeneration !== props.source.subscriptionGeneration) {
		throw new Error(
			`Rejected stale Bridge worktree file content generation: ${props.request.subscriptionGeneration}`,
		);
	}
	if (props.request.sourceCursor !== props.source.sourceCursor) {
		throw new Error(
			`Rejected stale Bridge worktree file content cursor: ${props.request.sourceCursor}`,
		);
	}
}

function rejectStaleDescriptorRequest(props: {
	readonly request: BridgeWorktreeDevProviderWorktreeFileDescriptorRequest;
	readonly source: WorktreeFileSurfaceSourceIdentity;
}): void {
	if (props.request.subscriptionGeneration !== props.source.subscriptionGeneration) {
		throw new Error(
			`Rejected stale Bridge worktree file descriptor generation: ${props.request.subscriptionGeneration}`,
		);
	}
	if (props.request.sourceCursor !== props.source.sourceCursor) {
		throw new Error(
			`Rejected stale Bridge worktree file descriptor cursor: ${props.request.sourceCursor}`,
		);
	}
}

function makeProviderState(props: {
	readonly config: BridgeWorktreeDevProviderConfig;
	readonly previousState: ProviderState | null;
	readonly revision: number;
	readonly snapshot: BridgeWorktreeDevSnapshot;
	readonly worktreeRoot: string;
	readonly worktreeRootToken: string;
}): ProviderState {
	const sourceIdentity: WorktreeFileSurfaceSourceIdentity = {
		sourceId: worktreeFileSourceId,
		repoId: 'dev-worktree-repo',
		worktreeId: 'dev-worktree',
		subscriptionGeneration: worktreeFileSubscriptionGeneration,
		sourceCursor: worktreeFileSourceCursor,
		rootRevisionToken: props.snapshot.fingerprint,
	};
	const worktreeFileContentByDescriptorId = new Map<string, string>();
	const treeRows = worktreeTreeRowsForCurrentFiles({
		changedFiles: props.snapshot.changedFiles,
		currentFilePaths: props.snapshot.currentFilePaths,
	});
	const renderedTreeRowCount = countFlattenedWorktreeFileTreeRows(props.snapshot.currentFilePaths);
	const initialTreeRows = treeRows.slice(0, worktreeFileTreeWindowRowLimit);
	const treeSizeFacts = exactTreeSizeFacts({
		renderedTreeRowCount,
		windowRowCount: initialTreeRows.length,
		windowStartIndex: 0,
	});
	const worktreeFileDescriptors = props.snapshot.changedFiles.flatMap(
		(changedFile): readonly WorktreeFileDescriptor[] =>
			worktreeFileDescriptorForChangedFile({
				changedFile,
				sourceIdentity,
				worktreeFileContentByDescriptorId,
			}),
	);
	const currentFilePathSet = new Set(props.snapshot.currentFilePaths);
	const worktreeFileSurfaceFrames = worktreeFileSurfaceFramesForTreeRows({
		initialTreeRows,
		renderedTreeRowCount,
		revision: props.revision,
		sourceIdentity,
		treeRows,
		treeSizeFacts,
	});
	const invalidationFrames = worktreeFileInvalidationFramesForChangedDescriptors({
		currentFilePaths: currentFilePathSet,
		previousState: props.previousState,
		sequenceStart: worktreeFileSurfaceFrames.length,
		sourceIdentity,
		worktreeFileDescriptors,
	});
	const worktreeFileSurface: BridgeWorktreeDevProviderWorktreeFileSurface = {
		frames: [...worktreeFileSurfaceFrames, ...invalidationFrames],
		provenance: {
			baseRef: props.config.baseRef,
			scenarioName: props.config.scenarioName,
			worktreeRootToken: props.worktreeRootToken,
		},
		source: sourceIdentity,
		treeSizeFacts,
	};
	return {
		currentFilePaths: currentFilePathSet,
		fingerprint: props.snapshot.fingerprint,
		revision: props.revision,
		worktreeFileDescriptorByPath: new Map(
			worktreeFileDescriptors.map((descriptor) => [descriptor.path, descriptor]),
		),
		worktreeFileDescriptorSequenceByPath: new Map(
			worktreeFileDescriptors.map((descriptor, index) => [
				descriptor.path,
				worktreeFileSurfaceFrames.length + index,
			]),
		),
		worktreeFileContentByDescriptorId,
		worktreeFileSurface,
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
		kind: 'snapshot',
		streamId: worktreeFileStreamId,
		generation: props.sourceIdentity.subscriptionGeneration,
		sequence: 0,
		frameKind: 'worktree.snapshot',
		source: props.sourceIdentity,
		metadataLineage: {
			loadedBy: 'startup_window',
			lane: 'foreground',
		},
		treeRows: [...props.initialTreeRows],
		treeSizeFacts: props.treeSizeFacts,
	} satisfies Extract<WorktreeFileProtocolFrame, { readonly frameKind: 'worktree.snapshot' }>;
	const continuationFrames = worktreeFileTreeWindowFrames({
		renderedTreeRowCount: props.renderedTreeRowCount,
		revision: props.revision,
		sourceIdentity: props.sourceIdentity,
		treeRows: props.treeRows,
	});
	return [snapshotFrame, ...continuationFrames].map((frame) =>
		worktreeFileProtocolFrameSchema.parse(frame),
	);
}

function worktreeFileInvalidationFramesForChangedDescriptors(props: {
	readonly currentFilePaths: ReadonlySet<string>;
	readonly previousState: ProviderState | null;
	readonly sequenceStart: number;
	readonly sourceIdentity: WorktreeFileSurfaceSourceIdentity;
	readonly worktreeFileDescriptors: readonly WorktreeFileDescriptor[];
}): readonly WorktreeFileInvalidatedFrame[] {
	if (props.previousState === null) {
		return [];
	}
	const invalidationFrames: WorktreeFileInvalidatedFrame[] = [];
	for (const latestDescriptor of props.worktreeFileDescriptors) {
		const previousDescriptor = props.previousState.worktreeFileDescriptorByPath.get(
			latestDescriptor.path,
		);
		if (previousDescriptor === undefined) {
			continue;
		}
		if (latestDescriptor.virtualizedExtentKind === 'unavailable') {
			invalidationFrames.push(
				worktreeFileInvalidatedFrameSchema.parse({
					kind: 'delta',
					streamId: worktreeFileStreamId,
					generation: props.sourceIdentity.subscriptionGeneration,
					sequence: props.sequenceStart + invalidationFrames.length,
					frameKind: 'worktree.fileInvalidated',
					invalidation: {
						path: latestDescriptor.path,
						fileId: latestDescriptor.fileId,
						reason: 'filesystemEvent',
						contentHandleIds: [previousDescriptor.contentHandle],
					},
				}),
			);
			continue;
		}
		if (previousDescriptor.contentHash === latestDescriptor.contentHash) {
			continue;
		}
		invalidationFrames.push(
			worktreeFileInvalidatedFrameSchema.parse({
				kind: 'delta',
				streamId: worktreeFileStreamId,
				generation: props.sourceIdentity.subscriptionGeneration,
				sequence: props.sequenceStart + invalidationFrames.length,
				frameKind: 'worktree.fileInvalidated',
				invalidation: {
					path: latestDescriptor.path,
					fileId: latestDescriptor.fileId,
					reason: 'contentChanged',
					contentHandleIds: [previousDescriptor.contentHandle],
					latestDescriptor,
				},
			}),
		);
	}
	const latestDescriptorPaths = new Set(
		props.worktreeFileDescriptors.map((descriptor) => descriptor.path),
	);
	for (const previousDescriptor of props.previousState.worktreeFileDescriptorByPath.values()) {
		if (
			props.currentFilePaths.has(previousDescriptor.path) ||
			latestDescriptorPaths.has(previousDescriptor.path)
		) {
			continue;
		}
		invalidationFrames.push(
			worktreeFileInvalidatedFrameSchema.parse({
				kind: 'delta',
				streamId: worktreeFileStreamId,
				generation: props.sourceIdentity.subscriptionGeneration,
				sequence: props.sequenceStart + invalidationFrames.length,
				frameKind: 'worktree.fileInvalidated',
				invalidation: {
					path: previousDescriptor.path,
					fileId: previousDescriptor.fileId,
					reason: 'filesystemEvent',
					contentHandleIds: [previousDescriptor.contentHandle],
				},
			}),
		);
	}
	return invalidationFrames;
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
		const treeWindowKey = `dev-tree-window-${props.revision}-${windowStartIndex}`;
		frames.push({
			kind: 'delta',
			streamId: worktreeFileStreamId,
			generation: props.sourceIdentity.subscriptionGeneration,
			sequence: frames.length + 1,
			frameKind: 'worktree.treeWindow',
			projectionIdentity: {
				source: props.sourceIdentity,
				pathScope: [],
				sortKey: 'path',
				groupKey: 'none',
				filterKey: 'all',
				treeWindowKey,
			},
			metadataLineage: {
				loadedBy: 'idle',
				lane: 'idle',
			},
			rows,
			treeSizeFacts: exactTreeSizeFacts({
				renderedTreeRowCount: props.renderedTreeRowCount,
				windowRowCount: rows.length,
				windowStartIndex,
			}),
		});
	}
	return frames;
}

function exactTreeSizeFacts(props: {
	readonly renderedTreeRowCount: number;
	readonly windowRowCount: number;
	readonly windowStartIndex: number;
}): WorktreeTreeVirtualizedSizeFacts {
	return {
		extentKind: 'exactPathCount',
		pathCount: props.renderedTreeRowCount,
		estimatedTotalHeightPixels: props.renderedTreeRowCount * worktreeFileRowHeightPixels,
		windowStartIndex: props.windowStartIndex,
		windowRowCount: props.windowRowCount,
		rowHeightPixels: worktreeFileRowHeightPixels,
	};
}

function nextDemandFrameSequence(state: ProviderState): number {
	return (
		Math.max(
			...state.worktreeFileSurface.frames.map((frame) => frame.sequence),
			...state.worktreeFileDescriptorSequenceByPath.values(),
		) + 1
	);
}

function worktreeTreeRowsForCurrentFiles(props: {
	readonly changedFiles: readonly BridgeWorktreeChangedFile[];
	readonly currentFilePaths: readonly string[];
}): WorktreeTreeRowMetadata[] {
	const changedFilesByPath = new Map(
		props.changedFiles.map((changedFile): readonly [string, BridgeWorktreeChangedFile] => [
			changedFile.path,
			changedFile,
		]),
	);
	return worktreeTreeRowsForPaths({
		changedFilesByPath,
		paths: props.currentFilePaths,
	});
}

function worktreeTreeRowsForPaths(props: {
	readonly changedFilesByPath: ReadonlyMap<string, BridgeWorktreeChangedFile>;
	readonly paths: readonly string[];
}): WorktreeTreeRowMetadata[] {
	const rowsByPath = new Map<string, WorktreeTreeRowMetadata>();
	for (const currentFilePath of props.paths) {
		const parts = currentFilePath.split('/').filter((part): boolean => part.length > 0);
		let parentPath: string | null = null;
		for (const [partIndex, part] of parts.entries()) {
			const path = parts.slice(0, partIndex + 1).join('/');
			if (rowsByPath.has(path)) {
				parentPath = path;
				continue;
			}
			const isDirectory = partIndex < parts.length - 1;
			rowsByPath.set(path, {
				rowId: `row:${path}`,
				path,
				name: part,
				parentPath,
				depth: partIndex,
				isDirectory,
				...(isDirectory
					? {}
					: {
							fileId: `dev-file-id-${hashText(currentFilePath).slice(0, 16)}`,
							...treeFileOverlayForChangedFile(props.changedFilesByPath.get(currentFilePath)),
						}),
			});
			parentPath = path;
		}
	}
	return [...rowsByPath.values()];
}

function treeFileOverlayForChangedFile(
	changedFile: BridgeWorktreeChangedFile | undefined,
): Pick<WorktreeTreeRowMetadata, 'changeStatus' | 'lineCount'> {
	if (changedFile === undefined) {
		return {};
	}
	return {
		changeStatus: changedFile.changeKind,
		lineCount: renderLineCount(changedFile.headContent ?? changedFile.baseContent ?? ''),
	};
}

function worktreeFileDescriptorForChangedFile(props: {
	readonly changedFile: BridgeWorktreeChangedFile;
	readonly sourceIdentity: WorktreeFileSurfaceSourceIdentity;
	readonly worktreeFileContentByDescriptorId: Map<string, string>;
}): readonly WorktreeFileDescriptor[] {
	if (props.changedFile.changeKind === 'deleted') {
		return [
			unavailableWorktreeFileDescriptorForChangedFile({
				changedFile: props.changedFile,
				sourceIdentity: props.sourceIdentity,
			}),
		];
	}
	const content = props.changedFile.headContent ?? props.changedFile.baseContent;
	if (content === null) {
		return [];
	}
	const pathHash = hashText(props.changedFile.path).slice(0, 16);
	const contentHash = hashText(content);
	const descriptorId = `dev-file-${pathHash}-${contentHash.slice(0, 16)}`;
	props.worktreeFileContentByDescriptorId.set(descriptorId, content);
	const extension = extensionForPath(props.changedFile.path);
	return [
		{
			path: props.changedFile.path,
			fileId: `dev-file-id-${pathHash}`,
			contentHandle: descriptorId,
			contentDescriptor: makeWorktreeAttachedDescriptor({
				content: {
					expectedBytes: byteLength(content),
					mediaType: mimeTypeForExtension(extension),
				},
				descriptorId,
				resourceKind: 'worktree.fileContent',
				sourceIdentity: props.sourceIdentity,
			}),
			contentHash: `sha256:${hashText(content)}`,
			sourceIdentity: props.sourceIdentity,
			sizeBytes: byteLength(content),
			virtualizedExtentKind: 'exactLineCount',
			lineCount: renderLineCount(content),
			isBinary: false,
			language: languageForExtension(extension),
			fileExtension: extension,
		},
	];
}

async function worktreeFileDescriptorForCurrentFile(props: {
	readonly path: string;
	readonly sourceIdentity: WorktreeFileSurfaceSourceIdentity;
	readonly worktreeFileContentByDescriptorId: Map<string, string>;
	readonly worktreeRoot: string;
}): Promise<WorktreeFileDescriptor> {
	const content = await readWorktreeFileText({
		path: props.path,
		worktreeRoot: props.worktreeRoot,
	});
	const pathHash = hashText(props.path).slice(0, 16);
	const contentHash = hashText(content);
	const descriptorId = `dev-file-${pathHash}-${contentHash.slice(0, 16)}`;
	props.worktreeFileContentByDescriptorId.set(descriptorId, content);
	const extension = extensionForPath(props.path);
	return {
		path: props.path,
		fileId: `dev-file-id-${pathHash}`,
		contentHandle: descriptorId,
		contentDescriptor: makeWorktreeAttachedDescriptor({
			content: {
				expectedBytes: byteLength(content),
				mediaType: mimeTypeForExtension(extension),
			},
			descriptorId,
			resourceKind: 'worktree.fileContent',
			sourceIdentity: props.sourceIdentity,
		}),
		contentHash: `sha256:${contentHash}`,
		sourceIdentity: props.sourceIdentity,
		sizeBytes: byteLength(content),
		virtualizedExtentKind: 'exactLineCount',
		lineCount: renderLineCount(content),
		isBinary: false,
		language: languageForExtension(extension),
		fileExtension: extension,
	};
}

function unavailableWorktreeFileDescriptorForChangedFile(props: {
	readonly changedFile: BridgeWorktreeChangedFile;
	readonly sourceIdentity: WorktreeFileSurfaceSourceIdentity;
}): WorktreeFileDescriptor {
	const pathHash = hashText(props.changedFile.path).slice(0, 16);
	const descriptorId = `dev-file-unavailable-${pathHash}`;
	const extension = extensionForPath(props.changedFile.path);
	const content = props.changedFile.baseContent ?? '';
	return {
		path: props.changedFile.path,
		fileId: `dev-file-id-${pathHash}`,
		contentHandle: descriptorId,
		contentDescriptor: makeWorktreeAttachedDescriptor({
			content: {
				expectedBytes: byteLength(content),
				mediaType: mimeTypeForExtension(extension),
			},
			descriptorId,
			resourceKind: 'worktree.fileContent',
			sourceIdentity: props.sourceIdentity,
		}),
		contentHash: `sha256:${hashText(content)}`,
		sourceIdentity: props.sourceIdentity,
		sizeBytes: byteLength(content),
		virtualizedExtentKind: 'unavailable',
		isBinary: false,
		language: languageForExtension(extension),
		fileExtension: extension,
	};
}

function makeWorktreeAttachedDescriptor(props: {
	readonly content: {
		readonly expectedBytes: number;
		readonly mediaType: string;
	};
	readonly descriptorId: string;
	readonly resourceKind: 'worktree.fileContent';
	readonly sourceIdentity: WorktreeFileSurfaceSourceIdentity;
}): BridgeAttachedResourceDescriptor {
	const identity = {
		paneId: worktreeFilePaneId,
		protocol: worktreeFileProtocol,
		sourceId: props.sourceIdentity.sourceId,
		generation: props.sourceIdentity.subscriptionGeneration,
		streamId: worktreeFileStreamId,
		cursor: props.sourceIdentity.sourceCursor,
	};
	const descriptor = {
		descriptorId: props.descriptorId,
		protocol: worktreeFileProtocol,
		resourceKind: props.resourceKind,
		resourceUrl: `agentstudio://resource/${worktreeFileProtocol}/${props.resourceKind}/${props.descriptorId}?generation=${props.sourceIdentity.subscriptionGeneration}&cursor=${props.sourceIdentity.sourceCursor}`,
		identity,
		content: {
			mediaType: props.content.mediaType,
			encoding: 'utf-8',
			expectedBytes: props.content.expectedBytes,
			maxBytes: Math.max(props.content.expectedBytes, 1),
		},
	} satisfies BridgeResourceDescriptor;
	return bridgeAttachedResourceDescriptorSchema.parse({
		ref: {
			descriptorId: descriptor.descriptorId,
			expectedProtocol: descriptor.protocol,
			expectedResourceKind: descriptor.resourceKind,
			expectedIdentity: descriptor.identity,
		},
		descriptor,
	});
}
