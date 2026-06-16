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

	test('accepts different slices from the same store with independent revision timelines', () => {
		const target = new EventTarget();
		const acceptedEnvelopes: BridgePushEnvelope[] = [];
		const uninstall = installBridgePushReceiver({
			target,
			getPushNonce: () => 'push-nonce',
			onEnvelope: (envelope: BridgePushEnvelope): void => {
				acceptedEnvelopes.push(envelope);
			},
		});

		dispatchPush(
			target,
			{
				...pushReplaceFixture,
				__revision: 4,
				slice: 'diff_status',
				data: { status: 'ready', error: null, epoch: 1 },
			},
			'push-nonce',
		);
		dispatchPush(
			target,
			{
				...pushReplaceFixture,
				__revision: 2,
				level: 'cold',
				slice: 'diff_package_metadata',
				data: { package: { packageId: 'package-1' } },
			},
			'push-nonce',
		);
		dispatchPush(
			target,
			{
				...pushReplaceFixture,
				__revision: 3,
				slice: 'diff_status',
				data: { status: 'loading', error: null, epoch: 1 },
			},
			'push-nonce',
		);
		dispatchPush(
			target,
			{
				...pushMergeFixture,
				__revision: 1,
				slice: 'diff_package_delta',
			},
			'push-nonce',
		);
		uninstall();

		expect(acceptedEnvelopes.map((envelope: BridgePushEnvelope): string => envelope.slice)).toEqual(
			['diff_status', 'diff_package_metadata', 'diff_package_delta'],
		);
		expect(
			acceptedEnvelopes.map((envelope: BridgePushEnvelope): number => envelope.revision),
		).toEqual([4, 2, 1]);
	});

	test('accepts JSON-string push details for large cross-world payloads', () => {
		const target = new EventTarget();
		const acceptedEnvelopes: BridgePushEnvelope[] = [];
		const invalidEnvelopes: Error[] = [];
		const droppedReasons: string[] = [];
		const uninstall = installBridgePushReceiver({
			target,
			getPushNonce: () => 'push-nonce',
			onEnvelope: (envelope: BridgePushEnvelope): void => {
				acceptedEnvelopes.push(envelope);
			},
			onInvalidEnvelope: (error: Error): void => {
				invalidEnvelopes.push(error);
			},
			onDroppedEnvelope: (reason): void => {
				droppedReasons.push(reason);
			},
		});

		const envelope = {
			...pushReplaceFixture,
			__revision: 5,
			level: 'cold',
			slice: 'diff_package_metadata',
			data: undefined,
			payload: {
				package: {
					orderedItemIds: ['item-source'],
					itemsById: {
						'item-source': { itemId: 'item-source' },
					},
				},
			},
		};
		target.dispatchEvent(
			new CustomEvent('__bridge_push_json', {
				detail: { json: JSON.stringify(envelope), nonce: 'push-nonce' },
			}),
		);
		target.dispatchEvent(
			new CustomEvent('__bridge_push_json', {
				detail: { json: '{', nonce: 'push-nonce' },
			}),
		);
		uninstall();

		expect(acceptedEnvelopes).toHaveLength(1);
		expect(acceptedEnvelopes[0]?.slice).toBe('diff_package_metadata');
		expect(acceptedEnvelopes[0]?.data).toEqual(envelope.payload);
		expect(invalidEnvelopes).toHaveLength(1);
		expect(droppedReasons).toEqual(['push_decode_failed']);
	});

	test('reports stale push drops without exposing payload data', () => {
		const target = new EventTarget();
		const acceptedEnvelopes: BridgePushEnvelope[] = [];
		const droppedReasons: string[] = [];
		const uninstall = installBridgePushReceiver({
			target,
			getPushNonce: () => 'push-nonce',
			onEnvelope: (envelope: BridgePushEnvelope): void => {
				acceptedEnvelopes.push(envelope);
			},
			onDroppedEnvelope: (reason): void => {
				droppedReasons.push(reason);
			},
		});

		dispatchPush(target, { ...pushReplaceFixture, __revision: 4 }, 'push-nonce');
		dispatchPush(target, { ...pushReplaceFixture, __revision: 3 }, 'push-nonce');
		uninstall();

		expect(acceptedEnvelopes).toHaveLength(1);
		expect(droppedReasons).toEqual(['stale_push']);
	});

	test('reports nonce validation drops without exposing payload data', () => {
		const target = new EventTarget();
		const acceptedEnvelopes: BridgePushEnvelope[] = [];
		const droppedReasons: string[] = [];
		const uninstall = installBridgePushReceiver({
			target,
			getPushNonce: () => null,
			onEnvelope: (envelope: BridgePushEnvelope): void => {
				acceptedEnvelopes.push(envelope);
			},
			onDroppedEnvelope: (reason): void => {
				droppedReasons.push(reason);
			},
		});

		dispatchPush(target, pushReplaceFixture, 'push-nonce');
		uninstall();

		const uninstallWithNonce = installBridgePushReceiver({
			target,
			getPushNonce: () => 'push-nonce',
			onEnvelope: (envelope: BridgePushEnvelope): void => {
				acceptedEnvelopes.push(envelope);
			},
			onDroppedEnvelope: (reason): void => {
				droppedReasons.push(reason);
			},
		});
		dispatchPush(target, pushReplaceFixture, 'wrong-nonce');
		uninstallWithNonce();

		expect(acceptedEnvelopes).toHaveLength(0);
		expect(droppedReasons).toEqual(['missing_push_nonce', 'push_nonce_mismatch']);
	});
});

function dispatchPush(target: EventTarget, detail: object, nonce: string): void {
	target.dispatchEvent(new CustomEvent('__bridge_push', { detail: { ...detail, nonce } }));
}
