import { afterEach, describe, expect, test, vi } from 'vitest';

import { BRIDGE_PRODUCT_MAXIMUM_CONCURRENT_CONTENT_RESPONSES } from './bridge-product-content-response-admission.js';
import {
	createContentTransportHarness,
	fileContentDescriptor,
	metadataAccepted,
	waitForCondition,
} from './test-fixtures/bridge-product-transport-content.test-support.js';

afterEach(() => {
	vi.unstubAllGlobals();
});

describe('Bridge product content transport', () => {
	test('opens concurrent content outside the control sequence', async () => {
		const harness = createContentTransportHarness(3);
		const first = harness.transport.openContent(
			fileContentDescriptor('descriptor-1'),
			new AbortController().signal,
		);
		const second = harness.transport.openContent(
			fileContentDescriptor('descriptor-2'),
			new AbortController().signal,
		);

		const terminals = await Promise.all([first.terminal, second.terminal]);
		await harness.transport.call('review.markFileViewed', { itemId: 'review-item-1' });

		expect(terminals.map((terminal) => terminal.kind)).toEqual(['complete', 'complete']);
		expect(harness.server.contentRequestHeaders).toEqual([
			{ capability: 'private-capability', contentType: 'application/json' },
			{ capability: 'private-capability', contentType: 'application/json' },
		]);
		expect(harness.server.contentRequests.map((request) => request.workerDerivationEpoch)).toEqual([
			3, 3,
		]);
		expect(harness.server.controlRequests).toHaveLength(1);
		expect(harness.server.controlRequests[0]?.requestSequence).toBe(2);
	});

	test('acknowledges every committed frame with its exact response identity', async () => {
		const harness = createContentTransportHarness(3);
		const content = harness.transport.openContent(
			fileContentDescriptor('descriptor-observed'),
			new AbortController().signal,
		);

		await expect(content.terminal).resolves.toMatchObject({ kind: 'complete' });

		const request = harness.server.contentRequests[0];
		if (request === undefined) throw new Error('Expected one product content request.');
		expect(harness.server.frameAcknowledgements).toEqual(
			[0, 1, 2].map((contentSequence) => ({
				contentRequestId: request.contentRequestId,
				contentSequence,
				kind: 'stream.frameObserved',
				leaseId: request.leaseId,
				paneSessionId: request.paneSessionId,
				streamKind: 'content',
				wireVersion: request.wireVersion,
				workerInstanceId: request.workerInstanceId,
			})),
		);
		expect(harness.server.requestRoutes).toEqual([
			'agentstudio://rpc/content',
			'agentstudio://rpc/command',
			'agentstudio://rpc/command',
			'agentstudio://rpc/command',
		]);
	});

	test('fails only the response whose observation is rejected', async () => {
		const harness = createContentTransportHarness();
		harness.server.leaveContentOpenAfterAcceptance = true;
		harness.server.nextAcknowledgementStatus = 409;
		const content = harness.transport.openContent(
			fileContentDescriptor('descriptor-rejected-observation'),
			new AbortController().signal,
		);
		const frameIterator = content.frames[Symbol.asyncIterator]();
		const terminalFailure = expect(content.terminal).rejects.toMatchObject({
			failureCode: 'rejected_status',
			name: 'BridgeProductFrameAcknowledgementFailure',
			status: 409,
		});

		await expect(frameIterator.next()).resolves.toMatchObject({
			done: false,
			value: { header: { contentSequence: 0, kind: 'content.accepted' } },
		});
		await terminalFailure;
		await expect(frameIterator.next()).rejects.toMatchObject({ status: 409 });
		expect(harness.server.contentReaderCancelCount).toBe(1);
		expect(harness.server.frameAcknowledgements).toHaveLength(1);
	});

	test('paces content independently from other content, metadata, and control', async () => {
		const harness = createContentTransportHarness();
		harness.server.holdContentAcknowledgement('content-request-1');
		const first = harness.transport.openContent(
			fileContentDescriptor('descriptor-held-observation'),
			new AbortController().signal,
		);
		let didFirstSettle = false;
		void first.terminal.then(
			(): void => {
				didFirstSettle = true;
			},
			(): void => {},
		);
		await harness.server.waitForFrameAcknowledgementCount(1);

		const second = harness.transport.openContent(
			fileContentDescriptor('descriptor-independent-observation'),
			new AbortController().signal,
		);
		await expect(second.terminal).resolves.toMatchObject({ kind: 'complete' });
		harness.transport.subscribe('review.metadata', { interests: [] });
		await harness.server.waitForMetadataStream();
		harness.server.emitMetadata(metadataAccepted(harness.server.requiredMetadataRequest()));
		await waitForCondition(
			() => harness.transport.metadataStreamDiagnostics?.().acknowledgedFrameCount === 1,
		);
		await expect(
			harness.transport.call('review.markFileViewed', { itemId: 'review-item-independent' }),
		).resolves.toBeNull();

		expect(didFirstSettle).toBe(false);
		expect(
			harness.server.frameAcknowledgements.filter(
				(acknowledgement) =>
					acknowledgement.streamKind === 'content' &&
					acknowledgement.contentRequestId === second.contentRequestId,
			),
		).toHaveLength(3);
		expect(
			harness.server.frameAcknowledgements.filter(
				(acknowledgement) => acknowledgement.streamKind === 'metadata',
			),
		).toHaveLength(1);
		harness.server.releaseHeldContentAcknowledgement();
		await expect(first.terminal).resolves.toMatchObject({ kind: 'complete' });
	});

	test('reserves request capacity for observations while content remains open', async () => {
		const harness = createContentTransportHarness();
		harness.server.holdContentResponses = true;
		const abortControllers = Array.from({ length: 13 }, () => new AbortController());
		const contentStreams = abortControllers.map((abortController, index) =>
			harness.transport.openContent(
				fileContentDescriptor(`descriptor-admission-${index}`),
				abortController.signal,
			),
		);

		await harness.server.waitForContentRequestCount(
			BRIDGE_PRODUCT_MAXIMUM_CONCURRENT_CONTENT_RESPONSES,
		);
		await Promise.resolve();
		expect(harness.server.contentRequests).toHaveLength(
			BRIDGE_PRODUCT_MAXIMUM_CONCURRENT_CONTENT_RESPONSES,
		);
		const waitingContentStream = contentStreams[12];
		expect(waitingContentStream?.responseStartControl).toBeDefined();
		waitingContentStream?.responseStartControl?.pauseBeforeStart();

		abortControllers[0]?.abort(new DOMException('release active admission', 'AbortError'));
		await expect(contentStreams[0]?.terminal).rejects.toThrow();
		expect(BRIDGE_PRODUCT_MAXIMUM_CONCURRENT_CONTENT_RESPONSES).toBe(12);
		await Promise.resolve();
		expect(harness.server.contentRequests).toHaveLength(12);

		waitingContentStream?.responseStartControl?.resumeBeforeStart();
		await harness.server.waitForContentRequestCount(13);
		expect(harness.server.contentRequests).toHaveLength(13);
		for (const abortController of abortControllers.slice(1)) {
			abortController.abort(new DOMException('test cleanup', 'AbortError'));
		}
		await Promise.allSettled(
			contentStreams.slice(1).map((contentStream) => contentStream.terminal),
		);
	});

	test('aborting a paused response waiter never starts its content request', async () => {
		const harness = createContentTransportHarness();
		harness.server.holdContentResponses = true;
		const abortControllers = Array.from({ length: 13 }, () => new AbortController());
		const contentStreams = abortControllers.map((abortController, index) =>
			harness.transport.openContent(
				fileContentDescriptor(`descriptor-paused-abort-${index}`),
				abortController.signal,
			),
		);
		await harness.server.waitForContentRequestCount(
			BRIDGE_PRODUCT_MAXIMUM_CONCURRENT_CONTENT_RESPONSES,
		);
		const waitingContentStream = contentStreams[12];
		if (waitingContentStream === undefined) throw new Error('Expected one waiting content stream.');
		waitingContentStream.responseStartControl?.pauseBeforeStart();
		abortControllers[0]?.abort(new DOMException('release active admission', 'AbortError'));
		await expect(contentStreams[0]?.terminal).rejects.toThrow();

		abortControllers[12]?.abort(new DOMException('cancel paused response', 'AbortError'));
		waitingContentStream.responseStartControl?.resumeBeforeStart();
		await expect(waitingContentStream.terminal).rejects.toThrow();
		expect(harness.server.contentRequests).toHaveLength(
			BRIDGE_PRODUCT_MAXIMUM_CONCURRENT_CONTENT_RESPONSES,
		);

		for (const abortController of abortControllers.slice(1, 12)) {
			abortController.abort(new DOMException('test cleanup', 'AbortError'));
		}
		await Promise.allSettled(contentStreams.slice(1, 12).map(({ terminal }) => terminal));
	});

	test('cancels the content response reader when its signal aborts', async () => {
		const harness = createContentTransportHarness();
		harness.server.holdContentResponses = true;
		const abortController = new AbortController();
		const content = harness.transport.openContent(
			fileContentDescriptor('descriptor-abort'),
			abortController.signal,
		);
		await harness.server.waitForContentRequestCount(1);

		abortController.abort(new DOMException('cancelled', 'AbortError'));

		await expect(content.terminal).rejects.toThrow();
		expect(harness.server.contentReaderCancelCount).toBe(1);
	});
});
