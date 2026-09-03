export function scheduleBridgeCommWorkerTaskBoundary(operation: () => void): Promise<void> {
	return new Promise((resolve): void => {
		const channel = new MessageChannel();
		channel.port1.addEventListener(
			'message',
			(): void => {
				channel.port1.close();
				channel.port2.close();
				operation();
				resolve();
			},
			{ once: true },
		);
		channel.port1.start();
		channel.port2.postMessage(null);
	});
}
