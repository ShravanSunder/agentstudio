import type {
	Page,
	Request as PlaywrightRequest,
	Response as PlaywrightResponse,
} from 'playwright';
import { describe, expect, test } from 'vitest';

import {
	BridgeViewerRealRouterObserver,
	mountedHeaderOrderViolationForExpectedOrder,
	nextFreshReviewTraversalScrollTop,
} from './product-only-real-router-page.ts';
import {
	hasCompleteFreshReviewPaintIdentityCoverage,
	previousFreshReviewTraversalScrollTop,
} from './product-only-real-router-review-hydration-window.ts';

type PageEventName = 'request' | 'requestfailed' | 'requestfinished' | 'response';
type PageEventHandler = (event: unknown) => void;

describe('BridgeViewerRealRouterObserver', () => {
	test('records the scrub-safe product call method in failure transport evidence', () => {
		// Arrange
		const harness = makeObserverHarness();
		const observer = new BridgeViewerRealRouterObserver(harness.page, (): number => 1);
		const request = makeProductCallRequest('review.activeViewerMode.update');
		harness.emit('request', request);

		// Act / Assert
		expect(observer.failureTransportSnapshot().entries).toEqual([
			expect.objectContaining({
				callMethod: 'review.activeViewerMode.update',
				requestKind: 'product.call',
			}),
		]);
	});

	test('retains scrubbed content lifecycle and unfinished request ordinals for a failed journey', () => {
		// Arrange
		const harness = makeObserverHarness();
		const observer = new BridgeViewerRealRouterObserver(harness.page, (): number => 1);
		const completedRequest = makeProductContentRequest('completed-request');
		const unfinishedRequest = makeProductContentRequest('unfinished-request');
		harness.emit('request', completedRequest);
		harness.emit('response', makeSuccessfulResponse(completedRequest));
		harness.emit('requestfinished', completedRequest);
		harness.emit('request', unfinishedRequest);

		// Act
		const snapshot = observer.failureTransportSnapshot();

		// Assert
		expect(snapshot.entries).toEqual([
			expect.objectContaining({
				contentKind: 'review.content',
				httpStatus: 200,
				ordinal: 1,
				path: '/__bridge-product/content',
				requestKind: 'content.open',
			}),
			expect.objectContaining({
				contentKind: 'review.content',
				httpStatus: null,
				ordinal: 2,
				path: '/__bridge-product/content',
				requestKind: 'content.open',
			}),
		]);
		expect(snapshot.unfinishedRequestOrdinals).toEqual([2]);
		expect(JSON.stringify(snapshot)).not.toContain('pane-session-secret');
		expect(JSON.stringify(snapshot)).not.toContain('worker-instance-secret');
	});

	test('waits for streaming request completion and one activity-stable browser frame', async () => {
		// Arrange
		const harness = makeObserverHarness();
		const observer = new BridgeViewerRealRouterObserver(harness.page, (): number => 1);
		const firstRequest = makeProductContentRequest('first-request');
		const secondRequest = makeProductContentRequest('second-request');
		let barrierResolved = false;

		harness.emit('request', firstRequest);
		harness.emit('response', makeSuccessfulResponse(firstRequest));

		// Act
		const barrier = observer.waitForAllProductResponses().then((): void => {
			barrierResolved = true;
		});
		await flushMicrotasks();

		// Assert
		expect(barrierResolved).toBe(false);

		// Act: completing the first body releases admission for a second request.
		harness.emit('requestfinished', firstRequest);
		await flushMicrotasks();
		expect(harness.pendingAnimationFrameCount()).toBe(1);
		harness.emit('request', secondRequest);
		harness.emit('response', makeSuccessfulResponse(secondRequest));
		harness.resolveNextAnimationFrame();
		await flushMicrotasks();

		// Assert: the activity checkpoint cannot hide the newly admitted body.
		expect(barrierResolved).toBe(false);

		// Act
		harness.emit('requestfinished', secondRequest);
		await flushMicrotasks();
		expect(harness.pendingAnimationFrameCount()).toBe(1);
		harness.resolveNextAnimationFrame();
		await barrier;

		// Assert
		expect(barrierResolved).toBe(true);
		expect(observer.productRouteTranscript().map((entry) => entry.httpStatus)).toEqual([200, 200]);
	});

	test('does not let an unfinished prior-document body block active-document quiescence', async () => {
		// Arrange
		const harness = makeObserverHarness();
		let documentGeneration = 1;
		const observer = new BridgeViewerRealRouterObserver(
			harness.page,
			(): number => documentGeneration,
		);
		const priorDocumentRequest = makeProductContentRequest('prior-document-request');
		harness.emit('request', priorDocumentRequest);
		documentGeneration = 2;

		// Act
		const barrier = observer.waitForAllProductResponses();
		await flushMicrotasks();
		expect(harness.pendingAnimationFrameCount()).toBe(1);
		harness.resolveNextAnimationFrame();
		await barrier;

		// Assert
		expect(observer.productRouteTranscript()).toEqual([
			expect.objectContaining({ documentGeneration: 1, httpStatus: null }),
		]);
	});

	test('does not let a retired-document response parser failure poison the active journey', async () => {
		// Arrange
		const harness = makeObserverHarness();
		let documentGeneration = 1;
		const observer = new BridgeViewerRealRouterObserver(
			harness.page,
			(): number => documentGeneration,
		);
		const retiredDocumentRequest = makeProductCallRequest('review.activeViewerMode.update');
		const retiredDocumentBody = makePendingStringPromise();
		harness.emit('request', retiredDocumentRequest);
		harness.emit(
			'response',
			makeSuccessfulCommandResponse(retiredDocumentRequest, retiredDocumentBody.promise),
		);

		// Act: navigation retires the response before Playwright can read its body.
		documentGeneration = 2;
		retiredDocumentBody.reject(new Error('Target page, context or browser has been closed'));
		await flushMicrotasks();

		// Assert
		await expect(observer.flushResponseParsers()).resolves.toBeUndefined();
		expect(observer.productRouteTranscript()).toEqual([
			expect.objectContaining({
				documentGeneration: 1,
				httpStatus: 200,
				responseKind: null,
			}),
		]);
	});

	test('still reports a response parser failure from the active document', async () => {
		// Arrange
		const harness = makeObserverHarness();
		const observer = new BridgeViewerRealRouterObserver(harness.page, (): number => 1);
		const activeDocumentRequest = makeProductCallRequest('review.activeViewerMode.update');
		const activeDocumentFailure = new Error('active document response body failed');
		harness.emit('request', activeDocumentRequest);
		harness.emit(
			'response',
			makeSuccessfulCommandResponse(activeDocumentRequest, Promise.reject(activeDocumentFailure)),
		);
		await flushMicrotasks();

		// Act / Assert
		await expect(observer.flushResponseParsers()).rejects.toBe(activeDocumentFailure);
	});

	test('treats a failed non-stream request without an HTTP response as terminal', async () => {
		// Arrange
		const harness = makeObserverHarness();
		const observer = new BridgeViewerRealRouterObserver(harness.page, (): number => 1);
		const cancelledContentRequest = makeProductContentRequest('cancelled-request');
		harness.emit('request', cancelledContentRequest);
		harness.emit('requestfailed', cancelledContentRequest);

		// Act
		const barrier = observer.waitForAllProductResponses();
		await flushMicrotasks();
		expect(harness.pendingAnimationFrameCount()).toBe(1);
		harness.resolveNextAnimationFrame();
		await barrier;

		// Assert
		expect(observer.failureTransportSnapshot()).toEqual({
			entries: [
				expect.objectContaining({
					httpStatus: null,
					requestKind: 'content.open',
					requestSettled: true,
				}),
			],
			unfinishedRequestOrdinals: [],
		});
	});
});

describe('mountedHeaderOrderViolationForExpectedOrder', () => {
	test('accepts a sparse mounted viewport that preserves catalog order', () => {
		// Arrange
		const expectedItemIndexById = new Map([
			['review-item-1', 0],
			['review-item-2', 1],
			['review-item-3', 2],
			['review-item-4', 3],
		]);

		// Act
		const violation = mountedHeaderOrderViolationForExpectedOrder({
			expectedItemIndexById,
			mountedItemIds: ['review-item-1', 'review-item-3', 'review-item-4'],
		});

		// Assert
		expect(violation).toBeNull();
	});

	test('reports a mounted viewport whose DOM order contradicts the catalog', () => {
		// Arrange
		const expectedItemIndexById = new Map([
			['review-item-1', 0],
			['review-item-2', 1],
			['review-item-3', 2],
		]);

		// Act
		const violation = mountedHeaderOrderViolationForExpectedOrder({
			expectedItemIndexById,
			mountedItemIds: ['review-item-1', 'review-item-3', 'review-item-2'],
		});

		// Assert
		expect(violation).toEqual({
			expectedItemIndexes: [0, 2, 1],
			mountedItemIds: ['review-item-1', 'review-item-3', 'review-item-2'],
		});
	});
});

describe('hasCompleteFreshReviewPaintIdentityCoverage', () => {
	test('requires every expected paint identity before forward traversal may complete', () => {
		// Arrange
		const expectedItemIds = ['review-item-1', 'review-item-2', 'review-item-3'];

		// Act
		const incompleteCoverage = hasCompleteFreshReviewPaintIdentityCoverage({
			expectedItemIds,
			paintIdentityByItemId: new Map([
				['review-item-1', 'paint-1'],
				['review-item-2', 'paint-2'],
			]),
		});
		const completeCoverage = hasCompleteFreshReviewPaintIdentityCoverage({
			expectedItemIds,
			paintIdentityByItemId: new Map([
				['review-item-1', 'paint-1'],
				['review-item-2', 'paint-2'],
				['review-item-3', 'paint-3'],
			]),
		});

		// Assert
		expect(incompleteCoverage).toBe(false);
		expect(completeCoverage).toBe(true);
	});
});

describe('nextFreshReviewTraversalScrollTop', () => {
	test('skips the already-hydrated body while retaining viewport overlap at the next header', () => {
		// Arrange
		const codeScroll = {
			clientHeight: 1_000,
			scrollHeight: 40_000,
			scrollTop: 5_000,
		};

		// Act
		const nextScrollTop = nextFreshReviewTraversalScrollTop({
			codeScroll,
			visibleItems: [
				{
					contentState: 'hydrated',
					hostBottomOffset: 6_000,
					hostTopOffset: -250,
					itemId: 'review-item-42',
					paintIdentity: 'paint-42',
				},
			],
		});

		// Assert
		expect(nextScrollTop).toBe(10_900);
	});

	test('falls back to bounded viewport progress when no host geometry is available', () => {
		// Arrange / Act
		const nextScrollTop = nextFreshReviewTraversalScrollTop({
			codeScroll: {
				clientHeight: 1_000,
				scrollHeight: 6_500,
				scrollTop: 5_000,
			},
			visibleItems: [],
		});

		// Assert
		expect(nextScrollTop).toBe(5_500);
	});
});

describe('previousFreshReviewTraversalScrollTop', () => {
	test('skips the already-hydrated body while retaining viewport overlap at the previous header', () => {
		// Arrange / Act
		const previousScrollTop = previousFreshReviewTraversalScrollTop({
			codeScroll: {
				clientHeight: 1_000,
				scrollTop: 10_000,
			},
			visibleItems: [{ hostTopOffset: -6_000 }],
		});

		// Assert
		expect(previousScrollTop).toBe(3_900);
	});

	test('falls back to bounded viewport progress when no host geometry is available', () => {
		// Arrange / Act
		const previousScrollTop = previousFreshReviewTraversalScrollTop({
			codeScroll: {
				clientHeight: 1_000,
				scrollTop: 5_000,
			},
			visibleItems: [],
		});

		// Assert
		expect(previousScrollTop).toBe(4_200);
	});
});

function makeObserverHarness(): {
	readonly emit: (eventName: PageEventName, event: unknown) => void;
	readonly page: Page;
	readonly pendingAnimationFrameCount: () => number;
	readonly resolveNextAnimationFrame: () => void;
} {
	const eventHandlers = new Map<PageEventName, PageEventHandler[]>();
	const animationFrameResolvers: Array<() => void> = [];
	let activeFrameSettlement:
		| {
				settled: boolean;
				readonly waiters: Array<() => void>;
		  }
		| undefined;
	const pageShape = {
		evaluate: async (): Promise<void> => {
			const frameSettlement = { settled: false, waiters: [] as Array<() => void> };
			activeFrameSettlement = frameSettlement;
			animationFrameResolvers.push((): void => {
				frameSettlement.settled = true;
				for (const resolveWaiter of frameSettlement.waiters) resolveWaiter();
				frameSettlement.waiters.length = 0;
			});
		},
		on: (eventName: PageEventName, eventHandler: PageEventHandler): void => {
			const handlers = eventHandlers.get(eventName) ?? [];
			handlers.push(eventHandler);
			eventHandlers.set(eventName, handlers);
		},
		waitForFunction: async (): Promise<void> => {
			const frameSettlement = activeFrameSettlement;
			if (frameSettlement === undefined) {
				throw new Error('Frame settlement wait began before a frame was scheduled.');
			}
			if (frameSettlement.settled) return;
			await new Promise<void>((resolve): void => {
				frameSettlement.waiters.push(resolve);
			});
		},
	};

	return {
		emit: (eventName, event): void => {
			for (const eventHandler of eventHandlers.get(eventName) ?? []) eventHandler(event);
		},
		page: pageShape as unknown as Page,
		pendingAnimationFrameCount: (): number => animationFrameResolvers.length,
		resolveNextAnimationFrame: (): void => {
			const resolveAnimationFrame = animationFrameResolvers.shift();
			if (resolveAnimationFrame === undefined) {
				throw new Error('No pending animation frame to resolve.');
			}
			resolveAnimationFrame();
		},
	};
}

function makeProductCallRequest(method: string): PlaywrightRequest {
	return {
		method: (): string => 'POST',
		postData: (): string =>
			JSON.stringify({
				call: { method, request: null },
				kind: 'product.call',
				paneSessionId: 'pane-session-secret',
				workerInstanceId: 'worker-instance-secret',
			}),
		url: (): string => 'http://127.0.0.1:5173/__bridge-product/command',
	} as unknown as PlaywrightRequest;
}

function makeProductContentRequest(contentRequestId: string): PlaywrightRequest {
	return {
		method: (): string => 'POST',
		postData: (): string =>
			JSON.stringify({
				contentKind: 'review.content',
				contentRequestId,
				kind: 'content.open',
				paneSessionId: 'pane-session-secret',
				workerInstanceId: 'worker-instance-secret',
			}),
		url: (): string => 'http://127.0.0.1:5173/__bridge-product/content',
	} as unknown as PlaywrightRequest;
}

function makeSuccessfulResponse(request: PlaywrightRequest): PlaywrightResponse {
	return {
		request: (): PlaywrightRequest => request,
		status: (): number => 200,
	} as unknown as PlaywrightResponse;
}

function makeSuccessfulCommandResponse(
	request: PlaywrightRequest,
	body: Promise<string>,
): PlaywrightResponse {
	return {
		request: (): PlaywrightRequest => request,
		status: (): number => 200,
		text: async (): Promise<string> => await body,
	} as unknown as PlaywrightResponse;
}

function makePendingStringPromise(): {
	readonly promise: Promise<string>;
	readonly reject: (error: Error) => void;
} {
	let rejectPromise: (error: Error) => void = (): void => {
		throw new Error('Pending string promise rejector was not initialized.');
	};
	const promise = new Promise<string>((_resolve, reject): void => {
		rejectPromise = (error): void => reject(error);
	});
	return { promise, reject: rejectPromise };
}

async function flushMicrotasks(): Promise<void> {
	await Promise.resolve();
	await Promise.resolve();
	await Promise.resolve();
}
