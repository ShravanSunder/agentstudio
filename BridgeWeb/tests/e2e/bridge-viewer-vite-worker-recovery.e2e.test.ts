import { chromium, type Browser, type Request, type Response } from 'playwright';
import { expect, test } from 'vitest';

import { decodeBridgeProductDevBootstrapDelivery } from '../../src/core/comm-worker/bridge-product-dev-bootstrap.js';
import {
	selectRangeForAnnotation,
	selectReviewFile,
	waitForCommittedAnnotationCommand,
	waitForSelectedReviewReady,
} from './bridge-viewer-vite-annotation-save-journey.ts';
import {
	createBridgeViewerViteProductFixture,
	startBridgeViewerOwnedViteProductServer,
	type BridgeViewerOwnedViteProductServer,
} from './bridge-viewer-vite-product-fixture.ts';
import { bridgeViewerViteProductReviewUrl } from './bridge-viewer-vite-product-url.ts';

test('reclaims a durable Review draft after worker failure and one unavailable replacement bootstrap', async () => {
	// Arrange — real Vite, Swift, comm worker, metadata and content establish a usable Review.
	const fixture = await createBridgeViewerViteProductFixture();
	let server: BridgeViewerOwnedViteProductServer | null = null;
	let browser: Browser | null = null;
	try {
		browser = await chromium.launch({ channel: 'chrome', headless: true });
		server = await startBridgeViewerOwnedViteProductServer(fixture.oracle);
		const page = await browser.newPage({ viewport: { height: 980, width: 1728 } });
		const reviewFile = fixture.oracle.reviewFiles[0];
		if (reviewFile === undefined) throw new Error('Worker recovery requires a real Review file.');
		let rejectedReplacementCount = 0;
		await page.route('**/__bridge-product/bootstrap', async (route): Promise<void> => {
			if (
				bootstrapReason(route.request()) === 'workerReplacement' &&
				rejectedReplacementCount === 0
			) {
				rejectedReplacementCount += 1;
				await route.fulfill({ body: '', contentType: 'text/plain', status: 502 });
				return;
			}
			await route.continue();
		});
		const initialBootstrapResponse = page.waitForResponse(
			(response): boolean => isBootstrapResponse(response, 'initial'),
			{ timeout: 30_000 },
		);
		const [initialResponse] = await Promise.all([
			initialBootstrapResponse,
			page.goto(bridgeViewerViteProductReviewUrl(server.origin), {
				timeout: 120_000,
				waitUntil: 'domcontentloaded',
			}),
		]);
		const initialWorkerInstanceId = await bootstrapWorkerInstanceId(initialResponse);
		await selectReviewFile({ page, path: reviewFile.path });
		await waitForSelectedReviewReady({ itemId: reviewFile.itemId, page });
		await selectRangeForAnnotation({ endLine: 5, page, startLine: 2, surface: 'review' });
		const draftBody = 'Durable draft remains reclaimable after worker replacement.';
		const draftCreated = waitForCommittedAnnotationCommand(page, 'root.create', 'review');
		await Promise.all([
			draftCreated,
			page.getByRole('textbox', { name: 'Write an annotation in Markdown' }).fill(draftBody),
		]);
		await page
			.locator('[data-testid="worktree-annotation-message"][data-annotation-draft="present"]')
			.waitFor({ state: 'visible', timeout: 30_000 });
		const worker = page
			.workers()
			.find((candidate) => candidate.url().includes('bridge-comm-worker-vite-entry.ts'));
		if (worker === undefined) throw new Error('The real pane comm worker was not created.');

		// Act — an uncaught worker error retires the worker; one proxy failure interrupts replacement.
		const unavailableReplacement = page.waitForResponse(
			(response): boolean =>
				isBootstrapResponse(response, 'workerReplacement') && response.status() === 502,
			{ timeout: 30_000 },
		);
		const freshBootstrapResponse = page.waitForResponse(
			(response): boolean => isBootstrapResponse(response, 'initial'),
			{ timeout: 30_000 },
		);
		const pageReload = page.waitForEvent('framenavigated', {
			predicate: (frame): boolean => frame === page.mainFrame(),
			timeout: 30_000,
		});
		const [, , freshResponse] = await Promise.all([
			unavailableReplacement,
			pageReload,
			freshBootstrapResponse,
			worker.evaluate((): void => {
				queueMicrotask((): never => {
					throw new Error('Controlled comm-worker failure for replacement recovery proof.');
				});
			}),
		]);

		// Assert — real backend authority changed and the requested Review is usable again.
		expect(rejectedReplacementCount).toBe(1);
		expect(await bootstrapWorkerInstanceId(freshResponse)).not.toBe(initialWorkerInstanceId);
		await selectReviewFile({ page, path: reviewFile.path });
		await waitForSelectedReviewReady({ itemId: reviewFile.itemId, page });
		const restoredDraft = page.getByText(draftBody, { exact: true });
		await restoredDraft.waitFor({ state: 'visible', timeout: 30_000 });

		// Act — reclaim the persisted draft through the replacement worker and save an edit.
		await page.getByRole('button', { name: 'Edit annotation', exact: true }).click();
		const savedBody = `${draftBody} Saved by the replacement worker.`;
		await page.getByRole('textbox', { name: 'Annotation Markdown', exact: true }).fill(savedBody);
		const saved = waitForCommittedAnnotationCommand(page, 'draft.save', 'review');
		await Promise.all([
			saved,
			page.getByRole('button', { name: 'Save annotation', exact: true }).click(),
		]);

		// Assert — a new committed mutation proves the old worker no longer owns the draft.
		await page.getByText(savedBody, { exact: true }).waitFor({ state: 'visible', timeout: 30_000 });
	} catch (error) {
		throw new Error(
			`Worker replacement journey failed. Backend: ${server?.diagnostics() ?? 'not started'}`,
			{
				cause: error,
			},
		);
	} finally {
		try {
			await browser?.close();
		} finally {
			try {
				if (server !== null) {
					const cleanup = await server.stop();
					expect(cleanup.ownedProcessAliveAfterStop).toBe(false);
					expect(cleanup.forcedTerminationRequired).toBe(false);
				}
			} finally {
				await fixture.dispose();
			}
		}
	}
});

function bootstrapReason(request: Request): string | null {
	const body: unknown = request.postDataJSON();
	return typeof body === 'object' &&
		body !== null &&
		'reason' in body &&
		typeof body.reason === 'string'
		? body.reason
		: null;
}

function isBootstrapResponse(response: Response, reason: string): boolean {
	return (
		new URL(response.url()).pathname === '/__bridge-product/bootstrap' &&
		bootstrapReason(response.request()) === reason
	);
}

async function bootstrapWorkerInstanceId(response: Response): Promise<string> {
	expect(response.status()).toBe(200);
	const bytes = Uint8Array.from(await response.body());
	return decodeBridgeProductDevBootstrapDelivery(bytes.buffer).bootstrap.workerInstanceId;
}
