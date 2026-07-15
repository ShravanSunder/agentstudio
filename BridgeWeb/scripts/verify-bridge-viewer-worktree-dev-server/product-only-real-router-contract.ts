export const bridgeProductStartupFixtureIdentities = {
	invalid: '78da34fabc8fdfeb2316df0b21e819691ea2bb4e861a74cbee3270231d6494c8',
	valid: '741cc2d9ed25fc4517636a80003bea1536a560acc9a766e58e7209e3a220c692',
} as const;

export const bridgeViewerProductOnlySelectors = {
	activeFileContextButton:
		'[data-bridge-viewer-mode-active="true"] [data-testid="bridge-viewer-context-file"]',
	activeReviewContextButton:
		'[data-bridge-viewer-mode-active="true"] [data-testid="bridge-viewer-context-review"]',
	appRoot: '[data-testid="bridge-app-root"]',
	fileCodeCanvas: '[data-testid="bridge-file-viewer-code-canvas"]',
	fileShell: '[data-testid="bridge-file-viewer-shell"]',
	reviewCodePanel: '[data-testid="bridge-code-view-panel"]',
	reviewCodeScrollOwner: '[data-testid="bridge-code-view-panel"] .bridge-code-view-scroll-owner',
	reviewShell: '[data-testid="review-viewer-shell"]',
	reviewTreeHost: '[data-testid="bridge-review-trees-panel"] file-tree-container',
} as const;

export interface BridgeViewerProductRouteTranscriptEntry {
	readonly contentKind: string | null;
	readonly documentGeneration: number;
	readonly httpStatus: number | null;
	readonly method: string;
	readonly ordinal: number;
	readonly paneSessionId: string | null;
	readonly path: string;
	readonly requestKind: string | null;
	readonly requestSequence: number | null;
	readonly responseCode: string | null;
	readonly responseKind: string | null;
	readonly streamKind: string | null;
	readonly subscriptionKind: string | null;
	readonly workerInstanceId: string | null;
}

export interface BridgeViewerLegacyRouteTranscriptEntry {
	readonly finalWindow: boolean | null;
	readonly frameKind: string | null;
	readonly httpStatus: number | null;
	readonly ordinal: number;
	readonly path: string;
	readonly sequence: number | null;
}

export interface BridgeViewerLegacyIntakeTranscriptEntry {
	readonly frameKind: string | null;
	readonly generation: number | null;
	readonly kind: string | null;
	readonly sequence: number | null;
	readonly streamId: string | null;
}

export interface BridgeViewerObservedWorker {
	readonly closed: boolean;
	readonly closedBeforeJourneyCompletion: boolean;
	readonly documentGeneration: number;
	readonly kind: 'comm-worker' | 'module-worker' | 'portable-blob-worker';
	readonly url: string;
}

export interface BridgeViewerFailedResponse {
	readonly method: string;
	readonly path: string;
	readonly resourceType: string;
	readonly status: number;
}

export interface BridgeViewerMainWindowProductRequest {
	readonly method: string;
	readonly path: string;
	readonly transport: 'fetch' | 'xmlHttpRequest';
}

export interface BridgeViewerConsoleDiagnostic {
	readonly columnNumber: number | null;
	readonly lineNumber: number | null;
	readonly path: string | null;
	readonly text: string;
	readonly type: 'error' | 'warning';
}

export interface BridgeViewerFileProductStateSnapshot {
	readonly bodyPreviewCharacterCount: number;
	readonly bodyPreviewSha256: string | null;
	readonly codeCanvasVisible: boolean;
	readonly displayStatus: string | null;
	readonly metadataFileRowCount: number;
	readonly metadataTreeRowCount: number;
	readonly renderedDisplayPath: string | null;
	readonly selectedContentState: string | null;
	readonly selectedDisplayPath: string | null;
	readonly shellCount: number;
}

export interface BridgeViewerReviewProductStateSnapshot {
	readonly codePanelVisible: boolean;
	readonly metadataItemCount: number;
	readonly metadataTreeRowCount: number;
	readonly selectedContentCacheKeyCount: number;
	readonly selectedContentCacheKeysSha256: string | null;
	readonly selectedContentCharacterCount: number;
	readonly selectedContentLineCount: number;
	readonly selectedContentState: string | null;
	readonly selectedDisplayPath: string | null;
	readonly shellCount: number;
	readonly unavailableTextVisible: boolean;
}

export interface BridgeViewerReviewDirectoryDisclosure {
	readonly expanded: string;
	readonly path: string;
}

export interface BridgeViewerReviewHydrationMilestone {
	readonly hydratedNonSelectedItemIds: readonly string[];
	readonly label: 'final' | 'initial' | 'middle' | 'quarter' | 'threeQuarter';
	readonly visibleNonSelectedItemIds: readonly string[];
}

export interface BridgeViewerReviewHydrationWindowFailure {
	readonly hydratedNonSelectedItemIds: readonly string[];
	readonly scrollTop: number;
	readonly visibleNonSelectedItemIds: readonly string[];
}

export interface BridgeViewerReviewHydrationCoverage {
	readonly missingHydratedVisibleWindows: readonly BridgeViewerReviewHydrationWindowFailure[];
	readonly observedHydratedNonSelectedItemIds: readonly string[];
	readonly settledWindowCount: number;
}

export interface BridgeViewerReviewMountedHeaderOrderViolation {
	readonly expectedItemIndexes: readonly (number | null)[];
	readonly mountedItemIds: readonly string[];
}

export interface BridgeViewerReviewFreshRouteProof {
	readonly codeScrollOwnerIdentityStable: boolean;
	readonly codeViewManifestItemCount: number;
	readonly completedScroll: {
		readonly clientHeight: number;
		readonly scrollHeight: number;
		readonly scrollTop: number;
	};
	readonly expectedItemIds: readonly string[];
	readonly finalDirectoryDisclosure: readonly BridgeViewerReviewDirectoryDisclosure[];
	readonly hydrationCoverage: BridgeViewerReviewHydrationCoverage;
	readonly hydrationMilestones: readonly BridgeViewerReviewHydrationMilestone[];
	readonly initialDirectoryDisclosure: readonly BridgeViewerReviewDirectoryDisclosure[];
	readonly metadataItemCount: number;
	readonly mountedHeaderOrderViolations: readonly BridgeViewerReviewMountedHeaderOrderViolation[];
	readonly observedHeaderItemIds: readonly string[];
	readonly selectedItemIdAtCompletion: string | null;
	readonly selectedItemIdAtStart: string | null;
	readonly treeHostIdentityStable: boolean;
	readonly treeShadowRootIdentityStable: boolean;
}

export interface BridgeViewerReviewTreeSelectionProof {
	readonly codeViewManifestItemCountAfterSelection: number;
	readonly codeViewManifestItemCountBeforeSelection: number;
	readonly mountedHeaderOrderViolation: BridgeViewerReviewMountedHeaderOrderViolation | null;
	readonly selectedContentState: string | null;
	readonly selectedItemIdAtCompletion: string | null;
	readonly selectedItemIdAtStart: string | null;
	readonly targetItemId: string;
	readonly targetPath: string;
}

export interface BridgeViewerSelectorSnapshot {
	readonly activeFileContextButtonCount: number;
	readonly activeReviewContextButtonCount: number;
	readonly fileCodeCanvasCount: number;
	readonly fileShellCount: number;
	readonly reviewShellCount: number;
}

export interface BridgeViewerProductOnlyJourneyProof {
	readonly browser: {
		readonly headless: true;
		readonly name: string;
		readonly version: string;
	};
	readonly browserCleanup: {
		readonly browserConnectedAfterClose: boolean;
		readonly closedWorkerCount: number;
		readonly observedWorkerCount: number;
		readonly pageClosed: boolean;
	};
	readonly consoleDiagnostics: readonly BridgeViewerConsoleDiagnostic[];
	readonly consoleErrors: readonly string[];
	readonly documentGeneration: {
		readonly atJourneyCompletion: number;
		readonly atJourneyStart: number;
	};
	readonly failedResponses: readonly BridgeViewerFailedResponse[];
	readonly fileAfterReviewFirstSwitch: BridgeViewerFileProductStateSnapshot;
	readonly fileAfterFirstAcknowledgement: BridgeViewerFileProductStateSnapshot;
	readonly fileAtCompletion: BridgeViewerFileProductStateSnapshot;
	readonly legacyIntakeTranscript: readonly BridgeViewerLegacyIntakeTranscriptEntry[];
	readonly legacyRouteTranscript: readonly BridgeViewerLegacyRouteTranscriptEntry[];
	readonly mainWindowProductRouteTranscript: readonly BridgeViewerMainWindowProductRequest[];
	readonly observedPageUrl: string;
	readonly productRouteTranscript: readonly BridgeViewerProductRouteTranscriptEntry[];
	readonly reviewFreshRoute: BridgeViewerReviewFreshRouteProof;
	readonly reviewTreeSelection: BridgeViewerReviewTreeSelectionProof;
	readonly reviewAtCompletion: BridgeViewerReviewProductStateSnapshot;
	readonly selectors: typeof bridgeViewerProductOnlySelectors;
	readonly selectorSnapshot: BridgeViewerSelectorSnapshot;
	readonly workers: readonly BridgeViewerObservedWorker[];
}

export interface BridgeViewerProductOnlyContractViolation {
	readonly actual: unknown;
	readonly code: string;
	readonly expected: string;
}

const minimumNontrivialContentCharacterCount = 64;
const minimumNontrivialContentLineCount = 2;

export function collectBridgeViewerProductOnlyContractViolations(
	proof: BridgeViewerProductOnlyJourneyProof,
): readonly BridgeViewerProductOnlyContractViolation[] {
	const violations: BridgeViewerProductOnlyContractViolation[] = [];
	if (
		proof.documentGeneration.atJourneyStart <= 0 ||
		proof.documentGeneration.atJourneyCompletion !== proof.documentGeneration.atJourneyStart
	) {
		violations.push({
			actual: proof.documentGeneration,
			code: 'browser.document-generation-stable-during-journey',
			expected: 'one unchanged main-frame document generation during File -> Review -> File',
		});
	}
	const measuredProductRouteTranscript = proof.productRouteTranscript.filter(
		(entry): boolean => entry.documentGeneration === proof.documentGeneration.atJourneyStart,
	);
	const measuredProof: BridgeViewerProductOnlyJourneyProof = {
		...proof,
		productRouteTranscript: measuredProductRouteTranscript,
	};
	const acknowledgementEntries = measuredProductRouteTranscript.filter(
		(entry): boolean => entry.requestKind === 'stream.frameObserved',
	);
	if (
		acknowledgementEntries.length === 0 ||
		acknowledgementEntries.some((entry): boolean => entry.httpStatus !== 204)
	) {
		violations.push({
			actual: acknowledgementEntries.map((entry) => ({
				status: entry.httpStatus,
				streamKind: entry.streamKind,
			})),
			code: 'transport.frame-observation-bodyless-204',
			expected: 'at least one frame observation and every observation accepted with HTTP 204',
		});
	}

	requireAcceptedSubscription({
		proof: measuredProof,
		subscriptionKind: 'file.metadata',
		violations,
	});
	requireAcceptedSubscription({
		proof: measuredProof,
		subscriptionKind: 'review.metadata',
		violations,
	});

	if (!fileProductStateReady(proof.fileAfterReviewFirstSwitch)) {
		violations.push({
			actual: proof.fileAfterReviewFirstSwitch,
			code: 'journey.review-first-file-switch-visible-readable',
			expected:
				'Review-first same-document activation paints nonempty File metadata and readable selected File content',
		});
	}

	if (!observesCurrentWorktreeFileStart(proof)) {
		violations.push({
			actual: {
				file: proof.fileAfterFirstAcknowledgement,
				observedPageUrl: proof.observedPageUrl,
			},
			code: 'journey.file-start-visible-readable',
			expected:
				'current-worktree File starts active with one real path and non-empty rendered content identity',
		});
	}

	if (!fileProductStateReady(proof.fileAtCompletion)) {
		violations.push({
			actual: proof.fileAtCompletion,
			code: 'file.product-display-ready',
			expected: 'File product metadata rows and selected product content are ready',
		});
	}
	if (!fileSelectedContentNontrivial(proof.fileAtCompletion)) {
		violations.push({
			actual: {
				bodyPreviewCharacterCount: proof.fileAtCompletion.bodyPreviewCharacterCount,
				selectedDisplayPath: proof.fileAtCompletion.selectedDisplayPath,
			},
			code: 'file.product-selected-content-nontrivial',
			expected: `at least ${minimumNontrivialContentCharacterCount} characters of actual selected File content`,
		});
	}
	if (!fileReturnPreservesVisibleContent(proof)) {
		violations.push({
			actual: {
				fileAtCompletion: proof.fileAtCompletion,
				fileAtStart: proof.fileAfterFirstAcknowledgement,
			},
			code: 'journey.file-return-stable-visible-readable',
			expected:
				'File is visible and readable after Review and retains its selected path and rendered body identity',
		});
	}
	if (!reviewProductStateReady(proof.reviewAtCompletion)) {
		violations.push({
			actual: proof.reviewAtCompletion,
			code: 'review.product-display-ready',
			expected: 'Review product metadata and selected product content are ready',
		});
	}
	if (!reviewSelectedContentNontrivial(proof.reviewAtCompletion)) {
		violations.push({
			actual: {
				metadataItemCount: proof.reviewAtCompletion.metadataItemCount,
				metadataTreeRowCount: proof.reviewAtCompletion.metadataTreeRowCount,
				selectedContentCharacterCount: proof.reviewAtCompletion.selectedContentCharacterCount,
				selectedContentLineCount: proof.reviewAtCompletion.selectedContentLineCount,
				selectedDisplayPath: proof.reviewAtCompletion.selectedDisplayPath,
			},
			code: 'review.product-selected-content-nontrivial',
			expected: `at least ${minimumNontrivialContentCharacterCount} characters and ${minimumNontrivialContentLineCount} lines of actual selected Review diff content`,
		});
	}
	requireFreshReviewRoute({ proof: proof.reviewFreshRoute, violations });
	requireReviewTreeSelection({ proof: proof.reviewTreeSelection, violations });
	if (proof.consoleDiagnostics.length > 0) {
		violations.push({
			actual: proof.consoleDiagnostics,
			code: 'browser.console-clean',
			expected: 'zero browser console warnings or errors',
		});
	}
	if (proof.failedResponses.length > 0) {
		violations.push({
			actual: proof.failedResponses,
			code: 'browser.failed-responses-absent',
			expected: 'zero browser responses with HTTP status >= 400',
		});
	}

	requireProductContentRequest({
		contentKind: 'file.content',
		proof: measuredProof,
		violations,
	});
	requireProductContentRequest({
		contentKind: 'review.content',
		proof: measuredProof,
		violations,
	});

	if (proof.legacyRouteTranscript.length > 0) {
		violations.push({
			actual: proof.legacyRouteTranscript,
			code: 'legacy.review-route-traffic-absent',
			expected: 'zero /__bridge-worktree/review-* requests',
		});
	}
	if (proof.legacyIntakeTranscript.length > 0) {
		violations.push({
			actual: proof.legacyIntakeTranscript,
			code: 'legacy.intake-json-traffic-absent',
			expected: 'zero __bridge_intake_json events',
		});
	}
	const mainWindowBootstrapEntries = proof.mainWindowProductRouteTranscript.filter(
		(entry): boolean => entry.method === 'POST' && entry.path === '/__bridge-product/bootstrap',
	);
	if (
		proof.mainWindowProductRouteTranscript.length !== 1 ||
		mainWindowBootstrapEntries.length !== 1
	) {
		violations.push({
			actual: proof.mainWindowProductRouteTranscript,
			code: 'transport.main-window-product-egress-bootstrap-only',
			expected:
				'exactly one main-window POST /__bridge-product/bootstrap and no main-window command, stream, or content request',
		});
	}

	const commWorkers = proof.workers.filter(
		(worker): boolean =>
			worker.kind === 'comm-worker' &&
			worker.documentGeneration === proof.documentGeneration.atJourneyStart,
	);
	if (commWorkers.length !== 1) {
		violations.push({
			actual: commWorkers,
			code: 'worker.single-real-pane-comm-worker',
			expected: 'exactly one real bridge-comm-worker-entry module Worker',
		});
	}
	if (commWorkers.some((worker): boolean => worker.closedBeforeJourneyCompletion)) {
		violations.push({
			actual: commWorkers,
			code: 'worker.comm-worker-survives-measured-journey',
			expected:
				'the measured document generation comm worker remains open through File -> Review -> File',
		});
	}
	if (
		!proof.browserCleanup.pageClosed ||
		proof.browserCleanup.browserConnectedAfterClose ||
		proof.browserCleanup.observedWorkerCount !== proof.workers.length ||
		proof.browserCleanup.closedWorkerCount !== proof.browserCleanup.observedWorkerCount
	) {
		violations.push({
			actual: proof.browserCleanup,
			code: 'worker.teardown-closes-observed-workers',
			expected:
				'closed page, disconnected browser, and one close observation for every observed page worker',
		});
	}
	const workerSessionIdentities = uniqueWorkerSessionIdentities(measuredProductRouteTranscript);
	if (workerSessionIdentities.length !== 1) {
		violations.push({
			actual: workerSessionIdentities,
			code: 'worker.single-pane-session-identity',
			expected: 'exactly one non-empty paneSessionId/workerInstanceId pair',
		});
	}

	const expectedSelectorCounts = {
		activeFileContextButtonCount: 1,
		activeReviewContextButtonCount: 1,
		fileCodeCanvasCount: 1,
		fileShellCount: 1,
		reviewShellCount: 1,
	};
	if (
		proof.selectorSnapshot.activeFileContextButtonCount !==
			expectedSelectorCounts.activeFileContextButtonCount ||
		proof.selectorSnapshot.activeReviewContextButtonCount !==
			expectedSelectorCounts.activeReviewContextButtonCount ||
		proof.selectorSnapshot.fileCodeCanvasCount !== expectedSelectorCounts.fileCodeCanvasCount ||
		proof.selectorSnapshot.fileShellCount !== expectedSelectorCounts.fileShellCount ||
		proof.selectorSnapshot.reviewShellCount !== expectedSelectorCounts.reviewShellCount
	) {
		violations.push({
			actual: proof.selectorSnapshot,
			code: 'composition.stable-selectors-present',
			expected: JSON.stringify(expectedSelectorCounts),
		});
	}

	const startupOrder = requiredProductStartupOrder(measuredProductRouteTranscript);
	if (!startupOrder.satisfied) {
		violations.push({
			actual: startupOrder,
			code: 'transport.exact-startup-order',
			expected:
				'workerSession.open -> metadataStream.open -> metadata frame observation -> Review and File subscription opens',
		});
	}
	return violations;
}

function requireReviewTreeSelection(props: {
	readonly proof: BridgeViewerReviewTreeSelectionProof;
	readonly violations: BridgeViewerProductOnlyContractViolation[];
}): void {
	if (
		props.proof.codeViewManifestItemCountAfterSelection !==
		props.proof.codeViewManifestItemCountBeforeSelection
	) {
		props.violations.push({
			actual: props.proof,
			code: 'REVIEW_TREE_SELECTION_MANIFEST_CHANGED',
			expected: 'tree selection hydrates one existing CodeView item without changing manifest size',
		});
	}
	if (props.proof.mountedHeaderOrderViolation !== null) {
		props.violations.push({
			actual: props.proof.mountedHeaderOrderViolation,
			code: 'REVIEW_TREE_SELECTION_LOGICAL_ORDER_MISMATCH',
			expected: "tree-selected hydration remains at the item's authoritative catalog position",
		});
	}
	if (
		props.proof.targetItemId === props.proof.selectedItemIdAtStart ||
		props.proof.selectedItemIdAtCompletion !== props.proof.targetItemId ||
		(props.proof.selectedContentState !== 'hydrated' &&
			props.proof.selectedContentState !== 'windowed')
	) {
		props.violations.push({
			actual: props.proof,
			code: 'REVIEW_TREE_SELECTION_CONTENT_MISSING',
			expected:
				'a distinct tree target becomes selected and hydrates as an existing continuous CodeView item',
		});
	}
}

function requireFreshReviewRoute(props: {
	readonly proof: BridgeViewerReviewFreshRouteProof;
	readonly violations: BridgeViewerProductOnlyContractViolation[];
}): void {
	const manifestMatches =
		props.proof.metadataItemCount === props.proof.expectedItemIds.length &&
		props.proof.codeViewManifestItemCount === props.proof.expectedItemIds.length &&
		stringArraysContainSameValues(props.proof.observedHeaderItemIds, props.proof.expectedItemIds);
	if (!manifestMatches) {
		props.violations.push({
			actual: {
				codeViewManifestItemCount: props.proof.codeViewManifestItemCount,
				expectedItemCount: props.proof.expectedItemIds.length,
				metadataItemCount: props.proof.metadataItemCount,
				observedHeaderItemCount: props.proof.observedHeaderItemIds.length,
				observedHeaderItemIds: props.proof.observedHeaderItemIds,
			},
			code: 'REVIEW_FRESH_ROUTE_MANIFEST_MISSING',
			expected:
				'fresh targetless Review traverses every expected Pierre header exactly once in catalog order before tree interaction',
		});
	}
	if (props.proof.mountedHeaderOrderViolations.length > 0) {
		props.violations.push({
			actual: props.proof.mountedHeaderOrderViolations,
			code: 'REVIEW_FRESH_ROUTE_LOGICAL_ORDER_MISMATCH',
			expected: 'every mounted Pierre CodeView viewport preserves the authoritative catalog order',
		});
	}
	const mixedInitialDisclosure = props.proof.initialDirectoryDisclosure.filter(
		(disclosure): boolean => disclosure.expanded !== 'true',
	);
	if (
		props.proof.initialDirectoryDisclosure.length === 0 ||
		mixedInitialDisclosure.length > 0 ||
		JSON.stringify(props.proof.finalDirectoryDisclosure) !==
			JSON.stringify(props.proof.initialDirectoryDisclosure)
	) {
		props.violations.push({
			actual: {
				finalDirectoryDisclosure: props.proof.finalDirectoryDisclosure,
				initialDirectoryDisclosure: props.proof.initialDirectoryDisclosure,
				mixedInitialDisclosure,
			},
			code: 'REVIEW_FRESH_ROUTE_DISCLOSURE_MIXED',
			expected:
				'all mounted fresh-route directories start expanded and CodeView-only scrolling leaves disclosure unchanged',
		});
	}
	const failedHydrationMilestones = props.proof.hydrationMilestones.filter(
		(milestone): boolean =>
			milestone.visibleNonSelectedItemIds.length === 0 ||
			!stringArraysEqual(milestone.hydratedNonSelectedItemIds, milestone.visibleNonSelectedItemIds),
	);
	const requiredMilestoneLabels: readonly BridgeViewerReviewHydrationMilestone['label'][] = [
		'initial',
		'quarter',
		'middle',
		'threeQuarter',
		'final',
	];
	if (
		failedHydrationMilestones.length > 0 ||
		!requiredMilestoneLabels.every((label): boolean =>
			props.proof.hydrationMilestones.some((milestone): boolean => milestone.label === label),
		)
	) {
		props.violations.push({
			actual: {
				failedHydrationMilestones,
				hydrationMilestones: props.proof.hydrationMilestones,
			},
			code: 'REVIEW_FRESH_ROUTE_VISIBLE_HYDRATION_MISSING',
			expected:
				'non-selected visible Review bodies hydrate in every settled sampled CodeView window without tree clicks',
		});
	}
	const expectedHydratedNonSelectedItemIds = props.proof.expectedItemIds.filter(
		(itemId): boolean => itemId !== props.proof.selectedItemIdAtStart,
	);
	const missingExpectedHydratedItemIds = expectedHydratedNonSelectedItemIds.filter(
		(itemId): boolean =>
			!props.proof.hydrationCoverage.observedHydratedNonSelectedItemIds.includes(itemId),
	);
	const unexpectedHydratedItemIds =
		props.proof.hydrationCoverage.observedHydratedNonSelectedItemIds.filter(
			(itemId): boolean => !expectedHydratedNonSelectedItemIds.includes(itemId),
		);
	if (
		props.proof.hydrationCoverage.settledWindowCount === 0 ||
		props.proof.hydrationCoverage.missingHydratedVisibleWindows.length > 0 ||
		missingExpectedHydratedItemIds.length > 0 ||
		unexpectedHydratedItemIds.length > 0
	) {
		props.violations.push({
			actual: {
				expectedHydratedNonSelectedItemCount: expectedHydratedNonSelectedItemIds.length,
				missingExpectedHydratedItemCount: missingExpectedHydratedItemIds.length,
				missingExpectedHydratedItemIds: missingExpectedHydratedItemIds.slice(0, 32),
				missingHydratedVisibleWindows:
					props.proof.hydrationCoverage.missingHydratedVisibleWindows,
				observedHydratedNonSelectedItemCount:
					props.proof.hydrationCoverage.observedHydratedNonSelectedItemIds.length,
				settledWindowCount: props.proof.hydrationCoverage.settledWindowCount,
				unexpectedHydratedItemCount: unexpectedHydratedItemIds.length,
				unexpectedHydratedItemIds: unexpectedHydratedItemIds.slice(0, 32),
			},
			code: 'REVIEW_FRESH_ROUTE_VISIBLE_HYDRATION_COVERAGE_MISSING',
			expected:
				'every expected non-selected Review item becomes geometry-visible and hydrated in a settled CodeView window without tree clicks',
		});
	}
	if (
		!props.proof.codeScrollOwnerIdentityStable ||
		!props.proof.treeHostIdentityStable ||
		!props.proof.treeShadowRootIdentityStable
	) {
		props.violations.push({
			actual: {
				codeScrollOwnerIdentityStable: props.proof.codeScrollOwnerIdentityStable,
				treeHostIdentityStable: props.proof.treeHostIdentityStable,
				treeShadowRootIdentityStable: props.proof.treeShadowRootIdentityStable,
			},
			code: 'REVIEW_FRESH_ROUTE_IDENTITY_REPLACED',
			expected: 'CodeView scroll owner, tree host, and tree shadow root retain identity',
		});
	}
	if (
		props.proof.selectedItemIdAtStart === null ||
		props.proof.selectedItemIdAtCompletion !== props.proof.selectedItemIdAtStart
	) {
		props.violations.push({
			actual: {
				selectedItemIdAtCompletion: props.proof.selectedItemIdAtCompletion,
				selectedItemIdAtStart: props.proof.selectedItemIdAtStart,
			},
			code: 'REVIEW_FRESH_ROUTE_SELECTION_CHANGED',
			expected: 'CodeView-only scrolling leaves fresh-route Review selection unchanged',
		});
	}
	const maximumScrollTop = Math.max(
		0,
		props.proof.completedScroll.scrollHeight - props.proof.completedScroll.clientHeight,
	);
	if (maximumScrollTop <= 0 || props.proof.completedScroll.scrollTop < maximumScrollTop - 1) {
		props.violations.push({
			actual: props.proof.completedScroll,
			code: 'REVIEW_FRESH_ROUTE_TRAVERSAL_INCOMPLETE',
			expected: 'fresh-route Review traversal settles at the current CodeView bottom',
		});
	}
}

function stringArraysEqual(left: readonly string[], right: readonly string[]): boolean {
	return (
		left.length === right.length && left.every((value, index): boolean => value === right[index])
	);
}

function stringArraysContainSameValues(left: readonly string[], right: readonly string[]): boolean {
	if (left.length !== right.length) return false;
	const leftValues = new Set(left);
	const rightValues = new Set(right);
	return (
		leftValues.size === left.length &&
		rightValues.size === right.length &&
		leftValues.size === rightValues.size &&
		[...leftValues].every((value): boolean => rightValues.has(value))
	);
}

export function uniqueWorkerSessionIdentities(
	transcript: readonly BridgeViewerProductRouteTranscriptEntry[],
): readonly { readonly paneSessionId: string; readonly workerInstanceId: string }[] {
	const identities = new Map<
		string,
		{ readonly paneSessionId: string; readonly workerInstanceId: string }
	>();
	for (const entry of transcript) {
		if (entry.paneSessionId === null || entry.workerInstanceId === null) continue;
		identities.set(`${entry.paneSessionId}\0${entry.workerInstanceId}`, {
			paneSessionId: entry.paneSessionId,
			workerInstanceId: entry.workerInstanceId,
		});
	}
	return [...identities.values()];
}

export function summarizeBridgeProductRequestBody(
	value: unknown,
): Pick<
	BridgeViewerProductRouteTranscriptEntry,
	| 'contentKind'
	| 'paneSessionId'
	| 'requestKind'
	| 'requestSequence'
	| 'streamKind'
	| 'subscriptionKind'
	| 'workerInstanceId'
> {
	const body = unknownRecord(value);
	const subscription = unknownRecord(body?.['subscription']);
	return {
		contentKind: stringValue(body?.['contentKind']),
		paneSessionId: stringValue(body?.['paneSessionId']),
		requestKind: stringValue(body?.['kind']),
		requestSequence: numberValue(body?.['requestSequence']),
		streamKind: stringValue(body?.['streamKind']),
		subscriptionKind:
			stringValue(body?.['subscriptionKind']) ?? stringValue(subscription?.['subscriptionKind']),
		workerInstanceId: stringValue(body?.['workerInstanceId']),
	};
}

export function summarizeBridgeProductResponseBody(value: unknown): {
	readonly responseCode: string | null;
	readonly responseKind: string | null;
} {
	const body = unknownRecord(value);
	return {
		responseCode: stringValue(body?.['code']),
		responseKind: stringValue(body?.['kind']),
	};
}

function requireAcceptedSubscription(props: {
	readonly proof: BridgeViewerProductOnlyJourneyProof;
	readonly subscriptionKind: 'file.metadata' | 'review.metadata';
	readonly violations: BridgeViewerProductOnlyContractViolation[];
}): void {
	const entries = props.proof.productRouteTranscript.filter(
		(entry): boolean =>
			entry.requestKind === 'subscription.open' &&
			entry.subscriptionKind === props.subscriptionKind,
	);
	if (
		entries.length === 0 ||
		entries.some((entry): boolean => entry.responseKind !== 'subscription.openAccepted')
	) {
		props.violations.push({
			actual: entries.map((entry) => ({
				code: entry.responseCode,
				responseKind: entry.responseKind,
				status: entry.httpStatus,
			})),
			code: `transport.${props.subscriptionKind}-accepted`,
			expected: `${props.subscriptionKind} opens only with subscription.openAccepted`,
		});
	}
}

function requireProductContentRequest(props: {
	readonly contentKind: 'file.content' | 'review.content';
	readonly proof: BridgeViewerProductOnlyJourneyProof;
	readonly violations: BridgeViewerProductOnlyContractViolation[];
}): void {
	const entries = props.proof.productRouteTranscript.filter(
		(entry): boolean =>
			entry.path === '/__bridge-product/content' && entry.contentKind === props.contentKind,
	);
	if (!entries.some((entry): boolean => entry.httpStatus === 200)) {
		props.violations.push({
			actual: entries.map((entry) => entry.httpStatus),
			code: `transport.${props.contentKind}-request`,
			expected: `at least one successful ${props.contentKind} product request`,
		});
	}
	const unclosedEntries = entries.filter((entry): boolean => entry.httpStatus === null);
	if (unclosedEntries.length > 0) {
		props.violations.push({
			actual: unclosedEntries.map((entry) => ({
				ordinal: entry.ordinal,
				status: entry.httpStatus,
			})),
			code: `transport.${props.contentKind}-request-unclosed`,
			expected: `zero unclosed ${props.contentKind} product requests at browser teardown`,
		});
	}
}

function fileProductStateReady(state: BridgeViewerFileProductStateSnapshot): boolean {
	return (
		state.shellCount === 1 &&
		state.codeCanvasVisible &&
		state.displayStatus === 'ready' &&
		state.metadataFileRowCount > 0 &&
		state.metadataTreeRowCount > 0 &&
		state.selectedContentState === 'ready' &&
		state.selectedDisplayPath !== null &&
		state.renderedDisplayPath === state.selectedDisplayPath &&
		state.bodyPreviewCharacterCount > 0 &&
		state.bodyPreviewSha256 !== null
	);
}

function reviewProductStateReady(state: BridgeViewerReviewProductStateSnapshot): boolean {
	return (
		state.shellCount === 1 &&
		state.codePanelVisible &&
		state.metadataItemCount > 0 &&
		state.metadataTreeRowCount > 0 &&
		state.selectedContentState === 'ready' &&
		state.selectedDisplayPath !== null &&
		state.selectedContentCacheKeyCount > 0 &&
		state.selectedContentCacheKeysSha256 !== null &&
		state.selectedContentCharacterCount > 0 &&
		state.selectedContentLineCount > 0 &&
		!state.unavailableTextVisible
	);
}

function fileSelectedContentNontrivial(state: BridgeViewerFileProductStateSnapshot): boolean {
	return state.bodyPreviewCharacterCount >= minimumNontrivialContentCharacterCount;
}

function reviewSelectedContentNontrivial(state: BridgeViewerReviewProductStateSnapshot): boolean {
	return (
		state.selectedContentCharacterCount >= minimumNontrivialContentCharacterCount &&
		state.selectedContentLineCount >= minimumNontrivialContentLineCount
	);
}

function observesCurrentWorktreeFileStart(proof: BridgeViewerProductOnlyJourneyProof): boolean {
	const pageUrl = new URL(proof.observedPageUrl);
	return (
		pageUrl.searchParams.get('scenario') === 'current-worktree' &&
		pageUrl.searchParams.get('viewer') === 'file' &&
		fileProductStateReady(proof.fileAfterFirstAcknowledgement)
	);
}

function fileReturnPreservesVisibleContent(proof: BridgeViewerProductOnlyJourneyProof): boolean {
	return (
		fileProductStateReady(proof.fileAtCompletion) &&
		proof.fileAtCompletion.selectedDisplayPath ===
			proof.fileAfterFirstAcknowledgement.selectedDisplayPath &&
		proof.fileAtCompletion.renderedDisplayPath ===
			proof.fileAfterFirstAcknowledgement.renderedDisplayPath &&
		proof.fileAtCompletion.bodyPreviewSha256 ===
			proof.fileAfterFirstAcknowledgement.bodyPreviewSha256
	);
}

function requiredProductStartupOrder(
	transcript: readonly BridgeViewerProductRouteTranscriptEntry[],
): {
	readonly fileSubscriptionOpenIndex: number;
	readonly frameObservedIndex: number;
	readonly metadataStreamOpenIndex: number;
	readonly reviewSubscriptionOpenIndex: number;
	readonly satisfied: boolean;
	readonly workerSessionOpenIndex: number;
} {
	const workerSessionOpenIndex = transcript.findIndex(
		(entry): boolean => entry.requestKind === 'workerSession.open',
	);
	const metadataStreamOpenIndex = transcript.findIndex(
		(entry): boolean => entry.requestKind === 'metadataStream.open',
	);
	const frameObservedIndex = transcript.findIndex(
		(entry): boolean => entry.requestKind === 'stream.frameObserved',
	);
	const reviewSubscriptionOpenIndex = transcript.findIndex(
		(entry): boolean =>
			entry.requestKind === 'subscription.open' && entry.subscriptionKind === 'review.metadata',
	);
	const fileSubscriptionOpenIndex = transcript.findIndex(
		(entry): boolean =>
			entry.requestKind === 'subscription.open' && entry.subscriptionKind === 'file.metadata',
	);
	return {
		fileSubscriptionOpenIndex,
		frameObservedIndex,
		metadataStreamOpenIndex,
		reviewSubscriptionOpenIndex,
		satisfied:
			workerSessionOpenIndex >= 0 &&
			metadataStreamOpenIndex > workerSessionOpenIndex &&
			frameObservedIndex > metadataStreamOpenIndex &&
			reviewSubscriptionOpenIndex > frameObservedIndex &&
			fileSubscriptionOpenIndex > frameObservedIndex,
		workerSessionOpenIndex,
	};
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

function numberValue(value: unknown): number | null {
	return typeof value === 'number' && Number.isSafeInteger(value) ? value : null;
}
