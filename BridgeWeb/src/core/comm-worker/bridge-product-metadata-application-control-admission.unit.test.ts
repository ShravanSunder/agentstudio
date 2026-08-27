import { describe, expect, test } from 'vitest';

import { parseBridgeProductRegisteredControlRequest } from './bridge-product-metadata-application-registry.js';
import { bridgeProductControlRequestSchema } from './bridge-product-session-contracts.js';

const requestIdentity = {
	paneSessionId: 'pane-session-1',
	requestId: 'resync-request-1',
	requestSequence: 2,
	wireVersion: 2,
	workerInstanceId: 'worker-instance-1',
} as const;

const reviewEpochSeven = {
	interestRevision: 0,
	interestSha256: 'a'.repeat(64),
	subscriptionId: 'review-subscription-1',
	subscriptionKind: 'review.metadata',
	workerDerivationEpoch: 7,
} as const;

const fileEpochTwo = {
	interestRevision: 0,
	interestSha256: 'b'.repeat(64),
	subscriptionId: 'file-subscription-1',
	subscriptionKind: 'file.metadata',
	workerDerivationEpoch: 2,
} as const;

describe('Bridge product registered control admission', () => {
	test('admits independent surface epochs and rejects split same-surface epochs', () => {
		const paneResync = {
			...requestIdentity,
			activeSubscriptions: [reviewEpochSeven, fileEpochTwo],
			kind: 'workerSession.resync',
			lastAcceptedRequestSequence: 1,
			lastAcceptedStreamSequence: 0,
		};

		expect(bridgeProductControlRequestSchema.safeParse(paneResync).success).toBe(true);
		expect(() => parseBridgeProductRegisteredControlRequest(paneResync)).not.toThrow();
		expect(() =>
			parseBridgeProductRegisteredControlRequest({
				...paneResync,
				activeSubscriptions: [
					reviewEpochSeven,
					{
						...reviewEpochSeven,
						subscriptionId: 'review-subscription-2',
						workerDerivationEpoch: 8,
					},
				],
			}),
		).toThrow(/one surface.*derivation epoch/iu);
	});
});
