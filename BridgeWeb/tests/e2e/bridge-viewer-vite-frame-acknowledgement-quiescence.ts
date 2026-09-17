import type { Frame, Page, Request } from 'playwright';
import { expect } from 'vitest';

import { settleBrowserFrames } from './bridge-viewer-vite-annotation-catalog-performance.ts';

export function observeFrameAcknowledgementQuiescence(
	page: Page,
	timeoutMilliseconds: number,
): {
	readonly pendingAcknowledgementCount: () => number;
	readonly wait: () => Promise<void>;
} {
	const pendingRequestDocumentEpochs = new Map<Request, number>();
	let currentDocumentEpoch = 0;
	const isFrameAcknowledgement = (request: Request): boolean => {
		if (new URL(request.url()).pathname !== '/__bridge-product/command') return false;
		try {
			const body: unknown = request.postDataJSON();
			return (
				typeof body === 'object' &&
				body !== null &&
				Reflect.get(body, 'kind') === 'stream.frameObserved'
			);
		} catch {
			return false;
		}
	};
	page.on('request', (request: Request): void => {
		if (isFrameAcknowledgement(request)) {
			pendingRequestDocumentEpochs.set(request, currentDocumentEpoch);
		}
	});
	const settleRequest = (request: Request): void => {
		pendingRequestDocumentEpochs.delete(request);
	};
	page.on('requestfinished', settleRequest);
	page.on('requestfailed', settleRequest);
	// Why: these acknowledgements are issued by a dedicated Web Worker, and Playwright 1.61 detaches
	// the worker target on navigation without emitting a terminal event for its in-flight requests.
	// A destroyed document can no longer owe an acknowledgement, so quiescence is a claim about the
	// current document only; retiring the previous document's entries is what lets the map drain.
	page.on('framenavigated', (frame: Frame): void => {
		if (frame !== page.mainFrame()) return;
		currentDocumentEpoch += 1;
		for (const [request, documentEpoch] of pendingRequestDocumentEpochs) {
			if (documentEpoch !== currentDocumentEpoch) pendingRequestDocumentEpochs.delete(request);
		}
	});
	const pendingAcknowledgementCount = (): number => {
		let count = 0;
		for (const documentEpoch of pendingRequestDocumentEpochs.values()) {
			if (documentEpoch === currentDocumentEpoch) count += 1;
		}
		return count;
	};

	return {
		pendingAcknowledgementCount,
		wait: async (): Promise<void> => {
			await expect
				.poll(pendingAcknowledgementCount, {
					timeout: timeoutMilliseconds,
				})
				.toBe(0);
			await settleBrowserFrames(page, 2);
			await expect
				.poll(pendingAcknowledgementCount, {
					timeout: timeoutMilliseconds,
				})
				.toBe(0);
		},
	};
}
