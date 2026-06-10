import { describe, expect, test } from 'vitest';

import { installBridgePageHandshake } from './bridge-page-handshake.js';

describe('bridge page handshake', () => {
	test('requests handshake replay and emits bridge ready after handshake arrives', () => {
		const target = new EventTarget();
		const eventNames: string[] = [];

		target.addEventListener('__bridge_handshake_request', () => {
			eventNames.push('__bridge_handshake_request');
			target.dispatchEvent(new CustomEvent('__bridge_handshake'));
		});
		target.addEventListener('__bridge_ready', () => {
			eventNames.push('__bridge_ready');
		});

		const uninstall = installBridgePageHandshake(target);
		target.dispatchEvent(new CustomEvent('__bridge_handshake'));
		uninstall();

		expect(eventNames).toEqual(['__bridge_handshake_request', '__bridge_ready']);
	});
});
