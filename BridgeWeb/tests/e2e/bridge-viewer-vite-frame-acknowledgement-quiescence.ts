import type { Page, Request } from 'playwright';
import { expect } from 'vitest';

import { settleBrowserFrames } from './bridge-viewer-vite-annotation-catalog-performance.ts';

export function observeFrameAcknowledgementQuiescence(
	page: Page,
	timeoutMilliseconds: number,
): { readonly wait: () => Promise<void> } {
	const pendingRequests = new Set<Request>();
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
		if (isFrameAcknowledgement(request)) pendingRequests.add(request);
	});
	const settleRequest = (request: Request): void => {
		pendingRequests.delete(request);
	};
	page.on('requestfinished', settleRequest);
	page.on('requestfailed', settleRequest);

	return {
		wait: async (): Promise<void> => {
			await expect
				.poll((): number => pendingRequests.size, {
					timeout: timeoutMilliseconds,
				})
				.toBe(0);
			await settleBrowserFrames(page, 2);
			await expect
				.poll((): number => pendingRequests.size, {
					timeout: timeoutMilliseconds,
				})
				.toBe(0);
		},
	};
}
