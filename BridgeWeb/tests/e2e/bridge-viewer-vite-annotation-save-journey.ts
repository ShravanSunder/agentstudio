import { chromium, type Page, type Response, type Route } from 'playwright';
import { expect, test } from 'vitest';

import {
	revealReviewTreeFilePath,
	reviewTreeReachablePathScrollTopMap,
	waitForVisibleReviewTreeFilePath,
} from '../../scripts/verify-bridge-viewer-worktree-dev-server/review-tree-click.ts';
import {
	type AnnotationOutputIdentityCapture,
	verifyAnnotationOutputCaptures,
} from './bridge-viewer-vite-annotation-output-capture.ts';
import {
	annotationProjectionContentRequestDiagnostic,
	annotationProjectionQueryResultDiagnostic,
	annotationProjectionUiDiagnostic,
	waitForDemandedAnnotationProjectionContent,
} from './bridge-viewer-vite-annotation-projection-test-support.ts';
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
const requiredAnnotationLifecycleStages = [
	'annotation_invalidation_received',
	'annotation_paint_started',
	'annotation_paint_terminal',
	'content_transfer_started',
	'content_transfer_terminal',
	'main_thread_install_started',
	'main_thread_install_terminal',
	'projection_convergence_started',
	'projection_query_started',
	'projection_store_started',
	'projection_store_terminal',
	'projection_validation_started',
	'projection_validation_terminal',
	'projection_query_terminal',
	'projection_convergence_terminal',
	'worker_application_started',
	'worker_application_terminal',
] as const;

export interface AnnotationSaveJourneyObservations {
	readonly correlatedLifecycleStageCount: number;
	readonly gatedProjectionRequestCount: number;
	readonly projectedSavedMessageCount: number;
	readonly reloadedSavedMessageCount: number;
	readonly savingControlCountAfterCommit: number;
	readonly committedBodyCountWhileProjectionGated: number;
	readonly outputIdentity: AnnotationOutputIdentityCapture;
}

interface ReleasedDraftReloadJourneyObservations {
	readonly reloadedCollapsedDraftCount: number;
	readonly reloadedDraftLabelCount: number;
	readonly removedDraftCount: number;
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
			expect(observations.correlatedLifecycleStageCount).toBe(
				requiredAnnotationLifecycleStages.length,
			);
			expect(observations.projectedSavedMessageCount).toBe(1);
			expect(observations.reloadedSavedMessageCount).toBe(1);
		},
	);

	test('restores a released Review root draft after a full document reload', async () => {
		const observations = await runReleasedDraftReloadJourney({
			oracle: props.oracle(),
			server: props.server(),
		});

		expect(observations.reloadedCollapsedDraftCount).toBe(1);
		expect(observations.reloadedDraftLabelCount).toBeGreaterThan(0);
		expect(observations.removedDraftCount).toBe(0);
	});
}

async function runReleasedDraftReloadJourney(props: {
	readonly oracle: BridgeViewerViteProductFixtureOracle;
	readonly server: BridgeViewerOwnedViteProductServer;
}): Promise<ReleasedDraftReloadJourneyObservations> {
	const browser = await chromium.launch({ channel: 'chrome', headless: true });
	let page: Page | null = null;
	try {
		page = await browser.newPage({ viewport: { height: 980, width: 1728 } });
		const reviewFile = props.oracle.reviewFiles[0];
		if (reviewFile === undefined) {
			throw new Error('Review released-draft journey requires a changed review file.');
		}
		await page.goto(bridgeViewerViteProductReviewUrl(props.server.origin), {
			timeout: annotationSaveJourneyTimeoutMilliseconds,
			waitUntil: 'domcontentloaded',
		});
		await selectReviewFile({ page, path: reviewFile.path });
		await waitForSelectedReviewReady({ itemId: reviewFile.itemId, page });
		await selectRangeForAnnotation({ endLine: 5, page, startLine: 2, surface: 'review' });

		const rootCreateCommitted = waitForCommittedAnnotationCommand(page, 'root.create', 'review');
		const draftBody = 'Released Review draft survives document reload.';
		const composer = page.getByRole('textbox', { name: 'Write an annotation in Markdown' });
		await composer.fill(draftBody);
		await rootCreateCommitted;
		await page
			.locator('[data-testid="worktree-annotation-message"][data-annotation-draft="present"]')
			.waitFor({ state: 'visible', timeout: annotationProjectionResponseTimeoutMilliseconds });

		const releaseCommitted = waitForCommittedAnnotationCommand(
			page,
			'draft.edit.release',
			'review',
			annotationProjectionResponseTimeoutMilliseconds,
		);
		await composer.press('Escape');
		await releaseCommitted;

		await page.reload({
			timeout: annotationSaveJourneyTimeoutMilliseconds,
			waitUntil: 'domcontentloaded',
		});
		await waitForSelectedReviewReady({ itemId: reviewFile.itemId, page });
		const reloadedDraft = page.getByText(draftBody, { exact: true });
		await reloadedDraft.waitFor({
			state: 'visible',
			timeout: annotationProjectionResponseTimeoutMilliseconds,
		});
		const reloadedCollapsedDraftCount = await reloadedDraft.count();
		const reloadedDraftLabelCount = await page.getByText('Draft', { exact: true }).count();

		await reloadedDraft.click();
		await page.getByRole('button', { name: 'Revert draft' }).click();
		await reloadedDraft.waitFor({
			state: 'hidden',
			timeout: annotationProjectionResponseTimeoutMilliseconds,
		});

		return {
			reloadedCollapsedDraftCount,
			reloadedDraftLabelCount,
			removedDraftCount: await reloadedDraft.count(),
		};
	} finally {
		await page?.close();
		await browser.close();
	}
}

export async function runAnnotationSaveJourney(props: {
	readonly oracle: BridgeViewerViteProductFixtureOracle;
	readonly server: BridgeViewerOwnedViteProductServer;
	readonly surface: 'file' | 'review';
}): Promise<AnnotationSaveJourneyObservations> {
	const browser = await chromium.launch({ channel: 'chrome', headless: true });
	const diagnostics: string[] = [];
	let page: Page | null = null;
	let expectedSavedBody: string | null = null;
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
		const sourceRefreshCommitted =
			props.surface === 'file'
				? waitForCommittedAnnotationCommand(page, 'source.refresh', 'file')
				: null;
		const demandedDraftProjectionCommitted =
			sourceRefreshCommitted === null
				? null
				: waitForDemandedAnnotationProjectionContent({
						afterRequestSequence: sourceRefreshCommitted.then((receipt) => receipt.requestSequence),
						page,
						sessionId: rootCreateCommitted.then((receipt) => {
							if (receipt.sessionId === null) {
								throw new Error('Committed root annotation did not identify its session.');
							}
							return receipt.sessionId;
						}),
					});
		const savedBody = `${props.surface === 'file' ? 'File' : 'Review'} Save must settle from its exact command receipt.`;
		expectedSavedBody = savedBody;
		await page.getByRole('textbox', { name: 'Write an annotation in Markdown' }).fill(savedBody);
		await rootCreateCommitted;
		if (sourceRefreshCommitted !== null) await sourceRefreshCommitted;
		if (demandedDraftProjectionCommitted !== null) await demandedDraftProjectionCommitted;
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
			const gatedProjectionRequest = page.waitForRequest(
				(request): boolean => {
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
			const draftSaveCommitted = waitForCommittedAnnotationCommand(
				page,
				'draft.save',
				props.surface,
			);
			await page.getByRole('button', { name: 'Save annotation' }).click();
			await draftSaveCommitted;
			await gatedProjectionRequest;
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
		const correlatedLifecycleStageCount = await waitForCompleteAnnotationLifecycleTelemetry(page);

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
		const reloadedSavedMessageCount = await reloadedSavedThreadBody.count();
		const outputIdentity = await verifyAnnotationOutputCaptures({
			dataRootPath: props.oracle.dataRootPath,
			page,
			savedBody,
			timeoutMilliseconds: annotationProjectionResponseTimeoutMilliseconds,
			worktreeRoot: props.oracle.worktreeRoot,
		});

		return {
			committedBodyCountWhileProjectionGated,
			correlatedLifecycleStageCount,
			gatedProjectionRequestCount,
			outputIdentity,
			projectedSavedMessageCount,
			reloadedSavedMessageCount,
			savingControlCountAfterCommit,
		};
	} catch (error: unknown) {
		if (page !== null) {
			recordAnnotationDiagnostic(
				diagnostics,
				`projection-ui:${JSON.stringify(
					await annotationProjectionUiDiagnostic(page, expectedSavedBody),
				)}`,
			);
			if (props.surface === 'file') {
				recordAnnotationDiagnostic(
					diagnostics,
					`file-readiness:${JSON.stringify(
						await selectedFileReadinessDiagnostic({ oracle: props.oracle, page }),
					)}`,
				);
				recordAnnotationDiagnostic(
					diagnostics,
					`file-render-telemetry:${JSON.stringify(
						await selectedFileRenderTelemetryDiagnostic(page),
					)}`,
				);
			}
		}
		throw new Error(
			`Annotation Save journey failed: cause=${JSON.stringify(annotationSaveJourneyCause(error))} browser=${JSON.stringify(diagnostics)} server=${props.server.diagnostics()}`,
			{ cause: error },
		);
	} finally {
		await page?.close();
		await browser.close();
	}
}

function annotationSaveJourneyCause(error: unknown): Readonly<Record<string, string>> {
	return error instanceof Error
		? { kind: error.name, message: error.message }
		: { kind: typeof error, message: String(error) };
}

async function waitForCompleteAnnotationLifecycleTelemetry(page: Page): Promise<number> {
	const statusUrl = new URL('/__bridge-dev-telemetry/status', page.url()).toString();
	let completedStageCount: number | null = null;
	await expect
		.poll(
			async (): Promise<boolean> => {
				const response = await fetch(statusUrl, { cache: 'no-store' });
				if (!response.ok) return false;
				const body: unknown = await response.json();
				if (typeof body !== 'object' || body === null || !('recentSamples' in body)) return false;
				const recentSamples = body.recentSamples;
				const operationLifecycle = Reflect.get(body, 'operationLifecycle');
				if (!Array.isArray(recentSamples)) return false;
				const stagesByOperation = new Map<string, Set<string>>();
				for (const sample of recentSamples) {
					if (typeof sample !== 'object' || sample === null || !('stringAttributes' in sample)) {
						continue;
					}
					const attributes = sample.stringAttributes;
					if (typeof attributes !== 'object' || attributes === null) continue;
					const operationId = Reflect.get(attributes, 'agentstudio.bridge.operation.id');
					const phase = Reflect.get(attributes, 'agentstudio.bridge.phase');
					if (typeof operationId !== 'string' || typeof phase !== 'string') continue;
					const stages = stagesByOperation.get(operationId) ?? new Set<string>();
					stages.add(phase);
					stagesByOperation.set(operationId, stages);
				}
				for (const [operationId, stages] of stagesByOperation) {
					if (!requiredAnnotationLifecycleStages.every((stage) => stages.has(stage))) continue;
					if (typeof operationLifecycle !== 'object' || operationLifecycle === null) continue;
					const completedOperationIds = Reflect.get(operationLifecycle, 'completedOperationIds');
					const malformed = Reflect.get(operationLifecycle, 'malformed');
					const missingTerminals = Reflect.get(operationLifecycle, 'missingTerminals');
					const matchingMalformed = Array.isArray(malformed)
						? malformed.filter(
								(entry): boolean =>
									typeof entry === 'object' &&
									entry !== null &&
									Reflect.get(entry, 'operationCorrelationId') === operationId,
							)
						: null;
					const matchingMissingTerminals = Array.isArray(missingTerminals)
						? missingTerminals.filter(
								(entry): boolean =>
									typeof entry === 'object' &&
									entry !== null &&
									Reflect.get(entry, 'operationCorrelationId') === operationId,
							)
						: null;
					if (
						Array.isArray(completedOperationIds) &&
						completedOperationIds.includes(operationId) &&
						matchingMalformed?.length === 0 &&
						matchingMissingTerminals?.length === 0
					) {
						completedStageCount = requiredAnnotationLifecycleStages.length;
						return true;
					}
				}
				return false;
			},
			{ timeout: annotationProjectionResponseTimeoutMilliseconds },
		)
		.toBe(true);
	if (completedStageCount === null) {
		throw new Error('Annotation lifecycle telemetry completed without a stage count');
	}
	return completedStageCount;
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
		const body: unknown = request.postDataJSON();
		recordAnnotationDiagnostic(
			diagnostics,
			`requestfailed:${path}:${errorText}:${JSON.stringify(annotationProjectionContentRequestDiagnostic(body))}`,
		);
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
		const callRequest = call !== null && isUnknownRecord(call['request']) ? call['request'] : null;
		const operation =
			callRequest !== null && isUnknownRecord(callRequest['operation'])
				? callRequest['operation']
				: null;
		const operationKind =
			operation !== null && typeof operation['kind'] === 'string' ? operation['kind'] : null;
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
						`projection-query-result:${JSON.stringify(
							annotationProjectionQueryResultDiagnostic(responseBody, callRequest),
						)}`,
					);
				})
				.catch((): void => {
					recordAnnotationDiagnostic(diagnostics, 'projection-query-result:unreadable');
				});
		}
		if (contentKind === 'annotation.projection') {
			recordAnnotationDiagnostic(
				diagnostics,
				`projection-content:${JSON.stringify(annotationProjectionContentRequestDiagnostic(body))}`,
			);
		}
		if (operationKind === 'output.history') {
			void response
				.json()
				.then((responseBody: unknown): void => {
					recordAnnotationDiagnostic(
						diagnostics,
						`history-result:${JSON.stringify(annotationHistoryResultDiagnostic(responseBody))}`,
					);
				})
				.catch((): void => {
					recordAnnotationDiagnostic(diagnostics, 'history-result:unreadable');
				});
		}
		recordAnnotationDiagnostic(
			diagnostics,
			`response:${path}:${response.status()}:${kind ?? '-'}:${method ?? contentKind ?? '-'}:${operationKind ?? '-'}:${requestSequence ?? '-'}`,
		);
	});
}

function annotationHistoryResultDiagnostic(value: unknown): unknown {
	if (!isUnknownRecord(value) || !isUnknownRecord(value['call'])) return { call: 'missing' };
	const call = value['call'];
	if (!isUnknownRecord(call['result'])) return { result: 'missing' };
	const result = call['result'];
	if (!isUnknownRecord(result['outcome']) || !isUnknownRecord(result['outcome']['status'])) {
		return { outcome: 'missing' };
	}
	const status = result['outcome']['status'];
	const summaries = Array.isArray(status['summaries']) ? status['summaries'] : [];
	const firstSummary = summaries[0];
	return {
		firstKeys: isUnknownRecord(firstSummary) ? Object.keys(firstSummary).toSorted() : [],
		kind: status['kind'],
		firstSessionId: isUnknownRecord(firstSummary) ? firstSummary['sessionId'] : null,
		outcomeSessionId: result['outcome']['sessionId'],
		summaryCount: summaries.length,
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

export async function waitForSelectedReviewReady(props: {
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

export async function selectReviewFile(props: {
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

export async function selectRangeForAnnotation(props: {
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
		const lineUtility = props.page.locator('[data-utility-button]').first();
		// oxlint-disable-next-line no-await-in-loop -- Each bounded pointer attempt must settle before retry.
		for (let attempt = 0; attempt < 3; attempt += 1) {
			startBounds = await startRow.boundingBox();
			endBounds = await endRow.boundingBox();
			if (startBounds === null || endBounds === null) {
				throw new Error('File annotation range rows must have visible pointer geometry.');
			}
			await props.page.mouse.move(startBounds.x + 4, startBounds.y + startBounds.height / 2);
			await props.page.mouse.down();
			await props.page.mouse.move(endBounds.x + 4, endBounds.y + endBounds.height / 2, {
				steps: 4,
			});
			await props.page.mouse.up();
			try {
				await lineUtility.waitFor({ state: 'visible', timeout: 2_000 });
				await lineUtility.click();
				await props.page
					.getByRole('textbox', { name: 'Write an annotation in Markdown' })
					.waitFor({ state: 'visible', timeout: annotationProjectionResponseTimeoutMilliseconds });
				return;
			} catch (error: unknown) {
				if (attempt === 2) throw error;
			}
		}
		throw new Error('File annotation range selection exhausted its bounded attempts.');
	} else {
		const interactionState = await props.page.evaluate(
			(): {
				readonly inert: boolean;
				readonly pointerEvents: string | null;
			} => {
				const canvas = document.querySelector('[data-testid="bridge-review-canvas"]');
				return {
					inert: canvas instanceof HTMLElement && canvas.inert,
					pointerEvents: canvas instanceof Element ? getComputedStyle(canvas).pointerEvents : null,
				};
			},
		);
		if (interactionState.inert || interactionState.pointerEvents === 'none') {
			throw new Error(
				`Review annotation canvas is not interactive: ${JSON.stringify(interactionState)}`,
			);
		}
		[startBounds, endBounds] = await reviewAdditionRangeBounds({
			endLine: props.endLine,
			page: props.page,
			startLine: props.startLine,
		});
	}
	if (startBounds === null || endBounds === null) {
		throw new Error('File annotation range rows must have visible pointer geometry.');
	}
	await props.page.mouse.move(startBounds.x + 4, startBounds.y + startBounds.height / 2);
	await props.page.mouse.down();
	await props.page.mouse.move(endBounds.x + 4, endBounds.y + endBounds.height / 2, { steps: 4 });
	await props.page.mouse.up();
	if (props.surface === 'review') {
		const selectionDiagnostic = await reviewRangeSelectionDiagnostic({
			endBounds,
			page: props.page,
			startBounds,
		});
		if (selectionDiagnostic.selectedLineCount === 0) {
			throw new Error(
				`Review annotation drag did not establish Pierre selection: ${JSON.stringify(selectionDiagnostic)}`,
			);
		}
	}
	const endpointUtility = props.page.locator('[data-utility-button]').first();
	await endpointUtility.waitFor({
		state: 'visible',
		timeout: annotationProjectionResponseTimeoutMilliseconds,
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

interface ReviewRangeSelectionDiagnostic {
	readonly endHitPath: readonly string[];
	readonly selectedLineCount: number;
	readonly startHitPath: readonly string[];
	readonly utilityButtonCount: number;
}

async function reviewRangeSelectionDiagnostic(props: {
	readonly endBounds: AnnotationRangeBounds;
	readonly page: Page;
	readonly startBounds: AnnotationRangeBounds;
}): Promise<ReviewRangeSelectionDiagnostic> {
	return await props.page.evaluate(
		({ endBounds, startBounds }): ReviewRangeSelectionDiagnostic => {
			const queryComposedCount = (selector: string): number => {
				const pending: Array<Document | ShadowRoot> = [document];
				let count = 0;
				while (pending.length > 0) {
					const current = pending.shift();
					if (current === undefined) break;
					count += current.querySelectorAll(selector).length;
					for (const descendant of current.querySelectorAll('*')) {
						if (descendant.shadowRoot !== null) pending.push(descendant.shadowRoot);
					}
				}
				return count;
			};
			const hitPath = (bounds: AnnotationRangeBounds): readonly string[] => {
				const point = { x: bounds.x + 4, y: bounds.y + bounds.height / 2 };
				const path: string[] = [];
				let currentRoot: Document | ShadowRoot = document;
				while (true) {
					const hit: Element | undefined = currentRoot.elementsFromPoint(point.x, point.y)[0];
					if (hit === undefined) break;
					path.push(
						[
							hit.tagName.toLowerCase(),
							hit.getAttribute('data-column-number'),
							hit.getAttribute('data-selected-line'),
							hit.getAttribute('data-testid'),
						]
							.filter((part): part is string => part !== null)
							.join(':'),
					);
					if (hit.shadowRoot === null) break;
					currentRoot = hit.shadowRoot;
				}
				return path;
			};
			return {
				endHitPath: hitPath(endBounds),
				selectedLineCount: queryComposedCount('[data-selected-line]'),
				startHitPath: hitPath(startBounds),
				utilityButtonCount: queryComposedCount('[data-utility-button]'),
			};
		},
		{ endBounds: props.endBounds, startBounds: props.startBounds },
	);
}

async function reviewAdditionRangeBounds(props: {
	readonly endLine: number;
	readonly page: Page;
	readonly startLine: number;
}): Promise<readonly [AnnotationRangeBounds, AnnotationRangeBounds]> {
	const additionRows = await props.page.evaluate((): AnnotationRangeBounds[] => {
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
		throw new Error('Review annotation journey requires three visible additions-side rows.');
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

export async function waitForCommittedAnnotationCommand(
	page: Page,
	operationKind: 'draft.edit.release' | 'draft.save' | 'root.create' | 'source.refresh',
	surface: 'file' | 'review',
	timeoutMilliseconds = annotationSaveJourneyTimeoutMilliseconds,
): Promise<{ readonly requestSequence: number; readonly sessionId: string | null }> {
	const response = await page.waitForResponse(
		(candidate): boolean => isAnnotationCommandResponse(candidate, operationKind, surface),
		{ timeout: timeoutMilliseconds },
	);
	const body: unknown = await response.json();
	if (
		!isUnknownRecord(body) ||
		typeof body['requestSequence'] !== 'number' ||
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
	const outcome = body['call']['result']['outcome'];
	return {
		requestSequence: body['requestSequence'],
		sessionId: typeof outcome['sessionId'] === 'string' ? outcome['sessionId'] : null,
	};
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
	operationKind: 'draft.edit.release' | 'draft.save' | 'root.create' | 'source.refresh',
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

export async function waitForSelectedFileReady(props: {
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

async function selectedFileReadinessDiagnostic(props: {
	readonly oracle: BridgeViewerViteProductFixtureOracle;
	readonly page: Page;
}): Promise<Readonly<Record<string, unknown>>> {
	return await props.page.evaluate(
		({ expectedLineCount, expectedSha256, path }): Readonly<Record<string, unknown>> => {
			const canvas = document.querySelector('[data-testid="bridge-file-viewer-code-canvas"]');
			const painted = canvas?.querySelector(
				'diffs-container[data-bridge-painted-source-correlations]',
			);
			const encodedCorrelations =
				painted?.getAttribute('data-bridge-painted-source-correlations') ?? '[]';
			let correlations: unknown = null;
			try {
				correlations = JSON.parse(encodedCorrelations);
			} catch {
				correlations = { invalidJSON: encodedCorrelations.slice(0, 1_000) };
			}
			return {
				canvasPresent: canvas !== null,
				expectedLineCount,
				expectedPath: path,
				expectedSha256,
				observedCorrelations: correlations,
				observedLineCount: canvas?.getAttribute('data-worktree-rendered-line-count') ?? null,
				observedOpenPath: canvas?.getAttribute('data-worktree-open-file-path') ?? null,
				observedOpenState: canvas?.getAttribute('data-worktree-open-file-state') ?? null,
				observedRenderedPath: canvas?.getAttribute('data-worktree-rendered-file-path') ?? null,
			};
		},
		{
			expectedLineCount: props.oracle.fileContent.lineCount,
			expectedSha256: props.oracle.fileContent.sha256,
			path: props.oracle.largeFilePath,
		},
	);
}

async function selectedFileRenderTelemetryDiagnostic(
	page: Page,
): Promise<readonly Readonly<Record<string, unknown>>[]> {
	return await page.evaluate(async (): Promise<readonly Readonly<Record<string, unknown>>[]> => {
		const response = await fetch('/__bridge-dev-telemetry/status');
		if (!response.ok) return [{ status: response.status }];
		const body: unknown = await response.json();
		if (typeof body !== 'object' || body === null) return [{ status: 'invalid-body' }];
		const recentSamples = Reflect.get(body, 'recentSamples');
		if (!Array.isArray(recentSamples)) return [{ status: 'missing-samples' }];
		return recentSamples
			.filter((sample): boolean => {
				if (typeof sample !== 'object' || sample === null) return false;
				const stringAttributes = Reflect.get(sample, 'stringAttributes');
				if (typeof stringAttributes !== 'object' || stringAttributes === null) return false;
				return (
					Reflect.get(stringAttributes, 'agentstudio.bridge.viewer') === 'file' &&
					(Reflect.get(sample, 'name') === 'performance.bridge.web.render_disposition_admission' ||
						Reflect.get(sample, 'name') ===
							'performance.bridge.worker.render_publication_outstanding')
				);
			})
			.slice(-16)
			.map((sample): Readonly<Record<string, unknown>> => {
				const numericAttributes = Reflect.get(sample, 'numericAttributes');
				const stringAttributes = Reflect.get(sample, 'stringAttributes');
				return {
					current:
						typeof numericAttributes === 'object' && numericAttributes !== null
							? Reflect.get(
									numericAttributes,
									'agentstudio.bridge.render_publication.current_count',
								)
							: null,
					event: Reflect.get(sample, 'name'),
					outcome:
						typeof stringAttributes === 'object' && stringAttributes !== null
							? (Reflect.get(stringAttributes, 'agentstudio.bridge.render_publication.outcome') ??
								Reflect.get(stringAttributes, 'agentstudio.bridge.render_disposition.outcome'))
							: null,
					pending:
						typeof numericAttributes === 'object' && numericAttributes !== null
							? Reflect.get(
									numericAttributes,
									'agentstudio.bridge.render_disposition.pending_count',
								)
							: null,
					phase:
						typeof stringAttributes === 'object' && stringAttributes !== null
							? Reflect.get(stringAttributes, 'agentstudio.bridge.phase')
							: null,
				};
			});
	});
}
