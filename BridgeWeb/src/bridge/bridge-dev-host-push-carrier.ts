export function dispatchBridgeDevHostAdmittedEnvelope(envelope: unknown): void {
	const channel = new MessageChannel();
	const message = {
		type: 'agentstudio.bridge.hostPushEnvelopeJSON',
		version: 1,
		json: JSON.stringify(envelope),
	};
	window.dispatchEvent(
		new MessageEvent('message', {
			data: {
				type: 'agentstudio.bridge.hostPushPort',
				version: 1,
			},
			ports: [channel.port2],
		}),
	);
	const portMessageEvent = new Event('message');
	Object.defineProperty(portMessageEvent, 'data', { value: message });
	try {
		channel.port2.dispatchEvent(portMessageEvent);
	} catch {
		// jsdom/Node MessagePort uses a different Event constructor; browser dev-server proof covers delivery.
	}
	window.setTimeout((): void => {
		channel.port1.close();
		channel.port2.close();
	}, 0);
}
