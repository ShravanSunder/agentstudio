import type { Page, Route } from 'playwright';
import { z } from 'zod';

import {
	bridgeWorktreeDevFileContentRouteMatchesHandle,
	bridgeWorktreeDevFileContentRouteUsesOrigin,
} from '../bridge-worktree-dev-reload-diagnostics.ts';
import {
	buildReviewContentRouteDeltaProof,
	reviewContentRouteDeltaSatisfied,
	type ReviewContentRouteDeltaProof,
	type ReviewMetadataBeforeContentProof,
} from '../verify-bridge-viewer-worktree-review-proof.ts';
import {
	scenarioNameFromDevServerUrl,
	worktreeDevServerOrigin,
	worktreeReviewDevServerUrl,
} from './config.ts';
import {
	normalWorktreeReviewPerformanceClickTargets,
	worktreeFilePathEligibleForPerformanceClick,
} from './scroll-performance.ts';
import {
	bridgeDevTelemetryStatusSchema,
	worktreeReviewMetadataFrameResponseSchema,
	type BridgeDevTelemetryStatusSample,
	type ReviewPerformanceClickTarget,
	type ReviewRouteProbe,
	type WorktreeBridgeTelemetrySampleProof,
	type WorktreeFileContentRouteProbe,
	type WorktreeReviewRouteProof,
} from './types.ts';
import type { Deferred } from './utils.ts';

export async function readBridgeWorktreeVerifierTelemetrySamples(
	page: Page,
): Promise<readonly WorktreeBridgeTelemetrySampleProof[]> {
	return await page.evaluate(
		(): readonly WorktreeBridgeTelemetrySampleProof[] =>
			window.bridgeWorktreeVerifierTelemetrySamples ?? [],
	);
}

export async function readBridgeDevTelemetryStatusSamples(
	page: Page,
): Promise<readonly WorktreeBridgeTelemetrySampleProof[]> {
	const response = await page.request.get(
		new URL('/__bridge-dev-telemetry/status', page.url()).toString(),
	);
	const responseBody = await response.json();
	const parsedStatus = bridgeDevTelemetryStatusSchema.safeParse(responseBody);
	if (!parsedStatus.success) {
		throw new Error('Bridge dev telemetry status endpoint returned an invalid contract');
	}
	return parsedStatus.data.recentSamples.map(mapBridgeTelemetrySampleToProof);
}

export function mapBridgeTelemetrySampleToProof(
	sample: BridgeDevTelemetryStatusSample,
): WorktreeBridgeTelemetrySampleProof {
	return {
		durationMilliseconds: sample.durationMilliseconds,
		name: sample.name,
		numericAttributes: sample.numericAttributes,
		phase: sample.stringAttributes['agentstudio.bridge.phase'] ?? null,
		result: sample.stringAttributes['agentstudio.bridge.result'] ?? null,
		slice: sample.stringAttributes['agentstudio.bridge.slice'] ?? null,
		transport: sample.stringAttributes['agentstudio.bridge.transport'] ?? null,
		viewer: sample.stringAttributes['agentstudio.bridge.viewer'] ?? null,
	};
}

export async function installFileContentRouteGate(props: {
	readonly gate: Deferred<void>;
	readonly failFirstHit?: boolean;
	readonly failFirstHitContentHandle?: string;
	readonly page: Page;
	readonly pathPattern?: string;
}): Promise<WorktreeFileContentRouteProbe> {
	const hitUrls: string[] = [];
	const foreignHitUrls: string[] = [];
	const pathPattern = props.pathPattern ?? '**/__bridge-worktree/file-content/**';
	let failedFirstHit = false;
	const routeHandler = async (route: Route): Promise<void> => {
		const requestUrl = route.request().url();
		if (
			!bridgeWorktreeDevFileContentRouteUsesOrigin({
				expectedOrigin: worktreeDevServerOrigin,
				url: requestUrl,
			})
		) {
			foreignHitUrls.push(requestUrl);
			await route.fulfill({
				status: 599,
				contentType: 'text/plain',
				body: `foreign Worktree/File content route origin rejected: ${requestUrl}`,
			});
			return;
		}
		hitUrls.push(requestUrl);
		const failFirstHitMatchesRequest =
			props.failFirstHitContentHandle === undefined ||
			bridgeWorktreeDevFileContentRouteMatchesHandle({
				expectedContentHandle: props.failFirstHitContentHandle,
				expectedOrigin: worktreeDevServerOrigin,
				url: requestUrl,
			});
		if (props.failFirstHit === true && !failedFirstHit && failFirstHitMatchesRequest) {
			failedFirstHit = true;
			await route.fulfill({
				status: 503,
				contentType: 'text/plain',
				body: 'forced refresh failure for Gate 0.a retry proof',
			});
			return;
		}
		await props.gate.promise;
		await route.continue();
	};
	await props.page.route(pathPattern, routeHandler);
	return {
		dispose: async (): Promise<void> => {
			await props.page.unroute(pathPattern, routeHandler);
		},
		foreignHitCount: (): number => foreignHitUrls.length,
		foreignHitUrls: (): readonly string[] => foreignHitUrls,
		hitCount: (): number => hitUrls.length,
		hitUrls: (): readonly string[] => hitUrls,
	};
}

export async function installReviewRouteProbe(
	page: Page,
	options: { readonly contentGate?: Deferred<void> } = {},
): Promise<ReviewRouteProbe> {
	const metadataHitUrls: string[] = [];
	const contentHitUrls: string[] = [];
	const metadataRoutePattern = '**/__bridge-worktree/review-metadata**';
	const contentRoutePattern = '**/__bridge-worktree/review-content/**';
	const assertReviewRouteOrigin = async (route: Route): Promise<boolean> => {
		const requestUrl = route.request().url();
		if (bridgeWorktreeDevReviewRouteUsesOrigin(requestUrl)) {
			return true;
		}
		await route.fulfill({
			status: 599,
			contentType: 'text/plain',
			body: `foreign Worktree/Review route origin rejected: ${requestUrl}`,
		});
		return false;
	};
	const metadataRouteHandler = async (route: Route): Promise<void> => {
		if (!(await assertReviewRouteOrigin(route))) {
			return;
		}
		metadataHitUrls.push(route.request().url());
		await route.continue();
	};
	const contentRouteHandler = async (route: Route): Promise<void> => {
		if (!(await assertReviewRouteOrigin(route))) {
			return;
		}
		contentHitUrls.push(route.request().url());
		if (options.contentGate !== undefined) {
			await options.contentGate.promise;
		}
		await route.continue();
	};
	await page.route(metadataRoutePattern, metadataRouteHandler);
	await page.route(contentRoutePattern, contentRouteHandler);
	return {
		contentHitCount: (): number => contentHitUrls.length,
		contentHitUrls: (): readonly string[] => contentHitUrls,
		dispose: async (): Promise<void> => {
			await page.unroute(metadataRoutePattern, metadataRouteHandler);
			await page.unroute(contentRoutePattern, contentRouteHandler);
		},
		metadataHitCount: (): number => metadataHitUrls.length,
		metadataHitUrls: (): readonly string[] => metadataHitUrls,
	};
}

export async function waitForReviewMetadataBeforeContentStartupProof(props: {
	readonly page: Page;
	readonly routeProbe: ReviewRouteProbe;
}): Promise<ReviewMetadataBeforeContentProof> {
	await waitForReviewContentRouteHitCountAbove({
		minHitCount: 1,
		routeProbe: props.routeProbe,
	});
	try {
		await props.page.waitForFunction(
			(): boolean => {
				const proof = window.bridgeWorktreeReviewMetadataBeforeContentProof();
				return (
					proof.treeVisibleWhileBlocked &&
					proof.treeVisibleRowCountWhileBlocked > 0 &&
					proof.selectedDisplayPathWhileBlocked !== null &&
					proof.selectedContentStateWhileBlocked !== 'ready'
				);
			},
			undefined,
			{ timeout: 30_000 },
		);
	} catch (error) {
		const diagnostic = await props.page.evaluate(() =>
			window.bridgeWorktreeReviewMetadataBeforeContentProof(),
		);
		throw new Error(
			`Timed out waiting for Worktree/Review metadata projection before content completion: ${JSON.stringify(diagnostic)}`,
			{ cause: error },
		);
	}
	const domProof = await props.page.evaluate(() =>
		window.bridgeWorktreeReviewMetadataBeforeContentProof(),
	);
	return {
		...domProof,
		blockedContentHitCount: props.routeProbe.contentHitCount(),
		metadataHitCount: props.routeProbe.metadataHitCount(),
	};
}

export async function fetchWorktreeReviewItemIdForDisplayPath(
	displayPath: string,
): Promise<string> {
	let metadataFrameResponse = await fetchWorktreeReviewMetadataFrame();
	let inspectedItemCount = 0;
	for (;;) {
		inspectedItemCount += metadataFrameResponse.protocolFrame.itemMetadata.length;
		const item = metadataFrameResponse.protocolFrame.itemMetadata.find(
			(candidate): boolean =>
				candidate.basePath === displayPath || candidate.headPath === displayPath,
		);
		if (item !== undefined) {
			return item.itemId;
		}
		const nextWindowCursor = metadataFrameResponse.nextWindowCursor ?? null;
		if (nextWindowCursor === null) {
			break;
		}
		metadataFrameResponse = await fetchWorktreeReviewMetadataWindowFrame(nextWindowCursor);
	}
	throw new Error(
		`Expected Worktree/Review metadata to include ${displayPath}; got ${inspectedItemCount} items`,
	);
}

export async function fetchWorktreeReviewPerformanceClickTargets(): Promise<
	readonly ReviewPerformanceClickTarget[]
> {
	let metadataFrameResponse = await fetchWorktreeReviewMetadataFrame();
	const displayPathByItemId = new Map<string, string>();
	const lineCountByItemId = new Map<string, number>();
	for (;;) {
		for (const row of metadataFrameResponse.protocolFrame.treeRows ?? []) {
			if (!row.isDirectory && worktreeFilePathEligibleForPerformanceClick(row.path)) {
				displayPathByItemId.set(row.itemId, row.path);
			}
		}
		for (const fact of metadataFrameResponse.protocolFrame.extentFacts ?? []) {
			lineCountByItemId.set(
				fact.itemId,
				(lineCountByItemId.get(fact.itemId) ?? 0) + fact.lineCount,
			);
		}
		const nextWindowCursor = metadataFrameResponse.nextWindowCursor ?? null;
		if (nextWindowCursor === null) {
			break;
		}
		metadataFrameResponse = await fetchWorktreeReviewMetadataWindowFrame(nextWindowCursor);
	}
	return normalWorktreeReviewPerformanceClickTargets(
		[...displayPathByItemId.entries()].map(
			([itemId, displayPath]): ReviewPerformanceClickTarget => ({
				displayPath,
				lineCount: lineCountByItemId.get(itemId) ?? null,
			}),
		),
	);
}

export async function fetchWorktreeReviewMetadataFrame(): Promise<
	z.infer<typeof worktreeReviewMetadataFrameResponseSchema>
> {
	const frameUrl = new URL('/__bridge-worktree/review-metadata', worktreeReviewDevServerUrl);
	frameUrl.searchParams.set('scenario', scenarioNameFromDevServerUrl(worktreeReviewDevServerUrl));
	frameUrl.searchParams.set('frame', 'review-metadata-snapshot');
	const response = await fetch(frameUrl);
	if (!response.ok) {
		throw new Error(`Expected Worktree/Review metadata frame route, got ${response.status}`);
	}
	return worktreeReviewMetadataFrameResponseSchema.parse(await response.json());
}

export function requireWorktreeReviewComparisonProof(
	metadataFrameResponse: z.infer<typeof worktreeReviewMetadataFrameResponseSchema>,
): Pick<
	WorktreeReviewRouteProof,
	| 'reviewMetadataBaseEndpointId'
	| 'reviewMetadataBaseEndpointKind'
	| 'reviewMetadataBaseProviderIdentity'
	| 'reviewMetadataHeadEndpointId'
	| 'reviewMetadataHeadEndpointKind'
	| 'reviewMetadataHeadProviderIdentity'
> {
	const comparison = metadataFrameResponse.protocolFrame.comparison;
	if (comparison === undefined) {
		throw new Error('Expected Worktree/Review metadata snapshot to include comparison identity');
	}
	return {
		reviewMetadataBaseEndpointId: comparison.baseEndpoint.endpointId,
		reviewMetadataBaseEndpointKind: comparison.baseEndpoint.kind,
		reviewMetadataBaseProviderIdentity: comparison.baseEndpoint.providerIdentity,
		reviewMetadataHeadEndpointId: comparison.headEndpoint.endpointId,
		reviewMetadataHeadEndpointKind: comparison.headEndpoint.kind,
		reviewMetadataHeadProviderIdentity: comparison.headEndpoint.providerIdentity,
	};
}

export async function fetchWorktreeReviewMetadataWindowFrame(
	cursor: string,
): Promise<z.infer<typeof worktreeReviewMetadataFrameResponseSchema>> {
	const frameUrl = new URL('/__bridge-worktree/review-metadata', worktreeReviewDevServerUrl);
	frameUrl.searchParams.set('scenario', scenarioNameFromDevServerUrl(worktreeReviewDevServerUrl));
	frameUrl.searchParams.set('frame', 'review-metadata-window');
	frameUrl.searchParams.set('cursor', cursor);
	const response = await fetch(frameUrl);
	if (!response.ok) {
		throw new Error(`Expected Worktree/Review metadata window route, got ${response.status}`);
	}
	return worktreeReviewMetadataFrameResponseSchema.parse(await response.json());
}

export function bridgeWorktreeDevReviewRouteUsesOrigin(url: string): boolean {
	let parsedUrl: URL;
	try {
		parsedUrl = new URL(url);
	} catch {
		return false;
	}
	return (
		parsedUrl.origin === worktreeDevServerOrigin &&
		(parsedUrl.pathname === '/__bridge-worktree/review-metadata' ||
			parsedUrl.pathname.startsWith('/__bridge-worktree/review-content/'))
	);
}

export async function waitForReviewContentRouteHitContaining(props: {
	readonly needle: string;
	readonly remainingAttempts?: number;
	readonly routeProbe: ReviewRouteProbe;
}): Promise<void> {
	const remainingAttempts = props.remainingAttempts ?? 1_000;
	if (props.routeProbe.contentHitUrls().some((url) => url.includes(props.needle))) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error(
			`Timed out waiting for Worktree/Review content route hit containing ${props.needle}: ${JSON.stringify(props.routeProbe.contentHitUrls())}`,
		);
	}
	await new Promise<void>((resolve): void => {
		setTimeout(resolve, 10);
	});
	await waitForReviewContentRouteHitContaining({
		needle: props.needle,
		remainingAttempts: remainingAttempts - 1,
		routeProbe: props.routeProbe,
	});
}

export async function waitForReviewContentRouteHitCountAbove(props: {
	readonly minHitCount: number;
	readonly remainingAttempts?: number;
	readonly routeProbe: ReviewRouteProbe;
}): Promise<void> {
	const remainingAttempts = props.remainingAttempts ?? 1_000;
	if (props.routeProbe.contentHitCount() >= props.minHitCount) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error(
			`Timed out waiting for Worktree/Review content route hit count ${props.minHitCount}; observed ${props.routeProbe.contentHitCount()}: ${JSON.stringify(props.routeProbe.contentHitUrls())}`,
		);
	}
	await new Promise<void>((resolve): void => {
		setTimeout(resolve, 10);
	});
	await waitForReviewContentRouteHitCountAbove({
		minHitCount: props.minHitCount,
		remainingAttempts: remainingAttempts - 1,
		routeProbe: props.routeProbe,
	});
}

export async function waitForReviewContentRouteHitAfterIndex(props: {
	readonly beforeHitCount: number;
	readonly expectedItemId: string;
	readonly remainingAttempts?: number;
	readonly routeProbe: ReviewRouteProbe;
}): Promise<ReviewContentRouteDeltaProof> {
	const routeProof = buildReviewContentRouteDeltaProof({
		allHitUrls: props.routeProbe.contentHitUrls(),
		beforeHitCount: props.beforeHitCount,
		expectedItemId: props.expectedItemId,
	});
	if (reviewContentRouteDeltaSatisfied(routeProof)) {
		return routeProof;
	}
	const remainingAttempts = props.remainingAttempts ?? 1_000;
	if (remainingAttempts <= 0) {
		throw new Error(
			`Timed out waiting for post-click Worktree/Review content route hit for ${props.expectedItemId}: ${JSON.stringify(routeProof)}`,
		);
	}
	await new Promise<void>((resolve): void => {
		setTimeout(resolve, 10);
	});
	return waitForReviewContentRouteHitAfterIndex({
		beforeHitCount: props.beforeHitCount,
		expectedItemId: props.expectedItemId,
		remainingAttempts: remainingAttempts - 1,
		routeProbe: props.routeProbe,
	});
}
