type BridgeHandshakeTarget = Pick<
	EventTarget,
	'addEventListener' | 'dispatchEvent' | 'removeEventListener'
>;

export function installBridgePageHandshake(target: BridgeHandshakeTarget = document): () => void {
	let didSendReady = false;

	const handleHandshake = (): void => {
		if (didSendReady) {
			return;
		}

		didSendReady = true;
		target.dispatchEvent(new CustomEvent('__bridge_ready'));
	};

	target.addEventListener('__bridge_handshake', handleHandshake);
	target.dispatchEvent(new CustomEvent('__bridge_handshake_request'));

	return (): void => {
		target.removeEventListener('__bridge_handshake', handleHandshake);
	};
}
