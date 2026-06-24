import { describe, expect, test } from 'vitest';

import type {
	BridgeAttachedResourceDescriptor,
	BridgeResourceDescriptor,
} from '../core/models/bridge-resource-descriptor.js';
import { bridgeAttachedResourceDescriptorSchema } from '../core/models/bridge-resource-descriptor.js';
import type {
	WorktreeFileDescriptor,
	WorktreeFileProtocolFrame,
	WorktreeFileSurfaceSourceIdentity,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import { worktreeFileIncrementalFramesFromSurfaces } from './bridge-app-dev-worktree.js';

describe('bridge app dev worktree frame subscription', () => {
	test('derives file invalidation frames when a descriptor content hash changes', () => {
		const previousDescriptor = makeFileDescriptor({
			contentHash: 'sha256:old',
			contentHandle: 'file-content-old',
			cursor: 'cursor-old',
		});
		const nextDescriptor = makeFileDescriptor({
			contentHash: 'sha256:new',
			contentHandle: 'file-content-new',
			cursor: 'cursor-new',
			lineCount: 2,
		});

		const frames = worktreeFileIncrementalFramesFromSurfaces({
			previousFrames: makeFrames(previousDescriptor),
			nextFrames: makeFrames(nextDescriptor),
		});

		expect(frames).toHaveLength(1);
		expect(frames[0]).toMatchObject({
			kind: 'delta',
			frameKind: 'worktree.fileInvalidated',
			invalidation: {
				path: 'src/app.ts',
				fileId: 'file-1',
				reason: 'contentChanged',
				contentHandleIds: ['file-content-old'],
				latestDescriptor: {
					contentHandle: 'file-content-new',
					contentHash: 'sha256:new',
					lineCount: 2,
				},
			},
		});
	});

	test('emits descriptor frames for files added after the initial surface', () => {
		const previousDescriptor = makeFileDescriptor();
		const addedDescriptor = makeFileDescriptor({
			contentHandle: 'file-content-added',
			fileId: 'file-added',
			path: 'src/added.ts',
		});

		const frames = worktreeFileIncrementalFramesFromSurfaces({
			previousFrames: makeFrames(previousDescriptor),
			nextFrames: makeFrames(previousDescriptor, addedDescriptor),
		});

		expect(frames).toHaveLength(1);
		expect(frames[0]).toMatchObject({
			kind: 'delta',
			frameKind: 'worktree.fileDescriptor',
			descriptor: {
				fileId: 'file-added',
				path: 'src/added.ts',
			},
		});
	});
});

function makeFrames(
	...descriptors: readonly WorktreeFileDescriptor[]
): readonly WorktreeFileProtocolFrame[] {
	return [
		{
			kind: 'snapshot',
			streamId: 'worktree-file:pane-1',
			generation: 1,
			sequence: 0,
			frameKind: 'worktree.snapshot',
			source: makeSourceIdentity('cursor-1'),
			treeDescriptor: makeAttachedDescriptor({
				cursor: 'cursor-1',
				descriptorId: 'tree-window-1',
				resourceKind: 'worktree.treeWindow',
			}),
			treeSizeFacts: {
				pathCount: descriptors.length,
				windowStartIndex: 0,
				windowRowCount: descriptors.length,
				rowHeightPixels: 24,
			},
		},
		...descriptors.map(
			(descriptor, index): WorktreeFileProtocolFrame => ({
				kind: 'delta',
				streamId: 'worktree-file:pane-1',
				generation: 1,
				sequence: index + 1,
				frameKind: 'worktree.fileDescriptor',
				descriptor,
			}),
		),
	];
}

interface MakeFileDescriptorProps {
	readonly contentHandle?: string;
	readonly contentHash?: string;
	readonly cursor?: string;
	readonly fileId?: string;
	readonly lineCount?: number;
	readonly path?: string;
}

function makeFileDescriptor(props: MakeFileDescriptorProps = {}): WorktreeFileDescriptor {
	const contentHandle = props.contentHandle ?? 'file-content-1';
	const cursor = props.cursor ?? 'cursor-1';
	return {
		path: props.path ?? 'src/app.ts',
		fileId: props.fileId ?? 'file-1',
		contentHandle,
		contentDescriptor: makeAttachedDescriptor({
			cursor,
			descriptorId: contentHandle,
			resourceKind: 'worktree.fileContent',
		}),
		contentHash: props.contentHash ?? 'sha256:default',
		sourceIdentity: makeSourceIdentity(cursor),
		sizeBytes: 24,
		virtualizedExtentKind: 'exactLineCount',
		lineCount: props.lineCount ?? 1,
		isBinary: false,
		language: 'typescript',
		fileExtension: 'ts',
	};
}

function makeSourceIdentity(cursor: string): WorktreeFileSurfaceSourceIdentity {
	return {
		sourceId: 'source-1',
		repoId: 'repo-1',
		worktreeId: 'worktree-1',
		subscriptionGeneration: 1,
		sourceCursor: cursor,
	};
}

function makeAttachedDescriptor(props: {
	readonly cursor: string;
	readonly descriptorId: string;
	readonly resourceKind: 'worktree.fileContent' | 'worktree.treeWindow';
}): BridgeAttachedResourceDescriptor {
	const identity = {
		paneId: 'pane-1',
		protocol: 'worktree-file',
		sourceId: 'source-1',
		generation: 1,
		streamId: 'worktree-file:pane-1',
		cursor: props.cursor,
	};
	const descriptor = {
		descriptorId: props.descriptorId,
		protocol: 'worktree-file',
		resourceKind: props.resourceKind,
		resourceUrl: `agentstudio://resource/worktree-file/${props.resourceKind}/${props.descriptorId}?generation=1&cursor=${props.cursor}`,
		identity,
		content: {
			mediaType: 'text/plain',
			encoding: 'utf-8',
			expectedBytes: 64,
			maxBytes: 1024,
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
