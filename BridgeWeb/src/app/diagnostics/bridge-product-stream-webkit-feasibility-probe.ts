import {
	type BridgeProductContentFrame,
	type BridgeProductContentRequest,
	type BridgeProductContentTerminal,
} from '../../core/comm-worker/bridge-product-content-contracts.js';
import { BridgeProductContentStreamValidator } from '../../core/comm-worker/bridge-product-content-frame-codec.js';
import { BridgeProductContentFrameDecoder } from '../../core/comm-worker/bridge-product-content-frame-decoder.js';
import {
	BRIDGE_PRODUCT_CAPABILITY_HEADER_NAME,
	BRIDGE_PRODUCT_MAXIMUM_CONTENT_DATA_PAYLOAD_BYTES,
	BRIDGE_PRODUCT_REQUEST_METHOD,
} from '../../core/comm-worker/bridge-product-contract-primitives.js';

// oxlint-disable unicorn/require-post-message-target-origin -- Worker postMessage has no targetOrigin.

export interface BridgeProductStreamWebKitFeasibilityRequest {
	readonly mode: 'product-stream-s2a';
	readonly endpointBaseUrl: string;
	readonly capability: string;
	readonly maxRequestBodyBytes: number;
	readonly nearCapWarmupRequestCount: number;
	readonly nearCapMeasuredRequestCount: number;
}

export interface BridgeProductStreamWebKitFeasibilityResponse {
	readonly kind: 's2a.completed';
	readonly mode: 'product-stream-s2a';
	readonly succeeded: boolean;
}

interface BridgeProductStreamWorkerResult {
	readonly kind: 's2a.result';
	readonly workerObservedExactFrames: boolean;
	readonly workerObservedIncrementalFrames: boolean;
	readonly cancellationObserved: boolean;
	readonly nearCapTiming: BridgeProductNearCapTimingResult;
}

type BridgeProductNearCapMeasurementPhase = 'measured' | 'warmup';

interface BridgeProductNearCapRequest {
	readonly kind: 's2a.near-cap';
	readonly phase: BridgeProductNearCapMeasurementPhase;
	readonly sampleIndex: number;
	readonly padding: string;
}

interface BridgeProductNearCapTimingResult {
	readonly bodyByteCount: number;
	readonly warmupRequestCount: number;
	readonly measuredRequestCount: number;
	readonly workerEncodeDurationsMicroseconds: readonly number[];
	readonly workerFetchCompletionDurationsMicroseconds: readonly number[];
}

interface BridgeProductWorkerStartedRequest {
	readonly kind: 's2a.worker.started';
}

interface BridgeProductStreamOpenRequest {
	readonly kind: 's2a.stream.open';
}

interface BridgeProductCancelStreamOpenRequest {
	readonly kind: 's2a.cancel-stream.open';
}

interface BridgeProductFrameObservedRequest {
	readonly kind: 's2a.frame.observed';
	readonly stream: 'completed' | 'cancellable';
	readonly sequence: number;
}

type BridgeProductProbeRouteRegistry = {
	readonly '/worker-started': BridgeProductWorkerStartedRequest;
	readonly '/stream': BridgeProductStreamOpenRequest;
	readonly '/cancel-stream': BridgeProductCancelStreamOpenRequest;
	readonly '/near-cap': BridgeProductNearCapRequest;
	readonly '/observed': BridgeProductFrameObservedRequest;
	readonly '/result': BridgeProductStreamWorkerResult;
};

interface ParsedStreamFrame {
	readonly frame: BridgeProductContentFrame;
	readonly terminal: BridgeProductContentTerminal<'file.content'> | null;
}

interface StreamFrameCursor {
	readonly decoder: BridgeProductContentFrameDecoder;
	readonly reader: ReadableStreamDefaultReader<Uint8Array>;
	readonly validator: BridgeProductContentStreamValidator;
}

const feasibilityContentPayloadSHA256 =
	'15601535eca4a38b7e31ad6494861121cb9f84ccf55d4beb6a707d4f7a87813d';
const feasibilityContentRequest = {
	contentKind: 'file.content',
	contentRequestId: 's2a-content-request',
	descriptor: {
		contentKind: 'file.content',
		declaredByteLength: BRIDGE_PRODUCT_MAXIMUM_CONTENT_DATA_PAYLOAD_BYTES,
		descriptorId: 's2a-file-descriptor',
		encoding: 'utf-8',
		expectedSha256: feasibilityContentPayloadSHA256,
		fileId: 's2a-file',
		maximumBytes: BRIDGE_PRODUCT_MAXIMUM_CONTENT_DATA_PAYLOAD_BYTES,
		source: {
			repoId: '00000000-0000-4000-8000-000000000001',
			rootRevisionToken: null,
			sourceCursor: 's2a-source-cursor',
			sourceId: 's2a-source',
			subscriptionGeneration: 1,
			worktreeId: '00000000-0000-4000-8000-000000000002',
		},
		window: {
			kind: 'prefix',
			maximumBytes: BRIDGE_PRODUCT_MAXIMUM_CONTENT_DATA_PAYLOAD_BYTES,
			maximumLines: 10_000,
			startByte: 0,
		},
	},
	kind: 'content.open',
	leaseId: 's2a-content-lease',
	paneSessionId: 's2a-pane-session',
	wireVersion: 2,
	workerDerivationEpoch: 1,
	workerInstanceId: 's2a-worker-instance',
} as const satisfies BridgeProductContentRequest;

export async function runProductStreamWebKitFeasibilityProbe(
	request: BridgeProductStreamWebKitFeasibilityRequest,
): Promise<void> {
	let result: BridgeProductStreamWorkerResult = failedProductStreamResult();
	try {
		validateProductStreamProbeRequest(request);
		const workerStarted = await postProductProbeRequest(request, '/worker-started', {
			kind: 's2a.worker.started',
		});
		const nearCapTiming = await runNearCapTimingProbe(request);
		const hostileStatuses = await runHostileProductRequestProof(request);
		const completedStreamSucceeded = await observeCompletedStream(request);
		const cancellationObserved = await observeCancellableStream(request);
		result = {
			kind: 's2a.result',
			workerObservedExactFrames:
				workerStarted.status === 204 && hostileStatuses && completedStreamSucceeded,
			workerObservedIncrementalFrames: completedStreamSucceeded,
			cancellationObserved,
			nearCapTiming,
		};
	} catch {
		result = failedProductStreamResult();
	}

	const resultAcknowledged = await postProductStreamResult(request, result);
	self.postMessage({
		kind: 's2a.completed',
		mode: 'product-stream-s2a',
		succeeded:
			resultAcknowledged &&
			result.workerObservedExactFrames &&
			result.workerObservedIncrementalFrames &&
			result.cancellationObserved,
	} satisfies BridgeProductStreamWebKitFeasibilityResponse);
}

async function runHostileProductRequestProof(
	request: BridgeProductStreamWebKitFeasibilityRequest,
): Promise<boolean> {
	const streamBody = JSON.stringify({
		kind: 's2a.stream.open',
	} satisfies BridgeProductStreamOpenRequest);
	const missingCapability = await postHostileProductRequest({
		url: `${request.endpointBaseUrl}/missing-capability`,
		body: streamBody,
	});
	const wrongCapability = await postHostileProductRequest({
		url: `${request.endpointBaseUrl}/wrong-capability`,
		capability: `${request.capability}-wrong`,
		body: streamBody,
	});
	const oversizedEncodedBody = encodeNearCapRequest({
		maximumBodyBytes: request.maxRequestBodyBytes + 1,
		phase: 'warmup',
		sampleIndex: 0,
	});
	const oversizedBody = await postHostileProductRequest({
		url: `${request.endpointBaseUrl}/oversized-body`,
		capability: request.capability,
		body: oversizedEncodedBody.body,
	});
	const routeMismatch = await postHostileProductRequest({
		url: `${request.endpointBaseUrl}/route-mismatch`,
		capability: request.capability,
		body: JSON.stringify(failedProductStreamResult()),
	});
	const strictExtraKey = await postHostileProductRequest({
		url: `${request.endpointBaseUrl}/strict-extra`,
		capability: request.capability,
		body: '{"kind":"s2a.stream.open","extra":true}',
	});
	return (
		missingCapability.status === 401 &&
		wrongCapability.status === 403 &&
		oversizedBody.status === 413 &&
		routeMismatch.status === 400 &&
		strictExtraKey.status === 400
	);
}

async function runNearCapTimingProbe(
	request: BridgeProductStreamWebKitFeasibilityRequest,
): Promise<BridgeProductNearCapTimingResult> {
	const encodeDurationsMicroseconds: number[] = [];
	const fetchCompletionDurationsMicroseconds: number[] = [];
	let observedBodyByteCount = 0;
	for (const phase of ['warmup', 'measured'] as const) {
		const requestCount =
			phase === 'warmup' ? request.nearCapWarmupRequestCount : request.nearCapMeasuredRequestCount;
		for (let sampleIndex = 0; sampleIndex < requestCount; sampleIndex += 1) {
			const encodedRequest = encodeNearCapRequest({
				maximumBodyBytes: request.maxRequestBodyBytes,
				phase,
				sampleIndex,
			});
			observedBodyByteCount = encodedRequest.bodyByteCount;
			const fetchStartedAt = performance.now();
			// oxlint-disable-next-line eslint/no-await-in-loop -- Sequential requests form one bounded timing cohort.
			const response = await postEncodedProductProbeRequest(
				request,
				'/near-cap',
				encodedRequest.body,
			);
			const fetchDurationMicroseconds = durationMicroseconds(fetchStartedAt, performance.now());
			if (response.status !== 204) {
				throw new Error('near_cap_request_rejected');
			}
			if (phase === 'measured') {
				encodeDurationsMicroseconds.push(encodedRequest.encodeDurationMicroseconds);
				fetchCompletionDurationsMicroseconds.push(fetchDurationMicroseconds);
			}
		}
	}
	return {
		bodyByteCount: observedBodyByteCount,
		warmupRequestCount: request.nearCapWarmupRequestCount,
		measuredRequestCount: request.nearCapMeasuredRequestCount,
		workerEncodeDurationsMicroseconds: encodeDurationsMicroseconds,
		workerFetchCompletionDurationsMicroseconds: fetchCompletionDurationsMicroseconds,
	};
}

function encodeNearCapRequest(props: {
	readonly maximumBodyBytes: number;
	readonly phase: BridgeProductNearCapMeasurementPhase;
	readonly sampleIndex: number;
}): {
	readonly body: string;
	readonly bodyByteCount: number;
	readonly encodeDurationMicroseconds: number;
} {
	const encodeStartedAt = performance.now();
	const emptyPaddingBody = JSON.stringify({
		kind: 's2a.near-cap',
		phase: props.phase,
		sampleIndex: props.sampleIndex,
		padding: '',
	} satisfies BridgeProductNearCapRequest);
	const encoder = new TextEncoder();
	const paddingByteCount = props.maximumBodyBytes - encoder.encode(emptyPaddingBody).byteLength;
	if (paddingByteCount < 0) {
		throw new Error('near_cap_envelope_exceeds_limit');
	}
	const body = JSON.stringify({
		kind: 's2a.near-cap',
		phase: props.phase,
		sampleIndex: props.sampleIndex,
		padding: 'x'.repeat(paddingByteCount),
	} satisfies BridgeProductNearCapRequest);
	const bodyByteCount = encoder.encode(body).byteLength;
	if (bodyByteCount !== props.maximumBodyBytes) {
		throw new Error('near_cap_body_size_mismatch');
	}
	return {
		body,
		bodyByteCount,
		encodeDurationMicroseconds: durationMicroseconds(encodeStartedAt, performance.now()),
	};
}

function durationMicroseconds(
	startedAtMilliseconds: number,
	completedAtMilliseconds: number,
): number {
	return Math.max(0, Math.round((completedAtMilliseconds - startedAtMilliseconds) * 1_000));
}

async function observeCompletedStream(
	request: BridgeProductStreamWebKitFeasibilityRequest,
): Promise<boolean> {
	const response = await postProductProbeRequest(request, '/stream', { kind: 's2a.stream.open' });
	const cursor = streamFrameCursor(response);
	const expectedFrameKinds = ['content.accepted', 'content.data', 'content.end'] as const;
	for (let sequence = 0; sequence < expectedFrameKinds.length; sequence += 1) {
		// oxlint-disable-next-line eslint/no-await-in-loop -- Each receipt unlocks the next native frame.
		const parsed = await readNextContentFrame(cursor);
		if (parsed.frame.header.kind !== expectedFrameKinds[sequence]) {
			return false;
		}
		if (
			parsed.frame.header.kind === 'content.data' &&
			(parsed.frame.payload.byteLength !== BRIDGE_PRODUCT_MAXIMUM_CONTENT_DATA_PAYLOAD_BYTES ||
				!parsed.frame.payload.every((byte) => byte === 0x78))
		) {
			return false;
		}
		if (sequence < expectedFrameKinds.length - 1 && parsed.terminal !== null) return false;
		if (
			sequence === expectedFrameKinds.length - 1 &&
			(parsed.terminal?.kind !== 'complete' ||
				parsed.terminal.bytes.byteLength !== BRIDGE_PRODUCT_MAXIMUM_CONTENT_DATA_PAYLOAD_BYTES ||
				parsed.terminal.observedSha256 !== feasibilityContentPayloadSHA256)
		) {
			return false;
		}
		// oxlint-disable-next-line eslint/no-await-in-loop -- Receipt order is the proof gate.
		const receipt = await postProductProbeRequest(request, '/observed', {
			kind: 's2a.frame.observed',
			stream: 'completed',
			sequence,
		});
		if (receipt.status !== 204) {
			return false;
		}
	}
	const terminalRead = await cursor.reader.read();
	if (!terminalRead.done) return false;
	cursor.decoder.finish();
	cursor.validator.finish();
	return response.status === 200;
}

async function observeCancellableStream(
	request: BridgeProductStreamWebKitFeasibilityRequest,
): Promise<boolean> {
	const abortController = new AbortController();
	const response = await postProductProbeRequest(
		request,
		'/cancel-stream',
		{ kind: 's2a.cancel-stream.open' },
		abortController.signal,
	);
	const cursor = streamFrameCursor(response);
	const accepted = await readNextContentFrame(cursor);
	if (response.status !== 200 || accepted.frame.header.kind !== 'content.accepted') {
		return false;
	}
	if (accepted.terminal !== null) return false;
	const receipt = await postProductProbeRequest(request, '/observed', {
		kind: 's2a.frame.observed',
		stream: 'cancellable',
		sequence: 0,
	});
	return receipt.status === 204 && (await readerRejectedAfterAbort(cursor.reader, abortController));
}

async function postProductProbeRequest<TRoute extends keyof BridgeProductProbeRouteRegistry>(
	request: BridgeProductStreamWebKitFeasibilityRequest,
	route: TRoute,
	body: BridgeProductProbeRouteRegistry[TRoute],
	signal?: AbortSignal,
): Promise<Response> {
	const requestInit = {
		method: BRIDGE_PRODUCT_REQUEST_METHOD,
		headers: productRequestHeaders(request.capability),
		body: JSON.stringify(body),
	} satisfies RequestInit;
	const encodedBody = requestInit.body;
	if (new TextEncoder().encode(encodedBody).byteLength > request.maxRequestBodyBytes) {
		throw new Error('product_probe_request_exceeds_sender_cap');
	}
	return postEncodedProductProbeRequest(request, route, encodedBody, signal);
}

function postEncodedProductProbeRequest(
	request: BridgeProductStreamWebKitFeasibilityRequest,
	route: keyof BridgeProductProbeRouteRegistry,
	body: string,
	signal?: AbortSignal,
): Promise<Response> {
	if (new TextEncoder().encode(body).byteLength > request.maxRequestBodyBytes) {
		throw new Error('product_probe_request_exceeds_sender_cap');
	}
	const requestInit = {
		method: BRIDGE_PRODUCT_REQUEST_METHOD,
		headers: productRequestHeaders(request.capability),
		body,
	} satisfies RequestInit;
	return fetch(
		`${request.endpointBaseUrl}${route}`,
		signal === undefined ? requestInit : { ...requestInit, signal },
	);
}

async function postHostileProductRequest(props: {
	readonly url: string;
	readonly capability?: string;
	readonly body: string;
}): Promise<Response> {
	const headers = new Headers({ 'Content-Type': 'application/json' });
	if (props.capability !== undefined) {
		headers.set(BRIDGE_PRODUCT_CAPABILITY_HEADER_NAME, props.capability);
	}
	const requestInit = {
		method: BRIDGE_PRODUCT_REQUEST_METHOD,
		headers,
		body: props.body,
	} satisfies RequestInit;
	return fetch(props.url, requestInit);
}

function productRequestHeaders(capability: string): Headers {
	const headers = new Headers({ 'Content-Type': 'application/json' });
	headers.set(BRIDGE_PRODUCT_CAPABILITY_HEADER_NAME, capability);
	return headers;
}

function streamFrameCursor(response: Response): StreamFrameCursor {
	if (response.body === null) {
		throw new Error('missing_stream_body');
	}
	return {
		decoder: new BridgeProductContentFrameDecoder(),
		reader: response.body.getReader(),
		validator: new BridgeProductContentStreamValidator(feasibilityContentRequest),
	};
}

async function readNextContentFrame(cursor: StreamFrameCursor): Promise<ParsedStreamFrame> {
	while (true) {
		// oxlint-disable-next-line eslint/no-await-in-loop -- A frame can span multiple transport chunks.
		const next = await cursor.reader.read();
		if (next.done) {
			throw new Error('stream_ended_before_frame');
		}
		const frames = cursor.decoder.push(next.value);
		if (frames.length > 1) throw new Error('frame_gate_bypassed');
		const frame = frames[0];
		if (frame !== undefined) {
			// oxlint-disable-next-line eslint/no-await-in-loop -- Stream validation is sequence-ordered.
			return { frame, terminal: await cursor.validator.accept(frame) };
		}
	}
}

async function readerRejectedAfterAbort(
	reader: ReadableStreamDefaultReader<Uint8Array>,
	abortController: AbortController,
): Promise<boolean> {
	let settledBeforeAbort = false;
	const pendingRead = reader.read();
	void pendingRead.then(
		() => {
			settledBeforeAbort = true;
		},
		() => {
			settledBeforeAbort = true;
		},
	);
	await Promise.resolve();
	if (settledBeforeAbort) {
		return false;
	}
	abortController.abort();
	try {
		await pendingRead;
		return false;
	} catch {
		return true;
	}
}

async function postProductStreamResult(
	request: BridgeProductStreamWebKitFeasibilityRequest,
	result: BridgeProductStreamWorkerResult,
): Promise<boolean> {
	try {
		const response = await postProductProbeRequest(request, '/result', result);
		return response.status === 200;
	} catch {
		return false;
	}
}

function failedProductStreamResult(): BridgeProductStreamWorkerResult {
	return {
		kind: 's2a.result',
		workerObservedExactFrames: false,
		workerObservedIncrementalFrames: false,
		cancellationObserved: false,
		nearCapTiming: {
			bodyByteCount: 0,
			warmupRequestCount: 0,
			measuredRequestCount: 0,
			workerEncodeDurationsMicroseconds: [],
			workerFetchCompletionDurationsMicroseconds: [],
		},
	};
}

function validateProductStreamProbeRequest(
	request: BridgeProductStreamWebKitFeasibilityRequest,
): void {
	for (const value of [
		request.maxRequestBodyBytes,
		request.nearCapWarmupRequestCount,
		request.nearCapMeasuredRequestCount,
	]) {
		if (!Number.isSafeInteger(value) || value < 0) {
			throw new Error('invalid_product_stream_probe_limit');
		}
	}
	if (request.nearCapWarmupRequestCount > 1 || request.nearCapMeasuredRequestCount > 100) {
		throw new Error('product_stream_probe_sample_count_exceeds_bound');
	}
}
