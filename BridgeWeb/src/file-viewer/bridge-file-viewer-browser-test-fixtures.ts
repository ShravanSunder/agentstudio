import type { BridgeViewerNavigationCommand } from '../app/bridge-viewer-navigation-models.js';
import type {
	BridgeAttachedResourceDescriptor,
	BridgeResourceDescriptor,
} from '../core/models/bridge-resource-descriptor.js';
import { bridgeAttachedResourceDescriptorSchema } from '../core/models/bridge-resource-descriptor.js';
import type {
	WorktreeFileDescriptor,
	WorktreeFileMetadataLineage,
	WorktreeFileProtocolFrame,
	WorktreeFileSurfaceSourceIdentity,
	WorktreeTreeRowMetadata,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import {
	worktreeFileDescriptorSchema,
	worktreeFileProtocolFrameSchema,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';

export type PublishWorktreeFileFrames = (frames: readonly WorktreeFileProtocolFrame[]) => void;

const startupWindowMetadataLineage = {
	loadedBy: 'startup_window',
	lane: 'foreground',
} satisfies WorktreeFileMetadataLineage;

const idleMetadataLineage = {
	loadedBy: 'idle',
	lane: 'idle',
} satisfies WorktreeFileMetadataLineage;

export function makeFrames(
	...descriptors: readonly WorktreeFileDescriptor[]
): readonly WorktreeFileProtocolFrame[] {
	return [
		parseWorktreeFileProtocolFrame({
			kind: 'snapshot',
			streamId: 'worktree-file:pane-1',
			generation: 1,
			sequence: 0,
			frameKind: 'worktree.snapshot',
			source: makeSourceIdentity(),
			metadataLineage: startupWindowMetadataLineage,
			treeRows: descriptors.map(makeTreeRowFromDescriptor),
			treeSizeFacts: {
				extentKind: 'exactPathCount',
				pathCount: descriptors.length,
				windowStartIndex: 0,
				windowRowCount: descriptors.length,
				rowHeightPixels: 24,
			},
		}),
		...descriptors.map(
			(descriptor, descriptorIndex): WorktreeFileProtocolFrame =>
				parseWorktreeFileProtocolFrame({
					kind: 'delta',
					streamId: 'worktree-file:pane-1',
					generation: 1,
					sequence: descriptorIndex + 1,
					frameKind: 'worktree.fileDescriptor',
					descriptor,
				}),
		),
	];
}

export function makeTreeRowFromDescriptor(
	descriptor: WorktreeFileDescriptor,
): WorktreeTreeRowMetadata {
	const pathParts = descriptor.path.split('/');
	const name = pathParts.at(-1) ?? descriptor.path;
	const parentPath =
		pathParts.length > 1 ? pathParts.slice(0, pathParts.length - 1).join('/') : null;
	return makeTreeRow({
		depth: Math.max(pathParts.length - 1, 0),
		fileId: descriptor.fileId,
		isDirectory: false,
		name,
		parentPath,
		path: descriptor.path,
		sizeBytes: descriptor.sizeBytes,
		...(descriptor.lineCount === undefined ? {} : { lineCount: descriptor.lineCount }),
	});
}

export function makeTreeRowsOnlyFrames(): readonly WorktreeFileProtocolFrame[] {
	return [
		parseWorktreeFileProtocolFrame({
			kind: 'snapshot',
			streamId: 'worktree-file:pane-1',
			generation: 1,
			sequence: 0,
			frameKind: 'worktree.snapshot',
			source: makeSourceIdentity(),
			metadataLineage: startupWindowMetadataLineage,
			treeRows: [
				makeTreeRow({
					depth: 0,
					isDirectory: true,
					name: 'Sources',
					parentPath: null,
					path: 'Sources',
				}),
				makeTreeRow({
					depth: 1,
					isDirectory: true,
					name: 'AgentStudio',
					parentPath: 'Sources',
					path: 'Sources/AgentStudio',
				}),
				makeTreeRow({
					depth: 2,
					isDirectory: true,
					name: 'App',
					parentPath: 'Sources/AgentStudio',
					path: 'Sources/AgentStudio/App',
				}),
				makeTreeRow({
					depth: 3,
					fileId: 'file-app-delegate',
					isDirectory: false,
					lineCount: 42,
					name: 'AppDelegate.swift',
					parentPath: 'Sources/AgentStudio/App',
					path: 'Sources/AgentStudio/App/AppDelegate.swift',
				}),
				makeTreeRow({
					depth: 2,
					isDirectory: true,
					name: 'Features',
					parentPath: 'Sources/AgentStudio',
					path: 'Sources/AgentStudio/Features',
				}),
				makeTreeRow({
					depth: 3,
					isDirectory: true,
					name: 'Bridge',
					parentPath: 'Sources/AgentStudio/Features',
					path: 'Sources/AgentStudio/Features/Bridge',
				}),
			],
			treeSizeFacts: {
				extentKind: 'exactPathCount',
				pathCount: 6,
				windowStartIndex: 0,
				windowRowCount: 6,
				rowHeightPixels: 24,
			},
		}),
	];
}

export function makeTreeWindowedSnapshotFrame(props: {
	readonly rowCount: number;
	readonly totalPathCount: number;
}): WorktreeFileProtocolFrame {
	return parseWorktreeFileProtocolFrame({
		kind: 'snapshot',
		streamId: 'worktree-file:pane-1',
		generation: 1,
		sequence: 0,
		frameKind: 'worktree.snapshot',
		source: makeSourceIdentity(),
		metadataLineage: startupWindowMetadataLineage,
		treeRows: makeFlatFileTreeRows({ count: props.rowCount, startIndex: 0 }),
		treeSizeFacts: {
			extentKind: 'exactPathCount',
			pathCount: props.totalPathCount,
			windowStartIndex: 0,
			windowRowCount: props.rowCount,
			rowHeightPixels: 24,
		},
	});
}

export function makeTreeWindowFrame(props: {
	readonly rowCount: number;
	readonly sequence: number;
	readonly startIndex: number;
	readonly totalPathCount: number;
}): WorktreeFileProtocolFrame {
	return parseWorktreeFileProtocolFrame({
		kind: 'delta',
		streamId: 'worktree-file:pane-1',
		generation: 1,
		sequence: props.sequence,
		frameKind: 'worktree.treeWindow',
		projectionIdentity: {
			source: makeSourceIdentity(),
			pathScope: [],
			sortKey: 'path',
			groupKey: 'none',
			filterKey: 'all',
			treeWindowKey: `tree-window-${props.startIndex}`,
		},
		metadataLineage: idleMetadataLineage,
		rows: makeFlatFileTreeRows({
			count: props.rowCount,
			startIndex: props.startIndex,
		}),
		treeSizeFacts: {
			extentKind: 'exactPathCount',
			pathCount: props.totalPathCount,
			windowStartIndex: props.startIndex,
			windowRowCount: props.rowCount,
			rowHeightPixels: 24,
		},
	});
}

export function makeFlatFileTreeRows(props: {
	readonly count: number;
	readonly startIndex: number;
}): readonly WorktreeTreeRowMetadata[] {
	return Array.from({ length: props.count }, (_value, index): WorktreeTreeRowMetadata => {
		const fileIndex = props.startIndex + index;
		const fileName = `File-${fileIndex.toString().padStart(3, '0')}.swift`;
		return makeTreeRow({
			depth: 0,
			fileId: `file-${fileIndex.toString().padStart(3, '0')}`,
			isDirectory: false,
			name: fileName,
			parentPath: null,
			path: fileName,
			sizeBytes: 24,
		});
	});
}

export function makeFileDescriptorFrame(
	descriptor: WorktreeFileDescriptor,
	props: { readonly generation?: number; readonly sequence: number },
): readonly WorktreeFileProtocolFrame[] {
	return [
		parseWorktreeFileProtocolFrame({
			kind: 'delta',
			streamId: 'worktree-file:pane-1',
			generation: props.generation ?? 1,
			sequence: props.sequence,
			frameKind: 'worktree.fileDescriptor',
			descriptor,
		}),
	];
}

export function makeSnapshotFrame(props: {
	readonly sequence: number;
	readonly sourceIdentity: WorktreeFileSurfaceSourceIdentity;
}): WorktreeFileProtocolFrame {
	return parseWorktreeFileProtocolFrame({
		kind: 'snapshot',
		streamId: 'worktree-file:pane-1',
		generation: props.sourceIdentity.subscriptionGeneration,
		sequence: props.sequence,
		frameKind: 'worktree.snapshot',
		source: props.sourceIdentity,
		metadataLineage: startupWindowMetadataLineage,
		treeRows: [
			makeTreeRow({
				depth: 0,
				fileId: 'file-source-less-reset-target',
				isDirectory: false,
				name: 'source-less-reset-target.ts',
				parentPath: null,
				path: 'src/source-less-reset-target.ts',
				sizeBytes: 64,
			}),
		],
		treeSizeFacts: {
			extentKind: 'exactPathCount',
			pathCount: 1,
			windowStartIndex: 0,
			windowRowCount: 1,
			rowHeightPixels: 24,
		},
	});
}

export function makeSourceLessResetFrames(): readonly WorktreeFileProtocolFrame[] {
	return [
		parseWorktreeFileProtocolFrame({
			kind: 'reset',
			streamId: 'worktree-file:pane-1',
			generation: 2,
			sequence: 0,
			frameKind: 'worktree.reset',
			reason: 'sourceChanged',
		}),
	];
}

export function makeFileInvalidatedFrames(props: {
	readonly fileId: string;
	readonly path: string;
	readonly sequence: number;
}): readonly WorktreeFileProtocolFrame[] {
	return [
		parseWorktreeFileProtocolFrame({
			kind: 'delta',
			streamId: 'worktree-file:pane-1',
			generation: 1,
			sequence: props.sequence,
			frameKind: 'worktree.fileInvalidated',
			invalidation: {
				path: props.path,
				fileId: props.fileId,
				reason: 'contentChanged',
			},
		}),
	];
}

export function makeTreeRow(props: {
	readonly changeStatus?: string;
	readonly depth: number;
	readonly fileId?: string;
	readonly isDirectory: boolean;
	readonly lineCount?: number;
	readonly name: string;
	readonly parentPath: string | null;
	readonly path: string;
	readonly sizeBytes?: number;
}): WorktreeTreeRowMetadata {
	return {
		rowId: `row:${props.path}`,
		path: props.path,
		name: props.name,
		parentPath: props.parentPath,
		depth: props.depth,
		isDirectory: props.isDirectory,
		...(props.fileId === undefined ? {} : { fileId: props.fileId }),
		...(props.sizeBytes === undefined ? {} : { sizeBytes: props.sizeBytes }),
		...(props.lineCount === undefined ? {} : { lineCount: props.lineCount }),
		...(props.changeStatus === undefined ? {} : { changeStatus: props.changeStatus }),
	};
}

export function makeResetFrames(
	...replacementDescriptors: readonly WorktreeFileDescriptor[]
): readonly WorktreeFileProtocolFrame[] {
	const resetSourceIdentity = makeSourceIdentity({
		subscriptionGeneration: 2,
		sourceCursor: 'cursor-2',
	});
	return [
		parseWorktreeFileProtocolFrame({
			kind: 'reset',
			streamId: 'worktree-file:pane-1',
			generation: 2,
			sequence: 0,
			frameKind: 'worktree.reset',
			source: resetSourceIdentity,
			reason: 'sourceChanged',
		}),
		parseWorktreeFileProtocolFrame({
			kind: 'snapshot',
			streamId: 'worktree-file:pane-1',
			generation: 2,
			sequence: 1,
			frameKind: 'worktree.snapshot',
			source: resetSourceIdentity,
			metadataLineage: {
				loadedBy: 'reset',
				lane: 'foreground',
			},
			treeRows: replacementDescriptors.map(makeTreeRowFromDescriptor),
			treeSizeFacts: {
				extentKind: 'exactPathCount',
				pathCount: replacementDescriptors.length,
				windowStartIndex: 0,
				windowRowCount: replacementDescriptors.length,
				rowHeightPixels: 24,
			},
		}),
		...replacementDescriptors.map(
			(descriptor, descriptorIndex): WorktreeFileProtocolFrame =>
				parseWorktreeFileProtocolFrame({
					kind: 'delta',
					streamId: 'worktree-file:pane-1',
					generation: 2,
					sequence: descriptorIndex + 2,
					frameKind: 'worktree.fileDescriptor',
					descriptor,
				}),
		),
	];
}

export interface MakeFileDescriptorProps {
	readonly contentExpectedBytes?: number;
	readonly contentHandle?: string;
	readonly contentHash?: string | null;
	readonly contentMaxBytes?: number;
	readonly fileId?: string;
	readonly generation?: number;
	readonly isBinary?: boolean;
	readonly lineCount?: number;
	readonly path: string;
	readonly sourceIdentity?: WorktreeFileSurfaceSourceIdentity;
	readonly virtualizedExtentKind?: WorktreeFileDescriptor['virtualizedExtentKind'];
}

export function makeFileDescriptor(props: MakeFileDescriptorProps): WorktreeFileDescriptor {
	const contentHandle = props.contentHandle ?? 'file-content-1';
	const generation = props.generation ?? 1;
	const sourceIdentity = props.sourceIdentity ?? makeSourceIdentity();
	const virtualizedExtentKind = props.virtualizedExtentKind ?? 'exactLineCount';
	const contentHash =
		props.contentHash === undefined ? `sha256:${contentHandle}` : props.contentHash;
	return worktreeFileDescriptorSchema.parse({
		path: props.path,
		fileId: props.fileId ?? 'file-1',
		contentHandle,
		contentDescriptor: makeAttachedDescriptor({
			descriptorId: contentHandle,
			generation,
			resourceKind: 'worktree.fileContent',
			sourceIdentity,
			...(props.contentExpectedBytes === undefined
				? {}
				: { expectedBytes: props.contentExpectedBytes }),
			...(props.contentMaxBytes === undefined ? {} : { maxBytes: props.contentMaxBytes }),
		}),
		...(contentHash === null ? {} : { contentHash }),
		sourceIdentity,
		sizeBytes: 64,
		virtualizedExtentKind,
		...(virtualizedExtentKind === 'exactLineCount' ? { lineCount: props.lineCount ?? 2 } : {}),
		isBinary: props.isBinary ?? false,
		language: 'typescript',
		fileExtension: 'ts',
	});
}

export function makeSourceIdentity(
	props: {
		readonly sourceCursor?: string;
		readonly subscriptionGeneration?: number;
	} = {},
): WorktreeFileSurfaceSourceIdentity {
	return {
		sourceId: 'dev-worktree-source',
		repoId: 'repo-1',
		worktreeId: 'worktree-1',
		subscriptionGeneration: props.subscriptionGeneration ?? 1,
		sourceCursor: props.sourceCursor ?? 'cursor-1',
	};
}

export function makeAttachedDescriptor(props: {
	readonly descriptorId: string;
	readonly expectedBytes?: number;
	readonly generation?: number;
	readonly maxBytes?: number;
	readonly resourceKind: 'worktree.fileContent' | 'worktree.fileRange';
	readonly sourceIdentity: WorktreeFileSurfaceSourceIdentity;
}): BridgeAttachedResourceDescriptor {
	const generation = props.generation ?? 1;
	const identity = {
		paneId: 'pane-1',
		protocol: 'worktree-file',
		sourceId: 'dev-worktree-source',
		generation,
		streamId: 'worktree-file:pane-1',
		cursor: props.sourceIdentity.sourceCursor,
	};
	const descriptor = {
		descriptorId: props.descriptorId,
		protocol: 'worktree-file',
		resourceKind: props.resourceKind,
		resourceUrl: `agentstudio://resource/worktree-file/${props.resourceKind}/${props.descriptorId}?cursor=${props.sourceIdentity.sourceCursor}&generation=${generation}`,
		identity,
		content: {
			mediaType: 'text/plain',
			encoding: 'utf-8',
			expectedBytes: props.expectedBytes ?? 64,
			maxBytes: props.maxBytes ?? DEFAULT_WORKTREE_FILE_TEST_CONTENT_MAX_BYTES,
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

const DEFAULT_WORKTREE_FILE_TEST_CONTENT_MAX_BYTES = 512 * 1024;

export function parseWorktreeFileProtocolFrame(frame: unknown): WorktreeFileProtocolFrame {
	return worktreeFileProtocolFrameSchema.parse(frame);
}

export function fileNavigationCommandForPath(path: string): BridgeViewerNavigationCommand {
	return {
		commandId: `test:file:${path}`,
		commandKind: 'initialize',
		context: 'files',
		restoreMemory: true,
		source: {
			sourceKind: 'worktree',
			sourceId: 'source-1',
		},
		target: {
			targetKind: 'file',
			fileRef: {
				sourceId: 'source-1',
				path,
			},
			version: 'current',
		},
	};
}
