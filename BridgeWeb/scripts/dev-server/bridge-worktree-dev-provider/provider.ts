import type {
	BridgeAttachedResourceDescriptor,
	BridgeResourceDescriptor,
} from '../../../src/core/models/bridge-resource-descriptor.js';
import { bridgeAttachedResourceDescriptorSchema } from '../../../src/core/models/bridge-resource-descriptor.js';
import type {
	WorktreeFileDescriptor,
	WorktreeFileProtocolFrame,
	WorktreeFileSurfaceSourceIdentity,
	WorktreeTreeRowMetadata,
	WorktreeTreeVirtualizedSizeFacts,
} from '../../../src/features/worktree-file/models/worktree-file-protocol-models.js';
import { worktreeFileProtocolFrameSchema } from '../../../src/features/worktree-file/models/worktree-file-protocol-models.js';
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
	const retainedStatesBySourceKey = new Map<string, ProviderState>();

	const loadCurrentState = async (): Promise<ProviderState> => {
		const snapshot = await loadBridgeWorktreeDevSnapshot({
			baseRef: parsedConfig.baseRef,
			worktreeRoot,
		});
		const revision =
			state === null
				? 1
				: state.fingerprint === snapshot.fingerprint
					? state.revision
					: state.revision + 1;
		const currentState = makeProviderState({
			config: parsedConfig,
			revision,
			snapshot,
			worktreeRoot,
			worktreeRootToken,
		});
		state = currentState;
		retainProviderState({
			retainedStatesBySourceKey,
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
			const acceptedState = providerStateForDescriptorRequest({
				request,
				retainedStatesBySourceKey,
				state,
			});
			if (acceptedState !== null) {
				return await descriptorFrameFromAcceptedProviderState({ request, state: acceptedState });
			}
			const currentState = await loadCurrentState();
			const refreshedAcceptedState = providerStateForDescriptorRequest({
				request,
				retainedStatesBySourceKey,
				state: currentState,
			});
			if (refreshedAcceptedState !== null) {
				return await descriptorFrameFromAcceptedProviderState({
					request,
					state: refreshedAcceptedState,
				});
			}
			const currentSource = currentState.worktreeFileSurface.source;
			if (request.subscriptionGeneration !== currentSource.subscriptionGeneration) {
				throw new Error(
					`Rejected stale Bridge worktree file descriptor generation: ${request.subscriptionGeneration}`,
				);
			}
			if (request.sourceCursor !== currentSource.sourceCursor) {
				throw new Error(
					`Rejected stale Bridge worktree file descriptor cursor: ${request.sourceCursor}`,
				);
			}
			return await descriptorFrameFromAcceptedProviderState({ request, state: currentState });
		},
		loadWorktreeFileContent: async (
			request: BridgeWorktreeDevProviderWorktreeFileContentRequest,
		): Promise<string> => {
			const acceptedState = providerStateForContentRequest({
				request,
				retainedStatesBySourceKey,
				state,
			});
			if (acceptedState !== null) {
				return contentFromAcceptedProviderState({ request, state: acceptedState });
			}
			const currentState = await loadCurrentState();
			const refreshedAcceptedState = providerStateForContentRequest({
				request,
				retainedStatesBySourceKey,
				state: currentState,
			});
			if (refreshedAcceptedState !== null) {
				return contentFromAcceptedProviderState({ request, state: refreshedAcceptedState });
			}
			const currentSource = currentState.worktreeFileSurface.source;
			if (request.subscriptionGeneration !== currentSource.subscriptionGeneration) {
				throw new Error(
					`Rejected stale Bridge worktree file content generation: ${request.subscriptionGeneration}`,
				);
			}
			if (request.sourceCursor !== currentSource.sourceCursor) {
				throw new Error(
					`Rejected stale Bridge worktree file content cursor: ${request.sourceCursor}`,
				);
			}
			const content = currentState.worktreeFileContentByDescriptorId.get(request.descriptorId);
			if (content === undefined) {
				throw new Error(`Unknown Bridge worktree file content descriptor: ${request.descriptorId}`);
			}
			return content;
		},
		loadWorktreeFileSurface: async (): Promise<BridgeWorktreeDevProviderWorktreeFileSurface> => {
			const currentState = await loadCurrentState();
			return currentState.worktreeFileSurface;
		},
	};
}

function retainProviderState(props: {
	readonly retainedStatesBySourceKey: Map<string, ProviderState>;
	readonly state: ProviderState;
}): void {
	props.retainedStatesBySourceKey.set(providerStateSourceKey(props.state), props.state);
	while (props.retainedStatesBySourceKey.size > retainedProviderStateLimit) {
		const oldestSourceKey = props.retainedStatesBySourceKey.keys().next().value;
		if (oldestSourceKey === undefined) {
			return;
		}
		props.retainedStatesBySourceKey.delete(oldestSourceKey);
	}
}

function providerStateForDescriptorRequest(props: {
	readonly request: BridgeWorktreeDevProviderWorktreeFileDescriptorRequest;
	readonly retainedStatesBySourceKey: ReadonlyMap<string, ProviderState>;
	readonly state: ProviderState | null;
}): ProviderState | null {
	if (props.state !== null && providerStateMatchesDescriptorRequest(props.state, props.request)) {
		return props.state;
	}
	return props.retainedStatesBySourceKey.get(descriptorRequestSourceKey(props.request)) ?? null;
}

function providerStateForContentRequest(props: {
	readonly request: BridgeWorktreeDevProviderWorktreeFileContentRequest;
	readonly retainedStatesBySourceKey: ReadonlyMap<string, ProviderState>;
	readonly state: ProviderState | null;
}): ProviderState | null {
	if (props.state !== null && providerStateMatchesContentRequest(props.state, props.request)) {
		return props.state;
	}
	return props.retainedStatesBySourceKey.get(contentRequestSourceKey(props.request)) ?? null;
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
	return providerStateSourceKey(state) === contentRequestSourceKey(request);
}

function providerStateMatchesDescriptorRequest(
	state: ProviderState,
	request: BridgeWorktreeDevProviderWorktreeFileDescriptorRequest,
): boolean {
	return providerStateSourceKey(state) === descriptorRequestSourceKey(request);
}

function providerStateSourceKey(state: ProviderState): string {
	const source = state.worktreeFileSurface.source;
	return sourceKey({
		sourceCursor: source.sourceCursor,
		subscriptionGeneration: source.subscriptionGeneration,
	});
}

function contentRequestSourceKey(
	request: BridgeWorktreeDevProviderWorktreeFileContentRequest,
): string {
	return sourceKey({
		sourceCursor: request.sourceCursor,
		subscriptionGeneration: request.subscriptionGeneration,
	});
}

function descriptorRequestSourceKey(
	request: BridgeWorktreeDevProviderWorktreeFileDescriptorRequest,
): string {
	return sourceKey({
		sourceCursor: request.sourceCursor,
		subscriptionGeneration: request.subscriptionGeneration,
	});
}

function sourceKey(props: {
	readonly sourceCursor: string;
	readonly subscriptionGeneration: number;
}): string {
	return `${props.subscriptionGeneration}\u{0}${props.sourceCursor}`;
}

function makeProviderState(props: {
	readonly config: BridgeWorktreeDevProviderConfig;
	readonly revision: number;
	readonly snapshot: BridgeWorktreeDevSnapshot;
	readonly worktreeRoot: string;
	readonly worktreeRootToken: string;
}): ProviderState {
	const sourceCursor = `cursor-${props.snapshot.fingerprint.slice(0, 32)}`;
	const sourceIdentity: WorktreeFileSurfaceSourceIdentity = {
		sourceId: worktreeFileSourceId,
		repoId: 'dev-worktree-repo',
		worktreeId: 'dev-worktree',
		subscriptionGeneration: worktreeFileSubscriptionGeneration,
		sourceCursor,
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
	const worktreeFileSurfaceFrames = worktreeFileSurfaceFramesForTreeRows({
		initialTreeRows,
		renderedTreeRowCount,
		revision: props.revision,
		sourceIdentity,
		treeRows,
		treeSizeFacts,
	});
	const worktreeFileSurface: BridgeWorktreeDevProviderWorktreeFileSurface = {
		frames: worktreeFileSurfaceFrames,
		provenance: {
			baseRef: props.config.baseRef,
			scenarioName: props.config.scenarioName,
			worktreeRootToken: props.worktreeRootToken,
		},
		source: sourceIdentity,
		treeSizeFacts,
	};
	return {
		currentFilePaths: new Set(props.snapshot.currentFilePaths),
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
