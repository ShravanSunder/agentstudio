import { chromium, type JSHandle, type Page, type Request } from 'playwright';
import { describe, expect, test } from 'vitest';

import { runAllOwnedCleanupOperations } from '../../scripts/dev-server/bridge-development-server-process.ts';
import {
	selectReviewFile,
	waitForSelectedReviewReady,
} from './bridge-viewer-vite-annotation-save-journey.ts';
import {
	createBridgeViewerViteProductFixture,
	startBridgeViewerOwnedViteProductServer,
} from './bridge-viewer-vite-product-fixture.ts';
import { bridgeViewerViteProductReviewUrl } from './bridge-viewer-vite-product-url.ts';
import { waitForSettledReviewComparison } from './bridge-viewer-vite-review-comparison-observation.ts';

const proportionalRefreshTimeoutMilliseconds = 120_000;
const proportionalRefreshConvergenceTimeoutMilliseconds = 30_000;
const retiredAndSuccessorAffectedFileIdentityCount = 2;

interface ReviewContentRequestObservation {
	readonly itemId: string | null;
	readonly responseStatus: number | null;
}

interface ReviewRefreshCandidateReadyObservation {
	readonly affectedStableFileCount: number;
	readonly presentationClass: string;
	readonly reviewGeneration: number;
}

describe('Bridge Viewer proportional Review refresh E2E', () => {
	test(
		'keeps an unchanged selected item mounted without unrelated content opens after one changed worktree file',
		async () => {
			const fixture = await createBridgeViewerViteProductFixture();
			let server: Awaited<ReturnType<typeof startBridgeViewerOwnedViteProductServer>> | null = null;
			const browser = await chromium.launch({ channel: 'chrome', headless: true });
			let page: Page | null = null;
			let primaryFailure: { readonly error: unknown } | null = null;
			try {
				server = await startBridgeViewerOwnedViteProductServer(fixture.oracle);
				page = await browser.newPage({ viewport: { height: 980, width: 1728 } });
				const reviewContentRequests = observeReviewContentRequests(page);
				await page.goto(bridgeViewerViteProductReviewUrl(server.origin), {
					timeout: proportionalRefreshTimeoutMilliseconds,
					waitUntil: 'domcontentloaded',
				});
				const affectedFile = fixture.oracle.reviewFiles[0];
				const unchangedFile = fixture.oracle.reviewFiles[1];
				if (affectedFile === undefined || unchangedFile === undefined) {
					throw new Error('Proportional Review refresh fixture requires two changed files.');
				}
				const initialComparison = await waitForSettledReviewComparison({
					expectedTargetLabel: 'HEAD',
					expectedTargetOID: fixture.oracle.baseRef,
					page,
					timeoutMilliseconds: proportionalRefreshTimeoutMilliseconds,
				});
				await selectReviewFile({ page, path: unchangedFile.path });
				await waitForSelectedReviewReady({ itemId: unchangedFile.itemId, page });
				const unchangedPaintedContainer = await waitForPaintedReviewItemContainer({
					itemId: unchangedFile.itemId,
					page,
				});
				const contentRequestCountBeforeRefresh = reviewContentRequests.length;

				const reviewMutation = await fixture.mutateReviewFile();
				let refreshedIdentity: Awaited<ReturnType<typeof waitForReviewRevision>>;
				try {
					refreshedIdentity = await waitForReviewRevision({
						page,
						predecessor: initialComparison,
					});
				} catch (error: unknown) {
					throw new Error(
						`Review worktree mutation did not advance the installed revision: ${JSON.stringify({
							lifecycle: await reviewRefreshLifecycleSamples(page),
							server: server.diagnostics(),
						})}`,
						{ cause: error },
					);
				}
				const refreshedComparison = await waitForSettledReviewComparison({
					expectedTargetLabel: 'HEAD',
					expectedTargetOID: fixture.oracle.baseRef,
					page,
					timeoutMilliseconds: proportionalRefreshTimeoutMilliseconds,
				});
				await waitForSelectedReviewReady({ itemId: unchangedFile.itemId, page });
				const candidateReady = await waitForReviewRefreshCandidateReady({
					affectedStableFileCount: retiredAndSuccessorAffectedFileIdentityCount,
					page,
					reviewGeneration: initialComparison.reviewGeneration,
				});
				const unchangedContainerRetained = await reviewItemContainerMatchesHandle({
					handle: unchangedPaintedContainer,
					itemId: unchangedFile.itemId,
					page,
				});
				const refreshContentRequests = reviewContentRequests.slice(
					contentRequestCountBeforeRefresh,
				);

				expect(reviewMutation.path).toBe(affectedFile.path);
				expect(refreshedComparison.packageId).toBe(initialComparison.packageId);
				expect(refreshedComparison.reviewGeneration).toBe(initialComparison.reviewGeneration);
				expect(refreshedComparison.revision).toBe(refreshedIdentity.revision);
				expect(candidateReady).toEqual({
					affectedStableFileCount: retiredAndSuccessorAffectedFileIdentityCount,
					presentationClass: 'ordinary',
					reviewGeneration: initialComparison.reviewGeneration,
				});
				expect(unchangedContainerRetained).toBe(true);
				expect(
					refreshContentRequests.every(
						(request): boolean =>
							request.itemId !== null &&
							request.itemId !== unchangedFile.itemId &&
							request.responseStatus === 200,
					),
				).toBe(true);
				expect(
					refreshContentRequests.some(
						(request): boolean => request.itemId === unchangedFile.itemId,
					),
				).toBe(false);
			} catch (error: unknown) {
				primaryFailure = { error };
			} finally {
				await runAllOwnedCleanupOperations({
					operations: [
						{
							name: 'proportional Review refresh page',
							run: async (): Promise<void> => {
								await page?.close();
							},
						},
						{
							name: 'proportional Review refresh browser',
							run: async (): Promise<void> => {
								await browser.close();
							},
						},
						{
							name: 'proportional Review refresh server',
							run: async (): Promise<void> => {
								await server?.stop();
							},
						},
						{ name: 'proportional Review refresh fixture', run: fixture.dispose },
					],
					...(primaryFailure === null ? {} : { primaryError: primaryFailure.error }),
				});
			}
		},
		proportionalRefreshTimeoutMilliseconds,
	);
});

function observeReviewContentRequests(page: Page): ReviewContentRequestObservation[] {
	const observations: ReviewContentRequestObservation[] = [];
	const observationByRequest = new WeakMap<Request, number>();
	page.on('request', (request): void => {
		if (
			request.method() !== 'POST' ||
			new URL(request.url()).pathname !== '/__bridge-product/content'
		)
			return;
		const body: unknown = request.postDataJSON();
		if (!isUnknownRecord(body) || body['contentKind'] !== 'review.content') return;
		const descriptor = body['descriptor'];
		const itemId = isUnknownRecord(descriptor) ? descriptor['itemId'] : null;
		observationByRequest.set(
			request,
			observations.push({
				itemId: typeof itemId === 'string' ? itemId : null,
				responseStatus: null,
			}) - 1,
		);
	});
	page.on('response', (response): void => {
		const observationIndex = observationByRequest.get(response.request());
		if (observationIndex === undefined) return;
		const observation = observations[observationIndex];
		if (observation === undefined) return;
		observations[observationIndex] = { ...observation, responseStatus: response.status() };
	});
	return observations;
}

async function waitForReviewRevision(props: {
	readonly page: Page;
	readonly predecessor: {
		readonly packageId: string;
		readonly reviewGeneration: number;
		readonly revision: number;
	};
}): Promise<{
	readonly packageId: string;
	readonly reviewGeneration: number;
	readonly revision: number;
}> {
	let currentIdentity = props.predecessor;
	await expect
		.poll(
			async (): Promise<boolean> => {
				const reviewShell = props.page.getByTestId('review-viewer-shell');
				const packageId = await reviewShell.getAttribute('data-review-metadata-id');
				const reviewGeneration = Number(
					await reviewShell.getAttribute('data-review-metadata-generation'),
				);
				const revision = Number(await reviewShell.getAttribute('data-review-metadata-revision'));
				if (
					packageId === null ||
					!Number.isSafeInteger(reviewGeneration) ||
					!Number.isSafeInteger(revision)
				) {
					return false;
				}
				currentIdentity = { packageId, reviewGeneration, revision };
				return (
					packageId === props.predecessor.packageId &&
					reviewGeneration === props.predecessor.reviewGeneration &&
					revision > props.predecessor.revision
				);
			},
			{ timeout: proportionalRefreshConvergenceTimeoutMilliseconds },
		)
		.toBe(true);
	return currentIdentity;
}

async function waitForReviewRefreshCandidateReady(props: {
	readonly affectedStableFileCount: number;
	readonly page: Page;
	readonly reviewGeneration: number;
}): Promise<ReviewRefreshCandidateReadyObservation> {
	const statusUrl = new URL('/__bridge-dev-telemetry/status', props.page.url()).toString();
	let observation: ReviewRefreshCandidateReadyObservation | null = null;
	try {
		await expect
			.poll(
				async (): Promise<boolean> => {
					observation = await readReviewRefreshCandidateReady(statusUrl, props);
					return observation !== null;
				},
				{ timeout: proportionalRefreshConvergenceTimeoutMilliseconds },
			)
			.toBe(true);
	} catch (error: unknown) {
		throw new Error(
			`Review refresh did not emit the exact proportional candidate: ${JSON.stringify(
				await reviewRefreshLifecycleSamples(props.page),
			)}`,
			{ cause: error },
		);
	}
	if (observation === null) {
		throw new Error('Review refresh telemetry has no exact candidate-ready lifecycle sample.');
	}
	return observation;
}

async function readReviewRefreshCandidateReady(
	statusUrl: string,
	expected: {
		readonly affectedStableFileCount: number;
		readonly reviewGeneration: number;
	},
): Promise<ReviewRefreshCandidateReadyObservation | null> {
	const response = await fetch(statusUrl, { cache: 'no-store' });
	if (!response.ok) {
		return null;
	}
	const body: unknown = await response.json();
	if (!isUnknownRecord(body) || !Array.isArray(body['recentSamples'])) {
		return null;
	}
	for (const sample of body['recentSamples'].toReversed()) {
		if (
			!isUnknownRecord(sample) ||
			sample['name'] !== 'performance.bridge.web.review_refresh_lifecycle'
		) {
			continue;
		}
		const stringAttributes = sample['stringAttributes'];
		const numericAttributes = sample['numericAttributes'];
		if (
			!isUnknownRecord(stringAttributes) ||
			stringAttributes['agentstudio.bridge.phase'] !== 'review_refresh_candidate_ready' ||
			!isUnknownRecord(numericAttributes)
		) {
			continue;
		}
		const affectedStableFileCount =
			numericAttributes['agentstudio.bridge.review.refresh.affected_stable_file.count'];
		const presentationClass =
			stringAttributes['agentstudio.bridge.review.refresh.presentation_class'];
		const reviewGeneration = numericAttributes['agentstudio.bridge.review.generation'];
		if (
			typeof affectedStableFileCount === 'number' &&
			affectedStableFileCount === expected.affectedStableFileCount &&
			typeof presentationClass === 'string' &&
			presentationClass === 'ordinary' &&
			typeof reviewGeneration === 'number' &&
			reviewGeneration === expected.reviewGeneration
		) {
			return { affectedStableFileCount, presentationClass, reviewGeneration };
		}
	}
	return null;
}

async function reviewRefreshLifecycleSamples(
	page: Page,
): Promise<readonly Readonly<Record<string, unknown>>[]> {
	const statusUrl = new URL('/__bridge-dev-telemetry/status', page.url()).toString();
	const response = await fetch(statusUrl, { cache: 'no-store' });
	if (!response.ok) return [{ status: response.status }];
	const body: unknown = await response.json();
	if (!isUnknownRecord(body) || !Array.isArray(body['recentSamples'])) {
		return [{ status: 'missing-samples' }];
	}
	return body['recentSamples']
		.filter(
			(sample): boolean =>
				isUnknownRecord(sample) &&
				sample['name'] === 'performance.bridge.web.review_refresh_lifecycle',
		)
		.slice(-16)
		.map((sample): Readonly<Record<string, unknown>> => {
			if (!isUnknownRecord(sample)) return {};
			const numericAttributes = sample['numericAttributes'];
			const stringAttributes = sample['stringAttributes'];
			return {
				affectedStableFileCount: isUnknownRecord(numericAttributes)
					? numericAttributes['agentstudio.bridge.review.refresh.affected_stable_file.count']
					: null,
				generation: isUnknownRecord(numericAttributes)
					? numericAttributes['agentstudio.bridge.review.generation']
					: null,
				phase: isUnknownRecord(stringAttributes)
					? stringAttributes['agentstudio.bridge.phase']
					: null,
				presentationClass: isUnknownRecord(stringAttributes)
					? stringAttributes['agentstudio.bridge.review.refresh.presentation_class']
					: null,
			};
		});
}

async function waitForPaintedReviewItemContainer(props: {
	readonly itemId: string;
	readonly page: Page;
}): Promise<JSHandle<Element | null>> {
	return await props.page.waitForFunction(
		(itemId: string): Element | null => {
			for (const container of document.querySelectorAll(
				'diffs-container[data-bridge-painted-source-correlations]',
			)) {
				const encodedCorrelations = container.getAttribute(
					'data-bridge-painted-source-correlations',
				);
				if (encodedCorrelations === null) continue;
				let correlations: unknown;
				try {
					correlations = JSON.parse(encodedCorrelations);
				} catch {
					continue;
				}
				if (
					Array.isArray(correlations) &&
					correlations.some(
						(correlation): boolean =>
							typeof correlation === 'object' &&
							correlation !== null &&
							'itemId' in correlation &&
							correlation.itemId === itemId,
					)
				)
					return container;
			}
			return null;
		},
		props.itemId,
		{ timeout: proportionalRefreshTimeoutMilliseconds },
	);
}

async function reviewItemContainerMatchesHandle(props: {
	readonly handle: Awaited<ReturnType<typeof waitForPaintedReviewItemContainer>>;
	readonly itemId: string;
	readonly page: Page;
}): Promise<boolean> {
	return await props.handle.evaluate((initialContainer, itemId): boolean => {
		for (const container of document.querySelectorAll(
			'diffs-container[data-bridge-painted-source-correlations]',
		)) {
			const encodedCorrelations = container.getAttribute('data-bridge-painted-source-correlations');
			if (encodedCorrelations === null) continue;
			let correlations: unknown;
			try {
				correlations = JSON.parse(encodedCorrelations);
			} catch {
				continue;
			}
			if (
				Array.isArray(correlations) &&
				correlations.some(
					(correlation): boolean =>
						typeof correlation === 'object' &&
						correlation !== null &&
						'itemId' in correlation &&
						correlation.itemId === itemId,
				)
			)
				return initialContainer === container;
		}
		return false;
	}, props.itemId);
}

function isUnknownRecord(value: unknown): value is Readonly<Record<string, unknown>> {
	return typeof value === 'object' && value !== null && !Array.isArray(value);
}
