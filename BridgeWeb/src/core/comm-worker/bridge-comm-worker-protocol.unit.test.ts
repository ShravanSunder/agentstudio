import { describe, expect, test } from 'vitest';

import {
	encodeBridgeWorkerFileViewSourceUpdateCommand,
	encodeBridgeWorkerHoverCommand,
	encodeBridgeWorkerMarkFileViewedCommand,
	encodeBridgeWorkerModeCommand,
	encodeBridgeWorkerSelectCommand,
	encodeBridgeWorkerViewportCommand,
} from './bridge-comm-worker-protocol.js';
import {
	BRIDGE_WORKER_WIRE_VERSION,
	bridgeWorkerMainToServerMessageSchema,
	type BridgeWorkerMainToServerCommand,
} from './bridge-worker-contracts.js';

describe('Bridge comm worker protocol', () => {
	test('encodes select viewport hover markViewed and mode commands through BridgeWorkerContracts', () => {
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
				filePathHash: 'file-hash-1',
				viewedAtSequence: 7,
			}),
			encodeBridgeWorkerModeCommand({
				requestId: 'request-mode',
				epoch: 1,
				mode: 'fileView',
			}),
		] satisfies readonly BridgeWorkerMainToServerCommand[];

		expect(commands.map((command) => command.command)).toEqual([
			'select',
			'viewport',
			'hover',
			'markFileViewed',
			'mode',
		]);
		for (const command of commands) {
			expect(command.wireVersion).toBe(BRIDGE_WORKER_WIRE_VERSION);
			expect(command.direction).toBe('mainToServerWorker');
			expect(command.issuedAtMilliseconds).toBeUndefined();
			expect(command.transferDescriptors).toEqual([]);
			expect(bridgeWorkerMainToServerMessageSchema.parse(command)).toEqual(command);
		}
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
