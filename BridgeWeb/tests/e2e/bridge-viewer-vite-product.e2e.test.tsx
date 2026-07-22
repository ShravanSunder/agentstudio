import { chromium, type Page, type Request } from 'playwright';
import { afterAll, beforeAll, describe, expect, test } from 'vitest';

import {
	collectBridgeViewerProductOnlyContractViolations,
	type BridgeViewerProductOnlyJourneyProof,
} from '../../scripts/verify-bridge-viewer-worktree-dev-server/product-only-real-router-contract.ts';
import { runBridgeViewerProductOnlyJourney } from '../../scripts/verify-bridge-viewer-worktree-dev-server/product-only-real-router-page.ts';
import {
	createBridgeViewerViteProductFixture,
	startBridgeViewerOwnedViteProductServer,
	type BridgeViewerOwnedViteProductServer,
	type BridgeViewerOwnedViteProductServerCleanup,
	type BridgeViewerViteProductContentOracle,
	type BridgeViewerViteProductFixtureOracle,
	type BridgeViewerViteProductReviewFileOracle,
} from './bridge-viewer-vite-product-fixture.ts';

const productJourneyTimeoutMilliseconds = 120_000;

interface PaintedSourceCorrelation {
	readonly descriptorId: string;
	readonly disposition: string;
	readonly itemId: string;
	readonly observedSha256: string;
	readonly pierreItemId: string;
	readonly position: string;
	readonly publicationId: string;
	readonly requestId: string;
	readonly role: string;
	readonly semanticItemId: string;
	readonly sourceGeneration: number;
	readonly sourceIdentity: string;
	readonly surface: string;
}

interface FileDeepScrollProof {
	readonly deepTreePathPainted: boolean;
	readonly finalMarkerPainted: boolean;
	readonly lineCount: number;
	readonly paintedCorrelations: readonly PaintedSourceCorrelation[];
	readonly renderedItemId: string | null;
	readonly renderedPath: string | null;
	readonly scrollHeight: number;
	readonly scrollTop: number;
	readonly selectedPath: string | null;
	readonly treeScrollTop: number;
	readonly workerUrls: readonly string[];
}

interface FileDeepScrollBrowserSnapshot extends Omit<FileDeepScrollProof, 'paintedCorrelations'> {
	readonly encodedPaintedCorrelations: string;
}

interface ProductContentRequestObservation {
	readonly contentKind: string;
	readonly contentRequestId: string;
	readonly descriptor: Readonly<Record<string, unknown>>;
	readonly leaseId: string;
	responseStatus: number | null;
}

interface ReviewSelectionProof {
	readonly bodyText: string;
	readonly paintedCorrelations: readonly PaintedSourceCorrelation[];
	readonly paintedPublicationId: string | null;
}

interface FileContentScrollProof {
	readonly finalMarkerPainted: boolean;
	readonly firstMarkerPainted: boolean;
	readonly middleMarkerPainted: boolean;
}

let disposeFixture: (() => Promise<void>) | null = null;
let fixtureOracle: BridgeViewerViteProductFixtureOracle | null = null;
let mutateLargeFileFixture: (() => Promise<BridgeViewerViteProductContentOracle>) | null = null;
let ownedServer: BridgeViewerOwnedViteProductServer | null = null;
let ownedServerCleanup: BridgeViewerOwnedViteProductServerCleanup | null = null;

describe('Bridge Viewer dedicated Vite product E2E', () => {
	beforeAll(async (): Promise<void> => {
		const fixture = await createBridgeViewerViteProductFixture();
		disposeFixture = fixture.dispose;
		fixtureOracle = fixture.oracle;
		mutateLargeFileFixture = fixture.mutateLargeFile;
		ownedServer = await startBridgeViewerOwnedViteProductServer(fixture.oracle);
	});

	afterAll(async (): Promise<void> => {
		try {
			if (ownedServer !== null) ownedServerCleanup = await ownedServer.stop();
		} finally {
			await disposeFixture?.();
		}
		if (ownedServerCleanup !== null) {
			expect(ownedServerCleanup.forcedTerminationRequired).toBe(false);
			expect(ownedServerCleanup.ownedProcessAliveAfterStop).toBe(false);
		}
	});

	test('correlates the disposable live-worktree journey through the product provider, worker, Pierre, and painted DOM', async () => {
		const oracle = requireFixtureOracle();
		const server = requireOwnedServer();
		expect(oracle.reviewFiles).toHaveLength(oracle.changedPaths.length);

		const proof = await runBridgeViewerProductOnlyJourney({
			baseUrl: server.origin,
			expectedReviewItemIds: oracle.expectedReviewItemIds,
		});

		expect(collectBridgeViewerProductOnlyContractViolations(proof)).toEqual([]);
		assertJourneyFreshness({ oracle, proof, server });
	});

	test('proves Review base/head body truth, request leases, painted publication correlation, and directory disclosure interaction', async () => {
		const oracle = requireFixtureOracle();
		const server = requireOwnedServer();
		const browser = await chromium.launch({ channel: 'chrome', headless: true });
		let page: Page | null = null;
		try {
			page = await browser.newPage({ viewport: { height: 980, width: 1728 } });
			const contentRequests = observeProductContentRequests(page);
			await page.goto(productReviewUrl(server.origin), {
				timeout: productJourneyTimeoutMilliseconds,
				waitUntil: 'domcontentloaded',
			});
			await page.waitForSelector('[data-testid="review-viewer-shell"]', {
				timeout: productJourneyTimeoutMilliseconds,
			});
			await collapseAndExpandReviewDirectory(page);

			const reviewFiles = selectedReviewOracleFiles(oracle.reviewFiles);
			for (const reviewFile of reviewFiles) {
				// oxlint-disable-next-line no-await-in-loop -- Each selection must reach painted terminal state before the next real user interaction.
				const selectionProof = await selectReviewFileAndReadProof({ page, reviewFile });
				expectReviewBodyLinesPainted(selectionProof.bodyText, reviewFile.base.body);
				expectReviewBodyLinesPainted(selectionProof.bodyText, reviewFile.head.body);
				expect(selectionProof.paintedCorrelations).toHaveLength(2);
				for (const roleOracle of [reviewFile.base, reviewFile.head]) {
					const correlation = selectionProof.paintedCorrelations.find(
						(candidate): boolean => candidate.role === roleOracle.role,
					);
					expect(correlation).toEqual(
						expect.objectContaining({
							disposition: 'painted',
							itemId: reviewFile.itemId,
							observedSha256: roleOracle.sha256,
							pierreItemId: reviewFile.itemId,
							position: 'whole',
							publicationId: selectionProof.paintedPublicationId,
							role: roleOracle.role,
							semanticItemId: reviewFile.itemId,
							surface: 'review',
						}),
					);
					expect(correlation?.sourceGeneration).toBeGreaterThan(0);
					expect(correlation?.sourceIdentity).toMatch(/\S/u);
					const request = contentRequests.find(
						(candidate): boolean =>
							candidate.contentRequestId === correlation?.requestId &&
							candidate.descriptor['descriptorId'] === correlation?.descriptorId,
					);
					expect(request).toEqual(
						expect.objectContaining({
							contentKind: 'review.content',
							leaseId: expect.stringMatching(/\S/u),
							responseStatus: 200,
						}),
					);
					expect(request?.descriptor).toEqual(
						expect.objectContaining({
							contentKind: 'review.content',
							itemId: reviewFile.itemId,
							reviewGeneration: correlation?.sourceGeneration,
							role: roleOracle.role,
							sourceIdentity: correlation?.sourceIdentity,
						}),
					);
				}
			}
		} finally {
			await page?.close();
			await browser.close();
		}
	});

	test('paints complete final File bytes after deep scroll with descriptor, role, request, source, and disposition correlation', async () => {
		const oracle = requireFixtureOracle();
		const server = requireOwnedServer();
		const browser = await chromium.launch({ channel: 'chrome', headless: true });
		let page: Page | null = null;
		try {
			page = await browser.newPage({ viewport: { height: 980, width: 1728 } });
			const contentRequests = observeProductContentRequests(page);
			const workerUrls: string[] = [];
			page.on('worker', (worker): void => {
				workerUrls.push(worker.url());
			});
			await page.goto(productFileUrl(server.origin), {
				timeout: productJourneyTimeoutMilliseconds,
				waitUntil: 'domcontentloaded',
			});
			await selectFileBySearch({ page, path: oracle.largeFilePath });
			await waitForSelectedFileReady({ oracle, page });
			await clearFileSearchAndScrollTreeDeep({ oracle, page });
			const contentScrollProof = await scrollSelectedFileThroughMarkers({
				content: oracle.fileContent,
				page,
			});
			const proof = await readFileDeepScrollProof({ oracle, page, workerUrls });

			expect(proof.selectedPath).toBe(oracle.largeFilePath);
			expect(proof.renderedPath).toBe(oracle.largeFilePath);
			expect(proof.lineCount).toBe(oracle.largeFileLineCount);
			expect(proof.scrollHeight).toBeGreaterThan(980);
			expect(proof.scrollTop).toBeGreaterThan(0);
			expect(proof.treeScrollTop).toBeGreaterThan(0);
			expect(proof.deepTreePathPainted).toBe(true);
			expect(contentScrollProof).toEqual({
				finalMarkerPainted: true,
				firstMarkerPainted: true,
				middleMarkerPainted: true,
			});
			expect(proof.finalMarkerPainted).toBe(true);
			expect(
				proof.workerUrls.some((url): boolean => url.includes('bridge-comm-worker-entry')),
			).toBe(true);
			expect(proof.paintedCorrelations).toEqual([
				expect.objectContaining({
					descriptorId: expect.stringMatching(/^dev-file-/u),
					disposition: 'painted',
					itemId: proof.renderedItemId,
					observedSha256: oracle.largeFileSha256,
					position: 'whole',
					publicationId: expect.stringMatching(/\S/u),
					requestId: expect.stringMatching(/\S/u),
					role: 'file',
					semanticItemId: proof.renderedItemId,
					sourceGeneration: expect.any(Number),
					sourceIdentity: expect.stringMatching(/\S/u),
					surface: 'file',
				}),
			]);
			expect(proof.paintedCorrelations[0]?.sourceGeneration).toBeGreaterThan(0);
			const initialCorrelation = proof.paintedCorrelations[0];
			const initialRequest = contentRequests.find(
				(candidate): boolean => candidate.contentRequestId === initialCorrelation?.requestId,
			);
			expect(initialRequest).toEqual(
				expect.objectContaining({
					contentKind: 'file.content',
					leaseId: expect.stringMatching(/\S/u),
					responseStatus: 200,
				}),
			);
			expect(initialRequest?.descriptor).toEqual(
				expect.objectContaining({
					declaredByteLength: oracle.fileContent.byteLength,
					expectedSha256: oracle.fileContent.sha256,
				}),
			);

			const mutatedContent = await requireMutateLargeFileFixture()();
			await page.reload({
				timeout: productJourneyTimeoutMilliseconds,
				waitUntil: 'domcontentloaded',
			});
			await selectFileBySearch({ page, path: oracle.largeFilePath });
			await waitForSelectedFileContentReady({ content: mutatedContent, oracle, page });
			await scrollSelectedFileThroughMarkers({ content: mutatedContent, page });
			const replacementProof = await readFileDeepScrollProof({
				content: mutatedContent,
				oracle,
				page,
				workerUrls,
			});
			expect(replacementProof.paintedCorrelations).toEqual([
				expect.objectContaining({
					disposition: 'painted',
					observedSha256: mutatedContent.sha256,
					surface: 'file',
				}),
			]);
			expect(replacementProof.paintedCorrelations).not.toEqual(
				expect.arrayContaining([
					expect.objectContaining({ observedSha256: oracle.fileContent.sha256 }),
				]),
			);
			const replacementRequest = contentRequests.find(
				(candidate): boolean =>
					candidate.contentRequestId === replacementProof.paintedCorrelations[0]?.requestId,
			);
			expect(replacementRequest?.descriptor).toEqual(
				expect.objectContaining({
					declaredByteLength: mutatedContent.byteLength,
					expectedSha256: mutatedContent.sha256,
				}),
			);
			expect(readFileDescriptorRootRevisionToken(replacementRequest?.descriptor)).not.toBe(
				readFileDescriptorRootRevisionToken(initialRequest?.descriptor),
			);
		} finally {
			await page?.close();
			await browser.close();
		}
	});
});

function assertJourneyFreshness(props: {
	readonly oracle: BridgeViewerViteProductFixtureOracle;
	readonly proof: BridgeViewerProductOnlyJourneyProof;
	readonly server: BridgeViewerOwnedViteProductServer;
}): void {
	expect(props.server.pid).toBeGreaterThan(0);
	expect(props.server.version).toMatch(/^\d+\.\d+\.\d+$/u);
	expect(new URL(props.proof.observedPageUrl).origin).toBe(props.server.origin);
	expect(props.proof.browser.name).toBe('chromium');
	expect(props.proof.reviewFreshRoute.expectedItemIds).toEqual(props.oracle.expectedReviewItemIds);
	expect(props.proof.reviewFreshRoute.observedHeaderItemIds).toEqual(
		props.oracle.expectedReviewItemIds,
	);
	expect(props.proof.reviewFreshRoute.hydrationMilestones.map(({ label }) => label)).toEqual([
		'initial',
		'quarter',
		'middle',
		'threeQuarter',
		'final',
	]);
	expect(props.proof.workers.some((worker): boolean => worker.kind === 'comm-worker')).toBe(true);
	expect(
		props.proof.productRouteTranscript.some(
			(entry): boolean => entry.contentKind === 'file.content' && entry.httpStatus === 200,
		),
	).toBe(true);
	expect(
		props.proof.productRouteTranscript.some(
			(entry): boolean => entry.contentKind === 'review.content' && entry.httpStatus === 200,
		),
	).toBe(true);
}

async function selectFileBySearch(props: {
	readonly page: Page;
	readonly path: string;
}): Promise<void> {
	await props.page.waitForSelector('[data-testid="bridge-file-viewer-shell"]', {
		timeout: productJourneyTimeoutMilliseconds,
	});
	const searchInput = props.page.locator('[data-testid="worktree-file-search-input"]');
	if ((await searchInput.count()) === 0) {
		await props.page.locator('[data-testid="worktree-file-search-toggle"]').click({
			timeout: productJourneyTimeoutMilliseconds,
		});
	}
	await props.page.locator('[data-testid="worktree-file-search-input"]').fill(props.path);
	await props.page.waitForFunction(
		(targetPath: string): boolean => {
			const treeHost = document.querySelector(
				'[data-testid="bridge-file-viewer-pierre-file-tree"] file-tree-container',
			);
			return (
				treeHost?.shadowRoot?.querySelector(`[data-item-path="${CSS.escape(targetPath)}"]`) !== null
			);
		},
		props.path,
		{ timeout: productJourneyTimeoutMilliseconds },
	);
	await props.page.evaluate((targetPath: string): void => {
		const treeHost = document.querySelector(
			'[data-testid="bridge-file-viewer-pierre-file-tree"] file-tree-container',
		);
		const row = treeHost?.shadowRoot?.querySelector(`[data-item-path="${CSS.escape(targetPath)}"]`);
		if (!(row instanceof HTMLElement)) throw new Error(`File row missing: ${targetPath}`);
		row.click();
	}, props.path);
}

async function waitForSelectedFileReady(props: {
	readonly oracle: BridgeViewerViteProductFixtureOracle;
	readonly page: Page;
}): Promise<void> {
	await waitForSelectedFileContentReady({
		content: props.oracle.fileContent,
		oracle: props.oracle,
		page: props.page,
	});
}

async function waitForSelectedFileContentReady(props: {
	readonly content: BridgeViewerViteProductContentOracle;
	readonly oracle: BridgeViewerViteProductFixtureOracle;
	readonly page: Page;
}): Promise<void> {
	await props.page.waitForFunction(
		({ expectedLineCount, expectedSha256, path }): boolean => {
			const canvas = document.querySelector('[data-testid="bridge-file-viewer-code-canvas"]');
			const painted = canvas?.querySelector(
				'diffs-container[data-bridge-painted-source-correlations]',
			);
			const correlations: unknown = JSON.parse(
				painted?.getAttribute('data-bridge-painted-source-correlations') ?? '[]',
			);
			return (
				canvas?.getAttribute('data-worktree-open-file-state') === 'ready' &&
				canvas.getAttribute('data-worktree-open-file-path') === path &&
				canvas.getAttribute('data-worktree-rendered-file-path') === path &&
				Number(canvas.getAttribute('data-worktree-rendered-line-count')) === expectedLineCount &&
				Array.isArray(correlations) &&
				correlations.some(
					(correlation): boolean =>
						typeof correlation === 'object' &&
						correlation !== null &&
						'observedSha256' in correlation &&
						correlation.observedSha256 === expectedSha256,
				)
			);
		},
		{
			expectedLineCount: props.content.lineCount,
			expectedSha256: props.content.sha256,
			path: props.oracle.largeFilePath,
		},
		{ timeout: productJourneyTimeoutMilliseconds },
	);
}

async function clearFileSearchAndScrollTreeDeep(props: {
	readonly oracle: BridgeViewerViteProductFixtureOracle;
	readonly page: Page;
}): Promise<void> {
	await props.page.locator('[data-testid="worktree-file-search-input"]').fill('');
	await props.page.waitForFunction(
		(targetPath: string): boolean => {
			const treeHost = document.querySelector(
				'[data-testid="bridge-file-viewer-pierre-file-tree"] file-tree-container',
			);
			const scrollOwner = treeHost?.shadowRoot?.querySelector(
				'[data-file-tree-virtualized-scroll="true"]',
			);
			if (!(scrollOwner instanceof HTMLElement)) return false;
			scrollOwner.scrollTop = Math.max(0, scrollOwner.scrollHeight - scrollOwner.clientHeight);
			scrollOwner.dispatchEvent(new Event('scroll', { bubbles: true }));
			return scrollOwner.scrollTop > 0 && targetPath.length > 0;
		},
		props.oracle.fileTreeDeepPath,
		{ timeout: productJourneyTimeoutMilliseconds },
	);
	await props.page.waitForFunction(
		(targetPath: string): boolean => {
			const treeHost = document.querySelector(
				'[data-testid="bridge-file-viewer-pierre-file-tree"] file-tree-container',
			);
			return (
				treeHost?.shadowRoot?.querySelector(`[data-item-path="${CSS.escape(targetPath)}"]`) !== null
			);
		},
		props.oracle.fileTreeDeepPath,
		{ timeout: productJourneyTimeoutMilliseconds },
	);
}

async function scrollSelectedFileThroughMarkers(props: {
	readonly content: BridgeViewerViteProductContentOracle;
	readonly page: Page;
}): Promise<FileContentScrollProof> {
	const observedMarkers = new Set<string>();
	for (const [scrollFraction, marker] of [
		[0, props.content.firstMarker],
		[0.5, props.content.middleMarker],
		[1, props.content.finalMarker],
	] as const) {
		// oxlint-disable-next-line no-await-in-loop -- Each virtualized content window must paint before advancing.
		await props.page.evaluate((fraction: number): void => {
			const scrollOwner = document.querySelector(
				'[data-testid="bridge-file-viewer-code-view"] .bridge-code-view-scroll-owner',
			);
			if (!(scrollOwner instanceof HTMLElement))
				throw new Error('File CodeView scroll owner missing.');
			scrollOwner.scrollTop = Math.max(
				0,
				(scrollOwner.scrollHeight - scrollOwner.clientHeight) * fraction,
			);
			scrollOwner.dispatchEvent(new Event('scroll', { bubbles: true }));
		}, scrollFraction);
		// oxlint-disable-next-line no-await-in-loop -- Marker observation is the bounded event for each scroll.
		await props.page.waitForFunction(
			(markerText: string): boolean => {
				const pendingRoots: Array<Document | Element | ShadowRoot> = [document];
				while (pendingRoots.length > 0) {
					const root = pendingRoots.shift();
					if (root === undefined) break;
					if (
						[...root.querySelectorAll('[data-line-index], [data-content]')].some((element) =>
							(element.textContent ?? '').includes(markerText),
						)
					) {
						return true;
					}
					for (const descendant of root.querySelectorAll('*')) {
						if (descendant.shadowRoot !== null) pendingRoots.push(descendant.shadowRoot);
					}
				}
				return false;
			},
			marker,
			{ timeout: productJourneyTimeoutMilliseconds },
		);
		observedMarkers.add(marker);
	}
	return {
		finalMarkerPainted: observedMarkers.has(props.content.finalMarker),
		firstMarkerPainted: observedMarkers.has(props.content.firstMarker),
		middleMarkerPainted: observedMarkers.has(props.content.middleMarker),
	};
}

async function readFileDeepScrollProof(props: {
	readonly content?: BridgeViewerViteProductContentOracle;
	readonly oracle: BridgeViewerViteProductFixtureOracle;
	readonly page: Page;
	readonly workerUrls: readonly string[];
}): Promise<FileDeepScrollProof> {
	const content = props.content ?? props.oracle.fileContent;
	const snapshot = await props.page.evaluate(
		({ deepTreePath, finalMarker, workerUrls }): FileDeepScrollBrowserSnapshot => {
			const canvas = document.querySelector('[data-testid="bridge-file-viewer-code-canvas"]');
			const renderedItem = canvas?.querySelector(
				'diffs-container[data-bridge-painted-source-correlations]',
			);
			const scrollOwner = document.querySelector(
				'[data-testid="bridge-file-viewer-code-view"] .bridge-code-view-scroll-owner',
			);
			if (!(canvas instanceof HTMLElement) || !(scrollOwner instanceof HTMLElement)) {
				throw new Error('File deep-scroll proof requires the mounted canvas and scroll owner.');
			}
			const encodedCorrelations =
				renderedItem?.getAttribute('data-bridge-painted-source-correlations') ?? '[]';
			const pendingRoots: Array<Document | Element | ShadowRoot> = [document];
			const paintedText: string[] = [];
			while (pendingRoots.length > 0) {
				const root = pendingRoots.shift();
				if (root === undefined) break;
				paintedText.push(
					...[...root.querySelectorAll('[data-line-index], [data-content]')].map(
						(element): string => element.textContent ?? '',
					),
				);
				for (const descendant of root.querySelectorAll('*')) {
					if (descendant.shadowRoot !== null) pendingRoots.push(descendant.shadowRoot);
				}
			}
			const treeHost = document.querySelector(
				'[data-testid="bridge-file-viewer-pierre-file-tree"] file-tree-container',
			);
			const treeScrollOwner = treeHost?.shadowRoot?.querySelector(
				'[data-file-tree-virtualized-scroll="true"]',
			);
			return {
				deepTreePathPainted:
					treeHost?.shadowRoot?.querySelector(`[data-item-path="${CSS.escape(deepTreePath)}"]`) !==
					null,
				encodedPaintedCorrelations: encodedCorrelations,
				finalMarkerPainted: paintedText.some((text): boolean => text.includes(finalMarker)),
				lineCount: Number(canvas.getAttribute('data-worktree-rendered-line-count') ?? '0'),
				renderedItemId: canvas.getAttribute('data-worktree-rendered-item-id'),
				renderedPath: canvas.getAttribute('data-worktree-rendered-file-path'),
				scrollHeight: scrollOwner.scrollHeight,
				scrollTop: scrollOwner.scrollTop,
				selectedPath: canvas.getAttribute('data-worktree-open-file-path'),
				treeScrollTop: treeScrollOwner instanceof HTMLElement ? treeScrollOwner.scrollTop : 0,
				workerUrls,
			};
		},
		{
			deepTreePath: props.oracle.fileTreeDeepPath,
			finalMarker: content.finalMarker,
			workerUrls: props.workerUrls,
		},
	);
	const { encodedPaintedCorrelations, ...proof } = snapshot;
	return {
		...proof,
		paintedCorrelations: decodePaintedSourceCorrelations(encodedPaintedCorrelations),
	};
}

function decodePaintedSourceCorrelations(
	encodedValue: string,
): readonly PaintedSourceCorrelation[] {
	const parsedValue: unknown = JSON.parse(encodedValue);
	if (!Array.isArray(parsedValue)) throw new Error('Painted source correlations must be an array.');
	return parsedValue.map((value, valueIndex): PaintedSourceCorrelation => {
		if (!isUnknownRecord(value)) {
			throw new Error(`Painted source correlation ${valueIndex} must be an object.`);
		}
		const stringFields = [
			'descriptorId',
			'disposition',
			'itemId',
			'observedSha256',
			'pierreItemId',
			'position',
			'publicationId',
			'requestId',
			'role',
			'semanticItemId',
			'sourceIdentity',
			'surface',
		] as const;
		for (const fieldName of stringFields) {
			if (typeof value[fieldName] !== 'string') {
				throw new Error(`Painted source correlation ${valueIndex} has invalid ${fieldName}.`);
			}
		}
		if (typeof value['sourceGeneration'] !== 'number') {
			throw new Error(`Painted source correlation ${valueIndex} has invalid sourceGeneration.`);
		}
		return {
			descriptorId: value['descriptorId'],
			disposition: value['disposition'],
			itemId: value['itemId'],
			observedSha256: value['observedSha256'],
			pierreItemId: value['pierreItemId'],
			position: value['position'],
			publicationId: value['publicationId'],
			requestId: value['requestId'],
			role: value['role'],
			semanticItemId: value['semanticItemId'],
			sourceGeneration: value['sourceGeneration'],
			sourceIdentity: value['sourceIdentity'],
			surface: value['surface'],
		};
	});
}

function observeProductContentRequests(page: Page): ProductContentRequestObservation[] {
	const observations: ProductContentRequestObservation[] = [];
	const observationByRequest = new WeakMap<Request, ProductContentRequestObservation>();
	page.on('request', (request): void => {
		if (
			request.method() !== 'POST' ||
			new URL(request.url()).pathname !== '/__bridge-product/content'
		) {
			return;
		}
		const body: unknown = request.postDataJSON();
		if (!isUnknownRecord(body) || !isUnknownRecord(body['descriptor'])) return;
		const contentKind = body['contentKind'];
		const contentRequestId = body['contentRequestId'];
		const leaseId = body['leaseId'];
		if (
			typeof contentKind !== 'string' ||
			typeof contentRequestId !== 'string' ||
			typeof leaseId !== 'string'
		) {
			return;
		}
		const observation: ProductContentRequestObservation = {
			contentKind,
			contentRequestId,
			descriptor: body['descriptor'],
			leaseId,
			responseStatus: null,
		};
		observations.push(observation);
		observationByRequest.set(request, observation);
	});
	page.on('response', (response): void => {
		const observation = observationByRequest.get(response.request());
		if (observation !== undefined) observation.responseStatus = response.status();
	});
	return observations;
}

async function collapseAndExpandReviewDirectory(page: Page): Promise<void> {
	const directoryPathHandle = await page.waitForFunction(
		(): string | null => {
			const host = document.querySelector(
				'[data-testid="bridge-review-trees-panel"] file-tree-container',
			);
			const root = host?.shadowRoot;
			if (root === undefined || root === null) return null;
			return (
				root.querySelector('[data-item-path][aria-expanded]')?.getAttribute('data-item-path') ??
				null
			);
		},
		null,
		{ timeout: productJourneyTimeoutMilliseconds },
	);
	const directoryPath: unknown = await directoryPathHandle.jsonValue();
	if (typeof directoryPath !== 'string') throw new Error('Review directory path missing.');
	const initialExpanded = await page.evaluate((path): boolean => {
		const host = document.querySelector(
			'[data-testid="bridge-review-trees-panel"] file-tree-container',
		);
		return (
			host?.shadowRoot
				?.querySelector(`[data-item-path="${CSS.escape(path)}"][aria-expanded]`)
				?.getAttribute('aria-expanded') === 'true'
		);
	}, directoryPath);
	if (!initialExpanded) {
		await clickReviewDirectory({ directoryPath, page });
		await waitForReviewDirectoryDisclosure({ directoryPath, expectedExpanded: true, page });
	}
	for (const expectedExpanded of [false, true]) {
		// oxlint-disable-next-line no-await-in-loop -- Collapse and expand are distinct user-observed transitions.
		await clickReviewDirectory({ directoryPath, page });
		// oxlint-disable-next-line no-await-in-loop -- The tree exposes its disclosure transition through aria-expanded.
		await waitForReviewDirectoryDisclosure({ directoryPath, expectedExpanded, page });
	}
}

async function clickReviewDirectory(props: {
	readonly directoryPath: string;
	readonly page: Page;
}): Promise<void> {
	await props.page.evaluate((path): void => {
		const host = document.querySelector(
			'[data-testid="bridge-review-trees-panel"] file-tree-container',
		);
		const row = host?.shadowRoot?.querySelector(
			`[data-item-path="${CSS.escape(path)}"][aria-expanded]`,
		);
		if (!(row instanceof HTMLElement)) throw new Error('Review directory row missing.');
		row.click();
	}, props.directoryPath);
}

async function waitForReviewDirectoryDisclosure(props: {
	readonly directoryPath: string;
	readonly expectedExpanded: boolean;
	readonly page: Page;
}): Promise<void> {
	await props.page.waitForFunction(
		({ directoryPath, expectedExpanded }): boolean => {
			const host = document.querySelector(
				'[data-testid="bridge-review-trees-panel"] file-tree-container',
			);
			return (
				host?.shadowRoot
					?.querySelector(`[data-item-path="${CSS.escape(directoryPath)}"][aria-expanded]`)
					?.getAttribute('aria-expanded') === String(expectedExpanded)
			);
		},
		{ directoryPath: props.directoryPath, expectedExpanded: props.expectedExpanded },
		{ timeout: productJourneyTimeoutMilliseconds },
	);
}

function readFileDescriptorRootRevisionToken(
	descriptor: Readonly<Record<string, unknown>> | undefined,
): string | null {
	const source = descriptor?.['source'];
	return isUnknownRecord(source) && typeof source['rootRevisionToken'] === 'string'
		? source['rootRevisionToken']
		: null;
}

async function selectReviewFileAndReadProof(props: {
	readonly page: Page;
	readonly reviewFile: BridgeViewerViteProductReviewFileOracle;
}): Promise<ReviewSelectionProof> {
	await props.page.evaluate((path: string): void => {
		const host = document.querySelector(
			'[data-testid="bridge-review-trees-panel"] file-tree-container',
		);
		const row = host?.shadowRoot?.querySelector(`[data-item-path="${CSS.escape(path)}"]`);
		if (!(row instanceof HTMLElement)) throw new Error(`Review file row missing: ${path}`);
		row.click();
	}, props.reviewFile.path);
	await props.page.waitForFunction(
		(itemId: string): boolean => {
			const panel = document.querySelector('[data-testid="bridge-code-view-panel"]');
			if (panel?.getAttribute('data-selected-item-id') !== itemId) return false;
			for (const host of queryAllOpenShadowRoots(panel, 'diffs-container')) {
				const marker =
					host.querySelector('[data-bridge-code-view-item-id]') ??
					host.shadowRoot?.querySelector('[data-bridge-code-view-item-id]');
				if (
					marker?.getAttribute('data-bridge-code-view-item-id') === itemId &&
					host.hasAttribute('data-bridge-painted-source-correlations')
				) {
					return true;
				}
			}
			return false;

			// oxlint-disable-next-line unicorn/consistent-function-scoping -- Playwright browser evaluation must carry this helper into the page realm.
			function queryAllOpenShadowRoots(root: Element, selector: string): Element[] {
				const matches: Element[] = [];
				const pending: Array<Element | ShadowRoot> = [root];
				while (pending.length > 0) {
					const current = pending.shift();
					if (current === undefined) break;
					matches.push(...current.querySelectorAll(selector));
					for (const descendant of current.querySelectorAll('*')) {
						if (descendant.shadowRoot !== null) pending.push(descendant.shadowRoot);
					}
				}
				return matches;
			}
		},
		props.reviewFile.itemId,
		{ timeout: productJourneyTimeoutMilliseconds },
	);
	const snapshot = await props.page.evaluate((itemId: string) => {
		const panel = document.querySelector('[data-testid="bridge-code-view-panel"]');
		if (panel === null) throw new Error('Review code panel missing.');
		for (const host of queryAllOpenShadowRoots(panel, 'diffs-container')) {
			const marker =
				host.querySelector('[data-bridge-code-view-item-id]') ??
				host.shadowRoot?.querySelector('[data-bridge-code-view-item-id]');
			if (marker?.getAttribute('data-bridge-code-view-item-id') !== itemId) continue;
			return {
				bodyText: host.shadowRoot?.textContent ?? host.textContent ?? '',
				encodedCorrelations: host.getAttribute('data-bridge-painted-source-correlations') ?? '[]',
				paintedPublicationId: host.getAttribute('data-bridge-painted-publication-id'),
			};
		}
		throw new Error(`Review painted host missing: ${itemId}`);

		// oxlint-disable-next-line unicorn/consistent-function-scoping -- Playwright browser evaluation must carry this helper into the page realm.
		function queryAllOpenShadowRoots(root: Element, selector: string): Element[] {
			const matches: Element[] = [];
			const pending: Array<Element | ShadowRoot> = [root];
			while (pending.length > 0) {
				const current = pending.shift();
				if (current === undefined) break;
				matches.push(...current.querySelectorAll(selector));
				for (const descendant of current.querySelectorAll('*')) {
					if (descendant.shadowRoot !== null) pending.push(descendant.shadowRoot);
				}
			}
			return matches;
		}
	}, props.reviewFile.itemId);
	return {
		bodyText: snapshot.bodyText,
		paintedCorrelations: decodePaintedSourceCorrelations(snapshot.encodedCorrelations),
		paintedPublicationId: snapshot.paintedPublicationId,
	};
}

function selectedReviewOracleFiles(
	reviewFiles: readonly BridgeViewerViteProductReviewFileOracle[],
): readonly BridgeViewerViteProductReviewFileOracle[] {
	const selectedIndexes = [0, Math.floor(reviewFiles.length / 2), reviewFiles.length - 1];
	return selectedIndexes.map((index): BridgeViewerViteProductReviewFileOracle => {
		const reviewFile = reviewFiles[index];
		if (reviewFile === undefined) throw new Error(`Review oracle missing at index ${index}.`);
		return reviewFile;
	});
}

function expectReviewBodyLinesPainted(paintedText: string, expectedBody: string): void {
	for (const expectedLine of expectedBody.split('\n').filter((line): boolean => line.length > 0)) {
		expect(paintedText).toContain(expectedLine);
	}
}

function isUnknownRecord(value: unknown): value is Readonly<Record<string, unknown>> {
	return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function productFileUrl(origin: string): string {
	const url = new URL('/', origin);
	url.searchParams.set('fixture', 'worktree');
	url.searchParams.set('scenario', 'current-worktree');
	url.searchParams.set('viewer', 'file');
	url.searchParams.set('workers', 'on');
	return url.toString();
}

function productReviewUrl(origin: string): string {
	const url = new URL(productFileUrl(origin));
	url.searchParams.set('viewer', 'review');
	return url.toString();
}

function requireFixtureOracle(): BridgeViewerViteProductFixtureOracle {
	if (fixtureOracle === null) throw new Error('Vite product fixture was not initialized.');
	return fixtureOracle;
}

function requireOwnedServer(): BridgeViewerOwnedViteProductServer {
	if (ownedServer === null) throw new Error('Owned Vite product server was not initialized.');
	return ownedServer;
}

function requireMutateLargeFileFixture(): () => Promise<BridgeViewerViteProductContentOracle> {
	if (mutateLargeFileFixture === null)
		throw new Error('Vite product fixture mutation is unavailable.');
	return mutateLargeFileFixture;
}
