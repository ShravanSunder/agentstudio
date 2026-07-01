import type {
	BridgeAttachedResourceDescriptor,
	BridgeIntegrityDescriptor,
	BridgeResourceDescriptor,
} from '../core/models/bridge-resource-descriptor.js';
import { bridgeAttachedResourceDescriptorSchema } from '../core/models/bridge-resource-descriptor.js';
import type {
	WorktreeFileDescriptor,
	WorktreeFileDescriptorFrame,
	WorktreeFileInvalidatedFrame,
	WorktreeFileSurfaceSourceIdentity,
	WorktreeSnapshotFrame,
	WorktreeResetFrame,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';

export function makeFileDescriptorFrame(
	descriptor: WorktreeFileDescriptor,
): WorktreeFileDescriptorFrame {
	return {
		kind: 'delta',
		streamId: 'worktree-file:pane-1',
		generation: 1,
		sequence: 1,
		frameKind: 'worktree.fileDescriptor',
		descriptor,
	};
}

export function makeInvalidationFrame(props: {
	readonly firstDescriptor: WorktreeFileDescriptor;
	readonly latestDescriptor: WorktreeFileDescriptor;
}): WorktreeFileInvalidatedFrame {
	return {
		kind: 'delta',
		streamId: 'worktree-file:pane-1',
		generation: 1,
		sequence: 2,
		frameKind: 'worktree.fileInvalidated',
		invalidation: {
			path: props.firstDescriptor.path,
			fileId: props.firstDescriptor.fileId,
			reason: 'filesystemEvent',
			latestDescriptor: props.latestDescriptor,
		},
	};
}

export function makeResetFrame(props?: {
	readonly source?: WorktreeFileSurfaceSourceIdentity | null;
}): WorktreeResetFrame {
	const source = props?.source === undefined ? makeSourceIdentity() : props.source;
	return {
		kind: 'reset',
		streamId: 'worktree-file:pane-1',
		generation: 2,
		sequence: 3,
		frameKind: 'worktree.reset',
		reason: 'sourceChanged',
		...(source === null ? {} : { source }),
	};
}

export function makeSnapshotFrame(
	source: WorktreeFileSurfaceSourceIdentity,
): WorktreeSnapshotFrame {
	return {
		kind: 'snapshot',
		streamId: 'worktree-file:pane-1',
		generation: source.subscriptionGeneration,
		sequence: 4,
		frameKind: 'worktree.snapshot',
		source,
		treeRows: [
			{
				rowId: `row-${source.sourceCursor}`,
				path: 'Sources/App/View.swift',
				name: 'View.swift',
				parentPath: 'Sources/App',
				depth: 2,
				isDirectory: false,
				fileId: `file-${source.sourceCursor}`,
			},
		],
		treeSizeFacts: {
			extentKind: 'exactPathCount',
			pathCount: 1,
			rowHeightPixels: 24,
		},
	};
}

export function makeDeferred<TValue>(): {
	readonly promise: Promise<TValue>;
	readonly resolve: (value: TValue | PromiseLike<TValue>) => void;
	readonly reject: (reason?: unknown) => void;
} {
	let resolvePromise: ((value: TValue | PromiseLike<TValue>) => void) | undefined;
	let rejectPromise: ((reason?: unknown) => void) | undefined;
	const promise = new Promise<TValue>((resolve, reject) => {
		resolvePromise = resolve;
		rejectPromise = reject;
	});
	if (resolvePromise === undefined || rejectPromise === undefined) {
		throw new Error('Expected deferred callbacks to initialize synchronously');
	}
	return {
		promise,
		resolve: resolvePromise,
		reject: rejectPromise,
	};
}

interface MakeFileDescriptorProps {
	readonly descriptorId: string;
	readonly contentHandle?: string;
	readonly expectedBytes?: number;
	readonly fileId?: string;
	readonly integrity?: BridgeIntegrityDescriptor;
	readonly isBinary?: boolean;
	readonly maxBytes?: number;
	readonly path?: string;
	readonly sourceIdentity?: WorktreeFileSurfaceSourceIdentity;
	readonly virtualizedExtentKind?: WorktreeFileDescriptor['virtualizedExtentKind'];
}

export function makeFileDescriptor(props: MakeFileDescriptorProps): WorktreeFileDescriptor {
	const virtualizedExtentKind = props.virtualizedExtentKind ?? 'exactLineCount';
	const sourceIdentity = props.sourceIdentity ?? makeSourceIdentity();
	return {
		path: props.path ?? 'Sources/App/View.swift',
		fileId: props.fileId ?? 'file-1',
		contentHandle: props.contentHandle ?? 'handle-1',
		contentDescriptor: makeAttachedDescriptor({
			descriptorId: props.descriptorId,
			...(props.expectedBytes === undefined ? {} : { expectedBytes: props.expectedBytes }),
			...(props.integrity === undefined ? {} : { integrity: props.integrity }),
			...(props.maxBytes === undefined ? {} : { maxBytes: props.maxBytes }),
			resourceKind: 'worktree.fileContent',
			sourceIdentity,
		}),
		sourceIdentity,
		sizeBytes: 64,
		virtualizedExtentKind,
		...(virtualizedExtentKind === 'exactLineCount' ? { lineCount: 4 } : {}),
		isBinary: props.isBinary ?? false,
		language: 'swift',
		fileExtension: 'swift',
	};
}

export function makeSourceIdentity(
	props: Partial<WorktreeFileSurfaceSourceIdentity> = {},
): WorktreeFileSurfaceSourceIdentity {
	return {
		sourceId: props.sourceId ?? 'source-1',
		repoId: props.repoId ?? 'repo-1',
		worktreeId: props.worktreeId ?? 'worktree-1',
		subscriptionGeneration: props.subscriptionGeneration ?? 1,
		sourceCursor: props.sourceCursor ?? 'cursor-1',
		...(props.rootRevisionToken === undefined
			? {}
			: { rootRevisionToken: props.rootRevisionToken }),
	};
}

interface MakeAttachedDescriptorProps {
	readonly descriptorId: string;
	readonly expectedBytes?: number;
	readonly integrity?: BridgeIntegrityDescriptor;
	readonly maxBytes?: number;
	readonly resourceKind: string;
	readonly sourceIdentity: WorktreeFileSurfaceSourceIdentity;
}

function makeAttachedDescriptor(
	props: MakeAttachedDescriptorProps,
): BridgeAttachedResourceDescriptor {
	const identity = {
		paneId: 'pane-1',
		protocol: 'worktree-file',
		sourceId: props.sourceIdentity.sourceId,
		generation: props.sourceIdentity.subscriptionGeneration,
		cursor: props.sourceIdentity.sourceCursor,
		streamId: 'worktree-file:pane-1',
	};
	const descriptor = {
		descriptorId: props.descriptorId,
		protocol: 'worktree-file',
		resourceKind: props.resourceKind,
		resourceUrl: `agentstudio://resource/worktree-file/${props.resourceKind}/${props.descriptorId}?generation=${props.sourceIdentity.subscriptionGeneration}&cursor=${encodeURIComponent(props.sourceIdentity.sourceCursor)}`,
		identity,
		content: {
			mediaType: 'text/plain',
			encoding: 'utf-8',
			expectedBytes: props.expectedBytes ?? 64,
			...(props.integrity === undefined ? {} : { integrity: props.integrity }),
			maxBytes: props.maxBytes ?? 1024,
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
