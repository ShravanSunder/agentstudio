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
import {
	observeBrowserRuntimeDiagnostics,
	waitForSettledReviewComparison,
} from './bridge-viewer-vite-review-comparison-observation.ts';

test('replaces the worker after exhausted installed receipts and installs the next Review revision', async () => {
	// Arrange — intercept only installed receipts; all source, metadata and content remain real.
	const fixture = await createBridgeViewerViteProductFixture();
	let server: BridgeViewerOwnedViteProductServer | null = null;
	let browser: Browser | null = null;
	let diagnostics: ReturnType<typeof observeBrowserRuntimeDiagnostics> | null = null;
	let rejectedReceiptCount = 0;
	try {
		browser = await chromium.launch({ channel: 'chrome', headless: true });
		server = await startBridgeViewerOwnedViteProductServer(fixture.oracle);
		const page = await browser.newPage({ viewport: { height: 980, width: 1728 } });
		diagnostics = observeBrowserRuntimeDiagnostics(page);
		await page.route('**/__bridge-product/command', async (route): Promise<void> => {
			const body: unknown = route.request().postDataJSON();
			if (
				typeof body === 'object' &&
				body !== null &&
				'kind' in body &&
				body.kind === 'product.call' &&
				'call' in body &&
				typeof body.call === 'object' &&
				body.call !== null &&
				'method' in body.call &&
				body.call.method === 'review.publication.applied' &&
				rejectedReceiptCount < 4
			) {
				rejectedReceiptCount += 1;
				await route.fulfill({ body: '', contentType: 'text/plain', status: 502 });
				return;
			}
			await route.continue();
		});
		const initialBootstrap = page.waitForResponse(
			(response): boolean => isBootstrapResponse(response, 'initial'),
			{ timeout: 30_000 },
		);
		const replacementBootstrap = page.waitForResponse(
			(response): boolean => isBootstrapResponse(response, 'workerReplacement'),
			{ timeout: 30_000 },
		);
		let mainFrameNavigationCount = 0;
		page.on('framenavigated', (frame): void => {
			if (frame === page.mainFrame()) mainFrameNavigationCount += 1;
		});

		// Act — both exact-byte attempts of each of two semantic receipt attempts fail.
		const [initialResponse, replacementResponse] = await Promise.all([
			initialBootstrap,
			replacementBootstrap,
			page.goto(bridgeViewerViteProductReviewUrl(server.origin), {
				timeout: 120_000,
				waitUntil: 'domcontentloaded',
			}),
		]);
		expect(rejectedReceiptCount).toBe(4);
		expect(await bootstrapWorkerInstanceId(replacementResponse)).not.toBe(
			await bootstrapWorkerInstanceId(initialResponse),
		);
		const recoveredComparison = await waitForSettledReviewComparison({
			expectedTargetLabel: 'HEAD',
			expectedTargetOID: fixture.oracle.baseRef,
			page,
			timeoutMilliseconds: 30_000,
		});
		const unchangedFile = fixture.oracle.reviewFiles[1];
		if (unchangedFile === undefined) throw new Error('Receipt recovery requires two Review files.');
		await selectReviewFile({ page, path: unchangedFile.path });
		await waitForSelectedReviewReady({ itemId: unchangedFile.itemId, page });

		// Assert — a subsequent real mutation must advance displayed authority, not merely repaint.
		await fixture.mutateReviewFile();
		await expect
			.poll(
				async (): Promise<number> =>
					Number(
						await page
							.getByTestId('review-viewer-shell')
							.getAttribute('data-review-metadata-revision'),
					),
				{ timeout: 30_000 },
			)
			.toBeGreaterThan(recoveredComparison.revision);
		await waitForSelectedReviewReady({ itemId: unchangedFile.itemId, page });
		expect(mainFrameNavigationCount).toBe(1);
		expect(rejectedReceiptCount).toBe(4);
	} catch (error: unknown) {
		throw new Error(
			`Installed-receipt recovery failed. Rejected: ${rejectedReceiptCount}. Browser: ${await diagnostics?.describe()}. Backend: ${server?.diagnostics() ?? 'not started'}`,
			{ cause: error },
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
