import { chromium, type Page, type Response, type Route } from 'playwright';
import { expect, test } from 'vitest';

import {
	revealReviewTreeFilePath,
	reviewTreeReachablePathScrollTopMap,
	waitForVisibleReviewTreeFilePath,
} from '../../scripts/verify-bridge-viewer-worktree-dev-server/review-tree-click.ts';
import type {
	BridgeViewerOwnedViteProductServer,
	BridgeViewerViteProductFixtureOracle,
} from './bridge-viewer-vite-product-fixture.ts';
import {
	bridgeViewerViteProductFileUrl,
	bridgeViewerViteProductReviewUrl,
} from './bridge-viewer-vite-product-url.ts';

const annotationSaveJourneyTimeoutMilliseconds = 120_000;
const annotationProjectionResponseTimeoutMilliseconds = 30_000;

export interface AnnotationSaveJourneyObservations {
	readonly gatedProjectionRequestCount: number;
	readonly projectedSavedMessageCount: number;
	readonly reloadedSavedMessageCount: number;
	readonly savingControlCountAfterCommit: number;
	readonly committedBodyCountWhileProjectionGated: number;
}

export function registerBridgeViewerViteAnnotationSaveJourneyTests(props: {
	readonly oracle: () => BridgeViewerViteProductFixtureOracle;
	readonly server: () => BridgeViewerOwnedViteProductServer;
}): void {
	test.each(['file', 'review'] as const)(
		'keeps an exact committed annotation visible while the %s projection is gated',
		async (surface) => {
			const observations = await runAnnotationSaveJourney({
				oracle: props.oracle(),
				server: props.server(),
				surface,
			});

			expect(observations.gatedProjectionRequestCount).toBeGreaterThan(0);
			expect(observations.savingControlCountAfterCommit).toBe(0);
			expect(observations.committedBodyCountWhileProjectionGated).toBe(1);
			expect(observations.projectedSavedMessageCount).toBe(1);
			expect(observations.reloadedSavedMessageCount).toBe(1);
		},
	);
}

export async function runAnnotationSaveJourney(props: {
	readonly oracle: BridgeViewerViteProductFixtureOracle;
	readonly server: BridgeViewerOwnedViteProductServer;
	readonly surface: 'file' | 'review';
}): Promise<AnnotationSaveJourneyObservations> {
	const browser = await chromium.launch({ channel: 'chrome', headless: true });
	const diagnostics: string[] = [];
	let page: Page | null = null;
	try {
		page = await browser.newPage({ viewport: { height: 980, width: 1728 } });
		observeAnnotationJourneyDiagnostics(page, diagnostics);
		const reviewFile = props.oracle.reviewFiles[0];
		if (props.surface === 'review' && reviewFile === undefined) {
			throw new Error('Review annotation Save journey requires a changed review file.');
		}
		const initialReviewProjectionReceived =
			props.surface === 'review' ? waitForAnnotationProjectionContentResponse(page) : null;
		await page.goto(
			props.surface === 'file'
				? bridgeViewerViteProductFileUrl(props.server.origin, props.oracle.largeFilePath)
				: bridgeViewerViteProductReviewUrl(props.server.origin),
			{
				timeout: annotationSaveJourneyTimeoutMilliseconds,
				waitUntil: 'domcontentloaded',
			},
		);
		if (props.surface === 'file') {
			await waitForSelectedFileReady({ oracle: props.oracle, page });
		} else {
			await selectReviewFile({ page, path: reviewFile?.path ?? '' });
			await waitForSelectedReviewReady({ itemId: reviewFile?.itemId ?? '', page });
			await initialReviewProjectionReceived;
		}
		await selectRangeForAnnotation({ endLine: 5, page, startLine: 2, surface: props.surface });

		const rootCreateCommitted = waitForCommittedAnnotationCommand(
			page,
			'root.create',
			props.surface,
		);
		const savedBody = 'Save must settle from its exact command receipt.';
		await page.getByRole('textbox', { name: 'Write an annotation in Markdown' }).fill(savedBody);
		await rootCreateCommitted;
		await page
			.locator('[data-testid="worktree-annotation-message"][data-annotation-draft="present"]')
			.waitFor({ state: 'visible', timeout: annotationProjectionResponseTimeoutMilliseconds });
		await page.waitForFunction(
			(): boolean => {
				const saveButton = document.querySelector<HTMLButtonElement>(
					'[aria-label="Save annotation"]',
				);
				return saveButton !== null && !saveButton.disabled;
			},
			undefined,
			{ timeout: annotationSaveJourneyTimeoutMilliseconds },
		);

		const projectionGate = createDeferred<void>();
		let gatedProjectionRequestCount = 0;
		let savingControlCountAfterCommit = 0;
		let committedBodyCountWhileProjectionGated = 0;
		const projectionRoutePattern = '**/__bridge-product/content**';
		const projectionRouteHandler = async (route: Route): Promise<void> => {
			const body: unknown = route.request().postDataJSON();
			if (isUnknownRecord(body) && body['contentKind'] === 'annotation.projection') {
				gatedProjectionRequestCount += 1;
				await projectionGate.promise;
			}
			await route.continue();
		};
		await page.route(projectionRoutePattern, projectionRouteHandler);
		try {
			const draftSaveCommitted = waitForCommittedAnnotationCommand(
				page,
				'draft.save',
				props.surface,
			);
			await page.getByRole('button', { name: 'Save annotation' }).click();
			await draftSaveCommitted;
			await settleBrowserFrames(page, 2);
			savingControlCountAfterCommit = await page
				.getByRole('button', { name: 'Saving annotation' })
				.count();
			committedBodyCountWhileProjectionGated = await page
				.getByText(savedBody, { exact: true })
				.count();
		} finally {
			projectionGate.resolve();
			await page.unrouteAll({ behavior: 'wait' });
		}
		const savedThreadBody = page
			.getByTestId('worktree-annotation-thread')
			.getByText(savedBody, { exact: true });
		await savedThreadBody.waitFor({
			state: 'visible',
			timeout: annotationProjectionResponseTimeoutMilliseconds,
		});
		const projectedSavedMessageCount = await savedThreadBody.count();

		await page.reload({
			timeout: annotationSaveJourneyTimeoutMilliseconds,
			waitUntil: 'domcontentloaded',
		});
		if (props.surface === 'file') {
			await waitForSelectedFileReady({ oracle: props.oracle, page });
		} else {
			await waitForSelectedReviewReady({ itemId: reviewFile?.itemId ?? '', page });
		}
		const reloadedSavedThreadBody = page
			.getByTestId('worktree-annotation-thread')
			.getByText(savedBody, { exact: true });
		await reloadedSavedThreadBody.waitFor({
			state: 'visible',
			timeout: annotationProjectionResponseTimeoutMilliseconds,
		});

		return {
			committedBodyCountWhileProjectionGated,
			gatedProjectionRequestCount,
			projectedSavedMessageCount,
			reloadedSavedMessageCount: await reloadedSavedThreadBody.count(),
			savingControlCountAfterCommit,
		};
	} catch (error: unknown) {
		if (page !== null) {
			recordAnnotationDiagnostic(
				diagnostics,
				`projection-ui:${JSON.stringify(await annotationProjectionUiDiagnostic(page))}`,
			);
		}
		throw new Error(
			`Annotation Save journey failed: browser=${JSON.stringify(diagnostics)} server=${props.server.diagnostics()}`,
			{ cause: error },
		);
	} finally {
		await page?.close();
		await browser.close();
	}
}

async function annotationProjectionUiDiagnostic(page: Page): Promise<{
	readonly composerCount: number;
	readonly refreshingCount: number;
	readonly unavailableCount: number;
}> {
	return {
		composerCount: await page
			.getByRole('textbox', { name: 'Write an annotation in Markdown' })
			.count(),
		refreshingCount: await page.getByText('Refreshing', { exact: true }).count(),
		unavailableCount: await page.getByText('Updates unavailable', { exact: true }).count(),
	};
}

function observeAnnotationJourneyDiagnostics(page: Page, diagnostics: string[]): void {
	page.on('console', (message): void => {
		if (message.type() === 'error' || message.type() === 'warning') {
			recordAnnotationDiagnostic(diagnostics, `console:${message.type()}:${message.text()}`);
		}
	});
	page.on('pageerror', (error): void => {
		recordAnnotationDiagnostic(diagnostics, `pageerror:${error.message}`);
	});
	page.on('requestfailed', (request): void => {
		const path = new URL(request.url()).pathname;
		const errorText = request.failure()?.errorText ?? 'unknown';
		if (path === '/__bridge-product/command' && errorText === 'net::ERR_ABORTED') return;
		recordAnnotationDiagnostic(diagnostics, `requestfailed:${path}:${errorText}`);
	});
	page.on('response', (response): void => {
		const request = response.request();
		const path = new URL(request.url()).pathname;
		if (!path.startsWith('/__bridge-product/')) return;
		const body: unknown = request.postDataJSON();
		const kind = isUnknownRecord(body) && typeof body['kind'] === 'string' ? body['kind'] : null;
		const contentKind =
			isUnknownRecord(body) && typeof body['contentKind'] === 'string' ? body['contentKind'] : null;
		const call = isUnknownRecord(body) && isUnknownRecord(body['call']) ? body['call'] : null;
		const requestSequence =
			isUnknownRecord(body) && typeof body['requestSequence'] === 'number'
				? body['requestSequence']
				: null;
		const method = call !== null && typeof call['method'] === 'string' ? call['method'] : null;
		if (method === 'file.activeViewerMode.update' && call !== null) {
			const activeViewerRequest = call['request'];
			const activeSource = isUnknownRecord(activeViewerRequest)
				? activeViewerRequest['activeSource']
				: null;
			recordAnnotationDiagnostic(
				diagnostics,
				`file-active-source:${JSON.stringify(
					isUnknownRecord(activeSource)
						? {
								generation: activeSource['generation'],
								streamIdPresent:
									typeof activeSource['streamId'] === 'string' &&
									activeSource['streamId'].length > 0,
							}
						: null,
				)}`,
			);
		}
		if (
			method === 'file.annotations.projection.query' ||
			method === 'review.annotations.projection.query'
		) {
			void response
				.json()
				.then((responseBody: unknown): void => {
					recordAnnotationDiagnostic(
						diagnostics,
						`projection-query-result:${JSON.stringify(annotationProjectionQueryResultDiagnostic(responseBody))}`,
					);
				})
				.catch((): void => {
					recordAnnotationDiagnostic(diagnostics, 'projection-query-result:unreadable');
				});
		}
		recordAnnotationDiagnostic(
			diagnostics,
			`response:${path}:${response.status()}:${kind ?? '-'}:${method ?? contentKind ?? '-'}:${requestSequence ?? '-'}`,
		);
	});
}

function annotationProjectionQueryResultDiagnostic(value: unknown): unknown {
	if (!isUnknownRecord(value)) return { shape: typeof value };
	if (value['kind'] === 'request.error') {
		return {
			code: value['code'],
			kind: value['kind'],
			nextExpectedRequestSequence: value['nextExpectedRequestSequence'],
			requestSequence: value['requestSequence'],
			retryable: value['retryable'],
			safeMessage: value['safeMessage'],
		};
	}
	const call = value['call'];
	if (!isUnknownRecord(call)) return { kind: value['kind'] };
	const result = call['result'];
	if (!isUnknownRecord(result)) return { kind: value['kind'], resultShape: typeof result };
	const descriptor = result['descriptor'];
	if (!isUnknownRecord(descriptor)) {
		return {
			code: result['code'],
			kind: value['kind'],
			resultKind: result['kind'],
		};
	}
	const page = descriptor['page'];
	return {
		descriptorPresent: true,
		kind: value['kind'],
		requestSequence: value['requestSequence'],
		page: isUnknownRecord(page)
			? {
					pageOrdinal: page['pageOrdinal'],
					sourceGeneration: page['sourceGeneration'],
				}
			: null,
	};
}

function recordAnnotationDiagnostic(diagnostics: string[], value: string): void {
	const maximumDiagnosticCount = 128;
	if (diagnostics.length >= maximumDiagnosticCount) diagnostics.shift();
	diagnostics.push(value);
}

function createDeferred<TValue>(): {
	readonly promise: Promise<TValue>;
	readonly resolve: (value: TValue) => void;
} {
	let resolvePromise: ((value: TValue) => void) | null = null;
	const promise = new Promise<TValue>((resolve): void => {
		resolvePromise = resolve;
	});
	return {
		promise,
		resolve: (value): void => {
			if (resolvePromise === null) throw new Error('Deferred resolver is unavailable.');
			resolvePromise(value);
		},
	};
}

function isUnknownRecord(value: unknown): value is Readonly<Record<string, unknown>> {
	return typeof value === 'object' && value !== null && !Array.isArray(value);
}

async function waitForSelectedReviewReady(props: {
	readonly itemId: string;
	readonly page: Page;
}): Promise<void> {
	await props.page.waitForFunction(
		(itemId: string): boolean => {
			const panel = document.querySelector('[data-testid="bridge-code-view-panel"]');
			if (panel?.getAttribute('data-selected-item-id') !== itemId) return false;
			const pending: Array<Element | ShadowRoot> = [panel];
			let visibleAdditionRowCount = 0;
			while (pending.length > 0) {
				const current = pending.shift();
				if (current === undefined) break;
				for (const row of current.querySelectorAll('[data-column-number]')) {
					const bounds = row.getBoundingClientRect();
					if (row.closest('[data-additions]') !== null && bounds.width > 0 && bounds.height > 0) {
						visibleAdditionRowCount += 1;
						if (visibleAdditionRowCount >= 3) return true;
					}
				}
				for (const descendant of current.querySelectorAll('*')) {
					if (descendant.shadowRoot !== null) pending.push(descendant.shadowRoot);
				}
			}
			return false;
		},
		props.itemId,
		{ timeout: annotationSaveJourneyTimeoutMilliseconds },
	);
}

async function selectReviewFile(props: {
	readonly page: Page;
	readonly path: string;
}): Promise<void> {
	await props.page.waitForSelector('[data-testid="review-viewer-shell"]', {
		timeout: annotationSaveJourneyTimeoutMilliseconds,
	});
	const scrollTopByPath = await reviewTreeReachablePathScrollTopMap(props.page);
	const scrollTopHint = scrollTopByPath.get(props.path);
	if (scrollTopHint === undefined) {
		throw new Error(`Review annotation journey cannot reach tree path ${props.path}.`);
	}
	await revealReviewTreeFilePath({ page: props.page, path: props.path, scrollTopHint });
	await waitForVisibleReviewTreeFilePath({ page: props.page, path: props.path });
	await props.page.evaluate((path: string): void => {
		const treeHost = document.querySelector(
			'[data-testid="bridge-review-trees-panel"] file-tree-container',
		);
		const row = treeHost?.shadowRoot?.querySelector(`[data-item-path="${CSS.escape(path)}"]`);
		if (!(row instanceof HTMLElement)) throw new Error(`Review file row missing: ${path}`);
		row.click();
	}, props.path);
}

async function selectRangeForAnnotation(props: {
	readonly endLine: number;
	readonly page: Page;
	readonly startLine: number;
	readonly surface: 'file' | 'review';
}): Promise<void> {
	let startBounds: AnnotationRangeBounds | null;
	let endBounds: AnnotationRangeBounds | null;
	if (props.surface === 'file') {
		const startRow = props.page.locator(`[data-column-number="${props.startLine}"]`).first();
		const endRow = props.page.locator(`[data-column-number="${props.endLine}"]`).first();
		await startRow.waitFor({ state: 'visible', timeout: annotationSaveJourneyTimeoutMilliseconds });
		await endRow.waitFor({ state: 'visible', timeout: annotationSaveJourneyTimeoutMilliseconds });
		startBounds = await startRow.boundingBox();
		endBounds = await endRow.boundingBox();
	} else {
		[startBounds, endBounds] = await reviewAdditionRangeBounds(props.page);
	}
	if (startBounds === null || endBounds === null) {
		throw new Error('File annotation range rows must have visible pointer geometry.');
	}
	await props.page.mouse.move(startBounds.x + 4, startBounds.y + startBounds.height / 2);
	await props.page.mouse.down();
	await props.page.mouse.move(endBounds.x + 4, endBounds.y + endBounds.height / 2, { steps: 4 });
	await props.page.mouse.up();
	const endpointUtility = props.page.locator('[data-utility-button]').first();
	await endpointUtility.waitFor({
		state: 'visible',
		timeout: annotationSaveJourneyTimeoutMilliseconds,
	});
	await endpointUtility.click();
	await props.page
		.getByRole('textbox', { name: 'Write an annotation in Markdown' })
		.waitFor({ state: 'visible', timeout: annotationSaveJourneyTimeoutMilliseconds });
}

interface AnnotationRangeBounds {
	readonly height: number;
	readonly width: number;
	readonly x: number;
	readonly y: number;
}

async function reviewAdditionRangeBounds(
	page: Page,
): Promise<readonly [AnnotationRangeBounds, AnnotationRangeBounds]> {
	const additionRows = await page.evaluate((): AnnotationRangeBounds[] => {
		const panel = document.querySelector('[data-testid="bridge-code-view-panel"]');
		if (panel === null) return [];
		const pending: Array<Element | ShadowRoot> = [panel];
		const rows: AnnotationRangeBounds[] = [];
		while (pending.length > 0) {
			const current = pending.shift();
			if (current === undefined) break;
			for (const row of current.querySelectorAll('[data-column-number]')) {
				const bounds = row.getBoundingClientRect();
				if (row.closest('[data-additions]') !== null && bounds.width > 0 && bounds.height > 0) {
					rows.push({ height: bounds.height, width: bounds.width, x: bounds.x, y: bounds.y });
				}
			}
			for (const descendant of current.querySelectorAll('*')) {
				if (descendant.shadowRoot !== null) pending.push(descendant.shadowRoot);
			}
		}
		return rows;
	});
	const orderedAdditionRows = additionRows.toSorted((left, right): number => left.y - right.y);
	const startBounds = orderedAdditionRows[0];
	const endBounds = orderedAdditionRows[2];
	if (startBounds === undefined || endBounds === undefined) {
		throw new Error('Review annotation journey requires visible additions-side line geometry.');
	}
	return [startBounds, endBounds];
}

async function settleBrowserFrames(page: Page, frameCount: number): Promise<void> {
	for (let frameIndex = 0; frameIndex < frameCount; frameIndex += 1) {
		// oxlint-disable-next-line no-await-in-loop -- Each frame is an ordered browser settlement boundary.
		await page.evaluate(async (): Promise<void> => {
			await new Promise<void>((resolve): void => {
				requestAnimationFrame((): void => resolve());
			});
		});
	}
}

async function waitForCommittedAnnotationCommand(
	page: Page,
	operationKind: 'draft.save' | 'root.create',
	surface: 'file' | 'review',
): Promise<void> {
	const response = await page.waitForResponse(
		(candidate): boolean => isAnnotationCommandResponse(candidate, operationKind, surface),
		{ timeout: annotationSaveJourneyTimeoutMilliseconds },
	);
	const body: unknown = await response.json();
	if (
		!isUnknownRecord(body) ||
		body['kind'] !== 'call.completed' ||
		!isUnknownRecord(body['call']) ||
		body['call']['method'] !== `${surface}.annotations.command` ||
		!isUnknownRecord(body['call']['result']) ||
		body['call']['result']['kind'] !== 'completed' ||
		!isUnknownRecord(body['call']['result']['outcome']) ||
		!isUnknownRecord(body['call']['result']['outcome']['status']) ||
		body['call']['result']['outcome']['status']['kind'] !== 'committed'
	) {
		throw new Error(
			`Expected committed ${operationKind} response, received ${JSON.stringify(body)}.`,
		);
	}
}

async function waitForAnnotationProjectionContentResponse(page: Page): Promise<void> {
	const response = await page.waitForResponse(
		(candidate): boolean => {
			const request = candidate.request();
			if (
				request.method() !== 'POST' ||
				new URL(request.url()).pathname !== '/__bridge-product/content'
			) {
				return false;
			}
			const body: unknown = request.postDataJSON();
			return isUnknownRecord(body) && body['contentKind'] === 'annotation.projection';
		},
		{ timeout: annotationProjectionResponseTimeoutMilliseconds },
	);
	if (!response.ok()) {
		throw new Error(`Annotation projection content failed with HTTP ${response.status()}.`);
	}
}

function isAnnotationCommandResponse(
	response: Response,
	operationKind: 'draft.save' | 'root.create',
	surface: 'file' | 'review',
): boolean {
	const request = response.request();
	if (
		request.method() !== 'POST' ||
		new URL(request.url()).pathname !== '/__bridge-product/command'
	) {
		return false;
	}
	const body: unknown = request.postDataJSON();
	return (
		isUnknownRecord(body) &&
		body['kind'] === 'product.call' &&
		isUnknownRecord(body['call']) &&
		body['call']['method'] === `${surface}.annotations.command` &&
		isUnknownRecord(body['call']['request']) &&
		isUnknownRecord(body['call']['request']['operation']) &&
		body['call']['request']['operation']['kind'] === operationKind
	);
}

async function waitForSelectedFileReady(props: {
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
			expectedLineCount: props.oracle.fileContent.lineCount,
			expectedSha256: props.oracle.fileContent.sha256,
			path: props.oracle.largeFilePath,
		},
		{ timeout: annotationSaveJourneyTimeoutMilliseconds },
	);
}
