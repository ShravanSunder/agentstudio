import { describe, expect, test } from 'vitest';

import type {
	BridgeAttachedResourceDescriptor,
	BridgeResourceDescriptor,
} from '../../../core/models/bridge-resource-descriptor.js';
import type {
	WorktreeFileDescriptor,
	WorktreeFileSurfaceSourceIdentity,
} from './worktree-file-protocol-models.js';
import {
	worktreeFileDemandStimulusSchema,
	worktreeFileDescriptorSchema,
	worktreeFileInvalidatedFrameSchema,
	worktreeSnapshotFrameSchema,
	worktreeStatusPatchFrameSchema,
} from './worktree-file-protocol-models.js';

describe('worktree file protocol models', () => {
	test('parses Worktree/File snapshot frames with provider extent facts', () => {
		const treeDescriptor = makeAttachedDescriptor({
			descriptorId: 'tree-window-1',
			resourceKind: 'worktree.treeWindow',
		});
		const statusDescriptor = makeAttachedDescriptor({
			descriptorId: 'status-1',
			resourceKind: 'worktree.status',
		});

		expect(
			worktreeSnapshotFrameSchema.parse({
				kind: 'snapshot',
				streamId: 'worktree-file:pane-1',
				generation: 1,
				sequence: 0,
				frameKind: 'worktree.snapshot',
				source: makeSourceIdentity(),
				requestSelector: {
					clientRequestId: 'request-1',
					repoId: 'repo-1',
					worktreeId: 'worktree-1',
					rootPathToken: 'root-token-1',
					includeStatuses: true,
					includeFileDescriptors: false,
					includeComments: false,
					includeAgentComms: false,
					freshness: 'live',
				},
				treeDescriptor,
				treeSizeFacts: {
					pathCount: 12_000,
					windowStartIndex: 0,
					windowRowCount: 50,
					rowHeightPixels: 24,
				},
				statusDescriptor,
			}),
		).toMatchObject({
			frameKind: 'worktree.snapshot',
			treeSizeFacts: {
				pathCount: 12_000,
				rowHeightPixels: 24,
			},
		});
	});

	test('requires explicit file virtualized extent facts', () => {
		const contentDescriptor = makeAttachedDescriptor({
			descriptorId: 'file-content-1',
			resourceKind: 'worktree.fileContent',
		});

		expect(
			worktreeFileDescriptorSchema.parse({
				path: 'Sources/App/View.swift',
				fileId: 'file-1',
				contentHandle: 'handle-1',
				contentDescriptor,
				sourceIdentity: makeSourceIdentity(),
				sizeBytes: 96,
				virtualizedExtentKind: 'exactLineCount',
				lineCount: 4,
				isBinary: false,
				language: 'swift',
				fileExtension: 'swift',
			}),
		).toMatchObject({
			virtualizedExtentKind: 'exactLineCount',
			lineCount: 4,
		});
		expect(
			worktreeFileDescriptorSchema.safeParse({
				path: 'Sources/App/View.swift',
				fileId: 'file-1',
				contentHandle: 'handle-1',
				contentDescriptor,
				sourceIdentity: makeSourceIdentity(),
				sizeBytes: 96,
				virtualizedExtentKind: 'exactLineCount',
				isBinary: false,
			}).success,
		).toBe(false);
		expect(
			worktreeFileDescriptorSchema.safeParse({
				path: 'Sources/App/View.swift',
				fileId: 'file-1',
				contentHandle: 'handle-1',
				contentDescriptor,
				sourceIdentity: makeSourceIdentity(),
				sizeBytes: 96,
				virtualizedExtentKind: 'estimatedHeight',
				isBinary: false,
			}).success,
		).toBe(false);
	});

	test('rejects loose demand stimuli and raw descriptor strings', () => {
		const descriptorRef = makeAttachedDescriptor({
			descriptorId: 'file-content-1',
			resourceKind: 'worktree.fileContent',
		}).ref;

		expect(
			worktreeFileDemandStimulusSchema.safeParse({
				kind: 'fileSelected',
				descriptorRef,
			}).success,
		).toBe(true);
		expect(
			worktreeFileDemandStimulusSchema.safeParse({
				kind: 'fileSelected',
				descriptorId: 'file-content-1',
			}).success,
		).toBe(false);
		expect(
			worktreeFileDemandStimulusSchema.safeParse({
				kind: 'openFileInvalidated',
				descriptorRef,
				autoFetch: true,
			}).success,
		).toBe(false);
		expect(
			worktreeFileDemandStimulusSchema.safeParse({
				kind: 'recentlyUpdatedFile',
				descriptorRef,
				proximity: 'nearby',
				sourceIdentity: 'source-1',
			}).success,
		).toBe(true);
		expect(
			worktreeFileDemandStimulusSchema.safeParse({
				kind: 'recentlyUpdatedFile',
				descriptorRef,
				proximity: 'foreground',
				sourceIdentity: 'source-1',
			}).success,
		).toBe(false);
	});

	test('parses status and invalidation frames without Review package lineage', () => {
		const descriptor = makeWorktreeFileDescriptor('Sources/App/View.swift');

		expect(
			worktreeStatusPatchFrameSchema.parse({
				kind: 'delta',
				streamId: 'worktree-file:pane-1',
				generation: 1,
				sequence: 1,
				frameKind: 'worktree.statusPatch',
				patch: {
					staged: 1,
					unstaged: 2,
					untracked: 3,
					branchName: 'feature/worktree-file',
				},
			}).patch,
		).toMatchObject({ staged: 1, unstaged: 2, untracked: 3 });
		expect(
			worktreeFileInvalidatedFrameSchema.parse({
				kind: 'delta',
				streamId: 'worktree-file:pane-1',
				generation: 1,
				sequence: 2,
				frameKind: 'worktree.fileInvalidated',
				invalidation: {
					path: 'Sources/App/View.swift',
					fileId: 'file-1',
					reason: 'filesystemEvent',
					contentHandleIds: ['handle-1'],
					latestDescriptor: descriptor,
				},
			}).invalidation.latestDescriptor?.path,
		).toBe('Sources/App/View.swift');
		expect(
			worktreeFileInvalidatedFrameSchema.safeParse({
				kind: 'delta',
				streamId: 'worktree-file:pane-1',
				generation: 1,
				sequence: 2,
				frameKind: 'worktree.fileInvalidated',
				packageId: 'review-package-1',
				invalidation: {
					path: 'Sources/App/View.swift',
					reason: 'filesystemEvent',
				},
			}).success,
		).toBe(false);
	});
});

function makeSourceIdentity(): WorktreeFileSurfaceSourceIdentity {
	return {
		sourceId: 'source-1',
		repoId: 'repo-1',
		worktreeId: 'worktree-1',
		subscriptionGeneration: 1,
		sourceCursor: 'cursor-1',
	};
}

function makeWorktreeFileDescriptor(path: string): WorktreeFileDescriptor {
	return {
		path,
		fileId: 'file-1',
		contentHandle: 'handle-1',
		contentDescriptor: makeAttachedDescriptor({
			descriptorId: 'file-content-1',
			resourceKind: 'worktree.fileContent',
		}),
		sourceIdentity: makeSourceIdentity(),
		sizeBytes: 96,
		virtualizedExtentKind: 'exactLineCount',
		lineCount: 4,
		isBinary: false,
		language: 'swift',
		fileExtension: 'swift',
	};
}

interface MakeAttachedDescriptorProps {
	readonly descriptorId: string;
	readonly resourceKind: string;
}

function makeAttachedDescriptor(
	props: MakeAttachedDescriptorProps,
): BridgeAttachedResourceDescriptor {
	const identity = {
		paneId: 'pane-1',
		protocol: 'worktree-file',
		sourceId: 'source-1',
		generation: 1,
		streamId: 'worktree-file:pane-1',
	};
	const descriptor = {
		descriptorId: props.descriptorId,
		protocol: 'worktree-file',
		resourceKind: props.resourceKind,
		resourceUrl: `agentstudio://resource/worktree-file/${props.resourceKind}/${props.descriptorId}?generation=1`,
		identity,
		content: {
			mediaType: 'application/json',
			encoding: 'utf-8',
			expectedBytes: 128,
			maxBytes: 1024,
		},
	} satisfies BridgeResourceDescriptor;
	return {
		ref: {
			descriptorId: descriptor.descriptorId,
			expectedProtocol: descriptor.protocol,
			expectedResourceKind: descriptor.resourceKind,
			expectedIdentity: identity,
		},
		descriptor,
	};
}
