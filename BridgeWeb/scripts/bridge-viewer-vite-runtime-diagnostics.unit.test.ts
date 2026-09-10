import type { Page } from 'playwright';
import { afterEach, expect, test, vi } from 'vitest';

import { observeBrowserRuntimeDiagnostics } from '../tests/e2e/bridge-viewer-vite-review-comparison-observation.js';

afterEach((): void => {
	vi.useRealTimers();
});

test.each(['responseBodies', 'reviewComparison', 'bodyText', 'none'] as const)(
	'failure diagnostics settle with %s unavailable',
	async (blockedRead) => {
		// Arrange: preserve the actual response observer, with only the browser I/O seam faked.
		vi.useFakeTimers();
		const listeners = new Map<string, (value: unknown) => void>();
		const pageShape = {
			on: (event: string, listener: (value: unknown) => void): void => {
				listeners.set(event, listener);
			},
			evaluate: (): Promise<null> =>
				blockedRead === 'reviewComparison' ? new Promise(() => {}) : Promise.resolve(null),
			locator: () => ({
				textContent: (): Promise<string> =>
					blockedRead === 'bodyText'
						? new Promise(() => {})
						: Promise.resolve('Retained Review content'),
			}),
			url: (): string => 'http://127.0.0.1:5173/',
		};
		// As in the existing page-harness tests, this cast is confined to the minimal test double.
		// oxlint-disable-next-line typescript/no-unsafe-type-assertion -- The test double implements the four browser methods exercised by this observer.
		const diagnostics = observeBrowserRuntimeDiagnostics(pageShape as unknown as Page);
		listeners.get('response')?.({
			url: (): string => 'http://127.0.0.1:5173/__bridge-product/command',
			status: (): number => 502,
			request: () => ({ postData: (): null => null, method: (): string => 'POST' }),
			text: (): Promise<string> =>
				blockedRead === 'responseBodies'
					? new Promise(() => {})
					: Promise.resolve('controlled failure'),
		});
		let diagnostic: string | null = null;
		const described = diagnostics.describe().then((value): void => {
			diagnostic = value;
		});

		// Act: advance only the diagnostic deadline, not a product operation timeout.
		await vi.advanceTimersByTimeAsync(2_001);

		// Assert: a missing optional body cannot prevent the primary failure and teardown.
		expect(diagnostic).not.toBeNull();
		await described;
		expect(JSON.parse(diagnostic ?? '{}')).toMatchObject({
			bodyText: blockedRead === 'bodyText' ? null : 'Retained Review content',
			diagnosticReadStatus: {
				responseBodies: blockedRead === 'responseBodies' ? 'timed_out' : 'fulfilled',
				reviewComparison: blockedRead === 'reviewComparison' ? 'timed_out' : 'fulfilled',
				bodyText: blockedRead === 'bodyText' ? 'timed_out' : 'fulfilled',
			},
			productErrorResponses: [
				blockedRead === 'responseBodies'
					? '502 POST /__bridge-product/command request='
					: '502 POST /__bridge-product/command request= body=controlled failure',
			],
		});
		expect(vi.getTimerCount()).toBe(0);
	},
);
