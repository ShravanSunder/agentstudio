import {
	bridgeTelemetryWorkerBatchResponseSchema,
	type BridgeTelemetryWorkerBatchTransport,
} from './bridge-telemetry-worker-contracts.js';

export interface CreateBridgeTelemetryWorkerFetchTransportProps {
	readonly endpointUrl: string;
	readonly fetch?: typeof globalThis.fetch;
}

export type BridgeTelemetryWorkerTransportFailureDetails =
	| { readonly stage: 'fetch'; readonly httpStatus: null }
	| { readonly stage: 'http_status'; readonly httpStatus: number }
	| { readonly stage: 'response_body'; readonly httpStatus: number }
	| { readonly stage: 'response_schema'; readonly httpStatus: number };

export type BridgeTelemetryWorkerTransportFailureStage =
	BridgeTelemetryWorkerTransportFailureDetails['stage'];

export class BridgeTelemetryWorkerTransportError extends Error {
	readonly details: BridgeTelemetryWorkerTransportFailureDetails;

	constructor(details: BridgeTelemetryWorkerTransportFailureDetails) {
		super(`Bridge telemetry transport failed at ${details.stage}.`);
		this.name = 'BridgeTelemetryWorkerTransportError';
		this.details = details;
	}
}

export function createBridgeTelemetryWorkerFetchTransport(
	props: CreateBridgeTelemetryWorkerFetchTransportProps,
): BridgeTelemetryWorkerBatchTransport {
	const fetchTelemetry = props.fetch ?? globalThis.fetch.bind(globalThis);
	return {
		postBatch: async (_request, encodedBody, telemetryCapability) => {
			const requestBody = new ArrayBuffer(encodedBody.byteLength);
			new Uint8Array(requestBody).set(encodedBody);
			let response: Response;
			try {
				response = await fetchTelemetry(props.endpointUrl, {
					method: 'POST',
					headers: {
						'Content-Type': 'application/json',
						'X-AgentStudio-Bridge-Telemetry-Capability': telemetryCapability,
					},
					body: requestBody,
				});
			} catch {
				throw new BridgeTelemetryWorkerTransportError({ stage: 'fetch', httpStatus: null });
			}
			if (!response.ok) {
				throw new BridgeTelemetryWorkerTransportError({
					stage: 'http_status',
					httpStatus: response.status,
				});
			}
			let responseBody: unknown;
			try {
				responseBody = await response.json();
			} catch {
				throw new BridgeTelemetryWorkerTransportError({
					stage: 'response_body',
					httpStatus: response.status,
				});
			}
			const decodedResponse = bridgeTelemetryWorkerBatchResponseSchema.safeParse(responseBody);
			if (!decodedResponse.success) {
				throw new BridgeTelemetryWorkerTransportError({
					stage: 'response_schema',
					httpStatus: response.status,
				});
			}
			return decodedResponse.data;
		},
	};
}
