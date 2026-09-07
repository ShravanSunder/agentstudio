import { chromium, type Browser } from 'playwright';
import { expect, test } from 'vitest';

import { runAllOwnedCleanupOperations } from '../../scripts/dev-server/bridge-development-server-process.ts';
import {
	selectReviewFile,
	waitForSelectedReviewReady,
} from './bridge-viewer-vite-annotation-save-journey.ts';
import {
	createBridgeViewerViteProductFixture,
	startBridgeViewerOwnedViteProductServer,
	type BridgeViewerOwnedViteProductServer,
} from './bridge-viewer-vite-product-fixture.ts';
import { bridgeViewerViteProductReviewUrl } from './bridge-viewer-vite-product-url.ts';

test('superseded development tabs stop until explicit takeover, including after reload', async (): Promise<void> => {
	// Arrange: two tabs in one browser profile against a real isolated Swift backend.
	const fixture = await createBridgeViewerViteProductFixture();
	let browser: Browser | null = null;
	let server: BridgeViewerOwnedViteProductServer | null = null;
	let primaryError: unknown;
	try {
		server = await startBridgeViewerOwnedViteProductServer(fixture.oracle);
		browser = await chromium.launch({ channel: 'chrome', headless: true });
		const context = await browser.newContext({ viewport: { width: 1728, height: 980 } });
		const pageErrors: string[] = [];
		context.on('page', (createdPage): void => {
			createdPage.on('pageerror', (error): void => {
				pageErrors.push(error.message);
			});
		});
		const firstTab = await context.newPage();
		let firstBootstrapCount = 0;
		firstTab.on('request', (request): void => {
			if (new URL(request.url()).pathname === '/__bridge-product/bootstrap')
				firstBootstrapCount += 1;
		});
		const reviewFile = fixture.oracle.reviewFiles[0];
		if (reviewFile === undefined) throw new Error('Tab ownership fixture needs a changed file.');
		const url = bridgeViewerViteProductReviewUrl(server.origin);
		await firstTab.goto(url, { waitUntil: 'domcontentloaded' });
		await selectReviewFile({ page: firstTab, path: reviewFile.path });
		await waitForSelectedReviewReady({ page: firstTab, itemId: reviewFile.itemId });

		// Act: a second tab becomes current; the first must stop instead of competing.
		const secondTab = await context.newPage();
		await secondTab.goto(url, { waitUntil: 'domcontentloaded' });
		await secondTab.getByTestId('review-viewer-shell').waitFor({ state: 'visible' });
		await firstTab
			.getByTestId('bridge-dev-session-inactive')
			.waitFor({ state: 'visible', timeout: 15_000 });
		expect(await firstTab.getByRole('button').count()).toBe(1);
		const bootstrapCountBeforeInactiveReload = firstBootstrapCount;
		await firstTab.reload({ waitUntil: 'domcontentloaded' });
		await firstTab.getByTestId('bridge-dev-session-inactive').waitFor({ state: 'visible' });
		expect(firstBootstrapCount).toBe(bootstrapCountBeforeInactiveReload);

		// Assert: only the explicit action takes ownership back and produces usable content.
		await firstTab.getByRole('button', { name: 'Use this tab', exact: true }).click();
		await secondTab.getByTestId('bridge-dev-session-inactive').waitFor({ state: 'visible' });
		await selectReviewFile({ page: firstTab, path: reviewFile.path });
		await waitForSelectedReviewReady({ page: firstTab, itemId: reviewFile.itemId });
		expect(firstBootstrapCount).toBe(bootstrapCountBeforeInactiveReload + 1);
		expect(pageErrors).toEqual([]);
	} catch (error: unknown) {
		primaryError = new Error(
			`Development tab ownership failed. Backend: ${server?.diagnostics() ?? 'not started'}`,
			{ cause: error },
		);
	} finally {
		await runAllOwnedCleanupOperations({
			operations: [
				{
					name: 'browser',
					run: async (): Promise<void> => {
						await browser?.close();
					},
				},
				{
					name: 'Vite and Swift',
					run: async (): Promise<void> => {
						if (server === null) return;
						const cleanup = await server.stop();
						expect(cleanup.ownedProcessAliveAfterStop).toBe(false);
						expect(cleanup.forcedTerminationRequired).toBe(false);
					},
				},
				{ name: 'fixture', run: fixture.dispose },
			],
			...(primaryError === undefined ? {} : { primaryError }),
		});
	}
});
