import { chromium, type Browser, type Page, type Response } from 'playwright';
import { expect, test } from 'vitest';

import { runAllOwnedCleanupOperations } from '../../scripts/dev-server/bridge-development-server-process.ts';
import {
	runAnnotationSaveJourney,
	selectReviewFile,
	selectRangeForAnnotation,
	waitForCommittedAnnotationCommand,
	waitForSelectedFileReady,
	waitForSelectedReviewReady,
} from './bridge-viewer-vite-annotation-save-journey.ts';
import {
	createBridgeViewerViteProductFixture,
	startBridgeViewerOwnedViteProductServer,
	type BridgeViewerOwnedViteProductServer,
} from './bridge-viewer-vite-product-fixture.ts';
import {
	bridgeViewerViteProductFileUrl,
	bridgeViewerViteProductReviewUrl,
} from './bridge-viewer-vite-product-url.ts';
import { waitForSettledReviewComparison } from './bridge-viewer-vite-review-comparison-observation.ts';

const annotationRestartJourneyTimeoutMilliseconds = 120_000;
const annotationComposedConvergenceTimeoutMilliseconds = 30_000;

export function registerBridgeViewerViteAnnotationSystemJourneyTests(): void {
	test('restores distinct File and Review annotations after a cold Vite and Swift restart', async () => {
		const fixture = await createBridgeViewerViteProductFixture();
		let serverA: BridgeViewerOwnedViteProductServer | null = null;
		let serverB: BridgeViewerOwnedViteProductServer | null = null;
		let browser: Browser | null = null;
		let page: Page | null = null;
		let primaryFailure: { readonly error: unknown } | null = null;
		try {
			serverA = await startBridgeViewerOwnedViteProductServer(fixture.oracle);
			await runAnnotationSaveJourney({ oracle: fixture.oracle, server: serverA, surface: 'file' });
			await runAnnotationSaveJourney({
				oracle: fixture.oracle,
				server: serverA,
				surface: 'review',
			});

			const backendPidA = serverA.backendPid;
			const cleanupA = await serverA.stop();
			expect(cleanupA.forcedTerminationRequired).toBe(false);
			expect(cleanupA.ownedProcessAliveAfterStop).toBe(false);
			serverA = null;

			serverB = await startBridgeViewerOwnedViteProductServer(fixture.oracle);
			browser = await chromium.launch({ channel: 'chrome', headless: true });
			page = await browser.newPage({ viewport: { height: 980, width: 1728 } });
			await page.goto(bridgeViewerViteProductFileUrl(serverB.origin), {
				timeout: annotationRestartJourneyTimeoutMilliseconds,
				waitUntil: 'domcontentloaded',
			});
			await waitForSelectedFileReady({ oracle: fixture.oracle, page });
			await page
				.getByText('File Save must settle from its exact command receipt.', { exact: true })
				.waitFor({ state: 'visible', timeout: annotationRestartJourneyTimeoutMilliseconds });

			await page.goto(bridgeViewerViteProductReviewUrl(serverB.origin), {
				timeout: annotationRestartJourneyTimeoutMilliseconds,
				waitUntil: 'domcontentloaded',
			});
			const reviewOriginFile = fixture.oracle.reviewFiles[0];
			if (reviewOriginFile === undefined) {
				throw new Error('Restart journey requires a Review-origin file.');
			}
			await selectReviewFile({ page, path: reviewOriginFile.path });
			await waitForSelectedReviewReady({ itemId: reviewOriginFile.itemId, page });
			await page
				.getByText('Review Save must settle from its exact command receipt.', { exact: true })
				.waitFor({ state: 'visible', timeout: annotationComposedConvergenceTimeoutMilliseconds });

			await page.goto(bridgeViewerViteProductFileUrl(serverB.origin, reviewOriginFile.path), {
				timeout: annotationRestartJourneyTimeoutMilliseconds,
				waitUntil: 'domcontentloaded',
			});
			await waitForFilePathReady({ page, path: reviewOriginFile.path });
			await page
				.getByText('Review Save must settle from its exact command receipt.', { exact: true })
				.waitFor({ state: 'visible', timeout: annotationComposedConvergenceTimeoutMilliseconds });
			expect(serverB.backendPid).not.toBe(backendPidA);
		} catch (error: unknown) {
			primaryFailure = { error };
		} finally {
			await runAllOwnedCleanupOperations({
				operations: [
					{
						name: 'cold-restart page',
						run: async (): Promise<void> => {
							await page?.close();
						},
					},
					{
						name: 'cold-restart browser',
						run: async (): Promise<void> => {
							await browser?.close();
						},
					},
					{
						name: 'cold-restart first product server',
						run: async (): Promise<void> => {
							if (serverA !== null) await stopOwnedProductServer(serverA);
						},
					},
					{
						name: 'cold-restart second product server',
						run: async (): Promise<void> => {
							if (serverB !== null) await stopOwnedProductServer(serverB);
						},
					},
					{ name: 'cold-restart fixture', run: fixture.dispose },
				],
				...(primaryFailure === null ? {} : { primaryError: primaryFailure.error }),
			});
		}
		// Named gap: this cold-stack journey does not prove a Swift-only restart while the
		// same Vite page and production comm worker reconnect. The current dev host recovers
		// backend health by reloading the document, which replaces that worker.
	});

	test('holds a promoted Review update for Apply now and auto-installs after focus leaves', async () => {
		const fixture = await createBridgeViewerViteProductFixture();
		let server: BridgeViewerOwnedViteProductServer | null = null;
		let browser: Browser | null = null;
		let page: Page | null = null;
		let primaryFailure: { readonly error: unknown } | null = null;
		try {
			server = await startBridgeViewerOwnedViteProductServer(fixture.oracle);
			browser = await chromium.launch({ channel: 'chrome', headless: true });
			page = await browser.newPage({ viewport: { height: 980, width: 1728 } });
			await page.goto(bridgeViewerViteProductReviewUrl(server.origin), {
				timeout: annotationRestartJourneyTimeoutMilliseconds,
				waitUntil: 'domcontentloaded',
			});
			const affectedFile = fixture.oracle.reviewFiles[0];
			const unaffectedFile = fixture.oracle.reviewFiles[1];
			if (affectedFile === undefined || unaffectedFile === undefined) {
				throw new Error('Promoted refresh journey requires two Review files.');
			}
			await selectReviewFile({ page, path: affectedFile.path });
			await waitForSelectedReviewReady({ itemId: affectedFile.itemId, page });
			const initialPackage = await requireReviewPackageIdentity(page);

			const firstAdvance = await fixture.advanceReviewedHeadByCommitCount(10);
			expect(firstAdvance.importedCommitCount).toBe(10);
			const promotedOutcome = await waitForPromotedReadyOrUnexpectedInstall({
				expectedTargetOID: firstAdvance.finalHeadOID,
				initialPackageId: initialPackage.packageId,
				page,
			});
			expect(promotedOutcome).toBe('updateReady');
			await page
				.getByText('Update ready', { exact: true })
				.waitFor({ state: 'visible', timeout: annotationComposedConvergenceTimeoutMilliseconds });
			expect(await requireReviewPackageIdentity(page)).toEqual(initialPackage);
			await selectRangeForAnnotation({ endLine: 5, page, startLine: 2, surface: 'review' });
			const rootCreateCommitted = waitForCommittedAnnotationCommand(page, 'root.create', 'review');
			const savedDuringHoldBody = 'A new root comment saved while the promoted refresh was held.';
			await page
				.getByRole('textbox', { name: 'Write an annotation in Markdown' })
				.fill(savedDuringHoldBody);
			await rootCreateCommitted;
			await page
				.locator('[data-testid="worktree-annotation-message"][data-annotation-draft="present"]')
				.waitFor({
					state: 'visible',
					timeout: annotationComposedConvergenceTimeoutMilliseconds,
				});
			await page.waitForFunction(
				(): boolean => {
					const saveButton = document.querySelector<HTMLButtonElement>(
						'[aria-label="Save annotation"]',
					);
					return saveButton !== null && !saveButton.disabled;
				},
				undefined,
				{ timeout: annotationComposedConvergenceTimeoutMilliseconds },
			);
			const draftSaveCommitted = waitForCommittedAnnotationCommand(page, 'draft.save', 'review');
			await Promise.all([
				draftSaveCommitted,
				page.getByRole('button', { name: 'Save annotation' }).click(),
			]);
			await page.getByText(savedDuringHoldBody, { exact: true }).waitFor({
				state: 'visible',
				timeout: annotationComposedConvergenceTimeoutMilliseconds,
			});
			const firstHeldCandidate = await waitForHeldCommitPromotionTelemetry({
				minimumGenerationExclusive: initialPackage.reviewGeneration,
				page,
			});
			const appliedReceiptResponse = page.waitForResponse(isReviewPublicationAppliedResponse, {
				timeout: annotationRestartJourneyTimeoutMilliseconds,
			});
			await page.getByRole('button', { name: 'Apply now' }).press('Enter');
			await requireCompletedReviewPublicationAppliedResponse(await appliedReceiptResponse);
			const appliedComparison = await waitForSettledReviewComparison({
				expectedTargetLabel: 'HEAD',
				expectedTargetOID: firstAdvance.finalHeadOID,
				page,
				timeoutMilliseconds: annotationRestartJourneyTimeoutMilliseconds,
			});
			expect(appliedComparison.packageId).not.toBe(initialPackage.packageId);
			expect(appliedComparison.reviewGeneration).toBeGreaterThanOrEqual(
				firstHeldCandidate.reviewGeneration,
			);
			await waitForSelectedReviewPathReady({ page, path: affectedFile.path });
			await page.getByText(savedDuringHoldBody, { exact: true }).waitFor({
				state: 'visible',
				timeout: annotationComposedConvergenceTimeoutMilliseconds,
			});
			await page.keyboard.press('Escape');
			await page
				.getByText('Update ready', { exact: true })
				.waitFor({ state: 'hidden', timeout: annotationRestartJourneyTimeoutMilliseconds });

			const secondAdvance = await fixture.advanceReviewedHeadByCommitCount(10);
			expect(secondAdvance).toMatchObject({
				importedCommitCount: 10,
				previousHeadOID: firstAdvance.finalHeadOID,
			});
			const secondPromotedOutcome = await waitForPromotedReadyOrUnexpectedInstall({
				expectedTargetOID: secondAdvance.finalHeadOID,
				initialPackageId: appliedComparison.packageId,
				page,
			});
			expect(secondPromotedOutcome).toBe('updateReady');
			await page
				.getByText('Update ready', { exact: true })
				.waitFor({ state: 'visible', timeout: annotationComposedConvergenceTimeoutMilliseconds });
			const secondHeldCandidate = await waitForHeldCommitPromotionTelemetry({
				minimumGenerationExclusive: appliedComparison.reviewGeneration,
				page,
			});
			await selectReviewFile({ page, path: unaffectedFile.path });
			await waitForSelectedReviewReady({ itemId: unaffectedFile.itemId, page });
			const automaticallyInstalledComparison = await waitForSettledReviewComparison({
				expectedTargetLabel: 'HEAD',
				expectedTargetOID: secondAdvance.finalHeadOID,
				page,
				timeoutMilliseconds: annotationRestartJourneyTimeoutMilliseconds,
			});
			expect(automaticallyInstalledComparison.reviewGeneration).toBeGreaterThanOrEqual(
				secondHeldCandidate.reviewGeneration,
			);
			expect(await page.getByText('Update ready', { exact: true }).count()).toBe(0);
		} catch (error: unknown) {
			primaryFailure = { error };
		} finally {
			await runAllOwnedCleanupOperations({
				operations: [
					{
						name: 'promoted-refresh page',
						run: async (): Promise<void> => {
							await page?.close();
						},
					},
					{
						name: 'promoted-refresh browser',
						run: async (): Promise<void> => {
							await browser?.close();
						},
					},
					{
						name: 'promoted-refresh product server',
						run: async (): Promise<void> => {
							if (server !== null) await stopOwnedProductServer(server);
						},
					},
					{ name: 'promoted-refresh fixture', run: fixture.dispose },
				],
				...(primaryFailure === null ? {} : { primaryError: primaryFailure.error }),
			});
		}
	});
}

async function stopOwnedProductServer(server: BridgeViewerOwnedViteProductServer): Promise<void> {
	const cleanup = await server.stop();
	if (cleanup.forcedTerminationRequired || cleanup.ownedProcessAliveAfterStop) {
		throw new Error(`Owned product server cleanup failed: ${JSON.stringify(cleanup)}.`);
	}
}

async function waitForPromotedReadyOrUnexpectedInstall(props: {
	readonly expectedTargetOID: string;
	readonly initialPackageId: string;
	readonly page: Page;
}): Promise<'installedWithoutHold' | 'updateReady'> {
	const handle = await props.page.waitForFunction(
		({
			expectedTargetOID,
			initialPackageId,
		}: {
			readonly expectedTargetOID: string;
			readonly initialPackageId: string;
		}): 'installedWithoutHold' | 'updateReady' | false => {
			const updateReady = [...document.querySelectorAll('*')].some(
				(element): boolean => element.textContent?.trim() === 'Update ready',
			);
			if (updateReady) return 'updateReady';
			const packageId = document
				.querySelector('[data-testid="review-viewer-shell"]')
				?.getAttribute('data-review-metadata-id');
			const targetOID = document
				.querySelector('[data-testid="bridge-review-comparison-current-state"]')
				?.getAttribute('data-resolved-target-oid');
			return packageId !== null &&
				packageId !== undefined &&
				packageId !== initialPackageId &&
				targetOID === expectedTargetOID
				? 'installedWithoutHold'
				: false;
		},
		{ expectedTargetOID: props.expectedTargetOID, initialPackageId: props.initialPackageId },
		{ timeout: annotationComposedConvergenceTimeoutMilliseconds },
	);
	const outcome = await handle.jsonValue();
	if (outcome === false) throw new Error('Promoted Review produced neither a hold nor an install.');
	return outcome;
}

function isReviewPublicationAppliedResponse(response: Response): boolean {
	const request = response.request();
	if (
		request.method() !== 'POST' ||
		new URL(request.url()).pathname !== '/__bridge-product/command'
	) {
		return false;
	}
	const body: unknown = request.postDataJSON();
	if (typeof body !== 'object' || body === null || Reflect.get(body, 'kind') !== 'product.call') {
		return false;
	}
	const call = Reflect.get(body, 'call');
	return (
		typeof call === 'object' &&
		call !== null &&
		Reflect.get(call, 'method') === 'review.publication.applied'
	);
}

async function requireCompletedReviewPublicationAppliedResponse(response: Response): Promise<void> {
	const body: unknown = await response.json();
	const call = typeof body === 'object' && body !== null ? Reflect.get(body, 'call') : null;
	if (
		!response.ok() ||
		typeof body !== 'object' ||
		body === null ||
		Reflect.get(body, 'kind') !== 'call.completed' ||
		typeof call !== 'object' ||
		call === null ||
		Reflect.get(call, 'method') !== 'review.publication.applied'
	) {
		throw new Error(`Review publication applied receipt did not complete: ${JSON.stringify(body)}`);
	}
}

async function waitForFilePathReady(props: {
	readonly page: Page;
	readonly path: string;
}): Promise<void> {
	await props.page.waitForFunction(
		(path: string): boolean => {
			const canvas = document.querySelector('[data-testid="bridge-file-viewer-code-canvas"]');
			return (
				canvas?.getAttribute('data-worktree-open-file-state') === 'ready' &&
				canvas.getAttribute('data-worktree-open-file-path') === path &&
				canvas.getAttribute('data-worktree-rendered-file-path') === path
			);
		},
		props.path,
		{ timeout: annotationRestartJourneyTimeoutMilliseconds },
	);
}

async function waitForSelectedReviewPathReady(props: {
	readonly page: Page;
	readonly path: string;
}): Promise<void> {
	await props.page.waitForFunction(
		(path: string): boolean => {
			const shell = document.querySelector('[data-testid="review-viewer-shell"]');
			return (
				shell?.getAttribute('data-selected-content-state') === 'ready' &&
				shell.getAttribute('data-selected-display-path') === path
			);
		},
		props.path,
		{ timeout: annotationRestartJourneyTimeoutMilliseconds },
	);
}

async function requireReviewPackageIdentity(page: Page): Promise<{
	readonly packageId: string;
	readonly reviewGeneration: number;
}> {
	const reviewShell = page.getByTestId('review-viewer-shell');
	const packageId = await reviewShell.getAttribute('data-review-metadata-id');
	const rawReviewGeneration = await reviewShell.getAttribute('data-review-metadata-generation');
	const reviewGeneration = Number(rawReviewGeneration);
	if (
		packageId === null ||
		packageId.length === 0 ||
		rawReviewGeneration === null ||
		!Number.isSafeInteger(reviewGeneration) ||
		reviewGeneration < 0
	) {
		throw new Error('Review shell did not expose its installed package identity.');
	}
	return { packageId, reviewGeneration };
}

async function waitForHeldCommitPromotionTelemetry(props: {
	readonly minimumGenerationExclusive: number;
	readonly page: Page;
}): Promise<{ readonly reviewGeneration: number }> {
	const statusUrl = new URL('/__bridge-dev-telemetry/status', props.page.url()).toString();
	let observation: { readonly reviewGeneration: number } | null = null;
	await expect
		.poll(
			async (): Promise<boolean> => {
				const response = await fetch(statusUrl, { cache: 'no-store' });
				if (!response.ok) return false;
				const body: unknown = await response.json();
				if (typeof body !== 'object' || body === null || !('recentSamples' in body)) return false;
				const recentSamples = body.recentSamples;
				if (!Array.isArray(recentSamples)) return false;
				for (const sample of recentSamples.toReversed()) {
					if (typeof sample !== 'object' || sample === null) continue;
					const stringAttributes = Reflect.get(sample, 'stringAttributes');
					const numericAttributes = Reflect.get(sample, 'numericAttributes');
					if (
						typeof stringAttributes !== 'object' ||
						stringAttributes === null ||
						typeof numericAttributes !== 'object' ||
						numericAttributes === null ||
						Reflect.get(stringAttributes, 'agentstudio.bridge.phase') !==
							'review_refresh_candidate_held' ||
						Reflect.get(
							stringAttributes,
							'agentstudio.bridge.review.refresh.presentation_class',
						) !== 'promoted' ||
						Reflect.get(stringAttributes, 'agentstudio.bridge.review.refresh.promotion_reason') !==
							'commits'
					) {
						continue;
					}
					const reviewGeneration = Reflect.get(
						numericAttributes,
						'agentstudio.bridge.review.generation',
					);
					if (
						typeof reviewGeneration === 'number' &&
						Number.isSafeInteger(reviewGeneration) &&
						reviewGeneration > props.minimumGenerationExclusive
					) {
						observation = { reviewGeneration };
						return true;
					}
				}
				return false;
			},
			{ timeout: annotationComposedConvergenceTimeoutMilliseconds },
		)
		.toBe(true);
	if (observation === null) {
		throw new Error('Review candidate did not emit held commit-promotion telemetry.');
	}
	return observation;
}
