import { describe, expect, test, vi } from 'vitest';

import type { BridgeTelemetrySample } from '../../foundation/telemetry/bridge-telemetry-event.js';
import { createBridgeCommWorkerCommandHandler } from './bridge-comm-worker-command-handler.js';
import { applyBridgeWorkerRenderDispositionCommand } from './bridge-comm-worker-render-disposition-application.js';
import type { BridgeWorkerRenderDispositionCommand } from './bridge-worker-contracts.js';
import type { BridgeWorkerRenderDispositionReceipt } from './bridge-worker-render-fulfillment.js';
import { makeBridgeWorkerRenderReceiptIdentity } from './bridge-worker-render-fulfillment.test-support.js';

describe('Bridge comm worker render disposition application', () => {
	test('applies every receipt even when an earlier receipt is rejected', () => {
		const telemetrySamples: BridgeTelemetrySample[] = [];
		const receipts = [makeQueuedReceipt(1), makeQueuedReceipt(2), makeQueuedReceipt(3)];
		const applyDisposition = vi
			.fn()
			.mockReturnValueOnce({ reason: 'stale', state: null, status: 'rejected' })
			.mockReturnValueOnce({ state: {}, status: 'accepted' })
			.mockReturnValueOnce({ state: {}, status: 'duplicate' });
		const command = {
			command: 'renderDisposition',
			direction: 'mainToServerWorker',
			epoch: 1,
			kind: 'command',
			receipts,
			requestId: 'mixed-batch',
			transferDescriptors: [],
			wireVersion: 1,
		} satisfies BridgeWorkerRenderDispositionCommand;

		const messages = applyBridgeWorkerRenderDispositionCommand({
			command,
			store: { renderFulfillmentRegistry: { applyDisposition } },
			telemetryClient: {
				record: (sample): void => {
					telemetrySamples.push(sample);
				},
			},
		});

		expect(applyDisposition.mock.calls.map(([receipt]) => receipt.itemId)).toEqual([
			'item-1',
			'item-2',
			'item-3',
		]);
		expect(messages).toEqual([
			expect.objectContaining({
				kind: 'health',
				requestId: 'mixed-batch',
				status: 'degraded',
			}),
		]);
		expect(telemetrySamples).toEqual([
			expect.objectContaining({
				name: 'performance.bridge.worker.render_disposition_batch',
				numericAttributes: expect.objectContaining({
					'agentstudio.bridge.render_disposition.accepted_count': 1,
					'agentstudio.bridge.render_disposition.batch_receipt_count': 3,
					'agentstudio.bridge.render_disposition.duplicate_count': 1,
					'agentstudio.bridge.render_disposition.rejected_count': 1,
				}),
				stringAttributes: expect.objectContaining({
					'agentstudio.bridge.phase': 'render_disposition_batch_applied',
					'agentstudio.bridge.result': 'failed',
				}),
			}),
		]);
	});

	test('routes default command handling through batch telemetry', () => {
		const telemetrySamples: BridgeTelemetrySample[] = [];
		const command = {
			command: 'renderDisposition',
			direction: 'mainToServerWorker',
			epoch: 1,
			kind: 'command',
			receipts: [makeQueuedReceipt(1)],
			requestId: 'default-handler-batch',
			transferDescriptors: [],
			wireVersion: 1,
		} satisfies BridgeWorkerRenderDispositionCommand;
		const handler = createBridgeCommWorkerCommandHandler({
			contentItems: [],
			rows: [],
			scheduleSelectedFileViewContentReadyPreparation: (): void => {},
			scheduleSelectedReviewContentReadyPreparation: (): void => {},
			telemetryClient: {
				record: (sample): void => {
					telemetrySamples.push(sample);
				},
			},
		});

		handler.handleMessage(command);

		expect(telemetrySamples).toEqual([
			expect.objectContaining({ name: 'performance.bridge.worker.render_disposition_batch' }),
		]);
	});
});

function makeQueuedReceipt(index: number): BridgeWorkerRenderDispositionReceipt {
	return {
		...makeBridgeWorkerRenderReceiptIdentity({
			itemId: `item-${index}`,
			publicationSequence: index,
			surface: 'review',
			workerDerivationEpoch: 1,
		}),
		disposition: 'queued',
		kind: 'render.disposition',
		receivedAtMilliseconds: index,
	};
}
