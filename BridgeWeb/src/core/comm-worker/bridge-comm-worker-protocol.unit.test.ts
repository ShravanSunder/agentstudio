import { describe, expect, test } from 'vitest';

import {
	encodeBridgeWorkerFileViewSourceUpdateCommand,
	encodeBridgeWorkerActiveViewerModeUpdateCommand,
	encodeBridgeWorkerHoverCommand,
	encodeBridgeWorkerMarkFileViewedCommand,
	encodeBridgeWorkerMetadataInterestUpdateCommand,
	encodeBridgeWorkerModeCommand,
	encodeBridgeWorkerReviewIntakeReadyCommand,
	encodeBridgeWorkerSelectCommand,
	encodeBridgeWorkerViewportCommand,
	encodeBridgeWorkerWorktreeFileIntakeReadyCommand,
	encodeBridgeWorkerWorktreeFileOpenSourceStreamCommand,
	encodeBridgeWorkerWorktreeFileRequestDescriptorCommand,
} from './bridge-comm-worker-protocol.js';
import {
	BRIDGE_WORKER_WIRE_VERSION,
	bridgeWorkerMainToServerMessageSchema,
	type BridgeWorkerMainToServerCommand,
} from './bridge-worker-contracts.js';

describe('Bridge comm worker protocol', () => {
	test('encodes select viewport hover ordinary RPC and mode commands through BridgeWorkerContracts', () => {
		const commands = [
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select',
				epoch: 1,
				selectedItemId: 'item-1',
				selectedSource: 'keyboard',
			}),
			encodeBridgeWorkerViewportCommand({
				requestId: 'request-viewport',
				epoch: 1,
				visibleItemIds: ['item-1', 'item-2'],
				firstVisibleIndex: 0,
				lastVisibleIndex: 1,
				phase: 'settled',
			}),
			encodeBridgeWorkerHoverCommand({
				requestId: 'request-hover',
				epoch: 1,
				hoveredItemId: 'item-2',
			}),
			encodeBridgeWorkerMarkFileViewedCommand({
				requestId: 'request-mark-viewed',
				epoch: 1,
				fileId: 'item-1',
			}),
			encodeBridgeWorkerMetadataInterestUpdateCommand({
				requestId: 'request-metadata-interest',
				epoch: 1,
				request: {
					protocol: 'review',
					streamId: 'stream-1',
					generation: 7,
					itemIds: ['item-1', 'item-2'],
					lane: 'visible',
					loaded_by: 'visible',
				},
			}),
			encodeBridgeWorkerReviewIntakeReadyCommand({
				requestId: 'request-review-intake-ready',
				epoch: 1,
				streamId: 'review:pane-1',
				reason: 'bridge-ready',
			}),
			encodeBridgeWorkerWorktreeFileIntakeReadyCommand({
				requestId: 'request-worktree-file-intake-ready',
				epoch: 1,
				generation: 3,
				streamId: 'worktree-file:pane-1',
			}),
			encodeBridgeWorkerWorktreeFileOpenSourceStreamCommand({
				requestId: 'request-worktree-file-open-source',
				epoch: 1,
				sourceSpec: makeWorktreeFileSourceSpec(),
			}),
			encodeBridgeWorkerWorktreeFileRequestDescriptorCommand({
				requestId: 'request-worktree-file-descriptor',
				epoch: 1,
				descriptorRequest: makeWorktreeFileDescriptorRequest(),
			}),
			encodeBridgeWorkerModeCommand({
				requestId: 'request-mode',
				epoch: 1,
				mode: 'fileView',
			}),
			encodeBridgeWorkerActiveViewerModeUpdateCommand({
				requestId: 'request-active-viewer-mode',
				epoch: 1,
				update: {
					sessionId: 'active-viewer-session',
					sequence: 2,
					mode: 'file',
					activeSource: {
						protocol: 'worktree-file',
						streamId: 'worktree-file:pane-1',
						generation: 3,
					},
				},
			}),
		] satisfies readonly BridgeWorkerMainToServerCommand[];

		expect(commands.map((command) => command.command)).toEqual([
			'select',
			'viewport',
			'hover',
			'markFileViewed',
			'metadataInterestUpdate',
			'reviewIntakeReady',
			'worktreeFileIntakeReady',
			'worktreeFileOpenSourceStream',
			'worktreeFileRequestDescriptor',
			'mode',
			'activeViewerModeUpdate',
		]);
		for (const command of commands) {
			expect(command.wireVersion).toBe(BRIDGE_WORKER_WIRE_VERSION);
			expect(command.direction).toBe('mainToServerWorker');
			expect(command.issuedAtMilliseconds).toBeUndefined();
			expect(command.transferDescriptors).toEqual([]);
			expect(bridgeWorkerMainToServerMessageSchema.parse(command)).toEqual(command);
		}
		expect(commands[3]).toMatchObject({
			command: 'markFileViewed',
			fileId: 'item-1',
		});
		expect(commands[4]).toMatchObject({
			command: 'metadataInterestUpdate',
			request: {
				protocol: 'review',
				itemIds: ['item-1', 'item-2'],
				lane: 'visible',
			},
		});
		expect(commands[5]).toMatchObject({
			command: 'reviewIntakeReady',
			protocolId: 'review',
			streamId: 'review:pane-1',
			reason: 'bridge-ready',
		});
		expect(commands[6]).toMatchObject({
			command: 'worktreeFileIntakeReady',
			protocolId: 'worktree-file',
			streamId: 'worktree-file:pane-1',
			generation: 3,
		});
		expect(commands[7]).toMatchObject({
			command: 'worktreeFileOpenSourceStream',
			sourceSpec: {
				clientRequestId: 'client-open-1',
				repoId: 'repo-1',
				worktreeId: 'worktree-1',
				freshness: 'live',
			},
		});
		expect(commands[8]).toMatchObject({
			command: 'worktreeFileRequestDescriptor',
			descriptorRequest: {
				rowId: 'row-1',
				path: 'Sources/App/File.swift',
				fileId: 'file-1',
				lane: 'foreground',
			},
		});
		expect(commands[10]).toMatchObject({
			command: 'activeViewerModeUpdate',
			update: {
				sessionId: 'active-viewer-session',
				sequence: 2,
				mode: 'file',
				activeSource: {
					protocol: 'worktree-file',
					streamId: 'worktree-file:pane-1',
					generation: 3,
				},
			},
		});
	});

	test('preserves explicit dispatch timestamps for worker queue-wait telemetry', () => {
		const command = encodeBridgeWorkerSelectCommand({
			requestId: 'request-select',
			epoch: 3,
			issuedAtMilliseconds: 42,
			selectedItemId: 'item-1',
			selectedSource: 'user',
		});

		expect(command.issuedAtMilliseconds).toBe(42);
		expect(bridgeWorkerMainToServerMessageSchema.parse(command)).toEqual(command);
	});

	test('encodes File View source updates through BridgeWorkerContracts', () => {
		const command = encodeBridgeWorkerFileViewSourceUpdateCommand({
			requestId: 'request-file-view-source',
			epoch: 4,
			contentItems: [
				{
					itemId: 'file-1',
					path: 'Sources/App/FileView.swift',
					language: 'swift',
					cacheKey: 'file-view:sha256:file-1',
					sizeBytes: 128,
					contentHandle: 'handle-file-1',
					descriptorId: 'descriptor-file-1',
					contentHash: 'sha256:file-1',
					virtualizedExtentKind: 'exactLineCount',
					lineCount: 7,
					isBinary: false,
					canFetchContent: true,
				},
			],
			contentRequestDescriptors: [
				{
					itemId: 'file-1',
					path: 'Sources/App/FileView.swift',
					handleId: 'handle-file-1',
					descriptorId: 'descriptor-file-1',
					resourceKind: 'worktree.fileContent',
					resourceUrl:
						'agentstudio://resource/worktree-file/worktree.fileContent/descriptor-file-1?cursor=cursor-1&generation=3',
					contentHash: 'sha256:file-1',
					contentHashAlgorithm: 'sha256',
					language: 'swift',
					sizeBytes: 128,
					maxBytes: 4096,
					isBinary: false,
				},
			],
			rows: [{ id: 'file-1', parentId: null, index: 0 }],
		});

		expect(command.command).toBe('fileViewSourceUpdate');
		expect(command.wireVersion).toBe(BRIDGE_WORKER_WIRE_VERSION);
		expect(command.direction).toBe('mainToServerWorker');
		expect(command.transferDescriptors).toEqual([]);
		expect(bridgeWorkerMainToServerMessageSchema.parse(command)).toEqual(command);
		expect(JSON.stringify(command.contentItems)).not.toMatch(/resourceUrl|contents|body/i);
	});
});

function makeWorktreeFileSourceSpec() {
	return {
		clientRequestId: 'client-open-1',
		repoId: 'repo-1',
		worktreeId: 'worktree-1',
		rootPathToken: 'root-token-1',
		includeStatuses: true,
		includeComments: false,
		includeAgentComms: false,
		freshness: 'live',
	} as const;
}

function makeWorktreeFileDescriptorRequest() {
	return {
		sourceIdentity: {
			sourceId: 'source-1',
			repoId: 'repo-1',
			worktreeId: 'worktree-1',
			subscriptionGeneration: 4,
			sourceCursor: 'cursor-1',
		},
		rowId: 'row-1',
		path: 'Sources/App/File.swift',
		fileId: 'file-1',
		lane: 'foreground',
	} as const;
}
