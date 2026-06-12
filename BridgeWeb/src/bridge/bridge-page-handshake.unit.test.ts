import { describe, expect, test } from 'vitest';

import {
	installBridgePageHandshake,
	installBridgePageHandshakeSession,
} from './bridge-page-handshake.js';

describe('bridge page handshake', () => {
	test('requests handshake replay and emits bridge ready after handshake with nonce arrives', () => {
		const target = new EventTarget();
		const eventNames: string[] = [];

		target.addEventListener('__bridge_handshake_request', () => {
			eventNames.push('__bridge_handshake_request');
			target.dispatchEvent(
				new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-1' } }),
			);
		});
		target.addEventListener('__bridge_ready', () => {
			eventNames.push('__bridge_ready');
		});

		const uninstall = installBridgePageHandshake(target);
		target.dispatchEvent(
			new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-2' } }),
		);
		uninstall();

		expect(eventNames).toEqual(['__bridge_handshake_request', '__bridge_ready']);
	});

	test('does not emit bridge ready until the handshake carries a push nonce', () => {
		const target = new EventTarget();
		const eventNames: string[] = [];

		target.addEventListener('__bridge_ready', () => {
			eventNames.push('__bridge_ready');
		});

		const session = installBridgePageHandshakeSession(target);
		target.dispatchEvent(new CustomEvent('__bridge_handshake'));
		expect(eventNames).toEqual([]);

		target.dispatchEvent(
			new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-1' } }),
		);
		session.uninstall();

		expect(session.getPushNonce()).toBe('push-1');
		expect(eventNames).toEqual(['__bridge_ready']);
	});

	test('retains the first push nonce from the bridge handshake', () => {
		const target = new EventTarget();

		target.addEventListener('__bridge_handshake_request', () => {
			target.dispatchEvent(
				new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-1' } }),
			);
		});

		const session = installBridgePageHandshakeSession(target);
		target.dispatchEvent(
			new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-2' } }),
		);
		session.uninstall();

		expect(session.getPushNonce()).toBe('push-1');
	});
});
