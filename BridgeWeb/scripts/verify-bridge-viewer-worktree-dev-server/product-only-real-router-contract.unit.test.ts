import { readFile } from 'node:fs/promises';

import { describe, expect, test } from 'vitest';

import {
	bridgeViewerProductOnlySelectors,
	collectBridgeViewerProductOnlyContractViolations,
	type BridgeViewerProductOnlyJourneyProof,
	type BridgeViewerProductRouteTranscriptEntry,
} from './product-only-real-router-contract.ts';
import { bridgeViewerProductOnlyRegressionPhase } from './product-only-real-router-regression.ts';

describe('Bridge Viewer product-only real-router regression contract', () => {
	test('keeps the observed acknowledgement, product subscription, legacy, and display topology red', () => {
		const proof = makePassingProductOnlyProof({
			fileReady: false,
			legacyTraffic: true,
			reviewReady: false,
			transcript: [
				makeProductEntry(1, '/__bridge-product/command', 'workerSession.open', 200),
				makeProductEntry(2, '/__bridge-product/stream', 'metadataStream.open', 200),
				{
					...makeProductEntry(3, '/__bridge-product/command', 'stream.frameObserved', 400),
					streamKind: 'metadata',
				},
				{
					...makeProductEntry(4, '/__bridge-product/command', 'subscription.open', 200),
					responseCode: 'unsupported_subscription',
					responseKind: 'request.error',
					subscriptionKind: 'review.metadata',
				},
				{
					...makeProductEntry(5, '/__bridge-product/command', 'subscription.open', 200),
					responseCode: 'resync_required',
					responseKind: 'request.error',
					subscriptionKind: 'file.metadata',
				},
			],
		});

		const violations = collectBridgeViewerProductOnlyContractViolations(proof);
		const codes = violations.map((violation) => violation.code);

		expect(codes).toContain('transport.frame-observation-bodyless-204');
		expect(codes).toContain('transport.file.metadata-accepted');
		expect(codes).toContain('transport.review.metadata-accepted');
		expect(codes).toContain('file.product-display-ready');
		expect(codes).toContain('review.product-display-ready');
		expect(codes).toContain('legacy.review-route-traffic-absent');
		expect(codes).toContain('legacy.intake-json-traffic-absent');
		expect(bridgeViewerProductOnlyRegressionPhase(violations)).toBe(
			'initial-product-transport-red',
		);
	});

	test('uses the same permanent contract for the product-only green state', () => {
		const proof = makePassingProductOnlyProof();

		const violations = collectBridgeViewerProductOnlyContractViolations(proof);

		expect(violations).toEqual([]);
		expect(bridgeViewerProductOnlyRegressionPhase(violations)).toBe('a0-product-only-green');
	});

	test('rejects browser console diagnostics and failed responses from product-only proof', () => {
		// Arrange
		const proof: BridgeViewerProductOnlyJourneyProof = {
			...makePassingProductOnlyProof(),
			consoleDiagnostics: [
				{
					columnNumber: 0,
					lineNumber: 0,
					path: '/favicon.ico',
					text: 'Failed to load resource',
					type: 'error',
				},
			],
			consoleErrors: ['Failed to load resource'],
			failedResponses: [
				{ method: 'GET', path: '/favicon.ico', resourceType: 'image', status: 404 },
			],
		};

		// Act
		const violationCodes = collectBridgeViewerProductOnlyContractViolations(proof).map(
			(violation) => violation.code,
		);

		// Assert
		expect(violationCodes).toContain('browser.console-clean');
		expect(violationCodes).toContain('browser.failed-responses-absent');
	});

	test('separates a completed File content response from unclosed teardown residue', () => {
		// Arrange
		const transcript = [
			...passingTranscript(),
			{
				...makeProductEntry(8, '/__bridge-product/content', 'content.open', null),
				contentKind: 'file.content',
			},
		];
		const proof = makePassingProductOnlyProof({ transcript });

		// Act
		const violationCodes = collectBridgeViewerProductOnlyContractViolations(proof).map(
			(violation) => violation.code,
		);

		// Assert
		expect(violationCodes).not.toContain('transport.file.content-request');
		expect(violationCodes).toContain('transport.file.content-request-unclosed');
	});

	test('requires the real File to Review to File journey to retain visible content identity', () => {
		// Arrange
		const passingProof = makePassingProductOnlyProof();
		const proof: BridgeViewerProductOnlyJourneyProof = {
			...passingProof,
			fileAtCompletion: {
				...passingProof.fileAtCompletion,
				bodyPreviewSha256: 'different-returned-content',
				codeCanvasVisible: false,
			},
			reviewAtCompletion: {
				...passingProof.reviewAtCompletion,
				selectedContentCharacterCount: 0,
			},
		};

		// Act
		const violationCodes = collectBridgeViewerProductOnlyContractViolations(proof).map(
			(violation) => violation.code,
		);

		// Assert
		expect(violationCodes).toContain('file.product-display-ready');
		expect(violationCodes).toContain('review.product-display-ready');
		expect(violationCodes).toContain('journey.file-return-stable-visible-readable');
	});

	test('rejects ordinary product requests issued by the main window', () => {
		// Arrange
		const proof: BridgeViewerProductOnlyJourneyProof = {
			...makePassingProductOnlyProof(),
			mainWindowProductRouteTranscript: [
				{ method: 'POST', path: '/__bridge-product/bootstrap', transport: 'fetch' },
				{ method: 'POST', path: '/__bridge-product/content', transport: 'fetch' },
				{
					method: 'POST',
					path: '/__bridge-product/command',
					transport: 'xmlHttpRequest',
				},
			],
		};

		// Act
		const violationCodes = collectBridgeViewerProductOnlyContractViolations(proof).map(
			(violation) => violation.code,
		);

		// Assert
		expect(violationCodes).toContain('transport.main-window-product-egress-bootstrap-only');
	});

	test('requires every observed worker to close during browser teardown', () => {
		// Arrange
		const proof: BridgeViewerProductOnlyJourneyProof = {
			...makePassingProductOnlyProof(),
			browserCleanup: {
				browserConnectedAfterClose: false,
				closedWorkerCount: 0,
				observedWorkerCount: 1,
				pageClosed: true,
			},
		};

		// Act
		const violationCodes = collectBridgeViewerProductOnlyContractViolations(proof).map(
			(violation) => violation.code,
		);

		// Assert
		expect(violationCodes).toContain('worker.teardown-closes-observed-workers');
	});

	test('rejects a main-frame document replacement during the measured File to Review to File journey', () => {
		const proof = {
			...makePassingProductOnlyProof(),
			documentGeneration: {
				atJourneyCompletion: 2,
				atJourneyStart: 1,
			},
		};

		const violationCodes = collectBridgeViewerProductOnlyContractViolations(proof).map(
			(violation) => violation.code,
		);

		expect(violationCodes).toContain('browser.document-generation-stable-during-journey');
	});

	test('rejects replacement comm workers and session identities across the journey', () => {
		// Arrange
		const passingProof = makePassingProductOnlyProof();
		const proof: BridgeViewerProductOnlyJourneyProof = {
			...passingProof,
			productRouteTranscript: [
				...passingProof.productRouteTranscript,
				{
					...makeProductEntry(8, '/__bridge-product/content', null, 200),
					contentKind: 'file.content',
					paneSessionId: 'pane-session-2',
					workerInstanceId: 'worker-instance-2',
				},
			],
			workers: [
				...passingProof.workers,
				{
					closed: false,
					closedBeforeJourneyCompletion: false,
					documentGeneration: 1,
					kind: 'comm-worker',
					url: '/src/core/comm-worker/bridge-comm-worker-entry.ts?replacement&type=module',
				},
			],
		};

		// Act
		const violationCodes = collectBridgeViewerProductOnlyContractViolations(proof).map(
			(violation) => violation.code,
		);

		// Assert
		expect(violationCodes).toContain('worker.single-real-pane-comm-worker');
		expect(violationCodes).toContain('worker.single-pane-session-identity');
	});

	test('rejects a token-sized Review payload presented as readable current-worktree content', () => {
		// Arrange
		const passingProof = makePassingProductOnlyProof();
		const proof: BridgeViewerProductOnlyJourneyProof = {
			...passingProof,
			reviewAtCompletion: {
				...passingProof.reviewAtCompletion,
				metadataItemCount: 1_215,
				metadataTreeRowCount: 1_215,
				selectedContentCharacterCount: 4,
				selectedContentLineCount: 1,
			},
		};

		// Act
		const violationCodes = collectBridgeViewerProductOnlyContractViolations(proof).map(
			(violation) => violation.code,
		);

		// Assert
		expect(violationCodes).toContain('review.product-selected-content-nontrivial');
	});

	test('requires at least one completed File content HTTP 200 independently of teardown closure', () => {
		// Arrange
		const transcript = [
			...passingTranscript().filter((entry) => entry.contentKind !== 'file.content'),
			{
				...makeProductEntry(8, '/__bridge-product/content', 'content.open', null),
				contentKind: 'file.content',
			},
		];
		const proof = makePassingProductOnlyProof({ transcript });

		// Act
		const violationCodes = collectBridgeViewerProductOnlyContractViolations(proof).map(
			(violation) => violation.code,
		);

		// Assert
		expect(violationCodes).toContain('transport.file.content-request');
		expect(violationCodes).toContain('transport.file.content-request-unclosed');
	});

	test('separates missing fresh-route Pierre membership from selected Review readiness', () => {
		// Arrange
		const passingProof = makePassingProductOnlyProof();
		const proof: BridgeViewerProductOnlyJourneyProof = {
			...passingProof,
			reviewFreshRoute: {
				...passingProof.reviewFreshRoute,
				observedHeaderItemIds: passingProof.reviewFreshRoute.observedHeaderItemIds.slice(0, -1),
			},
		};

		// Act
		const violationCodes = collectBridgeViewerProductOnlyContractViolations(proof).map(
			(violation) => violation.code,
		);

		// Assert
		expect(violationCodes).toContain('REVIEW_FRESH_ROUTE_MANIFEST_MISSING');
		expect(violationCodes).not.toContain('review.product-display-ready');
	});

	test('accepts complete first-seen membership when virtualization observes headers across changing windows', () => {
		// Arrange
		const passingProof = makePassingProductOnlyProof();
		const proof: BridgeViewerProductOnlyJourneyProof = {
			...passingProof,
			reviewFreshRoute: {
				...passingProof.reviewFreshRoute,
				observedHeaderItemIds: ['review-item-1', 'review-item-3', 'review-item-4', 'review-item-2'],
			},
		};

		// Act
		const violationCodes = collectBridgeViewerProductOnlyContractViolations(proof).map(
			(violation) => violation.code,
		);

		// Assert
		expect(violationCodes).not.toContain('REVIEW_FRESH_ROUTE_MANIFEST_MISSING');
		expect(violationCodes).not.toContain('REVIEW_FRESH_ROUTE_LOGICAL_ORDER_MISMATCH');
	});

	test('rejects a mounted Pierre viewport whose headers contradict catalog order', () => {
		// Arrange
		const passingProof = makePassingProductOnlyProof();
		const proof: BridgeViewerProductOnlyJourneyProof = {
			...passingProof,
			reviewFreshRoute: {
				...passingProof.reviewFreshRoute,
				mountedHeaderOrderViolations: [
					{
						expectedItemIndexes: [0, 2, 1],
						mountedItemIds: ['review-item-1', 'review-item-3', 'review-item-2'],
					},
				],
			},
		};

		// Act
		const violationCodes = collectBridgeViewerProductOnlyContractViolations(proof).map(
			(violation) => violation.code,
		);

		// Assert
		expect(violationCodes).toContain('REVIEW_FRESH_ROUTE_LOGICAL_ORDER_MISMATCH');
		expect(violationCodes).not.toContain('REVIEW_FRESH_ROUTE_MANIFEST_MISSING');
	});

	test('rejects a tree selection that changes the continuous manifest or fails to hydrate in place', () => {
		// Arrange
		const passingProof = makePassingProductOnlyProof();
		const proof: BridgeViewerProductOnlyJourneyProof = {
			...passingProof,
			reviewTreeSelection: {
				codeViewManifestItemCountAfterSelection: 5,
				codeViewManifestItemCountBeforeSelection: 4,
				mountedHeaderOrderViolation: {
					expectedItemIndexes: [0, 2, 1],
					mountedItemIds: ['review-item-1', 'review-item-3', 'review-item-2'],
				},
				selectedContentState: 'placeholder',
				selectedItemIdAtCompletion: 'review-item-2',
				selectedItemIdAtStart: 'review-item-1',
				targetItemId: 'review-item-2',
				targetPath: '.gitignore',
			},
		};

		// Act
		const violationCodes = collectBridgeViewerProductOnlyContractViolations(proof).map(
			(violation) => violation.code,
		);

		// Assert
		expect(violationCodes).toContain('REVIEW_TREE_SELECTION_MANIFEST_CHANGED');
		expect(violationCodes).toContain('REVIEW_TREE_SELECTION_LOGICAL_ORDER_MISMATCH');
		expect(violationCodes).toContain('REVIEW_TREE_SELECTION_CONTENT_MISSING');
	});

	test('rejects mixed fresh disclosure independently of continuous Review membership', () => {
		// Arrange
		const passingProof = makePassingProductOnlyProof();
		const mixedDisclosure = [
			...passingProof.reviewFreshRoute.initialDirectoryDisclosure,
			{ expanded: 'true', path: 'Sources/AgentStudio' },
		];
		const proof: BridgeViewerProductOnlyJourneyProof = {
			...passingProof,
			reviewFreshRoute: {
				...passingProof.reviewFreshRoute,
				finalDirectoryDisclosure: mixedDisclosure,
				initialDirectoryDisclosure: mixedDisclosure,
			},
		};

		// Act
		const violationCodes = collectBridgeViewerProductOnlyContractViolations(proof).map(
			(violation) => violation.code,
		);

		// Assert
		expect(violationCodes).toContain('REVIEW_FRESH_ROUTE_DISCLOSURE_MIXED');
		expect(violationCodes).not.toContain('REVIEW_FRESH_ROUTE_MANIFEST_MISSING');
	});

	test('rejects a settled visible Review window whose non-selected body never hydrates', () => {
		// Arrange
		const passingProof = makePassingProductOnlyProof();
		const proof: BridgeViewerProductOnlyJourneyProof = {
			...passingProof,
			reviewFreshRoute: {
				...passingProof.reviewFreshRoute,
				hydrationMilestones: passingProof.reviewFreshRoute.hydrationMilestones.map((milestone) =>
					milestone.label === 'middle'
						? { ...milestone, hydratedNonSelectedItemIds: [] }
						: milestone,
				),
			},
		};

		// Act
		const violationCodes = collectBridgeViewerProductOnlyContractViolations(proof).map(
			(violation) => violation.code,
		);

		// Assert
		expect(violationCodes).toContain('REVIEW_FRESH_ROUTE_VISIBLE_HYDRATION_MISSING');
		expect(violationCodes).not.toContain('REVIEW_FRESH_ROUTE_MANIFEST_MISSING');
	});

	test('rejects incomplete full-traversal visible-body hydration coverage between milestones', () => {
		// Arrange: the legacy five milestones are all green, but the exhaustive traversal receipt
		// records that one expected non-selected item was never observed hydrated while visible.
		const passingProof = makePassingProductOnlyProof();
		const reviewFreshRouteWithIncompleteCoverage = {
			...passingProof.reviewFreshRoute,
			hydrationCoverage: {
				expectedNonSelectedItemIds: ['review-item-2', 'review-item-3', 'review-item-4'],
				missingHydratedVisibleWindows: [],
				observedHydratedNonSelectedItemIds: ['review-item-2', 'review-item-4'],
				settledWindowCount: 12,
			},
		};
		const proof: BridgeViewerProductOnlyJourneyProof = {
			...passingProof,
			reviewFreshRoute: reviewFreshRouteWithIncompleteCoverage,
		};

		// Act
		const violationCodes = collectBridgeViewerProductOnlyContractViolations(proof).map(
			(violation) => violation.code,
		);

		// Assert
		expect(violationCodes).toContain('REVIEW_FRESH_ROUTE_VISIBLE_HYDRATION_COVERAGE_MISSING');
		expect(violationCodes).not.toContain('REVIEW_FRESH_ROUTE_VISIBLE_HYDRATION_MISSING');
	});

	test('keeps the registered worktree verifier pointed at the self-hosted real-router lane', async () => {
		const registeredVerifierSource = await readFile(
			new URL('../verify-bridge-viewer-worktree-dev-server.ts', import.meta.url),
			'utf8',
		);

		expect(registeredVerifierSource).toContain('runSelfHostedBridgeViewerProductOnlyRegression');
		expect(registeredVerifierSource).not.toContain(
			"from './verify-bridge-viewer-worktree-dev-server/runner.ts'",
		);
	});

	test('launches Browser Mode and the real-router journey through installed Chrome', async () => {
		// Arrange
		const [browserConfigSource, realRouterPageSource] = await Promise.all([
			readFile(new URL('../../vitest.browser.config.ts', import.meta.url), 'utf8'),
			readFile(new URL('./product-only-real-router-page.ts', import.meta.url), 'utf8'),
		]);

		// Act
		const browserConfigUsesInstalledChrome =
			/instances:\s*\[\{\s*browser:\s*'chromium',\s*launch:\s*\{\s*channel:\s*'chrome'\s*\}\s*\}\]/u.test(
				browserConfigSource,
			);
		const realRouterUsesInstalledChrome =
			/chromium\.launch\(\{\s*channel:\s*'chrome',\s*headless:\s*true\s*\}\)/u.test(
				realRouterPageSource,
			);

		// Assert
		expect(browserConfigSource).toContain(
			"import type {} from '@vitest/browser/providers/playwright';",
		);
		expect(browserConfigUsesInstalledChrome).toBe(true);
		expect(realRouterUsesInstalledChrome).toBe(true);
	});

	test('keeps the official journey ordered File to Review to the same visible File surface', async () => {
		// Arrange
		const [source, reviewProofSource] = await Promise.all([
			readFile(new URL('./product-only-real-router-page.ts', import.meta.url), 'utf8'),
			readFile(new URL('./product-only-real-router-review-proof.ts', import.meta.url), 'utf8'),
		]);

		// Act
		const reviewClickIndex = source.indexOf('activeReviewContextButton).click');
		const reviewCaptureIndex = source.indexOf('const reviewAtCompletion');
		const fileReturnClickIndex = source.indexOf('activeFileContextButton).click');
		const fileReturnCaptureIndex = source.indexOf(
			'fileAtCompletion: await readFileProductState(page)',
		);

		// Assert
		expect(reviewClickIndex).toBeGreaterThan(0);
		expect(reviewCaptureIndex).toBeGreaterThan(reviewClickIndex);
		expect(fileReturnClickIndex).toBeGreaterThan(reviewCaptureIndex);
		expect(fileReturnCaptureIndex).toBeGreaterThan(fileReturnClickIndex);
		expect(source).toContain('data-worktree-open-file-body-preview');
		expect(source).toContain('data-selected-content-character-count');
		expect(source).toContain('data-selected-content-cache-keys');
		expect(source.indexOf("pageUrl.searchParams.set('viewer', 'review')")).toBeLessThan(
			source.indexOf("pageUrl.searchParams.set('viewer', 'file')"),
		);
		expect(source).toContain('proveFreshReviewRoute');
		expect(reviewProofSource).toContain('REVIEW_FRESH_ROUTE_CODE_SCROLL_OWNER_MISSING');
		expect(reviewProofSource).toContain("'diffs-container'");
		expect(reviewProofSource).toContain('function bridgeReviewHostElement');
		expect(reviewProofSource).not.toContain('contentStates[headerIndex]');
	});
});

function makePassingProductOnlyProof(
	overrides: {
		readonly fileReady?: boolean;
		readonly legacyTraffic?: boolean;
		readonly reviewReady?: boolean;
		readonly transcript?: readonly BridgeViewerProductRouteTranscriptEntry[];
	} = {},
): BridgeViewerProductOnlyJourneyProof {
	const fileReady = overrides.fileReady ?? true;
	const reviewReady = overrides.reviewReady ?? true;
	const legacyTraffic = overrides.legacyTraffic ?? false;
	return {
		browser: { headless: true, name: 'chromium', version: 'test-version' },
		browserCleanup: {
			browserConnectedAfterClose: false,
			closedWorkerCount: 1,
			observedWorkerCount: 1,
			pageClosed: true,
		},
		consoleDiagnostics: [],
		consoleErrors: [],
		documentGeneration: { atJourneyCompletion: 1, atJourneyStart: 1 },
		failedResponses: [],
		fileAfterFirstAcknowledgement: fileState(fileReady),
		fileAtCompletion: fileState(fileReady),
		legacyIntakeTranscript: legacyTraffic
			? [
					{
						frameKind: 'review.metadataSnapshot',
						generation: 1,
						kind: 'snapshot',
						sequence: 1,
						streamId: 'legacy-review-stream',
					},
				]
			: [],
		legacyRouteTranscript: legacyTraffic
			? [
					{
						finalWindow: true,
						frameKind: 'review.metadataSnapshot',
						httpStatus: 200,
						ordinal: 6,
						path: '/__bridge-worktree/review-metadata',
						sequence: 1,
					},
				]
			: [],
		mainWindowProductRouteTranscript: [
			{ method: 'POST', path: '/__bridge-product/bootstrap', transport: 'fetch' },
		],
		observedPageUrl:
			'http://127.0.0.1:50000/?fixture=worktree&scenario=current-worktree&viewer=file',
		productRouteTranscript: overrides.transcript ?? passingTranscript(),
		reviewFreshRoute: {
			codeScrollOwnerIdentityStable: true,
			codeViewManifestItemCount: 4,
			completedScroll: { clientHeight: 900, scrollHeight: 1_800, scrollTop: 900 },
			expectedItemIds: ['review-item-1', 'review-item-2', 'review-item-3', 'review-item-4'],
			finalDirectoryDisclosure: [{ expanded: 'false', path: 'Sources' }],
			hydrationCoverage: {
				missingHydratedVisibleWindows: [],
				observedHydratedNonSelectedItemIds: ['review-item-2', 'review-item-3', 'review-item-4'],
				settledWindowCount: 4,
			},
			hydrationMilestones: (['initial', 'quarter', 'middle', 'threeQuarter', 'final'] as const).map(
				(label) => ({
					hydratedNonSelectedItemIds: ['review-item-2'],
					label,
					visibleNonSelectedItemIds: ['review-item-2'],
				}),
			),
			initialDirectoryDisclosure: [{ expanded: 'false', path: 'Sources' }],
			metadataItemCount: 4,
			mountedHeaderOrderViolations: [],
			observedHeaderItemIds: ['review-item-1', 'review-item-2', 'review-item-3', 'review-item-4'],
			selectedItemIdAtCompletion: 'review-item-1',
			selectedItemIdAtStart: 'review-item-1',
			treeHostIdentityStable: true,
			treeShadowRootIdentityStable: true,
		},
		reviewTreeSelection: {
			codeViewManifestItemCountAfterSelection: 4,
			codeViewManifestItemCountBeforeSelection: 4,
			mountedHeaderOrderViolation: null,
			selectedContentState: 'hydrated',
			selectedItemIdAtCompletion: 'review-item-2',
			selectedItemIdAtStart: 'review-item-1',
			targetItemId: 'review-item-2',
			targetPath: '.gitignore',
		},
		reviewAtCompletion: {
			codePanelVisible: reviewReady,
			metadataItemCount: reviewReady ? 3 : 1,
			metadataTreeRowCount: reviewReady ? 3 : 1,
			selectedContentCacheKeyCount: reviewReady ? 1 : 0,
			selectedContentCacheKeysSha256: reviewReady ? 'review-cache-keys-sha256' : null,
			selectedContentCharacterCount: reviewReady ? 128 : 0,
			selectedContentLineCount: reviewReady ? 8 : 0,
			selectedContentState: reviewReady ? 'ready' : 'failed',
			selectedDisplayPath: 'Sources/AgentStudio/App/AppDelegate.swift',
			shellCount: 1,
			unavailableTextVisible: !reviewReady,
		},
		selectors: bridgeViewerProductOnlySelectors,
		selectorSnapshot: {
			activeFileContextButtonCount: 1,
			activeReviewContextButtonCount: 1,
			fileCodeCanvasCount: 1,
			fileShellCount: 1,
			reviewShellCount: 1,
		},
		workers: [
			{
				closed: true,
				closedBeforeJourneyCompletion: false,
				documentGeneration: 1,
				kind: 'comm-worker',
				url: '/src/core/comm-worker/bridge-comm-worker-entry.ts?worker_file&type=module',
			},
		],
	};
}

function passingTranscript(): readonly BridgeViewerProductRouteTranscriptEntry[] {
	return [
		makeProductEntry(1, '/__bridge-product/command', 'workerSession.open', 200),
		makeProductEntry(2, '/__bridge-product/stream', 'metadataStream.open', 200),
		{
			...makeProductEntry(3, '/__bridge-product/command', 'stream.frameObserved', 204),
			streamKind: 'metadata',
		},
		{
			...makeProductEntry(4, '/__bridge-product/command', 'subscription.open', 200),
			responseKind: 'subscription.openAccepted',
			subscriptionKind: 'review.metadata',
		},
		{
			...makeProductEntry(5, '/__bridge-product/command', 'subscription.open', 200),
			responseKind: 'subscription.openAccepted',
			subscriptionKind: 'file.metadata',
		},
		{
			...makeProductEntry(6, '/__bridge-product/content', null, 200),
			contentKind: 'file.content',
		},
		{
			...makeProductEntry(7, '/__bridge-product/content', null, 200),
			contentKind: 'review.content',
		},
	];
}

function makeProductEntry(
	ordinal: number,
	path: string,
	requestKind: string | null,
	httpStatus: number | null,
): BridgeViewerProductRouteTranscriptEntry {
	return {
		contentKind: null,
		documentGeneration: 1,
		httpStatus,
		method: 'POST',
		ordinal,
		paneSessionId: 'pane-session-1',
		path,
		requestKind,
		requestSequence: ordinal,
		responseCode: null,
		responseKind: null,
		streamKind: null,
		subscriptionKind: null,
		workerInstanceId: 'worker-instance-1',
	};
}

function fileState(ready: boolean): BridgeViewerProductOnlyJourneyProof['fileAtCompletion'] {
	return {
		bodyPreviewCharacterCount: ready ? 128 : 0,
		bodyPreviewSha256: ready ? 'file-body-preview-sha256' : null,
		codeCanvasVisible: ready,
		displayStatus: ready ? 'ready' : 'pending',
		metadataFileRowCount: ready ? 3 : 0,
		metadataTreeRowCount: ready ? 3 : 0,
		renderedDisplayPath: ready ? 'Sources/AgentStudio/App/AppDelegate.swift' : null,
		selectedContentState: ready ? 'ready' : null,
		selectedDisplayPath: ready ? 'Sources/AgentStudio/App/AppDelegate.swift' : null,
		shellCount: 1,
	};
}
