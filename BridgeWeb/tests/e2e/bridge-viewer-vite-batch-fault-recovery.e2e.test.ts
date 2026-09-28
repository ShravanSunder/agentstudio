import type { Browser, Page } from 'playwright';
import { expect, test } from 'vitest';

import { runAllOwnedCleanupOperations } from '../../scripts/dev-server/bridge-development-server-process.ts';
import {
	selectReviewFile,
	waitForSelectedFileReady,
	waitForSelectedReviewReady,
} from './bridge-viewer-vite-annotation-save-journey.ts';
import { launchBridgeViewerE2EChromium } from './bridge-viewer-vite-e2e-browser.ts';
import { observeSelectedFileRetention } from './bridge-viewer-vite-file-retention-probe.ts';
import {
	createBridgeViewerViteProductFixture,
	startBridgeViewerOwnedViteProductServer,
	type BridgeViewerOwnedViteProductServer,
} from './bridge-viewer-vite-product-fixture.ts';
import { bridgeViewerViteProductFileUrl } from './bridge-viewer-vite-product-url.ts';
import {
	startBridgeStreamFaultProxy,
	type BridgeStreamFaultProxy,
} from './bridge-viewer-vite-stream-fault-proxy.ts';

test('File and Review semantic part faults recover on the live Vite and Swift stream', async () => {
	const fixture = await createBridgeViewerViteProductFixture();
	let server: BridgeViewerOwnedViteProductServer | null = null;
	let proxy: BridgeStreamFaultProxy | null = null;
	let browser: Browser | null = null;
	let page: Page | null = null;
	let retention: Awaited<ReturnType<typeof observeSelectedFileRetention>> | null = null;
	let primaryError: unknown;
	try {
		server = await startBridgeViewerOwnedViteProductServer(fixture.oracle);
		proxy = await startBridgeStreamFaultProxy(server.origin, { semanticBatchFaults: true });
		browser = await launchBridgeViewerE2EChromium();
		page = await browser.newPage({ viewport: { height: 980, width: 1728 } });
		page.setDefaultTimeout(0);
		page.setDefaultNavigationTimeout(0);
		await page.goto(bridgeViewerViteProductFileUrl(proxy.origin, fixture.oracle.largeFilePath), {
			waitUntil: 'domcontentloaded',
		});
		await waitForSelectedFileReady({ oracle: fixture.oracle, page });
		retention = await observeSelectedFileRetention(page, fixture.oracle.largeFilePath);
		const establishedStreamCount = proxy.snapshot().metadataRequestCount;
		expect(establishedStreamCount).toBe(1);
		expect(proxy.snapshot().semanticKindsByResponse).toEqual([
			expect.arrayContaining(['file.metadata']),
		]);

		const faultApplied = proxy.armSemanticBatchFault({
			mode: 'drop',
			subscriptionKind: 'file.metadata',
		});
		const updatedContent = await fixture.mutateLargeFile();
		const applied = await faultApplied;
		expect(applied).toMatchObject({
			mode: 'drop',
			subscriptionKind: 'file.metadata',
		});
		await waitForSelectedFileReady({
			expected: {
				lineCount: updatedContent.lineCount,
				path: fixture.oracle.largeFilePath,
				sha256: updatedContent.sha256,
			},
			oracle: fixture.oracle,
			page,
		});
		expect(proxy.snapshot().metadataRequestCount).toBe(establishedStreamCount);
		expect(await retention.stop()).toBeNull();
		retention = null;

		await page
			.getByTestId('bridge-viewer-mode-host-file')
			.getByRole('button', { name: 'Review', exact: true })
			.click();
		const reviewFile = fixture.oracle.reviewFiles[0];
		if (reviewFile === undefined) throw new Error('Fault recovery needs a changed Review file.');
		const reviewShell = page.getByTestId('review-viewer-shell');
		await reviewShell.waitFor({ state: 'attached' });
		const installedItemCount = Number(
			await reviewShell.getAttribute('data-review-metadata-item-count'),
		);
		const installedTreeRowCount = Number(
			await reviewShell.getAttribute('data-review-metadata-tree-row-count'),
		);
		expect(
			installedItemCount,
			'The changed Review fixture must install item rows.',
		).toBeGreaterThan(0);
		expect(
			installedTreeRowCount,
			'The changed Review fixture must install tree rows.',
		).toBeGreaterThan(0);
		await selectReviewFile({ page, path: reviewFile.path });
		await waitForSelectedReviewReady({ itemId: reviewFile.itemId, page });
		const priorReviewRevision = Number(
			await reviewShell.getAttribute('data-review-metadata-revision'),
		);
		expect(Number.isSafeInteger(priorReviewRevision)).toBe(true);
		const reorderApplied = proxy.armSemanticBatchFault({
			mode: 'reorder',
			subscriptionKind: 'review.metadata',
		});
		expect((await fixture.mutateReviewFile()).path).toBe(reviewFile.path);
		expect(await reorderApplied).toMatchObject({
			mode: 'reorder',
			subscriptionKind: 'review.metadata',
		});
		const reorderedBatch = proxy.snapshot().semanticFaultsApplied.at(-1);
		if (reorderedBatch === undefined)
			throw new Error('Review reorder fault has no batch identity.');
		await proxy.waitForBatchComplete(reorderedBatch.batchId);
		await waitForReviewRevisionAfter(page, priorReviewRevision);
		await waitForSelectedReviewReady({ itemId: reviewFile.itemId, page });
		expect(await reviewShell.getAttribute('data-review-metadata-revision')).not.toBe(
			String(priorReviewRevision),
		);
		expect(proxy.snapshot().metadataRequestCount).toBe(establishedStreamCount);
	} catch (error: unknown) {
		const snapshot = proxy?.snapshot();
		primaryError = new Error(
			`Semantic batch fault journey failed: proxy=${JSON.stringify(
				snapshot === undefined
					? null
					: {
							metadataRequestCount: snapshot.metadataRequestCount,
							semanticFaultsApplied: snapshot.semanticFaultsApplied,
							semanticKindsByResponse: snapshot.semanticKindsByResponse,
							lostViewAcknowledgements: snapshot.lostViewAcknowledgements,
							semanticMetadataClosures: snapshot.semanticMetadataClosures,
						},
			)} backend=${server?.diagnostics() ?? 'not started'}`,
			{ cause: error },
		);
	} finally {
		await runAllOwnedCleanupOperations({
			operations: [
				{
					name: 'last-good File retention',
					run: async (): Promise<void> => {
						if (retention !== null) expect(await retention.stop()).toBeNull();
					},
				},
				{ name: 'browser', run: async (): Promise<void> => await browser?.close() },
				{ name: 'semantic fault proxy', run: async (): Promise<void> => await proxy?.stop() },
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

async function waitForReviewRevisionAfter(page: Page, priorRevision: number): Promise<void> {
	await page.evaluate(
		(previousRevision): Promise<void> =>
			new Promise((resolve): void => {
				const currentRevision = (): number =>
					Number(
						document
							.querySelector('[data-testid="review-viewer-shell"]')
							?.getAttribute('data-review-metadata-revision'),
					);
				const observer = new MutationObserver((): void => {
					if (currentRevision() <= previousRevision) return;
					observer.disconnect();
					resolve();
				});
				observer.observe(document.body, {
					attributeFilter: ['data-review-metadata-revision'],
					attributes: true,
					childList: true,
					subtree: true,
				});
				if (currentRevision() > previousRevision) {
					observer.disconnect();
					resolve();
				}
			}),
		priorRevision,
	);
}
