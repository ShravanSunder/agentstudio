import { createHash } from 'node:crypto';

import type {
	Browser,
	Page,
	Request as PlaywrightRequest,
	Response as PlaywrightResponse,
} from 'playwright';
import { chromium, errors } from 'playwright';

import {
	bridgeViewerProductOnlySelectors,
	summarizeBridgeProductRequestBody,
	summarizeBridgeProductResponseBody,
	type BridgeViewerFileProductStateSnapshot,
	type BridgeViewerConsoleDiagnostic,
	type BridgeViewerFailedResponse,
	type BridgeViewerLegacyIntakeTranscriptEntry,
	type BridgeViewerLegacyRouteTranscriptEntry,
	type BridgeViewerMainWindowProductRequest,
	type BridgeViewerObservedWorker,
	type BridgeViewerProductFailureTransportSnapshot,
	type BridgeViewerProductOnlyJourneyFailureCheckpoint,
	type BridgeViewerProductOnlyJourneyProof,
	type BridgeViewerProductRouteTranscriptEntry,
	type BridgeViewerReviewProductStateSnapshot,
} from './product-only-real-router-contract.ts';
import {
	bridgeViewerJourneyFailureCode,
	BridgeViewerProductOnlyJourneyFailure,
} from './product-only-real-router-failure.ts';
import {
	proveFreshReviewRoute,
	proveReviewTreeSelection,
	readFreshReviewFailureSnapshot,
	waitForReviewProductTerminalState,
} from './product-only-real-router-review-proof.ts';
import { waitForProductBrowserFrameSettlement } from './product-only-real-router-settlement.ts';

export {
	mountedHeaderOrderViolationForExpectedOrder,
	nextFreshReviewTraversalScrollTop,
} from './product-only-real-router-review-proof.ts';
export { bridgeViewerProductOnlyJourneyFailureFromError } from './product-only-real-router-failure.ts';

const productJourneyTimeoutMilliseconds = 120_000;
const productCompositionSettleTimeoutMilliseconds = 10_000;
const productJourneyOwnedDeadlineMilliseconds = 120_000;
const maximumCapturedConsoleErrors = 32;
const maximumCapturedConsoleErrorCharacters = 500;

interface MutableProductRouteTranscriptEntry {
	contentKind: string | null;
	documentGeneration: number;
	httpStatus: number | null;
	method: string;
	ordinal: number;
	paneSessionId: string | null;
	path: string;
	requestKind: string | null;
	requestSettled: boolean;
	requestSequence: number | null;
	responseCode: string | null;
	responseKind: string | null;
	streamKind: string | null;
	subscriptionKind: string | null;
	workerInstanceId: string | null;
}

interface MutableObservedWorker extends BridgeViewerObservedWorker {
	closed: boolean;
	closedBeforeJourneyCompletion: boolean;
}

interface MutableLegacyRouteTranscriptEntry {
	finalWindow: boolean | null;
	frameKind: string | null;
	httpStatus: number | null;
	ordinal: number;
	path: string;
	sequence: number | null;
}

export async function runBridgeViewerProductOnlyJourney(props: {
	readonly baseUrl: string;
	readonly expectedReviewItemIds: readonly string[];
}): Promise<BridgeViewerProductOnlyJourneyProof> {
	const browser = await chromium.launch({ channel: 'chrome', headless: true });
	const observedWorkers: MutableObservedWorker[] = [];
	const observedWorkerClosePromises: Promise<void>[] = [];
	let closedWorkerCount = 0;
	const consoleDiagnostics: BridgeViewerConsoleDiagnostic[] = [];
	const consoleErrors: string[] = [];
	const failedResponses: BridgeViewerFailedResponse[] = [];
	const page = await browser.newPage({
		deviceScaleFactor: 1,
		viewport: { height: 980, width: 1728 },
	});
	const ownedJourneyDeadline = createOwnedProductJourneyDeadline({ browser, page });
	let journeyCompleted = false;
	let mainFrameDocumentGeneration = 0;
	page.on('framenavigated', (frame): void => {
		if (frame === page.mainFrame()) mainFrameDocumentGeneration += 1;
	});
	const routeObserver = new BridgeViewerRealRouterObserver(
		page,
		(): number => mainFrameDocumentGeneration,
	);
	page.on('worker', (worker): void => {
		const observedWorker = classifyObservedWorker(worker.url(), mainFrameDocumentGeneration);
		observedWorkers.push(observedWorker);
		observedWorkerClosePromises.push(
			new Promise((resolve): void => {
				worker.once('close', (): void => {
					observedWorker.closed = true;
					observedWorker.closedBeforeJourneyCompletion = !journeyCompleted;
					closedWorkerCount += 1;
					resolve();
				});
			}),
		);
	});
	page.on('console', (message): void => {
		const messageType = message.type();
		if (
			(messageType === 'error' || messageType === 'warning') &&
			consoleErrors.length < maximumCapturedConsoleErrors
		) {
			const text = message.text().slice(0, maximumCapturedConsoleErrorCharacters);
			const location = message.location();
			consoleErrors.push(text);
			consoleDiagnostics.push({
				columnNumber: location.columnNumber ?? null,
				lineNumber: location.lineNumber ?? null,
				path: consoleDiagnosticPath(location.url),
				text,
				type: messageType,
			});
		}
	});
	page.on('response', (response): void => {
		if (response.status() < 400) return;
		const request = response.request();
		failedResponses.push({
			method: request.method(),
			path: new URL(response.url()).pathname,
			resourceType: request.resourceType(),
			status: response.status(),
		});
	});
	await installMainWindowProductRouteObserver(page);
	await installLegacyIntakeObserver(page);

	let journeyProof: Omit<BridgeViewerProductOnlyJourneyProof, 'browserCleanup'> | null = null;
	let journeyFailure: Omit<
		BridgeViewerProductOnlyJourneyFailureCheckpoint,
		'browserCleanup' | 'workers'
	> | null = null;
	let journeyFailureCause: unknown = null;
	try {
		const pageUrl = new URL('/', props.baseUrl);
		pageUrl.searchParams.set('fixture', 'worktree');
		pageUrl.searchParams.set('scenario', 'current-worktree');
		pageUrl.searchParams.set('workers', 'on');
		pageUrl.searchParams.set('viewer', 'review');
		await page.goto(pageUrl.toString(), {
			timeout: productJourneyTimeoutMilliseconds,
			waitUntil: 'domcontentloaded',
		});
		const reviewFreshRoute = await proveFreshReviewRoute({
			expectedItemIds: props.expectedReviewItemIds,
			page,
		});
		const reviewTreeSelection = await proveReviewTreeSelection({
			expectedItemIds: props.expectedReviewItemIds,
			page,
		});
		await page.locator(bridgeViewerProductOnlySelectors.activeFileContextButton).click({
			timeout: productJourneyTimeoutMilliseconds,
		});
		await waitForViewerMode(page, 'file');
		await waitForFileProductTerminalState(page);
		const fileAfterReviewFirstSwitch = await readFileProductState(page);

		pageUrl.searchParams.set('viewer', 'file');
		const firstAcknowledgementResponse = page.waitForResponse(
			(response): boolean => responseIsFrameObservation(response),
			{ timeout: productJourneyTimeoutMilliseconds },
		);
		const fileSubscriptionResponse = page.waitForResponse(
			(response): boolean => responseIsSubscriptionOpen(response, 'file.metadata'),
			{ timeout: productJourneyTimeoutMilliseconds },
		);
		const reviewSubscriptionResponse = page.waitForResponse(
			(response): boolean => responseIsSubscriptionOpen(response, 'review.metadata'),
			{ timeout: productJourneyTimeoutMilliseconds },
		);
		await page.goto(pageUrl.toString(), {
			timeout: productJourneyTimeoutMilliseconds,
			waitUntil: 'domcontentloaded',
		});
		await page.waitForSelector(bridgeViewerProductOnlySelectors.fileShell, {
			timeout: productJourneyTimeoutMilliseconds,
		});
		const [acknowledgementResponse, fileOpenResponse, reviewOpenResponse] = await Promise.all([
			firstAcknowledgementResponse,
			fileSubscriptionResponse,
			reviewSubscriptionResponse,
		]);
		if (
			acknowledgementResponse.status() === 204 &&
			fileOpenResponse.status() === 200 &&
			reviewOpenResponse.status() === 200
		) {
			await waitForFileProductTerminalState(page);
		}
		const fileAfterFirstAcknowledgement = await readFileProductState(page);
		const journeyDocumentGenerationAtStart = mainFrameDocumentGeneration;

		await page.locator(bridgeViewerProductOnlySelectors.activeReviewContextButton).click({
			timeout: productJourneyTimeoutMilliseconds,
		});
		await waitForViewerMode(page, 'review');
		await waitForReviewProductTerminalState(page);
		const reviewAtCompletion = await readReviewProductState(page);

		await page.locator(bridgeViewerProductOnlySelectors.activeFileContextButton).click({
			timeout: productJourneyTimeoutMilliseconds,
		});
		await waitForViewerMode(page, 'file');
		await waitForFileProductTerminalState(page);
		await routeObserver.waitForObservedLegacyMetadataCompletion();
		await routeObserver.waitForAllProductResponses();
		await routeObserver.flushResponseParsers();
		journeyCompleted = true;

		journeyProof = {
			browser: {
				headless: true,
				name: browser.browserType().name(),
				version: browser.version(),
			},
			consoleDiagnostics,
			consoleErrors,
			documentGeneration: {
				atJourneyCompletion: mainFrameDocumentGeneration,
				atJourneyStart: journeyDocumentGenerationAtStart,
			},
			failedResponses,
			fileAfterReviewFirstSwitch,
			fileAfterFirstAcknowledgement,
			fileAtCompletion: await readFileProductState(page),
			legacyIntakeTranscript: await readLegacyIntakeTranscript(page),
			legacyRouteTranscript: routeObserver.legacyRouteTranscript(),
			mainWindowProductRouteTranscript: await readMainWindowProductRouteTranscript(page),
			observedPageUrl: page.url(),
			productRouteTranscript: routeObserver.productRouteTranscript(),
			reviewFreshRoute,
			reviewTreeSelection,
			reviewAtCompletion,
			selectors: bridgeViewerProductOnlySelectors,
			selectorSnapshot: await page.evaluate(
				(selectors) => ({
					activeFileContextButtonCount: document.querySelectorAll(selectors.activeFileContextButton)
						.length,
					activeReviewContextButtonCount: document.querySelectorAll(
						selectors.activeReviewContextButton,
					).length,
					fileCodeCanvasCount: document.querySelectorAll(selectors.fileCodeCanvas).length,
					fileShellCount: document.querySelectorAll(selectors.fileShell).length,
					reviewShellCount: document.querySelectorAll(selectors.reviewShell).length,
				}),
				bridgeViewerProductOnlySelectors,
			),
			workers: observedWorkers,
		};
	} catch (error: unknown) {
		journeyFailureCause = error;
		journeyFailure = await captureBridgeViewerProductOnlyJourneyFailure({
			documentGeneration: mainFrameDocumentGeneration,
			error,
			page,
			routeObserver,
		});
	} finally {
		await ownedJourneyDeadline.dispose();
		await page.close();
		await browser.close();
		try {
			await withBoundedTimeout(
				Promise.all(observedWorkerClosePromises),
				productCompositionSettleTimeoutMilliseconds,
				'observed worker closure',
			);
		} catch {
			// The proof reports incomplete closure through its explicit cleanup counters.
		}
	}
	const browserCleanup: BridgeViewerProductOnlyJourneyProof['browserCleanup'] = {
		browserConnectedAfterClose: browser.isConnected(),
		closedWorkerCount,
		observedWorkerCount: observedWorkers.length,
		pageClosed: page.isClosed(),
	};
	if (journeyFailure !== null) {
		throw new BridgeViewerProductOnlyJourneyFailure({
			cause: journeyFailureCause,
			checkpoint: {
				...journeyFailure,
				browserCleanup,
				workers: observedWorkers.map(
					({ url: _url, ...worker }): Omit<BridgeViewerObservedWorker, 'url'> => ({ ...worker }),
				),
			},
		});
	}
	if (journeyProof === null) {
		throw new Error('Bridge Viewer product-only journey ended without a proof result.');
	}
	return {
		...journeyProof,
		browserCleanup,
		legacyRouteTranscript: routeObserver.legacyRouteTranscript(),
		productRouteTranscript: routeObserver.productRouteTranscript(),
	};
}

async function captureBridgeViewerProductOnlyJourneyFailure(props: {
	readonly documentGeneration: number;
	readonly error: unknown;
	readonly page: Page;
	readonly routeObserver: BridgeViewerRealRouterObserver;
}): Promise<Omit<BridgeViewerProductOnlyJourneyFailureCheckpoint, 'browserCleanup' | 'workers'>> {
	try {
		await props.routeObserver.flushResponseParsers();
	} catch {}
	let review: BridgeViewerProductOnlyJourneyFailureCheckpoint['review'] = null;
	let captureStatus: BridgeViewerProductOnlyJourneyFailureCheckpoint['captureStatus'] =
		'unavailable';
	try {
		review = await readFreshReviewFailureSnapshot(props.page);
		captureStatus = 'captured';
	} catch {}
	return {
		captureStatus,
		documentGeneration: props.documentGeneration,
		failureCode: bridgeViewerJourneyFailureCode(props.error),
		review,
		transport: props.routeObserver.failureTransportSnapshot(),
	};
}

async function installMainWindowProductRouteObserver(page: Page): Promise<void> {
	await page.addInitScript((): void => {
		type ProofWindow = Window & {
			bridgeViewerMainWindowProductRouteTranscript?: BridgeViewerMainWindowProductRequest[];
		};
		const proofWindow = window as ProofWindow;
		proofWindow.bridgeViewerMainWindowProductRouteTranscript = [];
		const originalFetch = globalThis.fetch.bind(globalThis);
		globalThis.fetch = async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
			const request = input instanceof Request ? input : null;
			const requestUrl =
				input instanceof Request ? input.url : input instanceof URL ? input.href : input;
			recordProductRequest({
				method: init?.method ?? request?.method ?? 'GET',
				transport: 'fetch',
				url: requestUrl,
			});
			return await originalFetch(input, init);
		};

		// oxlint-disable-next-line typescript/unbound-method -- The wrapper invokes this saved method with the live XMLHttpRequest receiver below.
		const originalOpen = XMLHttpRequest.prototype.open;
		XMLHttpRequest.prototype.open = function (
			method: string,
			url: string | URL,
			async = true,
			username?: string | null,
			password?: string | null,
		): void {
			recordProductRequest({
				method,
				transport: 'xmlHttpRequest',
				url: url instanceof URL ? url.href : url,
			});
			Reflect.apply(originalOpen, this, [method, url, async, username, password]);
		};

		function recordProductRequest(props: {
			readonly method: string;
			readonly transport: BridgeViewerMainWindowProductRequest['transport'];
			readonly url: string;
		}): void {
			const url = new URL(props.url, location.href);
			if (!url.pathname.startsWith('/__bridge-product/')) return;
			proofWindow.bridgeViewerMainWindowProductRouteTranscript?.push({
				method: props.method.toUpperCase(),
				path: url.pathname,
				transport: props.transport,
			});
		}
	});
}

async function readMainWindowProductRouteTranscript(
	page: Page,
): Promise<readonly BridgeViewerMainWindowProductRequest[]> {
	return await page.evaluate((): readonly BridgeViewerMainWindowProductRequest[] => {
		type ProofWindow = Window & {
			bridgeViewerMainWindowProductRouteTranscript?: BridgeViewerMainWindowProductRequest[];
		};
		return (window as ProofWindow).bridgeViewerMainWindowProductRouteTranscript ?? [];
	});
}

function consoleDiagnosticPath(url: string): string | null {
	if (url.length === 0) return null;
	try {
		return new URL(url).pathname;
	} catch {
		return url.slice(0, maximumCapturedConsoleErrorCharacters);
	}
}

export class BridgeViewerRealRouterObserver {
	readonly #documentGeneration: () => number;
	readonly #page: Page;
	readonly #legacyCompletion: Promise<void>;
	readonly #legacyEntries: MutableLegacyRouteTranscriptEntry[] = [];
	#legacyMetadataObserved = false;
	readonly #productEntries: MutableProductRouteTranscriptEntry[] = [];
	readonly #productEntryByRequest = new WeakMap<
		PlaywrightRequest,
		MutableProductRouteTranscriptEntry
	>();
	readonly #legacyEntryByRequest = new WeakMap<
		PlaywrightRequest,
		MutableLegacyRouteTranscriptEntry
	>();
	readonly #responseParserPromises = new Set<Promise<void>>();
	readonly #productResponseClosureWaiters = new Set<() => void>();
	readonly #unfinishedProductRequests = new Set<PlaywrightRequest>();
	#productActivityRevision = 0;
	#responseParserFailure: unknown = null;
	#nextOrdinal = 1;
	#resolveLegacyCompletion: (() => void) | null = null;

	constructor(page: Page, documentGeneration: () => number) {
		this.#documentGeneration = documentGeneration;
		this.#page = page;
		this.#legacyCompletion = new Promise((resolve): void => {
			this.#resolveLegacyCompletion = resolve;
		});
		page.on('request', (request): void => this.#observeRequest(request));
		page.on('requestfailed', (request): void => this.#observeRequestSettled(request));
		page.on('requestfinished', (request): void => this.#observeRequestSettled(request));
		page.on('response', (response): void => this.#observeResponse(response));
	}

	productRouteTranscript(): readonly BridgeViewerProductRouteTranscriptEntry[] {
		return this.#productEntries.map((entry) => ({ ...entry }));
	}

	failureTransportSnapshot(): BridgeViewerProductFailureTransportSnapshot {
		return {
			entries: this.#productEntries.map(
				({ paneSessionId: _paneSessionId, workerInstanceId: _workerInstanceId, ...entry }) => entry,
			),
			unfinishedRequestOrdinals: [...this.#unfinishedProductRequests]
				.flatMap((request): readonly number[] => {
					const ordinal = this.#productEntryByRequest.get(request)?.ordinal;
					return ordinal === undefined ? [] : [ordinal];
				})
				.toSorted((left, right): number => left - right),
		};
	}

	legacyRouteTranscript(): readonly BridgeViewerLegacyRouteTranscriptEntry[] {
		return this.#legacyEntries.map((entry) => ({ ...entry }));
	}

	async flushResponseParsers(): Promise<void> {
		await Promise.allSettled(this.#responseParserPromises);
		if (this.#responseParserFailure !== null) throw this.#responseParserFailure;
	}

	async waitForObservedLegacyMetadataCompletion(): Promise<void> {
		await this.flushResponseParsers();
		if (!this.#legacyMetadataObserved || this.#legacyEntries.some((entry) => entry.finalWindow)) {
			return;
		}
		await withBoundedTimeout(
			this.#legacyCompletion,
			productJourneyTimeoutMilliseconds,
			'legacy Review metadata completion',
		);
	}

	async waitForAllProductResponses(): Promise<void> {
		await withBoundedTimeout(
			this.#waitForStableProductRequestQuiescence(),
			productCompositionSettleTimeoutMilliseconds,
			'all issued product request responses',
		);
	}

	#observeRequest(request: PlaywrightRequest): void {
		const requestUrl = new URL(request.url());
		if (requestUrl.pathname.startsWith('/__bridge-product/')) {
			const requestBody = parseJSONOrNull(request.postData());
			const requestSummary = summarizeBridgeProductRequestBody(requestBody);
			const entry: MutableProductRouteTranscriptEntry = {
				...requestSummary,
				documentGeneration: this.#documentGeneration(),
				httpStatus: null,
				method: request.method(),
				ordinal: this.#nextOrdinal++,
				path: requestUrl.pathname,
				responseCode: null,
				responseKind: null,
				requestSettled: false,
			};
			this.#productEntries.push(entry);
			this.#productEntryByRequest.set(request, entry);
			this.#productActivityRevision += 1;
			if (requestUrl.pathname !== '/__bridge-product/stream') {
				this.#unfinishedProductRequests.add(request);
			}
			return;
		}
		if (!requestUrl.pathname.startsWith('/__bridge-worktree/review-')) return;
		const entry: MutableLegacyRouteTranscriptEntry = {
			finalWindow: null,
			frameKind: null,
			httpStatus: null,
			ordinal: this.#nextOrdinal++,
			path: requestUrl.pathname,
			sequence: null,
		};
		this.#legacyEntries.push(entry);
		this.#legacyEntryByRequest.set(request, entry);
	}

	#observeResponse(response: PlaywrightResponse): void {
		const productEntry = this.#productEntryByRequest.get(response.request());
		if (productEntry !== undefined) {
			productEntry.httpStatus = response.status();
			this.#productActivityRevision += 1;
			this.#resolveProductResponseClosureWaitersIfQuiescent();
			if (productEntry.path === '/__bridge-product/command' && response.status() !== 204) {
				this.#trackResponseParser(this.#parseProductCommandResponse(response, productEntry));
			}
			return;
		}
		const legacyEntry = this.#legacyEntryByRequest.get(response.request());
		if (legacyEntry === undefined) return;
		legacyEntry.httpStatus = response.status();
		if (legacyEntry.path === '/__bridge-worktree/review-metadata') {
			this.#legacyMetadataObserved = true;
			this.#trackResponseParser(this.#parseLegacyMetadataResponse(response, legacyEntry));
		}
	}

	#observeRequestSettled(request: PlaywrightRequest): void {
		const entry = this.#productEntryByRequest.get(request);
		if (entry !== undefined) entry.requestSettled = true;
		if (!this.#unfinishedProductRequests.delete(request)) return;
		this.#productActivityRevision += 1;
		this.#resolveProductResponseClosureWaitersIfQuiescent();
	}

	async #waitForStableProductRequestQuiescence(): Promise<void> {
		while (true) {
			// oxlint-disable-next-line eslint/no-await-in-loop -- Each pass waits for the current body set before checking for newly admitted product activity.
			await this.#waitForProductRequestQuiescence();
			const observedActivityRevision = this.#productActivityRevision;
			// oxlint-disable-next-line eslint/no-await-in-loop -- The browser-frame checkpoint must follow the body-completion barrier serially.
			await waitForProductBrowserFrameSettlement({
				page: this.#page,
				stage: 'product-request-quiescence',
				timeoutMilliseconds: productCompositionSettleTimeoutMilliseconds,
			});
			if (
				observedActivityRevision === this.#productActivityRevision &&
				this.#productRequestsAreQuiescent()
			) {
				return;
			}
		}
	}

	async #waitForProductRequestQuiescence(): Promise<void> {
		if (this.#productRequestsAreQuiescent()) return;
		let resolveClosure: (() => void) | null = null;
		const closure = new Promise<void>((resolve): void => {
			resolveClosure = resolve;
			this.#productResponseClosureWaiters.add(resolveClosure);
		});
		try {
			await closure;
		} finally {
			if (resolveClosure !== null) this.#productResponseClosureWaiters.delete(resolveClosure);
		}
	}

	#productRequestsAreQuiescent(): boolean {
		const activeDocumentGeneration = this.#documentGeneration();
		return (
			![...this.#unfinishedProductRequests].some(
				(request): boolean =>
					this.#productEntryByRequest.get(request)?.documentGeneration === activeDocumentGeneration,
			) &&
			!this.#productEntries.some(
				(entry): boolean =>
					entry.documentGeneration === activeDocumentGeneration &&
					entry.path === '/__bridge-product/stream' &&
					entry.httpStatus === null,
			)
		);
	}

	#resolveProductResponseClosureWaitersIfQuiescent(): void {
		if (!this.#productRequestsAreQuiescent()) return;
		for (const resolveClosure of this.#productResponseClosureWaiters) resolveClosure();
		this.#productResponseClosureWaiters.clear();
	}

	async #parseProductCommandResponse(
		response: PlaywrightResponse,
		entry: MutableProductRouteTranscriptEntry,
	): Promise<void> {
		const body = parseJSONOrNull(await response.text());
		const summary = summarizeBridgeProductResponseBody(body);
		entry.responseCode = summary.responseCode;
		entry.responseKind = summary.responseKind;
	}

	async #parseLegacyMetadataResponse(
		response: PlaywrightResponse,
		entry: MutableLegacyRouteTranscriptEntry,
	): Promise<void> {
		const responseBody = unknownRecord(parseJSONOrNull(await response.text()));
		const protocolFrame = unknownRecord(responseBody?.['protocolFrame']);
		entry.frameKind = stringValue(protocolFrame?.['frameKind']);
		entry.sequence = integerValue(protocolFrame?.['sequence']);
		entry.finalWindow = responseBody?.['nextWindowCursor'] === null;
		if (entry.finalWindow) {
			this.#resolveLegacyCompletion?.();
			this.#resolveLegacyCompletion = null;
		}
	}

	#trackResponseParser(promise: Promise<void>): void {
		this.#responseParserPromises.add(promise);
		void promise.then(
			(): void => {
				this.#responseParserPromises.delete(promise);
			},
			(error: unknown): void => {
				this.#responseParserFailure ??= error;
				this.#responseParserPromises.delete(promise);
			},
		);
	}
}

interface OwnedProductJourneyDeadline {
	readonly dispose: () => Promise<void>;
}

function createOwnedProductJourneyDeadline(props: {
	readonly browser: Browser;
	readonly page: Page;
}): OwnedProductJourneyDeadline {
	let deadlineCleanup: Promise<void> | null = null;
	const deadlineReason = 'BRIDGE_PRODUCT_JOURNEY_DEADLINE_EXCEEDED';
	const timeout = setTimeout((): void => {
		deadlineCleanup = closeOwnedProductJourneyBrowser({
			browser: props.browser,
			page: props.page,
			reason: deadlineReason,
		});
	}, productJourneyOwnedDeadlineMilliseconds);
	return {
		dispose: async (): Promise<void> => {
			clearTimeout(timeout);
			await deadlineCleanup;
		},
	};
}

async function closeOwnedProductJourneyBrowser(props: {
	readonly browser: Browser;
	readonly page: Page;
	readonly reason: string;
}): Promise<void> {
	await Promise.allSettled([
		props.page.close({ reason: props.reason }),
		props.browser.close({ reason: props.reason }),
	]);
}

async function installLegacyIntakeObserver(page: Page): Promise<void> {
	await page.addInitScript((): void => {
		type ProofWindow = Window & {
			bridgeViewerProductOnlyLegacyIntakeTranscript?: BridgeViewerLegacyIntakeTranscriptEntry[];
		};
		const proofWindow = window as ProofWindow;
		proofWindow.bridgeViewerProductOnlyLegacyIntakeTranscript = [];
		document.addEventListener('__bridge_intake_json', (event): void => {
			const detail = event instanceof CustomEvent ? unknownRecordInPage(event.detail) : null;
			const envelope = parseJSONRecordInPage(detail?.['json']);
			const payload = unknownRecordInPage(envelope?.['payload']);
			proofWindow.bridgeViewerProductOnlyLegacyIntakeTranscript?.push({
				frameKind: stringValueInPage(payload?.['frameKind']),
				generation: integerValueInPage(envelope?.['generation']),
				kind: stringValueInPage(envelope?.['kind']),
				sequence: integerValueInPage(envelope?.['sequence']),
				streamId: stringValueInPage(envelope?.['streamId']),
			});
		});

		function parseJSONRecordInPage(value: unknown): Readonly<Record<string, unknown>> | null {
			if (typeof value !== 'string') return null;
			try {
				return unknownRecordInPage(JSON.parse(value) as unknown);
			} catch {
				return null;
			}
		}

		// oxlint-disable-next-line unicorn/consistent-function-scoping -- Init scripts serialize their closure.
		function unknownRecordInPage(value: unknown): Readonly<Record<string, unknown>> | null {
			return isUnknownRecordInPage(value) ? value : null;
		}

		// oxlint-disable-next-line unicorn/consistent-function-scoping -- Init scripts serialize their closure.
		function isUnknownRecordInPage(value: unknown): value is Readonly<Record<string, unknown>> {
			return typeof value === 'object' && value !== null && !Array.isArray(value);
		}

		// oxlint-disable-next-line unicorn/consistent-function-scoping -- Init scripts serialize their closure.
		function stringValueInPage(value: unknown): string | null {
			return typeof value === 'string' ? value : null;
		}

		// oxlint-disable-next-line unicorn/consistent-function-scoping -- Init scripts serialize their closure.
		function integerValueInPage(value: unknown): number | null {
			return typeof value === 'number' && Number.isSafeInteger(value) ? value : null;
		}
	});
}

async function readLegacyIntakeTranscript(
	page: Page,
): Promise<readonly BridgeViewerLegacyIntakeTranscriptEntry[]> {
	return await page.evaluate((): readonly BridgeViewerLegacyIntakeTranscriptEntry[] => {
		type ProofWindow = Window & {
			bridgeViewerProductOnlyLegacyIntakeTranscript?: BridgeViewerLegacyIntakeTranscriptEntry[];
		};
		return (window as ProofWindow).bridgeViewerProductOnlyLegacyIntakeTranscript ?? [];
	});
}

async function waitForFileProductTerminalState(page: Page): Promise<boolean> {
	return await waitForProductCompositionState(async (): Promise<void> => {
		await page.waitForFunction(
			(selectors): boolean => {
				const shell = document.querySelector(selectors.fileShell);
				const codeCanvas = document.querySelector(selectors.fileCodeCanvas);
				const selectedContentState = shell?.getAttribute('data-worktree-open-file-state');
				const selectedPath = shell?.getAttribute('data-worktree-open-file-path');
				const renderedPath = codeCanvas?.getAttribute('data-worktree-rendered-file-path');
				const bodyPreview = codeCanvas?.getAttribute('data-worktree-open-file-body-preview');
				return (
					Number(shell?.getAttribute('data-worktree-metadata-tree-row-count') ?? '0') > 0 &&
					selectedContentState === 'ready' &&
					selectedPath !== null &&
					renderedPath === selectedPath &&
					typeof bodyPreview === 'string' &&
					bodyPreview.length > 0 &&
					isVisibleInPage(codeCanvas)
				);

				// oxlint-disable-next-line unicorn/consistent-function-scoping -- Playwright serializes this browser callback without outer helpers.
				function isVisibleInPage(element: Element | null): boolean {
					if (!(element instanceof HTMLElement) || element.closest('[hidden]') !== null)
						return false;
					const style = getComputedStyle(element);
					return (
						style.display !== 'none' &&
						style.visibility !== 'hidden' &&
						element.getClientRects().length > 0
					);
				}
			},
			bridgeViewerProductOnlySelectors,
			{ timeout: productCompositionSettleTimeoutMilliseconds },
		);
	});
}

async function waitForProductCompositionState(wait: () => Promise<void>): Promise<boolean> {
	try {
		await wait();
		return true;
	} catch (error: unknown) {
		if (error instanceof errors.TimeoutError) return false;
		throw error;
	}
}

async function readFileProductState(page: Page): Promise<BridgeViewerFileProductStateSnapshot> {
	const state = await page.evaluate((selectors) => {
		const shells = document.querySelectorAll(selectors.fileShell);
		const shell = shells.item(0);
		const codeCanvas = document.querySelector(selectors.fileCodeCanvas);
		const bodyPreview = codeCanvas?.getAttribute('data-worktree-open-file-body-preview') ?? null;
		return {
			bodyPreview,
			codeCanvasVisible: isVisibleInPage(codeCanvas),
			displayStatus: shell?.getAttribute('data-file-display-status') ?? null,
			metadataFileRowCount: Number(
				shell?.getAttribute('data-worktree-metadata-file-row-count') ?? '0',
			),
			metadataTreeRowCount: Number(
				shell?.getAttribute('data-worktree-metadata-tree-row-count') ?? '0',
			),
			renderedDisplayPath: codeCanvas?.getAttribute('data-worktree-rendered-file-path') ?? null,
			selectedContentState: shell?.getAttribute('data-worktree-open-file-state') ?? null,
			selectedDisplayPath: shell?.getAttribute('data-worktree-open-file-path') ?? null,
			shellCount: shells.length,
		};

		// oxlint-disable-next-line unicorn/consistent-function-scoping -- Playwright serializes this browser callback without outer helpers.
		function isVisibleInPage(element: Element | null): boolean {
			if (!(element instanceof HTMLElement) || element.closest('[hidden]') !== null) return false;
			const style = getComputedStyle(element);
			return (
				style.display !== 'none' &&
				style.visibility !== 'hidden' &&
				element.getClientRects().length > 0
			);
		}
	}, bridgeViewerProductOnlySelectors);
	const { bodyPreview, ...snapshot } = state;
	return {
		...snapshot,
		bodyPreviewCharacterCount: bodyPreview?.length ?? 0,
		bodyPreviewSha256: sha256OrNull(bodyPreview),
	};
}

async function readReviewProductState(page: Page): Promise<BridgeViewerReviewProductStateSnapshot> {
	const state = await page.evaluate((selectors) => {
		const shells = document.querySelectorAll(selectors.reviewShell);
		const shell = shells.item(0);
		const codePanel = document.querySelector(selectors.reviewCodePanel);
		const selectedContentCacheKeys =
			codePanel?.getAttribute('data-selected-content-cache-keys') ?? null;
		return {
			codePanelVisible: isVisibleInPage(codePanel),
			metadataItemCount: Number(shell?.getAttribute('data-review-metadata-item-count') ?? '0'),
			metadataTreeRowCount: Number(
				shell?.getAttribute('data-review-metadata-tree-row-count') ?? '0',
			),
			selectedContentCacheKeyCount: Number(
				codePanel?.getAttribute('data-selected-content-cache-key-count') ?? '0',
			),
			selectedContentCacheKeys,
			selectedContentCharacterCount: Number(
				codePanel?.getAttribute('data-selected-content-character-count') ?? '0',
			),
			selectedContentLineCount: Number(
				codePanel?.getAttribute('data-selected-content-line-count') ?? '0',
			),
			selectedContentState: shell?.getAttribute('data-selected-content-state') ?? null,
			selectedDisplayPath: shell?.getAttribute('data-selected-display-path') ?? null,
			shellCount: shells.length,
			unavailableTextVisible: (shell?.textContent ?? '').includes('Content unavailable'),
		};

		// oxlint-disable-next-line unicorn/consistent-function-scoping -- Playwright serializes this browser callback without outer helpers.
		function isVisibleInPage(element: Element | null): boolean {
			if (!(element instanceof HTMLElement) || element.closest('[hidden]') !== null) return false;
			const style = getComputedStyle(element);
			return (
				style.display !== 'none' &&
				style.visibility !== 'hidden' &&
				element.getClientRects().length > 0
			);
		}
	}, bridgeViewerProductOnlySelectors);
	const { selectedContentCacheKeys, ...snapshot } = state;
	return {
		...snapshot,
		selectedContentCacheKeysSha256: sha256OrNull(selectedContentCacheKeys),
	};
}

async function waitForViewerMode(page: Page, mode: 'file' | 'review'): Promise<void> {
	await page.waitForFunction(
		({ expectedMode, selector }): boolean =>
			document.querySelector(selector)?.getAttribute('data-bridge-viewer-mode') === expectedMode,
		{ expectedMode: mode, selector: bridgeViewerProductOnlySelectors.appRoot },
		{ timeout: productJourneyTimeoutMilliseconds },
	);
}

function sha256OrNull(value: string | null): string | null {
	return value === null || value.length === 0
		? null
		: createHash('sha256').update(value).digest('hex');
}

function responseIsFrameObservation(response: PlaywrightResponse): boolean {
	if (new URL(response.url()).pathname !== '/__bridge-product/command') return false;
	const body = unknownRecord(parseJSONOrNull(response.request().postData()));
	return body?.['kind'] === 'stream.frameObserved';
}

function responseIsSubscriptionOpen(
	response: PlaywrightResponse,
	subscriptionKind: 'file.metadata' | 'review.metadata',
): boolean {
	if (new URL(response.url()).pathname !== '/__bridge-product/command') return false;
	const body = unknownRecord(parseJSONOrNull(response.request().postData()));
	const subscription = unknownRecord(body?.['subscription']);
	return (
		body?.['kind'] === 'subscription.open' &&
		subscription?.['subscriptionKind'] === subscriptionKind
	);
}

function classifyObservedWorker(url: string, documentGeneration: number): MutableObservedWorker {
	const lifecycle = {
		closed: false,
		closedBeforeJourneyCompletion: false,
		documentGeneration,
	};
	if (url.includes('/src/core/comm-worker/bridge-comm-worker-entry.ts')) {
		return { ...lifecycle, kind: 'comm-worker', url: safeWorkerUrl(url) };
	}
	if (url.startsWith('blob:')) {
		return { ...lifecycle, kind: 'portable-blob-worker', url: 'blob:<opaque>' };
	}
	return { ...lifecycle, kind: 'module-worker', url: safeWorkerUrl(url) };
}

function safeWorkerUrl(url: string): string {
	const parsedUrl = new URL(url);
	return `${parsedUrl.pathname}${parsedUrl.search}`;
}

function parseJSONOrNull(value: string | null): unknown {
	if (value === null || value.length === 0) return null;
	try {
		return JSON.parse(value) as unknown;
	} catch {
		return null;
	}
}

function unknownRecord(value: unknown): Readonly<Record<string, unknown>> | null {
	return isUnknownRecord(value) ? value : null;
}

function isUnknownRecord(value: unknown): value is Readonly<Record<string, unknown>> {
	return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function stringValue(value: unknown): string | null {
	return typeof value === 'string' ? value : null;
}

function integerValue(value: unknown): number | null {
	return typeof value === 'number' && Number.isSafeInteger(value) ? value : null;
}

async function withBoundedTimeout<TValue>(
	promise: Promise<TValue>,
	timeoutMilliseconds: number,
	label: string,
): Promise<TValue> {
	let timeout: ReturnType<typeof setTimeout> | null = null;
	try {
		return await Promise.race([
			promise,
			new Promise<TValue>((_resolve, reject): void => {
				timeout = setTimeout(
					(): void => reject(new Error(`Timed out waiting for ${label}`)),
					timeoutMilliseconds,
				);
			}),
		]);
	} finally {
		if (timeout !== null) clearTimeout(timeout);
	}
}
