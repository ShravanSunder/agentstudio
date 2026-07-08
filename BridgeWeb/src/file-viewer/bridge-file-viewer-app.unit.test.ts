import { describe, expect, test, vi } from 'vitest';

import type {
	WorktreeFileDescriptor,
	WorktreeFileDescriptorFrame,
	WorktreeFileProtocolFrame,
	WorktreeSnapshotFrame,
	WorktreeFileSurfaceSourceIdentity,
	WorktreeTreeRowMetadata,
	WorktreeTreeDeltaFrame,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import {
	applyFramesToRuntime,
	type BridgeFileViewerRenderState,
	pruneEmptyWorktreeFileTreeDirectories,
	projectBridgeFileViewerDescriptors,
	reconcileOpenFileStateWithFrames,
	resetSnapshotFramesKeepOpenFilePath,
	visibleFileDemandChangeWithoutDescriptorId,
} from './bridge-file-viewer-state.js';

describe('BridgeFileViewerApp tree row pruning', () => {
	test('removes empty directory rows after the last file descendant is deleted', () => {
		const treeRowsByPath = new Map<string, WorktreeTreeRowMetadata>([
			[
				'src',
				makeWorktreeTreeRow({
					rowId: 'row-dir-src',
					path: 'src',
					depth: 0,
					isDirectory: true,
				}),
			],
			[
				'src/a',
				makeWorktreeTreeRow({
					rowId: 'row-dir-src-a',
					path: 'src/a',
					depth: 1,
					isDirectory: true,
				}),
			],
			[
				'src/b',
				makeWorktreeTreeRow({
					rowId: 'row-dir-src-b',
					path: 'src/b',
					depth: 1,
					isDirectory: true,
				}),
			],
			[
				'src/b/File.swift',
				makeWorktreeTreeRow({
					rowId: 'row-file-b',
					path: 'src/b/File.swift',
					depth: 2,
					isDirectory: false,
				}),
			],
		]);

		pruneEmptyWorktreeFileTreeDirectories(treeRowsByPath);

		expect([...treeRowsByPath.keys()]).toEqual(['src', 'src/b', 'src/b/File.swift']);
	});

	test('prunes deep directory rows from parent metadata instead of reparsing ancestor paths', () => {
		const treeRowsByPath = new Map<string, WorktreeTreeRowMetadata>();
		let parentPath: string | null = null;
		for (let index = 0; index < 80; index += 1) {
			const directoryPath: string = parentPath === null ? 'src' : `${parentPath}/package-${index}`;
			treeRowsByPath.set(
				directoryPath,
				makeWorktreeTreeRow({
					rowId: `row-dir-${index}`,
					path: directoryPath,
					parentPath,
					depth: index,
					isDirectory: true,
				}),
			);
			treeRowsByPath.set(
				`${directoryPath}/File.swift`,
				makeWorktreeTreeRow({
					rowId: `row-file-${index}`,
					path: `${directoryPath}/File.swift`,
					parentPath: directoryPath,
					depth: index + 1,
					isDirectory: false,
				}),
			);
			parentPath = directoryPath;
		}
		const lastIndexOfSpy = vi.spyOn(String.prototype, 'lastIndexOf');

		try {
			pruneEmptyWorktreeFileTreeDirectories(treeRowsByPath);

			expect(lastIndexOfSpy).not.toHaveBeenCalled();
			expect(treeRowsByPath.size).toBe(160);
		} finally {
			lastIndexOfSpy.mockRestore();
		}
	});
});

describe('BridgeFileViewerApp frame projection', () => {
	test('does not project descriptor frames rejected by the runtime registry', () => {
		const sourceIdentity = makeWorktreeFileSourceIdentity();
		const descriptor = makeWorktreeFileDescriptor(sourceIdentity);
		const currentRenderState = makeBridgeFileViewerRenderState();

		const nextRenderState = applyFramesToRuntime({
			currentRenderState,
			frames: [makeWorktreeFileDescriptorFrame(descriptor)],
			runtime: {
				applyFrame: () => ({ ok: false, reason: 'descriptor_rejected' }),
			},
		});

		expect(nextRenderState.descriptors).toEqual([]);
		expect(nextRenderState.treeRows).toEqual([]);
		expect(nextRenderState.sourceIdentity).toBeNull();
	});

	test('stores accepted descriptors without synthesizing tree metadata rows', () => {
		const sourceIdentity = makeWorktreeFileSourceIdentity();
		const descriptor = makeWorktreeFileDescriptor(sourceIdentity);
		const currentRenderState = makeBridgeFileViewerRenderState();

		const nextRenderState = applyFramesToRuntime({
			currentRenderState,
			frames: [makeWorktreeFileDescriptorFrame(descriptor)],
			runtime: {
				applyFrame: () => ({ ok: true, deltaKind: 'fileDescriptor' }),
			},
		});

		expect(nextRenderState.descriptors).toEqual([descriptor]);
		expect(nextRenderState.treeRows).toEqual([]);
		expect(nextRenderState.sourceIdentity).toEqual(sourceIdentity);
	});

	test('clears stale descriptors when a new source snapshot arrives', () => {
		const oldSourceIdentity = makeWorktreeFileSourceIdentity();
		const newSourceIdentity = makeWorktreeFileSourceIdentity({
			sourceCursor: 'cursor-new-file-viewer-test',
			subscriptionGeneration: 2,
		});
		const staleDescriptor = makeWorktreeFileDescriptor(oldSourceIdentity);
		const nextTreeRow = makeWorktreeTreeRow({
			rowId: 'row-new-source-file',
			path: 'Sources/NewFileViewerTarget.swift',
			depth: 1,
			isDirectory: false,
		});
		const currentRenderState: BridgeFileViewerRenderState = {
			...makeBridgeFileViewerRenderState(),
			descriptors: [staleDescriptor],
			sourceIdentity: oldSourceIdentity,
			treeRows: [
				makeWorktreeTreeRow({
					rowId: 'row-old-source-file',
					path: staleDescriptor.path,
					depth: 1,
					isDirectory: false,
				}),
			],
		};

		const nextRenderState = applyFramesToRuntime({
			currentRenderState,
			frames: [makeWorktreeSnapshotFrame(newSourceIdentity, [nextTreeRow])],
			runtime: {
				applyFrame: () => ({ ok: true, deltaKind: 'snapshot' }),
			},
		});

		expect(nextRenderState.descriptors).toEqual([]);
		expect(nextRenderState.treeRows).toEqual([nextTreeRow]);
		expect(nextRenderState.sourceIdentity).toEqual(newSourceIdentity);
	});

	test('applies tree delta removals and upserts to the retained FileView tree', () => {
		const sourceIdentity = makeWorktreeFileSourceIdentity();
		const removedDescriptor = makeWorktreeFileDescriptor(sourceIdentity, {
			contentHandle: 'content-removed-file',
			fileId: 'file-removed',
			path: 'Sources/Removed.swift',
		});
		const keptDescriptor = makeWorktreeFileDescriptor(sourceIdentity, {
			contentHandle: 'content-kept-file',
			fileId: 'file-kept',
			path: 'Sources/Kept.swift',
		});
		const addedRow = makeWorktreeTreeRow({
			rowId: 'row-added-file',
			path: 'Sources/Added.swift',
			depth: 1,
			isDirectory: false,
		});
		const currentRenderState: BridgeFileViewerRenderState = {
			...makeBridgeFileViewerRenderState(),
			descriptors: [removedDescriptor, keptDescriptor],
			sourceIdentity,
			treeRows: [
				makeWorktreeTreeRow({
					rowId: 'row-dir-sources',
					path: 'Sources',
					depth: 0,
					isDirectory: true,
				}),
				makeWorktreeTreeRow({
					rowId: 'row-dir-empty',
					path: 'Sources/EmptyAfterDelete',
					depth: 1,
					isDirectory: true,
				}),
				makeWorktreeTreeRow({
					rowId: 'row-empty-child',
					path: 'Sources/EmptyAfterDelete/OnlyChild.swift',
					depth: 2,
					isDirectory: false,
				}),
				makeWorktreeTreeRow({
					rowId: 'row-removed-file',
					path: removedDescriptor.path,
					depth: 1,
					isDirectory: false,
				}),
				makeWorktreeTreeRow({
					rowId: 'row-kept-file',
					path: keptDescriptor.path,
					depth: 1,
					isDirectory: false,
				}),
			],
			treeSizeFacts: {
				extentKind: 'exactPathCount',
				pathCount: 5,
				rowHeightPixels: 24,
			},
		};

		const nextRenderState = applyFramesToRuntime({
			currentRenderState,
			frames: [
				makeWorktreeTreeDeltaFrame([
					{
						op: 'removeRows',
						rowIds: ['row-removed-file', 'row-empty-child'],
						paths: [removedDescriptor.path, 'Sources/EmptyAfterDelete/OnlyChild.swift'],
					},
					{
						op: 'upsertRows',
						rows: [addedRow],
					},
				]),
			],
			runtime: {
				applyFrame: () => ({ ok: true, deltaKind: 'treeDelta' }),
			},
		});

		expect(nextRenderState.treeRows.map((treeRow) => treeRow.path)).toEqual([
			'Sources',
			keptDescriptor.path,
			addedRow.path,
		]);
		expect(nextRenderState.descriptors).toEqual([keptDescriptor]);
		expect(nextRenderState.sourceIdentity).toEqual(sourceIdentity);
		expect(nextRenderState.treeSizeFacts).toMatchObject({
			extentKind: 'exactPathCount',
			pathCount: 4,
		});
	});

	test('evicts stale descriptors when a tree delta moves a loaded subtree', () => {
		const sourceIdentity = makeWorktreeFileSourceIdentity();
		const movedDescriptor = makeWorktreeFileDescriptor(sourceIdentity, {
			contentHandle: 'content-moved-file',
			fileId: 'file-moved',
			path: 'Sources/Old/Loaded.swift',
		});
		const currentRenderState: BridgeFileViewerRenderState = {
			...makeBridgeFileViewerRenderState(),
			descriptors: [movedDescriptor],
			sourceIdentity,
			treeRows: [
				makeWorktreeTreeRow({
					rowId: 'row-old-dir',
					path: 'Sources/Old',
					depth: 1,
					isDirectory: true,
				}),
				makeWorktreeTreeRow({
					rowId: 'row-moved-file',
					path: movedDescriptor.path,
					depth: 2,
					isDirectory: false,
				}),
			],
		};

		const nextRenderState = applyFramesToRuntime({
			currentRenderState,
			frames: [
				makeWorktreeTreeDeltaFrame([
					{
						op: 'moveSubtree',
						rowId: 'row-old-dir',
						oldPath: 'Sources/Old',
						newPath: 'Sources/New',
						newParentPath: 'Sources',
						depthDelta: 0,
					},
				]),
			],
			runtime: {
				applyFrame: () => ({ ok: true, deltaKind: 'treeDelta' }),
			},
		});

		expect(nextRenderState.treeRows.map((treeRow) => treeRow.path)).toEqual([
			'Sources/New',
			'Sources/New/Loaded.swift',
		]);
		expect(nextRenderState.descriptors).toEqual([]);
		expect(nextRenderState.sourceIdentity).toEqual(sourceIdentity);
	});

	test('replaces a shorter tree window without retaining stale tail rows', () => {
		const sourceIdentity = makeWorktreeFileSourceIdentity();
		const currentRenderState: BridgeFileViewerRenderState = {
			...makeBridgeFileViewerRenderState(),
			sourceIdentity,
			treeRows: [
				makeWorktreeTreeRow({
					rowId: 'row-window-0',
					path: 'Window/File-0.swift',
					depth: 1,
					isDirectory: false,
				}),
				makeWorktreeTreeRow({
					rowId: 'row-window-1',
					path: 'Window/File-1.swift',
					depth: 1,
					isDirectory: false,
				}),
				makeWorktreeTreeRow({
					rowId: 'row-window-2',
					path: 'Window/File-2.swift',
					depth: 1,
					isDirectory: false,
				}),
			],
			treeSizeFacts: {
				extentKind: 'exactPathCount',
				pathCount: 3,
				windowStartIndex: 0,
				windowRowCount: 3,
				rowHeightPixels: 24,
			},
		};
		const replacementRow = makeWorktreeTreeRow({
			rowId: 'row-window-replacement',
			path: 'Window/File-Replacement.swift',
			depth: 1,
			isDirectory: false,
		});

		const nextRenderState = applyFramesToRuntime({
			currentRenderState,
			frames: [
				makeWorktreeTreeDeltaFrame([
					{
						op: 'replaceWindow',
						projectionIdentity: {
							source: sourceIdentity,
							pathScope: [],
							treeWindowKey: 'tree-window-0',
						},
						startIndex: 0,
						rows: [replacementRow],
						totalRowCount: 1,
					},
				]),
			],
			runtime: {
				applyFrame: () => ({ ok: true, deltaKind: 'treeDelta' }),
			},
		});

		expect(nextRenderState.treeRows.map((treeRow) => treeRow.path)).toEqual([replacementRow.path]);
		expect(nextRenderState.treeSizeFacts).toMatchObject({
			extentKind: 'exactPathCount',
			pathCount: 1,
			windowStartIndex: 0,
			windowRowCount: 1,
		});
	});

	test('does not project descriptor-only rows into the file tree', () => {
		const sourceIdentity = makeWorktreeFileSourceIdentity();
		const descriptor = makeWorktreeFileDescriptor(sourceIdentity);

		const projection = projectBridgeFileViewerDescriptors({
			descriptors: [descriptor],
			filterMode: 'all',
			searchMode: 'text',
			searchText: '',
			treeRows: [],
		});

		expect(projection.descriptors).toEqual([]);
		expect(projection.paths).toEqual([]);
		expect(projection.treeRows).toEqual([]);
	});
});

describe('BridgeFileViewerApp open file reset reconciliation', () => {
	test('marks the open file stale when reset snapshot metadata keeps the same path without a matching descriptor', () => {
		const sourceIdentity = makeWorktreeFileSourceIdentity();
		const descriptor = makeWorktreeFileDescriptor(sourceIdentity);
		const matchingRow = makeWorktreeTreeRow({
			rowId: 'row-reset-kept-file',
			path: descriptor.path,
			depth: 1,
			isDirectory: false,
		});
		const frames: readonly WorktreeFileProtocolFrame[] = [
			makeWorktreeResetFrame(sourceIdentity),
			makeWorktreeSnapshotFrame(sourceIdentity, [matchingRow]),
		];
		const openFileRequestIdRef = { current: 7 };

		const nextOpenState = reconcileOpenFileStateWithFrames({
			currentOpenFileState: {
				status: 'ready',
				path: descriptor.path,
				descriptor,
			},
			frames,
			openFileRequestIdRef,
		});

		expect(
			resetSnapshotFramesKeepOpenFilePath({
				currentOpenFileState: {
					status: 'ready',
					path: descriptor.path,
					descriptor,
				},
				frames,
			}),
		).toBe(true);
		expect(nextOpenState).toEqual({
			status: 'stale',
			path: descriptor.path,
			descriptor,
		});
		expect(openFileRequestIdRef.current).toBe(8);
	});

	test('marks the open file stale when reset snapshot metadata omits the same path', () => {
		const sourceIdentity = makeWorktreeFileSourceIdentity();
		const descriptor = makeWorktreeFileDescriptor(sourceIdentity);
		const differentRow = makeWorktreeTreeRow({
			rowId: 'row-reset-other-file',
			path: 'Sources/OtherFileViewerTarget.swift',
			depth: 1,
			isDirectory: false,
		});
		const frames: readonly WorktreeFileProtocolFrame[] = [
			makeWorktreeResetFrame(sourceIdentity),
			makeWorktreeSnapshotFrame(sourceIdentity, [differentRow]),
		];
		const openFileRequestIdRef = { current: 7 };

		const nextOpenState = reconcileOpenFileStateWithFrames({
			currentOpenFileState: {
				status: 'ready',
				path: descriptor.path,
				descriptor,
			},
			frames,
			openFileRequestIdRef,
		});

		expect(
			resetSnapshotFramesKeepOpenFilePath({
				currentOpenFileState: {
					status: 'ready',
					path: descriptor.path,
					descriptor,
				},
				frames,
			}),
		).toBe(false);
		expect(nextOpenState).toEqual({
			status: 'stale',
			path: descriptor.path,
			descriptor,
		});
		expect(openFileRequestIdRef.current).toBe(8);
	});
});

describe('BridgeFileViewerApp visible demand batching', () => {
	test('filters a recently updated descriptor from a mixed visible batch without dropping siblings', () => {
		const sourceIdentity = makeWorktreeFileSourceIdentity();
		const recentlyUpdatedDescriptor = makeWorktreeFileDescriptor(sourceIdentity, {
			contentHandle: 'content-recently-updated',
			fileId: 'file-recently-updated',
			path: 'Sources/RecentlyUpdated.swift',
		});
		const siblingDescriptor = makeWorktreeFileDescriptor(sourceIdentity, {
			contentHandle: 'content-visible-sibling',
			fileId: 'file-visible-sibling',
			path: 'Sources/VisibleSibling.swift',
		});

		const filteredChange = visibleFileDemandChangeWithoutDescriptorId(
			{
				descriptorRefs: [
					recentlyUpdatedDescriptor.contentDescriptor.ref,
					siblingDescriptor.contentDescriptor.ref,
				],
				firstVisibleIndex: 4,
				lastVisibleIndex: 5,
				visibleItemIds: [recentlyUpdatedDescriptor.fileId, siblingDescriptor.fileId],
				visibleItemIndexes: [4, 5],
				visibleFileCount: 2,
			},
			recentlyUpdatedDescriptor.contentDescriptor.ref.descriptorId,
		);

		expect(filteredChange).toEqual({
			descriptorRefs: [siblingDescriptor.contentDescriptor.ref],
			firstVisibleIndex: 5,
			lastVisibleIndex: 5,
			visibleItemIds: [siblingDescriptor.fileId],
			visibleItemIndexes: [5],
			visibleFileCount: 1,
		});
	});
});

function makeWorktreeTreeRow(props: {
	readonly rowId: string;
	readonly path: string;
	readonly parentPath?: string | null;
	readonly depth: number;
	readonly isDirectory: boolean;
}): WorktreeTreeRowMetadata {
	return {
		rowId: props.rowId,
		path: props.path,
		name: props.path.split('/').at(-1) ?? props.path,
		parentPath:
			props.parentPath !== undefined
				? props.parentPath
				: props.path.includes('/')
					? props.path.slice(0, props.path.lastIndexOf('/'))
					: null,
		depth: props.depth,
		isDirectory: props.isDirectory,
	};
}

function makeBridgeFileViewerRenderState(): BridgeFileViewerRenderState {
	return {
		descriptors: [],
		provenance: null,
		sourceIdentity: null,
		treeRows: [],
		treeSizeFacts: null,
	};
}

function makeWorktreeFileSourceIdentity(
	props: {
		readonly sourceCursor?: string;
		readonly subscriptionGeneration?: number;
	} = {},
): WorktreeFileSurfaceSourceIdentity {
	return {
		sourceId: 'source-file-viewer-test',
		repoId: 'repo-file-viewer-test',
		worktreeId: 'worktree-file-viewer-test',
		subscriptionGeneration: props.subscriptionGeneration ?? 1,
		sourceCursor: props.sourceCursor ?? 'cursor-file-viewer-test',
	};
}

function makeWorktreeFileDescriptor(
	sourceIdentity: WorktreeFileSurfaceSourceIdentity,
	props: {
		readonly contentHandle?: string;
		readonly fileId?: string;
		readonly path?: string;
	} = {},
): WorktreeFileDescriptor {
	const path = props.path ?? 'Sources/FileViewerTarget.swift';
	const contentHandle = props.contentHandle ?? 'content-file-viewer-target';
	const fileId = props.fileId ?? 'file-viewer-target-id';
	return {
		path,
		fileId,
		contentHandle,
		contentDescriptor: {
			ref: {
				descriptorId: `descriptor-${contentHandle}`,
				expectedProtocol: 'worktree-file',
				expectedResourceKind: 'worktree.fileContent',
				expectedIdentity: {
					paneId: 'pane-file-viewer-test',
					protocol: 'worktree-file',
					sourceId: sourceIdentity.sourceId,
					generation: sourceIdentity.subscriptionGeneration,
					streamId: 'worktree-file:pane-file-viewer-test',
					cursor: sourceIdentity.sourceCursor,
				},
			},
			descriptor: {
				descriptorId: `descriptor-${contentHandle}`,
				protocol: 'worktree-file',
				resourceKind: 'worktree.fileContent',
				resourceUrl: `agentstudio://resource/worktree-file/worktree.fileContent/${contentHandle}?generation=1&cursor=cursor-file-viewer-test`,
				identity: {
					paneId: 'pane-file-viewer-test',
					protocol: 'worktree-file',
					sourceId: sourceIdentity.sourceId,
					generation: sourceIdentity.subscriptionGeneration,
					streamId: 'worktree-file:pane-file-viewer-test',
					cursor: sourceIdentity.sourceCursor,
				},
				content: {
					mediaType: 'text/plain',
					encoding: 'utf-8',
					expectedBytes: 24,
					maxBytes: 24,
				},
			},
		},
		sourceIdentity,
		sizeBytes: 24,
		virtualizedExtentKind: 'exactLineCount',
		lineCount: 1,
		isBinary: false,
		language: 'swift',
		fileExtension: 'swift',
	};
}

function makeWorktreeFileDescriptorFrame(
	descriptor: WorktreeFileDescriptor,
): WorktreeFileDescriptorFrame {
	return {
		kind: 'delta',
		frameKind: 'worktree.fileDescriptor',
		streamId: 'worktree-file:pane-file-viewer-test',
		generation: 1,
		sequence: 1,
		descriptor,
	};
}

function makeWorktreeSnapshotFrame(
	sourceIdentity: WorktreeFileSurfaceSourceIdentity,
	treeRows: readonly WorktreeTreeRowMetadata[],
): WorktreeSnapshotFrame {
	return {
		kind: 'snapshot',
		frameKind: 'worktree.snapshot',
		streamId: 'worktree-file:pane-file-viewer-test',
		generation: sourceIdentity.subscriptionGeneration,
		sequence: 0,
		source: sourceIdentity,
		metadataLineage: {
			loadedBy: 'startup_window',
			lane: 'foreground',
		},
		treeRows: [...treeRows],
	};
}

function makeWorktreeResetFrame(
	sourceIdentity: WorktreeFileSurfaceSourceIdentity,
): WorktreeFileProtocolFrame {
	return {
		kind: 'reset',
		frameKind: 'worktree.reset',
		streamId: 'worktree-file:pane-file-viewer-test',
		generation: sourceIdentity.subscriptionGeneration,
		sequence: 0,
		source: sourceIdentity,
		reason: 'sourceChanged',
	};
}

function makeWorktreeTreeDeltaFrame(
	operations: WorktreeTreeDeltaFrame['operations'],
): WorktreeTreeDeltaFrame {
	return {
		kind: 'delta',
		frameKind: 'worktree.treeDelta',
		streamId: 'worktree-file:pane-file-viewer-test',
		generation: 1,
		sequence: 2,
		operations,
	};
}
