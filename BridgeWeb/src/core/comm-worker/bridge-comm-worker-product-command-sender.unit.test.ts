import { describe, expect, test } from 'vitest';

import { BridgeCommWorkerProductController } from './bridge-comm-worker-product-controller.js';
import type { BridgeProductControlCommand } from './bridge-product-control-contracts.js';
import type { BridgeProductTransportSession } from './bridge-product-transport.js';

describe('Bridge comm worker product command sender', () => {
	test('maps permanent commands to closed surface-derived product calls', async () => {
		// Arrange
		const calls: unknown[] = [];
		const productTransport = {
			bumpWorkerDerivationEpoch: (): number => 1,
			call: async (...arguments_): Promise<null> => {
				calls.push(arguments_);
				return null;
			},
			openContent: (): never => {
				throw new Error('Unexpected content open.');
			},
			subscribe: (): never => {
				throw new Error('Unexpected subscription open.');
			},
			workerDerivationEpoch: (): number => 1,
		} satisfies BridgeProductTransportSession;
		const controller = new BridgeCommWorkerProductController({
			onFileMetadataEvent: (): void => {},
			productTransport,
		});

		// Act
		await controller.sendProductControl({
			method: 'review.markFileViewed',
			params: { fileId: 'item-1' },
		});
		await controller.sendProductControl({
			method: 'bridge.intakeReady',
			params: {
				protocolId: 'review',
				reason: 'sequence_gap',
				streamId: 'review-stream',
			},
		});
		await controller.sendProductControl(activeModeCommand('review'));
		await controller.sendProductControl(activeModeCommand('file'));

		// Assert
		expect(calls).toEqual([
			['review.markFileViewed', { itemId: 'item-1' }],
			['review.intake.ready', { reason: 'sequence_gap', streamId: 'review-stream' }],
			[
				'review.activeViewerMode.update',
				{
					activeSource: { generation: 3, streamId: 'review-stream' },
					sequence: 9,
					sessionId: 'viewer-session',
				},
			],
			[
				'file.activeViewerMode.update',
				{
					activeSource: { generation: 3, streamId: 'file-stream' },
					sequence: 9,
					sessionId: 'viewer-session',
				},
			],
		]);
	});

	test('rejects a cross-surface active source before product admission', async () => {
		// Arrange
		const calls: unknown[] = [];
		const productTransport = {
			bumpWorkerDerivationEpoch: (): number => 1,
			call: async (...arguments_): Promise<null> => {
				calls.push(arguments_);
				return null;
			},
			openContent: (): never => {
				throw new Error('Unexpected content open.');
			},
			subscribe: (): never => {
				throw new Error('Unexpected subscription open.');
			},
			workerDerivationEpoch: (): number => 1,
		} satisfies BridgeProductTransportSession;
		const controller = new BridgeCommWorkerProductController({
			onFileMetadataEvent: (): void => {},
			productTransport,
		});

		// Act / Assert
		await expect(
			controller.sendProductControl({
				...activeModeCommand('review'),
				params: {
					...activeModeCommand('review').params,
					activeSource: { generation: 3, protocol: 'worktree-file', streamId: 'wrong' },
				},
			}),
		).rejects.toThrow(/does not match.*surface/iu);
		expect(calls).toEqual([]);
	});
});

function activeModeCommand(
	mode: 'file' | 'review',
): Extract<BridgeProductControlCommand, { readonly method: 'bridge.activeViewerMode.update' }> {
	return {
		method: 'bridge.activeViewerMode.update',
		params: {
			activeSource: {
				generation: 3,
				protocol: mode === 'review' ? 'review' : 'worktree-file',
				streamId: mode === 'review' ? 'review-stream' : 'file-stream',
			},
			mode,
			sequence: 9,
			sessionId: 'viewer-session',
		},
	};
}
