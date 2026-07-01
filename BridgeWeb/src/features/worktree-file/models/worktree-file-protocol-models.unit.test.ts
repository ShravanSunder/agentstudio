import { describe, expect, test } from 'vitest';

import type {
	BridgeAttachedResourceDescriptor,
	BridgeResourceDescriptor,
} from '../../../core/models/bridge-resource-descriptor.js';
import invalidOpenSourceOutcomeExtraFieldFixture from '../../../test-fixtures/bridge-contract-fixtures/invalid/worktree-file-open-source-outcome-extra-field.json' with { type: 'json' };
import invalidOpenSourceOutcomeWrongProtocolFixture from '../../../test-fixtures/bridge-contract-fixtures/invalid/worktree-file-open-source-outcome-wrong-protocol.json' with { type: 'json' };
import invalidOpenSourceSpecExtraFieldFixture from '../../../test-fixtures/bridge-contract-fixtures/invalid/worktree-file-open-source-spec-extra-field.json' with { type: 'json' };
import validOpenSourceOutcomeFixture from '../../../test-fixtures/bridge-contract-fixtures/valid/worktree-file-open-source-outcome.json' with { type: 'json' };
import validOpenSourceSpecFixture from '../../../test-fixtures/bridge-contract-fixtures/valid/worktree-file-open-source-spec.json' with { type: 'json' };
import type {
	WorktreeFileDescriptor,
	WorktreeFileSurfaceSourceIdentity,
	WorktreeTreeRowMetadata,
} from './worktree-file-protocol-models.js';
import {
	worktreeFileDemandStimulusSchema,
	worktreeFileDescriptorSchema,
	worktreeFileInvalidatedFrameSchema,
	worktreeFileSurfaceResourceKindSchema,
	worktreeFileSurfaceOpenSourceOutcomeSchema,
	worktreeFileSurfaceSourceSpecSchema,
	worktreeFileProtocolFrameSchema,
	worktreeSnapshotFrameSchema,
	worktreeStatusPatchFrameSchema,
	worktreeTreeRowMetadataSchema,
	worktreeTreeWindowFrameSchema,
} from './worktree-file-protocol-models.js';

describe('worktree file protocol models', () => {
	test('limits Worktree/File resource kinds to body streams', () => {
		expect(worktreeFileSurfaceResourceKindSchema.options).toEqual([
			'worktree.fileContent',
			'worktree.fileRange',
		]);
	});

	test('parses shared open-source input and output contract fixtures', () => {
		const sourceSpec = worktreeFileSurfaceSourceSpecSchema.parse(validOpenSourceSpecFixture);
		expect(sourceSpec).toMatchObject({
			clientRequestId: 'request-1',
			freshness: 'live',
			pathScope: ['Sources/App'],
		});
		expect(sourceSpec).not.toHaveProperty('includeFileDescriptors');
		expect(worktreeFileSurfaceOpenSourceOutcomeSchema.parse(validOpenSourceOutcomeFixture)).toEqual(
			{
				status: 'accepted',
				protocol: 'worktree-file',
				streamId: 'worktree-file:00000000-0000-7000-8000-000000000003',
				generation: 1,
			},
		);
	});

	test('throws on malformed shared open-source contract fixtures', () => {
		expect(() =>
			worktreeFileSurfaceSourceSpecSchema.parse(invalidOpenSourceSpecExtraFieldFixture),
		).toThrow();
		expect(() =>
			worktreeFileSurfaceOpenSourceOutcomeSchema.parse(
				invalidOpenSourceOutcomeWrongProtocolFixture,
			),
		).toThrow();
		expect(() =>
			worktreeFileSurfaceOpenSourceOutcomeSchema.parse(invalidOpenSourceOutcomeExtraFieldFixture),
		).toThrow();
	});

	test('parses Worktree/File snapshot frames with provider extent facts', () => {
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
					includeComments: false,
					includeAgentComms: false,
					freshness: 'live',
				},
				treeRows: [
					{
						rowId: 'row-1',
						path: 'Sources/App/View.swift',
						name: 'View.swift',
						parentPath: 'Sources/App',
						depth: 2,
						isDirectory: false,
						fileId: 'file-1',
					},
				],
				treeSizeFacts: {
					extentKind: 'exactPathCount',
					pathCount: 12_000,
					windowStartIndex: 0,
					windowRowCount: 50,
					rowHeightPixels: 24,
				},
				statusPatch: {
					staged: 0,
					unstaged: 1,
					untracked: 0,
				},
			}),
		).toMatchObject({
			frameKind: 'worktree.snapshot',
			treeSizeFacts: {
				extentKind: 'exactPathCount',
				pathCount: 12_000,
				rowHeightPixels: 24,
			},
		});
	});

	test('requires streamed tree rows on snapshot and tree-window metadata frames', () => {
		const sourceIdentity = makeSourceIdentity();
		const row = {
			rowId: 'row-1',
			path: 'Sources/App/View.swift',
			name: 'View.swift',
			parentPath: 'Sources/App',
			depth: 2,
			isDirectory: false,
			fileId: 'file-1',
		};

		expect(
			worktreeSnapshotFrameSchema.safeParse({
				kind: 'snapshot',
				streamId: 'worktree-file:pane-1',
				generation: 1,
				sequence: 0,
				frameKind: 'worktree.snapshot',
				source: sourceIdentity,
			}).success,
		).toBe(false);
		expect(
			worktreeTreeWindowFrameSchema.safeParse({
				kind: 'delta',
				streamId: 'worktree-file:pane-1',
				generation: 1,
				sequence: 1,
				frameKind: 'worktree.treeWindow',
				projectionIdentity: {
					source: sourceIdentity,
					pathScope: [],
					treeWindowKey: 'tree-window-1',
				},
			}).success,
		).toBe(false);
		expect(
			worktreeTreeWindowFrameSchema.parse({
				kind: 'delta',
				streamId: 'worktree-file:pane-1',
				generation: 1,
				sequence: 1,
				frameKind: 'worktree.treeWindow',
				projectionIdentity: {
					source: sourceIdentity,
					pathScope: [],
					treeWindowKey: 'tree-window-1',
				},
				rows: [row],
			}).rows,
		).toEqual([row]);
	});

	test('parses native metadata lineage on streamed tree rows', () => {
		const sourceIdentity = makeSourceIdentity();
		const snapshotRow = makeTreeRow({
			path: 'Sources/App/View.swift',
			loaded_by: 'startup_window',
			lane: 'foreground',
		});
		const idleWindowRow = makeTreeRow({
			path: 'Sources/App/Details.swift',
			loaded_by: 'idle',
			lane: 'idle',
		});

		const parsedSnapshotFrame = worktreeFileProtocolFrameSchema.parse({
			kind: 'snapshot',
			streamId: 'worktree-file:pane-1',
			generation: 1,
			sequence: 0,
			frameKind: 'worktree.snapshot',
			source: sourceIdentity,
			treeRows: [snapshotRow],
		});
		expect(parsedSnapshotFrame.frameKind).toBe('worktree.snapshot');
		if (parsedSnapshotFrame.frameKind !== 'worktree.snapshot') {
			throw new Error('expected parsed snapshot frame');
		}
		expect(parsedSnapshotFrame.treeRows[0]).toMatchObject({
			loaded_by: 'startup_window',
			lane: 'foreground',
		});
		const parsedTreeWindowFrame = worktreeFileProtocolFrameSchema.parse({
			kind: 'delta',
			streamId: 'worktree-file:pane-1',
			generation: 1,
			sequence: 1,
			frameKind: 'worktree.treeWindow',
			projectionIdentity: {
				source: sourceIdentity,
				pathScope: [],
				treeWindowKey: 'tree-window-1',
			},
			rows: [idleWindowRow],
		});
		expect(parsedTreeWindowFrame.frameKind).toBe('worktree.treeWindow');
		if (parsedTreeWindowFrame.frameKind !== 'worktree.treeWindow') {
			throw new Error('expected parsed tree window frame');
		}
		expect(parsedTreeWindowFrame.rows[0]).toMatchObject({
			loaded_by: 'idle',
			lane: 'idle',
		});
	});

	test('parses shared demand lane loaded_by vocabulary', () => {
		const loadedByValues: readonly WorktreeTreeRowMetadata['loaded_by'][] = [
			'startup_window',
			'foreground',
			'visible',
			'nearby',
			'speculative',
			'idle',
			'delta',
			'reset',
			'replacement',
		];

		for (const loaded_by of loadedByValues) {
			expect(
				worktreeTreeRowMetadataSchema.parse(
					makeTreeRow({
						path: `Sources/App/${loaded_by}.swift`,
						loaded_by,
						lane: loaded_by === 'startup_window' ? 'foreground' : 'idle',
					}),
				).loaded_by,
			).toBe(loaded_by);
		}
	});

	test('rejects legacy Worktree/File-specific loaded_by tokens', () => {
		for (const loaded_by of [
			'foreground_interest',
			'visible_window',
			'nearby_window',
			'speculative_interest',
		]) {
			expect(
				worktreeTreeRowMetadataSchema.safeParse({
					...makeTreeRow({
						path: `Sources/App/${loaded_by}.swift`,
						loaded_by: 'idle',
						lane: 'idle',
					}),
					loaded_by,
				}).success,
			).toBe(false);
		}
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

interface MakeTreeRowProps {
	readonly path: string;
	readonly loaded_by: WorktreeTreeRowMetadata['loaded_by'];
	readonly lane: WorktreeTreeRowMetadata['lane'];
}

function makeTreeRow(props: MakeTreeRowProps): WorktreeTreeRowMetadata {
	const name = props.path.split('/').at(-1) ?? props.path;
	const parentPath = props.path.includes('/')
		? props.path.slice(0, Math.max(0, props.path.lastIndexOf('/')))
		: null;
	return {
		rowId: `row:${props.path}`,
		path: props.path,
		name,
		parentPath,
		depth: props.path.split('/').length - 1,
		isDirectory: false,
		fileId: `file:${props.path}`,
		loaded_by: props.loaded_by,
		lane: props.lane,
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
	readonly resourceKind: 'worktree.fileContent' | 'worktree.fileRange';
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
