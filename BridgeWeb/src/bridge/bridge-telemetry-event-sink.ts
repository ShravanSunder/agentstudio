import type { BridgeTelemetryBatch } from '../foundation/telemetry/bridge-telemetry-event.js';
import type { BridgeTelemetrySink } from '../foundation/telemetry/bridge-telemetry-sink.js';

export interface CreateBridgeTelemetryEventSinkProps {
	readonly endpointUrl?: string;
	readonly fetch?: (input: RequestInfo | URL, init?: RequestInit) => boolean | Promise<Response>;
}

export function createBridgeTelemetryEventSink(
	props: CreateBridgeTelemetryEventSinkProps,
): BridgeTelemetrySink {
	const endpointUrl = props.endpointUrl ?? 'agentstudio://telemetry/batch';
	const fetchTelemetry = props.fetch ?? globalThis.fetch.bind(globalThis);
	const pendingPostBodies: string[] = [];
	let isPostInFlight = false;
	const startNextPost = (): void => {
		if (isPostInFlight) {
			return;
		}
		const body = pendingPostBodies.shift();
		if (body === undefined) {
			return;
		}
		isPostInFlight = true;
		let postResult: boolean | Promise<Response>;
		try {
			postResult = fetchTelemetry(endpointUrl, {
				body,
				headers: { 'Content-Type': 'application/json' },
				method: 'POST',
			});
		} catch (error) {
			isPostInFlight = false;
			throw error;
		}
		void Promise.resolve(postResult)
			.catch(() => undefined)
			.finally((): void => {
				isPostInFlight = false;
				startNextPost();
			});
	};
	const enqueuePost = (body: string): void => {
		pendingPostBodies.push(body);
		startNextPost();
	};
	return {
		flush: (batch: BridgeTelemetryBatch): boolean => {
			try {
				enqueuePost(JSON.stringify(batch));
				return true;
			} catch {
				return false;
			}
		},
	};
}
