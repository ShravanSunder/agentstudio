import { describe, expect, test } from 'vitest';

import {
	encodeBridgeWorkerActiveViewerModeUpdateCommand,
	encodeBridgeWorkerFileDisplayResyncCommand,
	encodeBridgeWorkerHoverCommand,
	encodeBridgeWorkerMarkFileViewedCommand,
	encodeBridgeWorkerMetadataInterestUpdateCommand,
	encodeBridgeWorkerModeCommand,
	encodeBridgeWorkerRenderDispositionCommand,
	encodeBridgeWorkerReviewIntakeReadyCommand,
	encodeBridgeWorkerSelectCommand,
	encodeBridgeWorkerViewportCommand,
} from './bridge-comm-worker-protocol.js';
import {
	BRIDGE_WORKER_WIRE_VERSION,
	bridgeWorkerMainToServerMessageSchema,
	type BridgeWorkerMainToServerCommand,
	type BridgeWorkerRenderDispositionCommand,
} from './bridge-worker-contracts.js';

describe('Bridge comm worker protocol', () => {
	test('encodes select viewport hover ordinary RPC and mode commands through BridgeWorkerContracts', () => {
		const commands = [
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select',
				epoch: 1,
				surface: 'review',
				selectedItemId: 'item-1',
				selectedSource: 'keyboard',
			}),
			encodeBridgeWorkerViewportCommand({
				requestId: 'request-viewport',
				epoch: 1,
				surface: 'fileView',
				visibleItemIds: ['item-1', 'item-2'],
				firstVisibleIndex: 0,
				lastVisibleIndex: 1,
				phase: 'settled',
			}),
			encodeBridgeWorkerHoverCommand({
				requestId: 'request-hover',
				epoch: 1,
				surface: 'review',
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
					nativeSelectionRequestId: null,
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
		expect(
			commands.slice(0, 3).map((command) => ('surface' in command ? command.surface : null)),
		).toEqual(['review', 'fileView', 'review']);
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
		expect(commands[7]).toMatchObject({
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
			surface: 'review',
			selectedItemId: 'item-1',
			selectedSource: 'user',
		});

		expect(command.issuedAtMilliseconds).toBe(42);
		expect(command.surface).toBe('review');
		expect(bridgeWorkerMainToServerMessageSchema.parse(command)).toEqual(command);
	});

	test('encodes a strict File display resync command with failure context', () => {
		const command = encodeBridgeWorkerFileDisplayResyncCommand({
			epoch: 8,
			reason: 'bufferOverflow',
			requestId: 'request-file-display-resync',
			transactionId: 'file-query-4',
		});

		expect(command).toMatchObject({
			command: 'fileDisplayResync',
			epoch: 8,
			reason: 'bufferOverflow',
			transactionId: 'file-query-4',
		});
		expect(bridgeWorkerMainToServerMessageSchema.parse(command)).toEqual(command);
	});

	test('encodes a strict identity-bound render disposition command', () => {
		const command = encodeBridgeWorkerRenderDispositionCommand({
			epoch: 5,
			receipt: reviewQueuedRenderDispositionReceipt(),
			requestId: 'request-render-disposition',
		});

		expect(command).toMatchObject({
			command: 'renderDisposition',
			epoch: 5,
			receipt: {
				disposition: 'queued',
				itemId: 'item-1',
				publicationId: 'publication-review-8',
				publicationSequence: 8,
				surface: 'review',
			},
		});
		expect(bridgeWorkerMainToServerMessageSchema.parse(command)).toEqual(command);
	});
});

function reviewQueuedRenderDispositionReceipt(): BridgeWorkerRenderDispositionCommand['receipt'] {
	return {
		attemptId: 'attempt-review-8',
		disposition: 'queued' as const,
		itemId: 'item-1',
		kind: 'render.disposition' as const,
		paneSessionId: 'pane-session-1',
		publicationId: 'publication-review-8',
		publicationSequence: 8,
		receivedAtMilliseconds: 42,
		submissionId: 'submission-review-8',
		surface: 'review' as const,
		windowKey: 'window-review-8',
		workerDerivationEpoch: 5,
		workerInstanceId: 'worker-instance-1',
	};
}
