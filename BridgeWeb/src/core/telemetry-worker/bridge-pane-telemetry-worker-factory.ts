import type { BridgeTelemetryWorkerLike } from './bridge-pane-telemetry-worker-session.js';

export interface CreateBridgePaneTelemetryWorkerFactoryProps {
	readonly createObjectURL?: (blob: Blob) => string;
	readonly fetch?: typeof globalThis.fetch;
	readonly revokeObjectURL?: (url: string) => void;
	readonly workerScriptUrl?: string;
}

export function createBridgePaneTelemetryWorkerFactory(
	props: CreateBridgePaneTelemetryWorkerFactoryProps = {},
): () => Promise<BridgeTelemetryWorkerLike> {
	const createObjectURL = props.createObjectURL ?? URL.createObjectURL.bind(URL);
	const fetchWorker = props.fetch ?? globalThis.fetch.bind(globalThis);
	const revokeObjectURL = props.revokeObjectURL ?? URL.revokeObjectURL.bind(URL);
	const isHTTPRuntime =
		globalThis.location?.protocol === 'http:' || globalThis.location?.protocol === 'https:';
	const workerScriptUrl =
		props.workerScriptUrl ?? 'agentstudio://app/assets/bridge-telemetry-worker.js';
	let workerScriptBlobUrl: string | null = null;

	return async (): Promise<BridgeTelemetryWorkerLike> => {
		if (isHTTPRuntime && props.workerScriptUrl === undefined) {
			return new Worker(new URL('./bridge-telemetry-worker-entry.ts', import.meta.url), {
				type: 'module',
			});
		}
		if (workerScriptBlobUrl === null) {
			const response = await fetchWorker(workerScriptUrl);
			if (!response.ok) {
				throw new Error(`Failed to load bridge telemetry worker: ${response.status}`);
			}
			const workerSource = await response.text();
			workerScriptBlobUrl = createObjectURL(
				new Blob([workerSource], { type: 'application/javascript' }),
			);
		}
		const worker = new Worker(workerScriptBlobUrl, { type: 'module' });
		worker.addEventListener(
			'error',
			(): void => {
				if (workerScriptBlobUrl !== null) {
					revokeObjectURL(workerScriptBlobUrl);
					workerScriptBlobUrl = null;
				}
			},
			{ once: true },
		);
		return worker;
	};
}
