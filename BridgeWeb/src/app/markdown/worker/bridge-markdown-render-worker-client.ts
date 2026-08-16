import {
	bridgeMarkdownRenderWorkerRequestSchema,
	bridgeMarkdownRenderWorkerResponseSchema,
	markdownRenderIdentitiesMatch,
	type BridgeMarkdownRenderWorkerAbortRequest,
	type BridgeMarkdownRenderWorkerFailureResponse,
	type BridgeMarkdownRenderRequestIdentity,
	type BridgeMarkdownSourceIdentity,
	type BridgeMarkdownRenderWorkerRequest,
	type BridgeMarkdownRenderWorkerResponse,
	type BridgeMarkdownRenderWorkerSuccessResponse,
} from './bridge-markdown-render-worker-rpc.js';

export interface BridgeMarkdownRenderWorkerTransport {
	readonly send: (request: BridgeMarkdownRenderWorkerRequest) => Promise<unknown>;
	readonly abort?: (request: BridgeMarkdownRenderWorkerAbortRequest) => void;
	readonly dispose?: () => void;
}

export interface CreateBridgeMarkdownRenderWorkerClientProps {
	readonly transport: BridgeMarkdownRenderWorkerTransport;
	readonly createRequestId?: () => string;
}

export interface StartBridgeMarkdownRenderWorkerTaskProps {
	readonly sourceIdentity: BridgeMarkdownSourceIdentity;
	readonly contentCacheKey: string;
	readonly contentHash: string;
	readonly markdownText: string;
	readonly sourcePath: string;
	readonly abortKey?: string;
}

export type BridgeMarkdownRenderWorkerClientCompletion =
	| {
			readonly status: 'success';
			readonly identity: BridgeMarkdownRenderRequestIdentity;
			readonly response: BridgeMarkdownRenderWorkerSuccessResponse;
	  }
	| {
			readonly status: 'failure';
			readonly identity: BridgeMarkdownRenderRequestIdentity;
			readonly response: Exclude<BridgeMarkdownRenderWorkerResponse, { readonly ok: true }>;
	  }
	| {
			readonly status: 'stale';
			readonly reason: 'superseded' | 'identityMismatch' | 'invalidResponse' | 'disposed';
			readonly identity: BridgeMarkdownRenderRequestIdentity;
	  };

export interface BridgeMarkdownRenderWorkerTask {
	readonly identity: BridgeMarkdownRenderRequestIdentity;
	readonly request: BridgeMarkdownRenderWorkerRequest;
	readonly completed: Promise<BridgeMarkdownRenderWorkerClientCompletion>;
}

export interface BridgeMarkdownRenderWorkerClient {
	readonly startRender: (
		props: StartBridgeMarkdownRenderWorkerTaskProps,
	) => BridgeMarkdownRenderWorkerTask;
	readonly abort: (abortKey: string) => void;
	readonly dispose: () => void;
}

export function createBridgeMarkdownRenderWorkerClient(
	props: CreateBridgeMarkdownRenderWorkerClientProps,
): BridgeMarkdownRenderWorkerClient {
	const activeIdentityByAbortKey = new Map<string, BridgeMarkdownRenderRequestIdentity>();
	const createRequestId = props.createRequestId ?? defaultRequestIdFactory;
	let isDisposed = false;

	const startRender = (
		taskProps: StartBridgeMarkdownRenderWorkerTaskProps,
	): BridgeMarkdownRenderWorkerTask => {
		const identity: BridgeMarkdownRenderRequestIdentity = {
			requestId: createRequestId(),
			sourceIdentity: taskProps.sourceIdentity,
			contentCacheKey: taskProps.contentCacheKey,
			contentHash: taskProps.contentHash,
			...(taskProps.abortKey === undefined ? {} : { abortKey: taskProps.abortKey }),
		};
		const request = bridgeMarkdownRenderWorkerRequestSchema.parse({
			schemaVersion: 1,
			method: 'markdown.render',
			...identity,
			markdownText: taskProps.markdownText,
			sourcePath: taskProps.sourcePath,
		});

		if (taskProps.abortKey !== undefined) {
			const activeIdentity = activeIdentityByAbortKey.get(taskProps.abortKey);
			if (activeIdentity !== undefined) {
				props.transport.abort?.(abortRequestForIdentity(activeIdentity));
			}
			activeIdentityByAbortKey.set(taskProps.abortKey, identity);
		}

		const completed = props.transport.send(request).then(
			(responseValue: unknown): BridgeMarkdownRenderWorkerClientCompletion =>
				isDisposed
					? disposedCompletion(identity)
					: completeMarkdownRenderRequest({
							activeIdentityByAbortKey,
							identity,
							responseValue,
						}),
			(error: unknown): BridgeMarkdownRenderWorkerClientCompletion =>
				isDisposed
					? disposedCompletion(identity)
					: completeMarkdownRenderTransportFailure({
							activeIdentityByAbortKey,
							identity,
							error,
						}),
		);

		return {
			identity,
			request,
			completed,
		};
	};

	const abort = (abortKey: string): void => {
		if (!activeIdentityByAbortKey.has(abortKey)) {
			return;
		}
		props.transport.abort?.(abortRequestForIdentity(activeIdentityByAbortKey.get(abortKey)));
		activeIdentityByAbortKey.delete(abortKey);
	};

	const dispose = (): void => {
		if (isDisposed) {
			return;
		}
		isDisposed = true;
		for (const abortKey of activeIdentityByAbortKey.keys()) {
			abort(abortKey);
		}
		props.transport.dispose?.();
	};

	return { startRender, abort, dispose };
}

function disposedCompletion(
	identity: BridgeMarkdownRenderRequestIdentity,
): BridgeMarkdownRenderWorkerClientCompletion {
	return { status: 'stale', reason: 'disposed', identity };
}

function abortRequestForIdentity(
	identity: BridgeMarkdownRenderRequestIdentity | undefined,
): BridgeMarkdownRenderWorkerAbortRequest {
	if (identity === undefined || identity.abortKey === undefined) {
		throw new Error('Cannot abort markdown render without active identity');
	}
	return {
		schemaVersion: 1,
		method: 'markdown.render.abort',
		...identity,
		abortKey: identity.abortKey,
	};
}

interface CompleteMarkdownRenderRequestProps {
	readonly activeIdentityByAbortKey: Map<string, BridgeMarkdownRenderRequestIdentity>;
	readonly identity: BridgeMarkdownRenderRequestIdentity;
	readonly responseValue: unknown;
}

function completeMarkdownRenderRequest(
	props: CompleteMarkdownRenderRequestProps,
): BridgeMarkdownRenderWorkerClientCompletion {
	const activeIdentity = readActiveIdentity(props.activeIdentityByAbortKey, props.identity);
	if (
		props.identity.abortKey !== undefined &&
		!markdownRenderIdentitiesMatch(activeIdentity, props.identity)
	) {
		return {
			status: 'stale',
			reason: 'superseded',
			identity: props.identity,
		};
	}

	const parsedResponse = bridgeMarkdownRenderWorkerResponseSchema.safeParse(props.responseValue);
	if (!parsedResponse.success) {
		clearActiveIdentity(props.activeIdentityByAbortKey, props.identity);
		return {
			status: 'stale',
			reason: 'invalidResponse',
			identity: props.identity,
		};
	}

	if (!markdownRenderIdentitiesMatch(parsedResponse.data, props.identity)) {
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

interface CompleteMarkdownRenderTransportFailureProps {
	readonly activeIdentityByAbortKey: Map<string, BridgeMarkdownRenderRequestIdentity>;
	readonly identity: BridgeMarkdownRenderRequestIdentity;
	readonly error: unknown;
}

function completeMarkdownRenderTransportFailure(
	props: CompleteMarkdownRenderTransportFailureProps,
): BridgeMarkdownRenderWorkerClientCompletion {
	const activeIdentity = readActiveIdentity(props.activeIdentityByAbortKey, props.identity);
	if (
		props.identity.abortKey !== undefined &&
		!markdownRenderIdentitiesMatch(activeIdentity, props.identity)
	) {
		return {
			status: 'stale',
			reason: 'superseded',
			identity: props.identity,
		};
	}
	clearActiveIdentity(props.activeIdentityByAbortKey, props.identity);
	return {
		status: 'failure',
		identity: props.identity,
		response: {
			schemaVersion: 1,
			method: 'markdown.render',
			ok: false,
			...props.identity,
			error: {
				code: 'transportFailed',
				message:
					props.error instanceof Error ? props.error.message : 'Markdown worker transport failed',
			},
		} satisfies BridgeMarkdownRenderWorkerFailureResponse,
	};
}

function readActiveIdentity(
	activeIdentityByAbortKey: Map<string, BridgeMarkdownRenderRequestIdentity>,
	identity: BridgeMarkdownRenderRequestIdentity,
): BridgeMarkdownRenderRequestIdentity | null {
	return identity.abortKey === undefined
		? identity
		: (activeIdentityByAbortKey.get(identity.abortKey) ?? null);
}

function clearActiveIdentity(
	activeIdentityByAbortKey: Map<string, BridgeMarkdownRenderRequestIdentity>,
	identity: BridgeMarkdownRenderRequestIdentity,
): void {
	if (identity.abortKey === undefined) {
		return;
	}
	if (
		markdownRenderIdentitiesMatch(activeIdentityByAbortKey.get(identity.abortKey) ?? null, identity)
	) {
		activeIdentityByAbortKey.delete(identity.abortKey);
	}
}

function defaultRequestIdFactory(): string {
	return `markdown_${crypto.randomUUID()}`;
}
