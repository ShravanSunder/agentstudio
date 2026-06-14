import { describe, expect, test } from 'vitest';

import pushEpochMismatchFixture from '../test-fixtures/bridge-contract-fixtures/edge/push-epoch-mismatch.json' with { type: 'json' };
import pushStaleRevisionFixture from '../test-fixtures/bridge-contract-fixtures/edge/push-stale-revision.json' with { type: 'json' };
import pushMergeFixture from '../test-fixtures/bridge-contract-fixtures/valid/push-envelope-merge.json' with { type: 'json' };
import pushReplaceFixture from '../test-fixtures/bridge-contract-fixtures/valid/push-envelope-replace.json' with { type: 'json' };
import type { BridgePushEnvelope } from './bridge-push-envelope.js';
import { installBridgePushReceiver } from './bridge-push-receiver.js';

describe('bridge push receiver', () => {
	test('validates nonce and drops stale revisions within an epoch', () => {
		const target = new EventTarget();
		const acceptedEnvelopes: BridgePushEnvelope[] = [];
		const uninstall = installBridgePushReceiver({
			target,
			getPushNonce: () => 'push-nonce',
			onEnvelope: (envelope: BridgePushEnvelope): void => {
				acceptedEnvelopes.push(envelope);
			},
		});

		dispatchPush(target, pushReplaceFixture, 'wrong-nonce');
		dispatchPush(target, pushReplaceFixture, 'push-nonce');
		dispatchPush(target, pushStaleRevisionFixture, 'push-nonce');
		dispatchPush(target, pushMergeFixture, 'push-nonce');
		dispatchPush(target, pushEpochMismatchFixture, 'push-nonce');
		uninstall();
		dispatchPush(target, { ...pushMergeFixture, __revision: 3 }, 'push-nonce');

		expect(
			acceptedEnvelopes.map((envelope: BridgePushEnvelope): number => envelope.revision),
		).toEqual([1, 2, 1]);
		expect(acceptedEnvelopes.map((envelope: BridgePushEnvelope): number => envelope.epoch)).toEqual(
			[1, 1, 2],
		);
	});
});

function dispatchPush(target: EventTarget, detail: object, nonce: string): void {
	target.dispatchEvent(new CustomEvent('__bridge_push', { detail: { ...detail, nonce } }));
}
