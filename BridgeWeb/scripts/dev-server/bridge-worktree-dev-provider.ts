import { execFile } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFile, realpath } from 'node:fs/promises';
import { extname, relative, resolve, sep } from 'node:path';
import { promisify } from 'node:util';

import { z } from 'zod';

import type {
	BridgeAttachedResourceDescriptor,
	BridgeResourceDescriptor,
} from '../../src/core/models/bridge-resource-descriptor.js';
import { bridgeAttachedResourceDescriptorSchema } from '../../src/core/models/bridge-resource-descriptor.js';
import type {
	WorktreeFileDescriptor,
	WorktreeFileProtocolFrame,
	WorktreeFileSurfaceSourceIdentity,
	WorktreeTreeRowMetadata,
	WorktreeTreeVirtualizedSizeFacts,
} from '../../src/features/worktree-file/models/worktree-file-protocol-models.js';
import { worktreeFileProtocolFrameSchema } from '../../src/features/worktree-file/models/worktree-file-protocol-models.js';
import { countFlattenedWorktreeFileTreeRows } from '../../src/features/worktree-file/models/worktree-file-tree-size.js';

const execFileAsync = promisify(execFile);
const worktreeFileSubscriptionGeneration = 1;
const worktreeFileProtocol = 'worktree-file';
const worktreeFilePaneId = 'bridge-worktree-dev-pane';
const worktreeFileSourceId = 'dev-worktree-source';
const worktreeFileStreamId = `${worktreeFileProtocol}:${worktreeFilePaneId}`;
const worktreeFileRowHeightPixels = 24;
const worktreeFileTreeWindowRowLimit = 200;
const retainedProviderStateLimit = 4;

export const bridgeWorktreeDevScenarioNameSchema = z.enum(['current-worktree']);
export type BridgeWorktreeDevScenarioName = z.infer<typeof bridgeWorktreeDevScenarioNameSchema>;

export const bridgeWorktreeDevProviderConfigSchema = z
	.object({
		baseRef: z.string().min(1),
		scenarioName: bridgeWorktreeDevScenarioNameSchema,
		worktreeRoot: z.string().min(1),
	})
	.strict();

export type BridgeWorktreeDevProviderConfig = z.infer<typeof bridgeWorktreeDevProviderConfigSchema>;

export interface ResolveBridgeWorktreeDevProviderConfigProps {
	readonly env: Readonly<Record<string, string | undefined>>;
	readonly packageRoot: string;
	readonly requestUrl: string | null;
}

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

type WorktreeFileChangeKind = 'added' | 'copied' | 'deleted' | 'modified' | 'renamed';

export interface BridgeWorktreeChangedFile {
	readonly additions: number;
	readonly baseContent: string | null;
	readonly basePath: string | null;
	readonly changeKind: WorktreeFileChangeKind;
	readonly deletions: number;
	readonly headContent: string | null;
	readonly headPath: string | null;
	readonly path: string;
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

export interface BridgeWorktreeDevSnapshot {
	readonly changedFiles: readonly BridgeWorktreeChangedFile[];
	readonly currentFilePaths: readonly string[];
	readonly fingerprint: string;
}

interface GitNameStatusRecord {
	readonly basePath: string | null;
	readonly changeKind: WorktreeFileChangeKind;
	readonly headPath: string | null;
	readonly path: string;
}

export async function resolveBridgeWorktreeDevProviderConfig(
	props: ResolveBridgeWorktreeDevProviderConfigProps,
): Promise<BridgeWorktreeDevProviderConfig> {
	const requestSearchParams = searchParamsForRequestUrl(props.requestUrl);
	rejectRawPathOverrides(requestSearchParams);
	const scenarioName = parseBridgeWorktreeDevScenarioName(
		firstNonEmptyStringOrNull([
			requestSearchParams.get('scenario'),
			props.env['BRIDGE_WEB_DEV_SCENARIO'],
			'current-worktree',
		]) ?? 'current-worktree',
	);
	const worktreeRoot = await resolveAllowedWorktreeRoot(
		firstNonEmptyStringOrNull([
			props.env['BRIDGE_WEB_DEV_WORKTREE'],
			resolve(props.packageRoot, '..'),
		]) ?? resolve(props.packageRoot, '..'),
	);
	const baseRef =
		firstNonEmptyStringOrNull([
			requestSearchParams.get('base'),
			props.env['BRIDGE_WEB_DEV_BASE'],
			null,
		]) ?? (await resolveDefaultBaseRef(worktreeRoot));
	return bridgeWorktreeDevProviderConfigSchema.parse({ baseRef, scenarioName, worktreeRoot });
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

export async function loadBridgeWorktreeDevSnapshot(props: {
	readonly baseRef: string;
	readonly worktreeRoot: string;
}): Promise<BridgeWorktreeDevSnapshot> {
	const worktreeRoot = await realpath(props.worktreeRoot);
	const [changedFiles, currentFilePaths] = await Promise.all([
		readChangedFiles({
			baseRef: props.baseRef,
			worktreeRoot,
		}),
		readCurrentWorktreeFilePaths(worktreeRoot),
	]);
	return {
		changedFiles,
		currentFilePaths,
		fingerprint: fingerprintWorktreeSnapshot({ changedFiles, currentFilePaths }),
	};
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
	const treeDescriptor = makeWorktreeAttachedDescriptor({
		content: {
			expectedBytes: byteLength(JSON.stringify(initialTreeRows)),
			mediaType: 'application/json',
		},
		descriptorId: `dev-tree-window-${props.revision}-0`,
		resourceKind: 'worktree.treeWindow',
		sourceIdentity,
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
		treeDescriptor,
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
	readonly treeDescriptor: BridgeAttachedResourceDescriptor;
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
		treeDescriptor: props.treeDescriptor,
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
		const descriptorId = `dev-tree-window-${props.revision}-${windowStartIndex}`;
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
				treeWindowKey: descriptorId,
			},
			windowDescriptor: makeWorktreeAttachedDescriptor({
				content: {
					expectedBytes: byteLength(JSON.stringify(rows)),
					mediaType: 'application/json',
				},
				descriptorId,
				resourceKind: 'worktree.treeWindow',
				sourceIdentity: props.sourceIdentity,
			}),
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

export async function bridgeWorktreeDevRootTokenForPath(path: string): Promise<string> {
	return `root-${hashText(await realpath(path)).slice(0, 32)}`;
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
	readonly resourceKind: 'worktree.fileContent' | 'worktree.treeWindow';
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

async function readChangedFiles(props: {
	readonly baseRef: string;
	readonly worktreeRoot: string;
}): Promise<readonly BridgeWorktreeChangedFile[]> {
	const records = await gitNameStatusRecords(props);
	const changedFiles = await Promise.all(
		records.map(async (record): Promise<BridgeWorktreeChangedFile> => {
			const [baseContent, headContent] = await Promise.all([
				record.changeKind === 'added'
					? Promise.resolve(null)
					: gitShowOrNull(props.worktreeRoot, props.baseRef, record.basePath ?? record.path),
				record.changeKind === 'deleted'
					? Promise.resolve(null)
					: readWorktreeFileText({ path: record.path, worktreeRoot: props.worktreeRoot }),
			]);
			const lineDelta = countLineDelta(baseContent, headContent);
			return {
				additions: lineDelta.additions,
				baseContent,
				basePath: record.basePath,
				changeKind: record.changeKind,
				deletions: lineDelta.deletions,
				headContent,
				headPath: record.headPath,
				path: record.path,
			};
		}),
	);
	return changedFiles;
}

function fingerprintWorktreeSnapshot(props: {
	readonly changedFiles: readonly BridgeWorktreeChangedFile[];
	readonly currentFilePaths: readonly string[];
}): string {
	return hashText(
		JSON.stringify({
			changedFiles: props.changedFiles.map((changedFile) => ({
				additions: changedFile.additions,
				baseContentHash:
					changedFile.baseContent === null ? null : hashText(changedFile.baseContent),
				changeKind: changedFile.changeKind,
				deletions: changedFile.deletions,
				basePath: changedFile.basePath,
				headContentHash:
					changedFile.headContent === null ? null : hashText(changedFile.headContent),
				headPath: changedFile.headPath,
				path: changedFile.path,
			})),
			currentFilePaths: props.currentFilePaths,
		}),
	);
}

async function gitNameStatusRecords(props: {
	readonly baseRef: string;
	readonly worktreeRoot: string;
}): Promise<readonly GitNameStatusRecord[]> {
	const diffOutput = await gitStdout(props.worktreeRoot, [
		'diff',
		'--name-status',
		'--find-renames',
		'--find-copies',
		props.baseRef,
		'--',
	]);
	const untrackedOutput = await gitStdout(props.worktreeRoot, [
		'ls-files',
		'--others',
		'--exclude-standard',
	]);
	const diffRecords = diffOutput
		.split('\n')
		.map((line) => line.trim())
		.filter((line) => line.length > 0)
		.map(parseNameStatusLine);
	const untrackedRecords = untrackedOutput
		.split('\n')
		.map((line) => line.trim())
		.filter((path) => path.length > 0)
		.map(
			(path): GitNameStatusRecord => ({
				basePath: null,
				changeKind: 'added',
				headPath: path,
				path,
			}),
		);
	const recordByPath = new Map<string, GitNameStatusRecord>();
	for (const record of [...diffRecords, ...untrackedRecords]) {
		recordByPath.set(record.path, record);
	}
	return [...recordByPath.values()].toSorted((left, right) => left.path.localeCompare(right.path));
}

async function readCurrentWorktreeFilePaths(worktreeRoot: string): Promise<readonly string[]> {
	const currentFilesOutput = await gitStdout(worktreeRoot, [
		'ls-files',
		'--cached',
		'--others',
		'--exclude-standard',
		'-z',
	]);
	const candidatePaths = currentFilesOutput
		.split('\0')
		.map((path) => path.trim())
		.filter((path) => path.length > 0);
	const pathEntries = await Promise.all(
		candidatePaths.map(async (path): Promise<string | null> => {
			const absolutePath = resolve(worktreeRoot, path);
			try {
				const realAbsolutePath = await realpath(absolutePath);
				return isPathInsideRoot({ absolutePath: realAbsolutePath, rootPath: worktreeRoot })
					? path
					: null;
			} catch {
				return null;
			}
		}),
	);
	return pathEntries
		.filter((path): path is string => path !== null)
		.toSorted((left, right) => left.localeCompare(right));
}

function parseNameStatusLine(line: string): GitNameStatusRecord {
	const columns = line.split('\t');
	const status = columns[0] ?? '';
	const oldPath = status.startsWith('R') || status.startsWith('C') ? columns[1] : null;
	const path = status.startsWith('R') || status.startsWith('C') ? columns[2] : columns[1];
	if (path === undefined || path.length === 0 || oldPath === undefined) {
		throw new Error(`Invalid git name-status line: ${line}`);
	}
	const changeKind = changeKindForGitStatus(status);
	return {
		basePath: changeKind === 'added' ? null : (oldPath ?? path),
		changeKind,
		headPath: changeKind === 'deleted' ? null : path,
		path,
	};
}

function changeKindForGitStatus(status: string): WorktreeFileChangeKind {
	const statusKind = status[0] ?? '';
	switch (statusKind) {
		case 'A':
			return 'added';
		case 'C':
			return 'copied';
		case 'D':
			return 'deleted';
		case 'M':
			return 'modified';
		case 'R':
			return 'renamed';
		default:
			return 'modified';
	}
}

async function resolveAllowedWorktreeRoot(rawWorktreeRoot: string): Promise<string> {
	const worktreeRoot = await realpath(resolve(rawWorktreeRoot));
	const gitRoot = (await gitStdout(worktreeRoot, ['rev-parse', '--show-toplevel'])).trim();
	const realGitRoot = await realpath(gitRoot);
	if (worktreeRoot !== realGitRoot) {
		throw new Error(`Bridge worktree dev provider root must be the git root: ${realGitRoot}`);
	}
	return worktreeRoot;
}

async function resolveDefaultBaseRef(worktreeRoot: string): Promise<string> {
	const remoteDefaultBranchMergeBase = await gitRemoteDefaultBranchMergeBaseOrNull(worktreeRoot);
	if (remoteDefaultBranchMergeBase !== null) {
		return remoteDefaultBranchMergeBase;
	}
	const mergeBaseCandidates = await Promise.all(
		['origin/main', 'main', 'origin/master', 'master'].map(
			async (candidateRef): Promise<string | null> =>
				await gitMergeBaseOrNull(worktreeRoot, candidateRef),
		),
	);
	return mergeBaseCandidates.find((mergeBase): mergeBase is string => mergeBase !== null) ?? 'HEAD';
}

async function gitRemoteDefaultBranchMergeBaseOrNull(worktreeRoot: string): Promise<string | null> {
	try {
		const defaultBranchRef = (
			await gitStdout(worktreeRoot, ['symbolic-ref', '--quiet', 'refs/remotes/origin/HEAD'])
		).trim();
		if (defaultBranchRef.length === 0) {
			return null;
		}
		return await gitMergeBaseOrNull(worktreeRoot, defaultBranchRef);
	} catch {
		return null;
	}
}

async function gitMergeBaseOrNull(
	worktreeRoot: string,
	candidateRef: string,
): Promise<string | null> {
	try {
		const mergeBase = (await gitStdout(worktreeRoot, ['merge-base', 'HEAD', candidateRef])).trim();
		return mergeBase.length === 0 ? null : mergeBase;
	} catch {
		return null;
	}
}

function searchParamsForRequestUrl(requestUrl: string | null): URLSearchParams {
	if (requestUrl === null) {
		return new URLSearchParams();
	}
	const parsedUrl = new URL(requestUrl, 'http://127.0.0.1');
	if (requestUrl.includes('://') && !isLoopbackHostname(parsedUrl.hostname)) {
		throw new Error('Bridge worktree dev provider request URL must use a loopback host');
	}
	return parsedUrl.searchParams;
}

function isLoopbackHostname(hostname: string): boolean {
	return hostname === '127.0.0.1' || hostname === 'localhost' || hostname === '[::1]';
}

function rejectRawPathOverrides(searchParams: URLSearchParams): void {
	for (const rawPathOverrideName of ['worktree', 'repo', 'base']) {
		if (searchParams.has(rawPathOverrideName)) {
			throw new Error(
				'Bridge worktree dev provider rejects raw worktree, repo, or base query parameters; use scenario instead',
			);
		}
	}
}

function parseBridgeWorktreeDevScenarioName(
	rawScenarioName: string,
): BridgeWorktreeDevScenarioName {
	const parsedScenarioName = bridgeWorktreeDevScenarioNameSchema.safeParse(rawScenarioName);
	if (!parsedScenarioName.success) {
		throw new Error(
			`Invalid Bridge worktree dev provider config: unknown scenario ${rawScenarioName}`,
		);
	}
	return parsedScenarioName.data;
}

function firstNonEmptyStringOrNull(values: readonly (string | null | undefined)[]): string | null {
	return (
		values.find(
			(candidate): candidate is string =>
				candidate !== null && candidate !== undefined && candidate.length > 0,
		) ?? null
	);
}

async function readWorktreeFileText(props: {
	readonly path: string;
	readonly worktreeRoot: string;
}): Promise<string> {
	const absolutePath = resolve(props.worktreeRoot, props.path);
	if (!isPathInsideRoot({ absolutePath, rootPath: props.worktreeRoot })) {
		throw new Error(`Bridge worktree path escapes root: ${props.path}`);
	}
	const realAbsolutePath = await realpath(absolutePath);
	if (!isPathInsideRoot({ absolutePath: realAbsolutePath, rootPath: props.worktreeRoot })) {
		throw new Error(`Bridge worktree path escapes root: ${props.path}`);
	}
	return await readFile(realAbsolutePath, 'utf8');
}

function isPathInsideRoot(props: {
	readonly absolutePath: string;
	readonly rootPath: string;
}): boolean {
	const relativePath = relative(props.rootPath, props.absolutePath);
	return (
		!relativePath.startsWith('..') && relativePath !== '' && !relativePath.split(sep).includes('..')
	);
}

async function gitShowOrNull(
	worktreeRoot: string,
	baseRef: string,
	path: string,
): Promise<string | null> {
	try {
		return await gitStdout(worktreeRoot, ['show', `${baseRef}:${path}`]);
	} catch {
		return null;
	}
}

async function gitStdout(cwd: string, args: readonly string[]): Promise<string> {
	// Dev-server only: production Swift-side Bridge git data prep must use agentstudio-git.
	const result = await execFileAsync('git', [...args], { cwd, maxBuffer: 32 * 1024 * 1024 });
	return result.stdout;
}

function countLineDelta(
	baseContent: string | null,
	headContent: string | null,
): { readonly additions: number; readonly deletions: number } {
	if (baseContent === null) {
		return { additions: lineCount(headContent), deletions: 0 };
	}
	if (headContent === null) {
		return { additions: 0, deletions: lineCount(baseContent) };
	}
	const baseLines = new Set(linesForDiff(baseContent));
	const headLines = new Set(linesForDiff(headContent));
	return {
		additions: [...headLines].filter((line) => !baseLines.has(line)).length,
		deletions: [...baseLines].filter((line) => !headLines.has(line)).length,
	};
}

function linesForDiff(content: string): readonly string[] {
	return content.split('\n').filter((line) => line.length > 0);
}

function lineCount(content: string | null | undefined): number {
	return linesForDiff(content ?? '').length;
}

function renderLineCount(content: string): number {
	if (content.length === 0) {
		return 0;
	}
	const renderedContent = content.endsWith('\n') ? content.slice(0, -1) : content;
	return renderedContent.split('\n').length;
}

function extensionForPath(path: string): string {
	const extension = extname(path).replace(/^\./u, '');
	return extension.length === 0 ? 'txt' : extension;
}

function languageForExtension(extension: string): string {
	switch (extension) {
		case 'md':
		case 'mdx':
			return 'markdown';
		case 'swift':
			return 'swift';
		case 'ts':
		case 'tsx':
			return 'typescript';
		case 'js':
		case 'jsx':
			return 'javascript';
		case 'json':
			return 'json';
		case 'yml':
		case 'yaml':
			return 'yaml';
		default:
			return 'text';
	}
}

function mimeTypeForExtension(extension: string): string {
	switch (extension) {
		case 'md':
		case 'mdx':
			return 'text/markdown';
		case 'ts':
		case 'tsx':
			return 'text/typescript';
		case 'js':
		case 'jsx':
			return 'text/javascript';
		case 'json':
			return 'application/json';
		default:
			return 'text/plain';
	}
}

function hashText(text: string): string {
	return createHash('sha256').update(text).digest('hex');
}

function byteLength(text: string): number {
	return new TextEncoder().encode(text).byteLength;
}
