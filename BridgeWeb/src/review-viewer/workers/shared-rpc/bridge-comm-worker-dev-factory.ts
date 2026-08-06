export function createBridgeCommWorkerModuleWorker(): Worker {
	return new Worker(
		new URL('../../../core/comm-worker/bridge-comm-worker-vite-entry.ts', import.meta.url),
		{ type: 'module' },
	);
}
