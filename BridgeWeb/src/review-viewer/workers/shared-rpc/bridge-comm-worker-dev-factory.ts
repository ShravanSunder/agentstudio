export function createBridgeCommWorkerModuleWorker(): Worker {
	return new Worker(
		new URL('../../../core/comm-worker/bridge-comm-worker-entry.ts', import.meta.url),
		{ type: 'module' },
	);
}
