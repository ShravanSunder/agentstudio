import { describe, expect, test } from 'vitest';

import pushEpochMismatchFixture from '../test-fixtures/bridge-contract-fixtures/edge/push-epoch-mismatch.json' with { type: 'json' };
import pushMissingRevisionFixture from '../test-fixtures/bridge-contract-fixtures/invalid/push-missing-revision.json' with { type: 'json' };
import pushMergeFixture from '../test-fixtures/bridge-contract-fixtures/valid/push-envelope-merge.json' with { type: 'json' };
import pushReplaceFixture from '../test-fixtures/bridge-contract-fixtures/valid/push-envelope-replace.json' with { type: 'json' };
import { decodeBridgePushEnvelope } from './bridge-push-envelope.js';

describe('bridge push envelope', () => {
	test('decodes Swift push envelope fixtures', () => {
		const replaceEnvelope = decodeBridgePushEnvelope(pushReplaceFixture);
		const mergeEnvelope = decodeBridgePushEnvelope(pushMergeFixture);
		const epochAdvanceEnvelope = decodeBridgePushEnvelope(pushEpochMismatchFixture);

		expect(replaceEnvelope.store).toBe('diff');
		expect(replaceEnvelope.op).toBe('replace');
		expect(replaceEnvelope.revision).toBe(1);
		expect(mergeEnvelope.op).toBe('merge');
		expect(mergeEnvelope.data).toEqual({ status: 'running', error: null, epoch: 1 });
		expect(epochAdvanceEnvelope.epoch).toBe(2);
	});

	test('rejects invalid push envelopes before state mutation', () => {
		expect(() => decodeBridgePushEnvelope(pushMissingRevisionFixture)).toThrow(
			/Invalid bridge push envelope/u,
		);
	});

	test('decodes optional trace context outside the push payload', () => {
		const envelope = decodeBridgePushEnvelope({
			...pushReplaceFixture,
			__traceContext: {
				traceId: '11111111111111111111111111111111',
				spanId: '2222222222222222',
				parentSpanId: null,
				sampled: true,
			},
		});

		expect(envelope.traceContext?.traceId).toBe('11111111111111111111111111111111');
		expect(envelope.data).toEqual(pushReplaceFixture.data);
	});
});
