import { describe, expect, test } from 'vitest';

import { bridgeProductMetadataFrameSchema } from './bridge-product-session-contracts.js';

describe('Bridge product raw metadata application envelope', () => {
	test('requires raw application data without validating an application schema', () => {
		const rawFrame = {
			cursor: null,
			data: { applicationOwned: true },
			interestRevision: 0,
			interestSha256: 'a'.repeat(64),
			kind: 'subscription.data',
			metadataStreamId: 'metadata-stream-raw-1',
			operationCorrelationId: null,
			paneSessionId: 'pane-session-raw-1',
			sourceGeneration: 1,
			streamSequence: 1,
			subscriptionId: 'subscription-raw-1',
			subscriptionKind: 'fixture.metadata',
			subscriptionSequence: 1,
			wireVersion: 2,
			workerDerivationEpoch: 0,
			workerInstanceId: 'worker-instance-raw-1',
		};

		expect(bridgeProductMetadataFrameSchema.parse(rawFrame)).toEqual(rawFrame);
		const { data: _missingData, ...frameWithoutData } = rawFrame;
		expect(bridgeProductMetadataFrameSchema.safeParse(frameWithoutData).success).toBe(false);
	});
});
