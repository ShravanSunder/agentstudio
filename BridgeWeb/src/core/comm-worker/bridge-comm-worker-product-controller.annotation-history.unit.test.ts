import { expect, test } from 'vitest';

import { BridgeCommWorkerProductController } from './bridge-comm-worker-product-controller.js';
import type { BridgeProductTransportSession } from './bridge-product-transport.js';

test('product controller preserves decoded nonempty annotation output history', async () => {
	const sessionId = '00000000-0000-7000-8000-000000000041';
	const historyResult = {
		kind: 'completed',
		outcome: {
			requestId: 'history-request-1',
			sessionId,
			status: {
				kind: 'history',
				summaries: [
					{
						attemptId: '00000000-0000-7000-8000-000000000042',
						canMarkNotHandled: true,
						createdAt: 1_700_000_000_000,
						messageCount: 1,
						outputKind: 'clipboard_markdown',
						repeatedFromAttemptId: null,
						sessionId,
						state: 'succeeded',
						updatedAt: 1_700_000_000_001,
					},
				],
			},
			surface: 'review',
		},
	} as const;
	const controller = new BridgeCommWorkerProductController({
		onFileMetadataEvent: (): void => {},
		productTransport: decodedHistoryProductTransport(historyResult),
	});

	const result = await controller.sendProductControl({
		method: 'review.annotations.command',
		params: { operation: { kind: 'output.history', sessionId } },
	});

	expect(result).toEqual(historyResult);
});

function decodedHistoryProductTransport(historyResult: unknown): BridgeProductTransportSession {
	return {
		bumpWorkerDerivationEpoch: (): number => 0,
		// oxlint-disable-next-line typescript/no-unsafe-type-assertion -- This fake returns the one decoded annotation history result under test.
		call: (async (): Promise<unknown> => historyResult) as BridgeProductTransportSession['call'],
		openContent: (): never => {
			throw new Error('Unexpected annotation history content open.');
		},
		subscribe: (): never => {
			throw new Error('Unexpected annotation history subscription.');
		},
		workerDerivationEpoch: (): number => 0,
	};
}
