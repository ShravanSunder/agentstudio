import { describe, expect, test } from 'vitest';

import commandNotificationFixture from '../test-fixtures/bridge-contract-fixtures/valid/rpc-command-notification.json' with { type: 'json' };
import commandWithIdFixture from '../test-fixtures/bridge-contract-fixtures/valid/rpc-command-with-id.json' with { type: 'json' };
import { createBridgeRPCClient } from './bridge-rpc-client.js';

describe('bridge RPC client', () => {
	test('dispatches JSON-RPC commands with bridge nonce and command id', () => {
		const target = new EventTarget();
		const sentDetails: unknown[] = [];
		target.addEventListener('__bridge_command', (event: Event): void => {
			sentDetails.push(extractEventDetail(event));
		});
		const client = createBridgeRPCClient({
			target,
			getBridgeNonce: () => 'bridge-nonce',
			createCommandId: () => 'cmd-fixed',
		});

		const didSend = client.sendCommand({
			id: commandWithIdFixture.id,
			method: commandWithIdFixture.method,
			params: commandWithIdFixture.params,
		});

		expect(didSend).toBe(true);
		expect(sentDetails).toEqual([
			{
				...commandWithIdFixture,
				__nonce: 'bridge-nonce',
				__commandId: 'cmd-fixed',
			},
		]);
	});

	test('dispatches JSON-RPC notifications from shared contract fixtures', () => {
		const target = new EventTarget();
		const sentDetails: unknown[] = [];
		target.addEventListener('__bridge_command', (event: Event): void => {
			sentDetails.push(extractEventDetail(event));
		});
		const client = createBridgeRPCClient({
			target,
			getBridgeNonce: () => 'bridge-nonce',
			createCommandId: () => 'cmd-fixed-notification',
		});

		const didSend = client.sendCommand({
			method: commandNotificationFixture.method,
			params: commandNotificationFixture.params,
		});

		expect(didSend).toBe(true);
		expect(sentDetails).toEqual([
			{
				...commandNotificationFixture,
				__nonce: 'bridge-nonce',
				__commandId: 'cmd-fixed-notification',
			},
		]);
	});

	test('drops commands when bridge nonce is not available', () => {
		const target = new EventTarget();
		const sentDetails: unknown[] = [];
		target.addEventListener('__bridge_command', (event: Event): void => {
			sentDetails.push(extractEventDetail(event));
		});
		const client = createBridgeRPCClient({
			target,
			getBridgeNonce: () => null,
			createCommandId: () => 'cmd-fixed',
		});

		const didSend = client.sendCommand({ method: 'inbox.post' });

		expect(didSend).toBe(false);
		expect(sentDetails).toEqual([]);
	});
});

function extractEventDetail(event: Event): unknown {
	return 'detail' in event ? event.detail : null;
}
