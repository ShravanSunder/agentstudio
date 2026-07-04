import { describe, expect, test } from 'vitest';

import {
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
			expect(bridgeWorkerMainToServerMessageSchema.parse(command)).toEqual(command);
		}
	});
});
