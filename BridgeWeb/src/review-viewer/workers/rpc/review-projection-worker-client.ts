import type {
	BridgeReviewProjectionInput,
	BridgeReviewProjectionRequest,
	BridgeReviewProjectionRequestIdentity,
	BridgeReviewProjectionWorkloadId,
} from '../../models/review-projection-models.js';
import {
	bridgeReviewProjectionWorkerRequestSchema,
	bridgeReviewProjectionWorkerResponseSchema,
	fingerprintBridgeReviewProjectionRequest,
	identitiesMatch,
	type BridgeReviewProjectionWorkerRequest,
	type BridgeReviewProjectionWorkerResponse,
	type BridgeReviewProjectionWorkerSuccessResponse,
} from './review-projection-worker-rpc.js';

export interface BridgeReviewProjectionWorkerTransport {
	readonly send: (request: BridgeReviewProjectionWorkerRequest) => Promise<unknown>;
	readonly abort?: (abortKey: string) => void;
}

export interface CreateBridgeReviewProjectionWorkerClientProps {
	readonly transport: BridgeReviewProjectionWorkerTransport;
	readonly createRequestId?: () => string;
}

export interface StartBridgeReviewProjectionWorkerTaskProps {
	readonly projectionInput: BridgeReviewProjectionInput;
	readonly projectionRequest: BridgeReviewProjectionRequest;
	readonly visibleItemIds: readonly string[];
	readonly workloadId: BridgeReviewProjectionWorkloadId;
	readonly abortKey?: string;
}

export type BridgeReviewProjectionWorkerClientCompletion =
	| {
			readonly status: 'success';
			readonly identity: BridgeReviewProjectionRequestIdentity;
			readonly response: BridgeReviewProjectionWorkerSuccessResponse;
	  }
	| {
			readonly status: 'failure';
			readonly identity: BridgeReviewProjectionRequestIdentity;
			readonly response: Exclude<BridgeReviewProjectionWorkerResponse, { readonly ok: true }>;
	  }
	| {
			readonly status: 'stale';
			readonly reason: 'superseded' | 'identityMismatch' | 'invalidResponse';
			readonly identity: BridgeReviewProjectionRequestIdentity;
	  };

export interface BridgeReviewProjectionWorkerTask {
	readonly identity: BridgeReviewProjectionRequestIdentity;
	readonly request: BridgeReviewProjectionWorkerRequest;
	readonly completed: Promise<BridgeReviewProjectionWorkerClientCompletion>;
}

export interface BridgeReviewProjectionWorkerClient {
	readonly startProjection: (
		props: StartBridgeReviewProjectionWorkerTaskProps,
	) => BridgeReviewProjectionWorkerTask;
}

export function createBridgeReviewProjectionWorkerClient(
	props: CreateBridgeReviewProjectionWorkerClientProps,
): BridgeReviewProjectionWorkerClient {
	const activeIdentityByAbortKey = new Map<string, BridgeReviewProjectionRequestIdentity>();
	const createRequestId = props.createRequestId ?? defaultRequestIdFactory;

	const startProjection = (
		taskProps: StartBridgeReviewProjectionWorkerTaskProps,
	): BridgeReviewProjectionWorkerTask => {
		const identity: BridgeReviewProjectionRequestIdentity = {
			requestId: createRequestId(),
			packageId: taskProps.projectionInput.packageId,
			reviewGeneration: taskProps.projectionInput.reviewGeneration,
			revision: taskProps.projectionInput.revision,
			projectionRequestFingerprint: fingerprintBridgeReviewProjectionRequest(
				taskProps.projectionRequest,
			),
			...(taskProps.abortKey === undefined ? {} : { abortKey: taskProps.abortKey }),
		};
		const request = bridgeReviewProjectionWorkerRequestSchema.parse({
			schemaVersion: 1,
			method: 'reviewProjection.build',
			...identity,
			projectionRequest: taskProps.projectionRequest,
			projectionInput: taskProps.projectionInput,
			visibleItemIds: taskProps.visibleItemIds,
			workloadId: taskProps.workloadId,
		});

		if (taskProps.abortKey !== undefined) {
			if (activeIdentityByAbortKey.has(taskProps.abortKey)) {
				props.transport.abort?.(taskProps.abortKey);
			}
			activeIdentityByAbortKey.set(taskProps.abortKey, identity);
		}

		const completed = props.transport.send(request).then(
			(responseValue: unknown): BridgeReviewProjectionWorkerClientCompletion =>
				completeWorkerRequest({
					activeIdentityByAbortKey,
					identity,
					responseValue,
				}),
		);

		return {
			identity,
			request,
			completed,
		};
	};

	return { startProjection };
}

interface CompleteWorkerRequestProps {
	readonly activeIdentityByAbortKey: Map<string, BridgeReviewProjectionRequestIdentity>;
	readonly identity: BridgeReviewProjectionRequestIdentity;
	readonly responseValue: unknown;
}

function completeWorkerRequest(
	props: CompleteWorkerRequestProps,
): BridgeReviewProjectionWorkerClientCompletion {
	const activeIdentity = readActiveIdentity(props.activeIdentityByAbortKey, props.identity);
	if (props.identity.abortKey !== undefined && !identitiesMatch(activeIdentity, props.identity)) {
		return {
			status: 'stale',
			reason: 'superseded',
			identity: props.identity,
		};
	}

	const parsedResponse = bridgeReviewProjectionWorkerResponseSchema.safeParse(props.responseValue);
	if (!parsedResponse.success) {
		clearActiveIdentity(props.activeIdentityByAbortKey, props.identity);
		return {
			status: 'stale',
			reason: 'invalidResponse',
			identity: props.identity,
		};
	}

	if (!identitiesMatch(parsedResponse.data, props.identity)) {
		clearActiveIdentity(props.activeIdentityByAbortKey, props.identity);
		return {
			status: 'stale',
			reason: 'identityMismatch',
			identity: props.identity,
		};
	}

	clearActiveIdentity(props.activeIdentityByAbortKey, props.identity);

	if (!parsedResponse.data.ok) {
		return {
			status: 'failure',
			identity: props.identity,
			response: parsedResponse.data,
		};
	}

	return {
		status: 'success',
		identity: props.identity,
		response: parsedResponse.data,
	};
}

function readActiveIdentity(
	activeIdentityByAbortKey: Map<string, BridgeReviewProjectionRequestIdentity>,
	identity: BridgeReviewProjectionRequestIdentity,
): BridgeReviewProjectionRequestIdentity | null {
	return identity.abortKey === undefined
		? identity
		: (activeIdentityByAbortKey.get(identity.abortKey) ?? null);
}

function clearActiveIdentity(
	activeIdentityByAbortKey: Map<string, BridgeReviewProjectionRequestIdentity>,
	identity: BridgeReviewProjectionRequestIdentity,
): void {
	if (identity.abortKey === undefined) {
		return;
	}
	if (identitiesMatch(activeIdentityByAbortKey.get(identity.abortKey) ?? null, identity)) {
		activeIdentityByAbortKey.delete(identity.abortKey);
	}
}

function defaultRequestIdFactory(): string {
	return `projection_${crypto.randomUUID()}`;
}
