import type {
	BridgeProductContentFrameFor,
	BridgeProductContentKind,
	BridgeProductContentRequestFor,
	BridgeProductContentTerminal,
} from './bridge-product-content-contracts.js';
import { awaitBridgeProductContentProgress } from './bridge-product-content-progress-deadline.js';
import {
	BridgeProductContentResponseAdmission,
	type BridgeProductContentResponseAdmissionLease,
} from './bridge-product-content-response-admission.js';
import { BridgeProductContentStreamDecoder } from './bridge-product-content-stream-decoder.js';
import type { BridgeProductContentStreamOpening } from './bridge-product-content-stream-opening.js';
import type { BridgeProductDeadlineClock } from './bridge-product-deadline-clock.js';
import { BridgeProductReadAhead } from './bridge-product-read-ahead.js';
import { encodeBridgeProductRequestBody } from './bridge-product-request-body.js';
import type { BridgeProductRequestExecutor } from './bridge-product-request-executor.js';
import type { BridgeProductSessionAuthority } from './bridge-product-session-authority.js';

export async function readBridgeProductContentResponse<
	TContentKind extends BridgeProductContentKind,
>(props: {
	readonly acknowledgeFrame: (
		request: BridgeProductContentRequestFor<TContentKind>,
		frame: BridgeProductContentFrameFor<TContentKind>,
	) => Promise<void>;
	readonly authority: BridgeProductSessionAuthority;
	readonly clock: BridgeProductDeadlineClock;
	readonly executeProductRequest: BridgeProductRequestExecutor;
	readonly opening: BridgeProductContentStreamOpening<TContentKind>;
	readonly responseAdmission: BridgeProductContentResponseAdmission;
}): Promise<void> {
	const opening = props.opening;
	let reader: ReadableStreamDefaultReader<Uint8Array> | null = null;
	let responseAdmissionLease: BridgeProductContentResponseAdmissionLease | null = null;
	const readAbortController = new AbortController();
	const abortResponse = (): void => {
		readAbortController.abort(opening.abortSignal.reason);
		void reader?.cancel(opening.abortSignal.reason).catch((): void => {});
		responseAdmissionLease?.release();
	};
	opening.abortSignal.addEventListener('abort', abortResponse, { once: true });
	try {
		opening.abortSignal.throwIfAborted();
		await props.authority.open;
		opening.abortSignal.throwIfAborted();
		responseAdmissionLease = await opening.responseStartAdmission.acquire(
			props.responseAdmission,
			opening.abortSignal,
		);
		opening.abortSignal.throwIfAborted();
		const response = await awaitBridgeProductContentProgress({
			abortRead: (): void => readAbortController.abort(),
			clock: props.clock,
			delayMilliseconds: props.authority.bootstrap.policy.contentProgressDeadlineMilliseconds,
			pending: () =>
				props.executeProductRequest('content', {
					body: encodeBridgeProductRequestBody(opening.request),
					headers: {
						'Content-Type': 'application/json',
						'X-AgentStudio-Bridge-Product-Capability': props.authority.capabilityHeader,
					},
					method: 'POST',
					signal: readAbortController.signal,
				}),
		});
		opening.abortSignal.throwIfAborted();
		if (!response.ok || response.body === null) {
			throw new Error(`Bridge product content stream failed with status ${response.status}.`);
		}
		const responseReader = response.body.getReader();
		const readAhead = new BridgeProductReadAhead(responseReader);
		reader = responseReader;
		const decoder = new BridgeProductContentStreamDecoder(opening.request);
		let terminalResult: BridgeProductContentTerminal<TContentKind> | null = null;
		while (true) {
			// eslint-disable-next-line no-await-in-loop -- Stream chunks are ordered.
			const chunk = await awaitBridgeProductContentProgress({
				abortRead: (): void => {
					readAbortController.abort();
					void reader?.cancel().catch((): void => {});
				},
				clock: props.clock,
				delayMilliseconds: props.authority.bootstrap.policy.contentProgressDeadlineMilliseconds,
				pending: () => readAhead.next(),
			});
			if (chunk.done) break;
			// eslint-disable-next-line no-await-in-loop -- Decoder digest validation is ordered.
			const decoded = await decoder.push(chunk.value);
			for (const frame of decoded.frames) {
				opening.frames.push(frame);
				// eslint-disable-next-line no-await-in-loop -- Each decoded frame is observed before the response advances.
				await props.acknowledgeFrame(opening.request, frame);
			}
			terminalResult = decoded.terminal ?? terminalResult;
		}
		decoder.finish();
		if (terminalResult === null) {
			throw new Error('Bridge product content stream ended without a terminal result.');
		}
		opening.frames.close(true);
		opening.terminal.resolve(terminalResult);
	} catch (error) {
		if (reader !== null) await reader.cancel(error).catch((): void => {});
		opening.frames.fail(error, true);
		opening.terminal.reject(error);
	} finally {
		opening.abortSignal.removeEventListener('abort', abortResponse);
		reader?.releaseLock();
		responseAdmissionLease?.release();
	}
}
