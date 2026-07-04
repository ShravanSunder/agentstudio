import type { BridgeIntakeFrame } from '../../core/models/bridge-intake-frame.js';
import { parseBridgeCoreResourceUrl } from '../../core/resources/bridge-resource-url.js';
import type {
	ReviewExtentFact,
	ReviewMetadataOperation,
	ReviewProtocolFrame,
	ReviewTreeRowMetadata,
} from '../../features/review/models/review-protocol-models.js';
import {
	buildReviewMetadataDeltaFrame,
	buildReviewMetadataSnapshotFrame,
	buildReviewMetadataWindowFrame,
} from '../../features/review/protocol/review-metadata-frame-builder.js';
import type { BridgeContentFetch } from '../../foundation/content/content-resource-loader.js';
import {
	applyBridgeReviewDelta,
	type BridgeReviewDelta,
} from '../../foundation/review-package/bridge-review-delta.js';
import { makeBridgeReviewPackage } from '../../foundation/review-package/bridge-review-package-test-support.js';
import type {
	BridgeContentRole,
	BridgeFileClass,
	BridgeFileChangeKind,
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package.js';
import type { BridgeTelemetryBootstrapHandshakeConfig } from '../../foundation/telemetry/bridge-telemetry-bootstrap-config.js';
import { makeBridgeReviewProjectionInput } from '../navigation/review-projection.js';
import {
	createBridgeReviewProjectionWorkerClient,
	type BridgeReviewProjectionWorkerClient,
} from '../workers/projection/review-projection-worker-client.js';
import {
	buildBridgeReviewProjectionWorkerSuccessResponse,
	identityFromWorkerRequest,
	type BridgeReviewProjectionWorkerRequest,
	type BridgeReviewProjectionWorkerResponse,
} from '../workers/projection/review-projection-worker-rpc.js';
import * as mockedBackendSupport from './bridge-viewer-mocked-backend-support.js';

export type BridgeViewerMockedBackendLatencyProfile = 'zero' | 'small' | 'slowBounded';
export type BridgeViewerBrowserFixtureClass =
	| 'small-mixed'
	| 'medium-agentstudio'
	| 'large-diffshub';
export type BridgeViewerMockedBackendDeliveryMode = 'full-load' | 'streaming-append';
export type BridgeViewerLargeFixtureItemPlacement = 'near-start' | 'after-fillers';
type BridgeViewerReviewIntakeKind = 'snapshot' | 'delta' | 'invalidate' | 'reset';
const bridgeViewerReviewMetadataWindowSize = 80;

export interface InstallBridgeViewerMockedBackendOptions {
	readonly latencyProfile?: BridgeViewerMockedBackendLatencyProfile;
	readonly contentFailures?: readonly string[];
	readonly deferContentHandleIds?: readonly string[];
	readonly projectionFailure?: boolean;
	readonly deferProjectionResponses?: boolean;
	readonly telemetryConfig?: BridgeTelemetryBootstrapHandshakeConfig;
}

export interface BridgeViewerMockedBackendPushRecord {
	readonly op: 'replace' | 'merge';
	readonly revision: number;
	readonly reviewGeneration: number;
	readonly payloadKind: 'metadata' | 'metadataDelta' | 'metadataWindow';
}

export interface BridgeViewerDeferredProjectionResponse {
	readonly request: BridgeReviewProjectionWorkerRequest;
	readonly resolve: () => void;
	readonly abort: () => void;
}

export interface BridgeViewerDeferredContentResponse {
	readonly url: string;
	readonly handleId: string | null;
	readonly resolve: () => void;
}

export interface BridgeViewerMockedBackend {
	readonly reviewPackage: BridgeReviewPackage;
	readonly fetchContent: BridgeContentFetch;
	readonly projectionWorkerClient: BridgeReviewProjectionWorkerClient;
	readonly commandDetails: readonly unknown[];
	readonly projectionRequests: readonly BridgeReviewProjectionWorkerRequest[];
	readonly projectionAbortKeys: readonly string[];
	readonly pendingProjectionResponses: readonly BridgeViewerDeferredProjectionResponse[];
	readonly pendingContentResponses: readonly BridgeViewerDeferredContentResponse[];
	readonly requestedUrls: readonly string[];
	readonly pushRecords: readonly BridgeViewerMockedBackendPushRecord[];
	readonly pushMetadata: (reviewPackage?: BridgeReviewPackage) => Promise<void>;
	readonly pushDelta: (delta?: BridgeReviewDelta) => Promise<void>;
	readonly dispose: () => void;
}

const activeMockedBackendDisposers = new Set<() => void>();

export function disposeBridgeViewerMockedBackends(): void {
	for (const dispose of activeMockedBackendDisposers) {
		dispose();
	}
	activeMockedBackendDisposers.clear();
}

export interface BridgeViewerBrowserFixture {
	readonly reviewPackage: BridgeReviewPackage;
	readonly contentByHandleId: ReadonlyMap<string, string>;
	readonly streamingAppendDelta: BridgeReviewDelta;
	readonly metadata: {
		readonly fixtureId: string;
		readonly fixtureClass: BridgeViewerBrowserFixtureClass;
		readonly deliveryMode: BridgeViewerMockedBackendDeliveryMode;
		readonly itemCount: number;
		readonly pathCount: number;
		readonly diffLineCount: number;
		readonly packageBytes: number;
		readonly fixtureChecksum: string;
		readonly changeKindCounts: Readonly<Record<BridgeFileChangeKind, number>>;
		readonly fileClassCounts: Readonly<Record<BridgeFileClass, number>>;
		readonly selectedLargeFileLineCount: number;
		readonly addedFullContentTargetCount: number;
	};
	readonly expected: {
		readonly initialPath: string;
		readonly initialText: string;
		readonly secondPath: string;
		readonly secondText: string;
		readonly addedPath: string;
		readonly addedText: string;
		readonly addedHeadHandleId: string;
		readonly hunkPath: string;
		readonly hunkExpandedText: string;
		readonly docsPath: string;
		readonly docsMarkdownText: string;
		readonly docsMarkdownHeading: string;
		readonly searchText: string;
		readonly searchPath: string;
		readonly testFilterPath: string;
		readonly testFilterText: string;
		readonly largePath: string;
		readonly largeText: string;
		readonly largeHeadHandleId: string;
		readonly secondHeadHandleId: string;
		readonly appendedPath: string;
		readonly appendedText: string;
		readonly appendedHeadHandleId: string;
	};
}

const bridgeViewerPushNonce = 'browser-push-nonce';
const bridgeViewerCommandNonce = 'browser-command-nonce';
const bridgeViewerReviewPaneId = 'bridge-viewer-dev-pane';
const bridgeViewerReviewStreamId = `review:${bridgeViewerReviewPaneId}`;

export function makeBridgeViewerBrowserFixture(
	props: {
		readonly fixtureClass?: BridgeViewerBrowserFixtureClass;
		readonly largeItemPlacement?: BridgeViewerLargeFixtureItemPlacement;
	} = {},
): BridgeViewerBrowserFixture {
	const fixtureClass = props.fixtureClass ?? 'small-mixed';
	const largeItemPlacement = props.largeItemPlacement ?? 'near-start';
	const basePackage = makeBridgeReviewPackage();
	const sourceItem = mockedBackendSupport.makeBrowserFixtureItem({
		itemId: 'browser-source-a',
		path: 'Sources/BridgeViewer/Alpha.ts',
		changeKind: 'modified',
		fileClass: 'source',
		language: 'typescript',
		extension: 'ts',
	});
	const secondItem = mockedBackendSupport.makeBrowserFixtureItem({
		itemId: 'browser-source-b',
		path: 'Sources/BridgeViewer/Beta.ts',
		changeKind: 'modified',
		fileClass: 'source',
		language: 'typescript',
		extension: 'ts',
	});
	const addedItem = mockedBackendSupport.makeBrowserFixtureItem({
		itemId: 'browser-added-source',
		path: 'Sources/BridgeViewer/NewPanel.ts',
		itemKind: 'file',
		changeKind: 'added',
		fileClass: 'source',
		language: 'typescript',
		extension: 'ts',
	});
	const docsItem = mockedBackendSupport.makeBrowserFixtureItem({
		itemId: 'browser-docs-plan',
		path: 'docs/plans/bridge-viewer-browser.md',
		changeKind: 'added',
		fileClass: 'docs',
		language: 'markdown',
		extension: 'md',
	});
	const largeItem = mockedBackendSupport.makeBrowserFixtureItem({
		itemId: 'browser-large-diff',
		path: 'large/browser/huge-diff.ts',
		itemKind: 'file',
		changeKind: 'modified',
		fileClass: 'source',
		language: 'typescript',
		extension: 'ts',
	});
	const hunkedItem = mockedBackendSupport.makeBrowserFixtureItem({
		itemId: 'browser-hunked-diff',
		path: 'Sources/BridgeViewer/HunkedContext.ts',
		changeKind: 'modified',
		fileClass: 'source',
		language: 'typescript',
		extension: 'ts',
	});
	const appendedItem = mockedBackendSupport.makeBrowserFixtureItem({
		itemId: 'browser-streaming-append',
		path: 'streaming/append/NewStreamingPanel.ts',
		changeKind: 'added',
		fileClass: 'source',
		language: 'typescript',
		extension: 'ts',
	});
	const fillerItems = Array.from(
		{ length: mockedBackendSupport.fillerItemCountForFixtureClass(fixtureClass) },
		(_value: unknown, index: number) =>
			mockedBackendSupport.makeBrowserFillerItem({ fixtureClass, index }),
	);
	const leadingItems = [sourceItem, secondItem, addedItem, docsItem];
	const items =
		largeItemPlacement === 'after-fillers'
			? [...leadingItems, hunkedItem, ...fillerItems, largeItem]
			: [...leadingItems, largeItem, hunkedItem, ...fillerItems];
	const contentByHandleId = new Map<string, string>();

	mockedBackendSupport.addContent(contentByHandleId, sourceItem, {
		base: "export const selectedFile = 'alpha base';\n",
		head: "export const selectedFile = 'alpha head visible';\n",
	});
	mockedBackendSupport.addContent(contentByHandleId, secondItem, {
		base: "export const selectedFile = 'beta base';\n",
		head: "export const selectedFile = 'beta selected content';\n",
	});
	mockedBackendSupport.addContent(contentByHandleId, addedItem, {
		head: [
			'export function renderAddedPanel(): string {',
			"\treturn 'full added file content';",
			'}',
			'',
		].join('\n'),
	});
	mockedBackendSupport.addContent(contentByHandleId, docsItem, {
		head: '# Browser fixture\n\n```ts\nconst fixture = true;\n```\n',
	});
	mockedBackendSupport.addContent(contentByHandleId, largeItem, {
		base: mockedBackendSupport.largeBrowserDiffText('base'),
		head: mockedBackendSupport.largeBrowserDiffText('head'),
	});
	mockedBackendSupport.addContent(contentByHandleId, hunkedItem, {
		base: mockedBackendSupport.hunkedBrowserDiffText('base'),
		head: mockedBackendSupport.hunkedBrowserDiffText('head'),
	});
	mockedBackendSupport.addContent(contentByHandleId, appendedItem, {
		head: [
			'export function renderStreamingPanel(): string {',
			"\treturn 'streaming appended file content';",
			'}',
			'',
		].join('\n'),
	});

	for (const item of fillerItems) {
		mockedBackendSupport.addContent(contentByHandleId, item, {
			base: `export const filler${item.itemId} = 'base';\n`,
			head: `export const filler${item.itemId} = 'head';\n`,
		});
	}
	const sizedItems = items.map(
		(item): BridgeReviewItemDescriptor =>
			mockedBackendSupport.reviewItemWithContentSizes({ item, contentByHandleId }),
	);
	const sizedAppendedItem = mockedBackendSupport.reviewItemWithContentSizes({
		item: appendedItem,
		contentByHandleId,
	});

	const reviewPackage: BridgeReviewPackage = {
		...basePackage,
		packageId: `browser-mode-${fixtureClass}`,
		reviewGeneration: 338,
		revision: 1,
		orderedItemIds: sizedItems.map((item): string => item.itemId),
		itemsById: Object.fromEntries(sizedItems.map((item) => [item.itemId, item])),
		query: {
			...basePackage.query,
			pathScope: [],
		},
		summary: {
			filesChanged: sizedItems.length,
			additions: sizedItems.reduce((total, item): number => total + item.additions, 0),
			deletions: sizedItems.reduce((total, item): number => total + item.deletions, 0),
			visibleFileCount: sizedItems.length,
			hiddenFileCount: 0,
		},
		filterState: {
			...basePackage.filterState,
			showLargeFiles: true,
		},
	};

	const packageBytes = new TextEncoder().encode(JSON.stringify(reviewPackage)).byteLength;
	const selectedLargeFileLineCount = mockedBackendSupport.selectedLargeContentLineCount(
		contentByHandleId,
		largeItem,
	);
	const addedFullContentTargetCount = items.filter((item: BridgeReviewItemDescriptor): boolean => {
		const headHandle = item.contentRoles.head ?? null;
		return (
			item.changeKind === 'added' &&
			headHandle !== null &&
			mockedBackendSupport.lineCount(contentByHandleId.get(headHandle.handleId)) > 2
		);
	}).length;
	const streamingAppendDelta: BridgeReviewDelta = {
		packageId: reviewPackage.packageId,
		reviewGeneration: reviewPackage.reviewGeneration,
		revision: reviewPackage.revision + 1,
		operations: {
			addItems: [sizedAppendedItem],
			updateItems: [],
			removeItems: [],
			moveItems: [...reviewPackage.orderedItemIds, appendedItem.itemId],
			updateGroups: null,
			updateSummary: {
				filesChanged: reviewPackage.summary.filesChanged + 1,
				additions: reviewPackage.summary.additions + appendedItem.additions,
				deletions: reviewPackage.summary.deletions + appendedItem.deletions,
				visibleFileCount: reviewPackage.summary.visibleFileCount + 1,
				hiddenFileCount: reviewPackage.summary.hiddenFileCount,
			},
			invalidateContent: [],
		},
	};
	const fixtureChecksum = [
		reviewPackage.packageId,
		fixtureClass,
		sizedItems.length.toString(),
		contentByHandleId.size.toString(),
		packageBytes.toString(),
	].join(':');

	return {
		reviewPackage,
		streamingAppendDelta,
		metadata: {
			fixtureId: reviewPackage.packageId,
			fixtureClass,
			deliveryMode: 'full-load',
			itemCount: items.length,
			pathCount: new Set(
				items.flatMap((item): readonly string[] =>
					[item.basePath, item.headPath].filter(
						(path: string | null | undefined): path is string =>
							path !== null && path !== undefined,
					),
				),
			).size,
			diffLineCount: [...contentByHandleId.values()].reduce(
				(total: number, content: string): number => total + content.split('\n').length,
				0,
			),
			packageBytes,
			fixtureChecksum,
			changeKindCounts: mockedBackendSupport.countChangeKinds(items),
			fileClassCounts: mockedBackendSupport.countFileClasses(items),
			selectedLargeFileLineCount,
			addedFullContentTargetCount,
		},
		contentByHandleId,
		expected: {
			initialPath: 'Sources/BridgeViewer/Alpha.ts',
			initialText: "export const selectedFile = 'alpha head visible';",
			secondPath: 'Sources/BridgeViewer/Beta.ts',
			secondText: "export const selectedFile = 'beta selected content';",
			addedPath: 'Sources/BridgeViewer/NewPanel.ts',
			addedText: "return 'full added file content';",
			addedHeadHandleId: mockedBackendSupport.requiredHandleId(
				addedItem.contentRoles.head,
				'added head',
			),
			hunkPath: 'Sources/BridgeViewer/HunkedContext.ts',
			hunkExpandedText: "export const stableContextLine0025 = 'same';",
			docsPath: 'docs/plans/bridge-viewer-browser.md',
			docsMarkdownText: '# Browser fixture',
			docsMarkdownHeading: 'Browser fixture',
			searchText: 'Hunked',
			searchPath: 'Sources/BridgeViewer/HunkedContext.ts',
			testFilterPath: 'tree/module-00/file-007.ts',
			testFilterText: "export const fillerbrowser-filler-small-mixed-007 = 'head';",
			largePath: 'large/browser/huge-diff.ts',
			largeText: "export const generatedLine0000 = 'head';",
			largeHeadHandleId: mockedBackendSupport.requiredHandleId(
				largeItem.contentRoles.head,
				'large head',
			),
			secondHeadHandleId: mockedBackendSupport.requiredHandleId(
				secondItem.contentRoles.head,
				'second head',
			),
			appendedPath: 'streaming/append/NewStreamingPanel.ts',
			appendedText: "return 'streaming appended file content';",
			appendedHeadHandleId: mockedBackendSupport.requiredHandleId(
				appendedItem.contentRoles.head,
				'appended head',
			),
		},
	};
}

export function makeBridgeViewerContentUnavailableFixture(): BridgeViewerBrowserFixture {
	const fixture = makeBridgeViewerBrowserFixture();
	const secondItem = fixture.reviewPackage.itemsById['browser-source-b'];
	const secondHeadHandle = secondItem?.contentRoles.head ?? null;
	if (secondItem === undefined || secondHeadHandle === null) {
		throw new Error('expected content-unavailable fixture second item head handle');
	}
	const isolatedSecondHeadHandleId = `${secondHeadHandle.handleId}-failure-content-unavailable`;
	const isolatedSecondHeadHandle = {
		...secondHeadHandle,
		handleId: isolatedSecondHeadHandleId,
		cacheKey: `${secondHeadHandle.cacheKey}:failure-content-unavailable`,
		contentHash: `${secondHeadHandle.contentHash}:failure-content-unavailable`,
		resourceUrl: `agentstudio://resource/review/content/${isolatedSecondHeadHandleId}?generation=${secondHeadHandle.reviewGeneration}`,
	};
	const isolatedSecondItem = {
		...secondItem,
		contentRoles: {
			...secondItem.contentRoles,
			head: isolatedSecondHeadHandle,
		},
		cacheKey: `${secondItem.cacheKey}|failure-content-unavailable`,
	};
	const contentByHandleId = new Map(fixture.contentByHandleId);
	const secondHeadContent = fixture.contentByHandleId.get(secondHeadHandle.handleId);
	if (secondHeadContent !== undefined) {
		contentByHandleId.set(isolatedSecondHeadHandle.handleId, secondHeadContent);
	}
	return {
		...fixture,
		contentByHandleId,
		reviewPackage: {
			...fixture.reviewPackage,
			itemsById: {
				...fixture.reviewPackage.itemsById,
				[isolatedSecondItem.itemId]: isolatedSecondItem,
			},
		},
		expected: {
			...fixture.expected,
			secondHeadHandleId: isolatedSecondHeadHandle.handleId,
		},
	};
}

export interface BridgeViewerContentRevisionFixture extends BridgeViewerBrowserFixture {
	// A follow-up snapshot that bumps only the package revision (extent-fact / path churn) without
	// touching any content identity. The content-validity gate must keep already-loaded content.
	readonly bareRevisionPackage: BridgeReviewPackage;
	// A follow-up snapshot where the initially selected file's head handle carries a fresher
	// contentHash and body. The gate must invalidate the loaded content and reload the new body.
	readonly revisedContentPackage: BridgeReviewPackage;
	readonly revisedInitialText: string;
	readonly initialHeadHandleId: string;
}

// Content-addressed content-validity gate proof surface: the initially selected file (Alpha) can be
// re-delivered as a benign revision bump (must keep loaded content) or with a genuinely fresher head
// contentHash (must invalidate + reload). See makeReviewItemContentResourcesKey.
export function makeBridgeViewerContentRevisionFixture(): BridgeViewerContentRevisionFixture {
	const fixture = makeBridgeViewerBrowserFixture();
	const sourceItem = fixture.reviewPackage.itemsById['browser-source-a'];
	const sourceHeadHandle = sourceItem?.contentRoles.head ?? null;
	if (sourceItem === undefined || sourceHeadHandle === null) {
		throw new Error('expected content-revision fixture source item head handle');
	}
	const revisedInitialBody = "export const selectedFile = 'alpha head REVISED';\n";
	const revisedHeadHandleId = `${sourceHeadHandle.handleId}-revised`;
	const revisedHeadHandle = {
		...sourceHeadHandle,
		handleId: revisedHeadHandleId,
		contentHash: `${sourceHeadHandle.contentHash}:revised`,
		cacheKey: `${sourceHeadHandle.cacheKey}:revised`,
		resourceUrl: `agentstudio://resource/review/content/${revisedHeadHandleId}?generation=${sourceHeadHandle.reviewGeneration}`,
	};
	const contentByHandleId = new Map(fixture.contentByHandleId);
	contentByHandleId.set(revisedHeadHandleId, revisedInitialBody);
	const revisedSourceItem = mockedBackendSupport.reviewItemWithContentSizes({
		item: {
			...sourceItem,
			itemVersion: sourceItem.itemVersion + 1,
			headContentHash: revisedHeadHandle.contentHash,
			contentRoles: { ...sourceItem.contentRoles, head: revisedHeadHandle },
			cacheKey: `${sourceItem.cacheKey}:revised`,
		},
		contentByHandleId,
	});
	const bareRevisionPackage: BridgeReviewPackage = {
		...fixture.reviewPackage,
		revision: fixture.reviewPackage.revision + 1,
	};
	const revisedContentPackage: BridgeReviewPackage = {
		...fixture.reviewPackage,
		revision: fixture.reviewPackage.revision + 2,
		itemsById: {
			...fixture.reviewPackage.itemsById,
			[revisedSourceItem.itemId]: revisedSourceItem,
		},
	};
	return {
		...fixture,
		contentByHandleId,
		bareRevisionPackage,
		revisedContentPackage,
		revisedInitialText: "export const selectedFile = 'alpha head REVISED';",
		initialHeadHandleId: sourceHeadHandle.handleId,
	};
}

export function installBridgeViewerMockedBackend(
	fixture: BridgeViewerBrowserFixture = makeBridgeViewerBrowserFixture(),
	options: InstallBridgeViewerMockedBackendOptions = {},
): BridgeViewerMockedBackend {
	document.documentElement.setAttribute('data-bridge-nonce', bridgeViewerCommandNonce);
	document.documentElement.setAttribute('data-bridge-review-pane-id', bridgeViewerReviewPaneId);
	document.documentElement.setAttribute('data-bridge-review-stream-id', bridgeViewerReviewStreamId);
	const commandDetails: unknown[] = [];
	const projectionRequests: BridgeReviewProjectionWorkerRequest[] = [];
	const projectionAbortKeys: string[] = [];
	const pendingProjectionResponses: BridgeViewerDeferredProjectionResponse[] = [];
	const pendingContentResponses: BridgeViewerDeferredContentResponse[] = [];
	const requestedUrls: string[] = [];
	const pushRecords: BridgeViewerMockedBackendPushRecord[] = [];
	const contentFailures = new Set(options.contentFailures ?? []);
	const deferredContentHandleIds = new Set(options.deferContentHandleIds ?? []);
	const latencyProfile = options.latencyProfile ?? 'zero';
	let currentReviewPackage = fixture.reviewPackage;
	let nextReviewSequence = fixture.reviewPackage.revision;
	let didReceiveHandshakeRequest = false;
	const commandListener = (event: Event): void => {
		commandDetails.push('detail' in event ? event.detail : null);
	};
	const handshakeRequestListener = (): void => {
		didReceiveHandshakeRequest = true;
		document.dispatchEvent(
			new CustomEvent('__bridge_handshake', {
				detail: {
					pushNonce: bridgeViewerPushNonce,
					...(options.telemetryConfig === undefined
						? {}
						: { telemetryConfig: options.telemetryConfig }),
				},
			}),
		);
	};
	document.addEventListener('__bridge_command', commandListener);
	document.addEventListener('__bridge_handshake_request', handshakeRequestListener);
	const projectionWorkerClient = createBridgeReviewProjectionWorkerClient({
		createRequestId: (): string => `browser-projection-${projectionRequests.length + 1}`,
		transport: {
			send: async (
				request: BridgeReviewProjectionWorkerRequest,
			): Promise<BridgeReviewProjectionWorkerResponse> => {
				projectionRequests.push(request);
				await mockedBackendSupport.waitForLatencyProfile(latencyProfile);
				const response = (): BridgeReviewProjectionWorkerResponse =>
					options.projectionFailure === true
						? {
								schemaVersion: 1,
								method: request.method,
								ok: false,
								...identityFromWorkerRequest(request),
								error: {
									code: 'projectionFailed',
									message: 'mocked projection failure',
								},
							}
						: buildBridgeReviewProjectionWorkerSuccessResponse({
								request,
								durationMilliseconds: 3,
							});
				if (options.deferProjectionResponses === true) {
					return await new Promise<BridgeReviewProjectionWorkerResponse>((resolve): void => {
						pendingProjectionResponses.push({
							request,
							resolve: (): void => {
								resolve(response());
							},
							abort: (): void => {
								resolve({
									schemaVersion: 1,
									method: request.method,
									ok: false,
									...identityFromWorkerRequest(request),
									error: {
										code: 'aborted',
										message: 'mocked projection aborted',
									},
								});
							},
						});
					});
				}
				return response();
			},
			abort: (abortKey: string): void => {
				projectionAbortKeys.push(abortKey);
				for (let index = pendingProjectionResponses.length - 1; index >= 0; index -= 1) {
					const pendingResponse = pendingProjectionResponses[index];
					if (pendingResponse?.request.abortKey === abortKey) {
						pendingResponse.abort();
						pendingProjectionResponses.splice(index, 1);
					}
				}
			},
		},
	});

	let isDisposed = false;
	const dispose = (): void => {
		if (isDisposed) {
			return;
		}
		isDisposed = true;
		while (pendingProjectionResponses.length > 0) {
			pendingProjectionResponses.shift()?.resolve();
		}
		while (pendingContentResponses.length > 0) {
			pendingContentResponses.shift()?.resolve();
		}
		document.removeEventListener('__bridge_command', commandListener);
		document.removeEventListener('__bridge_handshake_request', handshakeRequestListener);
		document.documentElement.removeAttribute('data-bridge-nonce');
		document.documentElement.removeAttribute('data-bridge-review-pane-id');
		document.documentElement.removeAttribute('data-bridge-review-stream-id');
		activeMockedBackendDisposers.delete(dispose);
	};
	activeMockedBackendDisposers.add(dispose);

	return {
		reviewPackage: fixture.reviewPackage,
		projectionWorkerClient,
		commandDetails,
		projectionRequests,
		projectionAbortKeys,
		pendingProjectionResponses,
		pendingContentResponses,
		requestedUrls,
		pushRecords,
		fetchContent: async (url: string, init?: RequestInit): Promise<Response> => {
			requestedUrls.push(url);
			await mockedBackendSupport.waitForLatencyProfile(latencyProfile);
			if (init?.signal?.aborted === true) {
				return new Response('', { status: 499 });
			}
			const parsedResourceUrl = parseBridgeCoreResourceUrl(url, {
				allowedResourceKindsByProtocol: {
					review: new Set(['content']),
				},
			});
			if (parsedResourceUrl === null) {
				return new Response(`invalid mocked content URL ${url}`, { status: 400 });
			}
			const handleId = mockedBackendSupport.handleIdFromResourceUrl(url);
			if (handleId !== null && contentFailures.has(handleId)) {
				return new Response(`mocked content failure for ${handleId}`, { status: 503 });
			}
			const content = handleId === null ? undefined : fixture.contentByHandleId.get(handleId);
			if (content === undefined) {
				return new Response(`missing mocked content for ${url}`, { status: 404 });
			}
			const response = (): Response =>
				init?.signal?.aborted === true ? new Response('', { status: 499 }) : new Response(content);
			if (handleId !== null && deferredContentHandleIds.has(handleId)) {
				return await new Promise<Response>((resolve): void => {
					let didSettle = false;
					const pendingResponse: BridgeViewerDeferredContentResponse = {
						url,
						handleId,
						resolve: (): void => {
							if (didSettle) {
								return;
							}
							didSettle = true;
							init?.signal?.removeEventListener('abort', resolveAbort);
							resolve(response());
						},
					};
					const resolveAbort = (): void => {
						if (didSettle) {
							return;
						}
						didSettle = true;
						const pendingIndex = pendingContentResponses.indexOf(pendingResponse);
						if (pendingIndex >= 0) {
							pendingContentResponses.splice(pendingIndex, 1);
						}
						resolve(response());
					};
					if (init?.signal?.aborted === true) {
						resolveAbort();
						return;
					}
					init?.signal?.addEventListener('abort', resolveAbort, { once: true });
					pendingContentResponses.push(pendingResponse);
				});
			}
			return response();
		},
		pushMetadata: async (
			reviewPackage: BridgeReviewPackage = fixture.reviewPackage,
		): Promise<void> => {
			await waitForBridgeHandshakeRequest((): boolean => didReceiveHandshakeRequest);
			currentReviewPackage = reviewPackage;
			pushRecords.push({
				op: 'replace',
				revision: reviewPackage.revision,
				reviewGeneration: reviewPackage.reviewGeneration,
				payloadKind: 'metadata',
			});
			const protocolFrame = buildReviewMetadataSnapshotFrame({
				package: reviewPackage,
				paneId: bridgeViewerReviewPaneId,
				sourceIdentity: reviewPackage.query.queryId,
				streamId: bridgeViewerReviewStreamId,
				sequence: nextReviewSequence,
				selectedItemId: reviewPackage.orderedItemIds[0] ?? null,
				visibleItemIds: reviewPackage.orderedItemIds.slice(0, bridgeViewerReviewMetadataWindowSize),
			});
			nextReviewSequence += 1;
			dispatchBridgeViewerReviewIntakeFrame(protocolFrame);
			for (const itemIds of reviewMetadataWindowItemIdBatches(reviewPackage)) {
				pushRecords.push({
					op: 'replace',
					revision: reviewPackage.revision,
					reviewGeneration: reviewPackage.reviewGeneration,
					payloadKind: 'metadataWindow',
				});
				const windowFrame = buildReviewMetadataWindowFrame({
					package: reviewPackage,
					paneId: bridgeViewerReviewPaneId,
					sourceIdentity: reviewPackage.query.queryId,
					streamId: bridgeViewerReviewStreamId,
					sequence: nextReviewSequence,
					itemIds,
				});
				nextReviewSequence += 1;
				dispatchBridgeViewerReviewIntakeFrame(windowFrame);
			}
			await Promise.resolve();
			await Promise.resolve();
		},
		pushDelta: async (delta: BridgeReviewDelta = fixture.streamingAppendDelta): Promise<void> => {
			await waitForBridgeHandshakeRequest((): boolean => didReceiveHandshakeRequest);
			const previousReviewPackage = currentReviewPackage;
			const nextReviewPackage = applyBridgeReviewDelta(previousReviewPackage, delta);
			currentReviewPackage = nextReviewPackage;
			pushRecords.push({
				op: 'merge',
				revision: delta.revision,
				reviewGeneration: delta.reviewGeneration,
				payloadKind: 'metadataDelta',
			});
			const protocolFrame = buildReviewMetadataDeltaFrame({
				package: nextReviewPackage,
				paneId: bridgeViewerReviewPaneId,
				sourceIdentity: nextReviewPackage.query.queryId,
				streamId: bridgeViewerReviewStreamId,
				sequence: nextReviewSequence,
				fromRevision: previousReviewPackage.revision,
				toRevision: nextReviewPackage.revision,
				operations: reviewMetadataOperationsForFixtureDelta({
					delta,
					reviewPackage: nextReviewPackage,
				}),
			});
			nextReviewSequence += 1;
			dispatchBridgeViewerReviewIntakeFrame(protocolFrame);
			await Promise.resolve();
			await Promise.resolve();
		},
		dispose,
	};
}

async function waitForBridgeHandshakeRequest(
	didReceiveHandshakeRequest: () => boolean,
	remainingAttempts = 180,
): Promise<void> {
	if (didReceiveHandshakeRequest()) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error('expected Bridge handshake request before metadata push');
	}
	await Promise.resolve();
	await new Promise<void>((resolve) => {
		requestAnimationFrame((): void => resolve());
	});
	await waitForBridgeHandshakeRequest(didReceiveHandshakeRequest, remainingAttempts - 1);
}

function dispatchBridgeViewerReviewIntakeFrame(protocolFrame: ReviewProtocolFrame): void {
	const intakeFrame: BridgeIntakeFrame = {
		kind: reviewIntakeKindForProtocolFrame(protocolFrame),
		streamId: protocolFrame.streamId,
		generation: protocolFrame.generation,
		sequence: protocolFrame.sequence,
		payload: protocolFrame,
	};
	document.dispatchEvent(
		new CustomEvent('__bridge_intake_json', {
			detail: {
				json: JSON.stringify(intakeFrame),
				nonce: bridgeViewerPushNonce,
			},
		}),
	);
}

function reviewIntakeKindForProtocolFrame(
	protocolFrame: ReviewProtocolFrame,
): BridgeViewerReviewIntakeKind {
	switch (protocolFrame.frameKind) {
		case 'review.metadataSnapshot':
			return 'snapshot';
		case 'review.metadataWindow':
		case 'review.metadataDelta':
			return 'delta';
		case 'review.invalidate':
			return 'invalidate';
		case 'review.reset':
			return 'reset';
	}
	const exhaustiveFrameKind: never = protocolFrame;
	void exhaustiveFrameKind;
	throw new Error('Unhandled Review protocol frame kind');
}

function reviewMetadataWindowItemIdBatches(
	reviewPackage: BridgeReviewPackage,
): readonly (readonly string[])[] {
	const remainingItemIds = reviewPackage.orderedItemIds.slice(bridgeViewerReviewMetadataWindowSize);
	const batches: string[][] = [];
	for (
		let itemIdOffset = 0;
		itemIdOffset < remainingItemIds.length;
		itemIdOffset += bridgeViewerReviewMetadataWindowSize
	) {
		batches.push(
			remainingItemIds.slice(itemIdOffset, itemIdOffset + bridgeViewerReviewMetadataWindowSize),
		);
	}
	return batches;
}

function reviewMetadataOperationsForFixtureDelta(props: {
	readonly delta: BridgeReviewDelta;
	readonly reviewPackage: BridgeReviewPackage;
}): readonly ReviewMetadataOperation[] {
	const projectionInput = makeBridgeReviewProjectionInput(props.reviewPackage);
	const projectionItemById = new Map(
		projectionInput.orderedItems.map((item): readonly [string, typeof item] => [item.itemId, item]),
	);
	const operations: ReviewMetadataOperation[] = [];
	const appendedItems = props.delta.operations.addItems
		.map((item) => projectionItemById.get(item.itemId) ?? null)
		.filter((item): item is NonNullable<typeof item> => item !== null);
	if (appendedItems.length > 0) {
		operations.push({ kind: 'appendItems', items: appendedItems });
		operations.push({
			kind: 'upsertTreeRows',
			rows: reviewTreeRowsForItems(props.delta.operations.addItems),
		});
		operations.push({
			kind: 'upsertExtentFacts',
			facts: reviewExtentFactsForItems(props.delta.operations.addItems),
		});
	}
	for (const item of props.delta.operations.updateItems) {
		const projectionItem = projectionItemById.get(item.itemId) ?? null;
		if (projectionItem !== null) {
			operations.push({ kind: 'upsertItemMetadata', item: projectionItem });
		}
	}
	if (props.delta.operations.removeItems.length > 0) {
		operations.push({ kind: 'removeItems', itemIds: props.delta.operations.removeItems });
	}
	if (props.delta.operations.moveItems.length > 0) {
		operations.push({
			kind: 'replaceItemOrder',
			itemIds: props.delta.operations.moveItems,
		});
	}
	return operations;
}

function reviewTreeRowsForItems(
	items: readonly BridgeReviewItemDescriptor[],
): ReviewTreeRowMetadata[] {
	return items.map((item): ReviewTreeRowMetadata => {
		const path = mockedBackendSupport.primaryPathForItem(item);
		return {
			rowId: `review-row:${item.itemId}`,
			itemId: item.itemId,
			path,
			depth: path.split('/').length - 1,
			isDirectory: false,
		};
	});
}

function reviewExtentFactsForItems(
	items: readonly BridgeReviewItemDescriptor[],
): ReviewExtentFact[] {
	return items.flatMap((item): ReviewExtentFact[] =>
		(['base', 'head', 'diff', 'file'] as const satisfies BridgeContentRole[]).flatMap(
			(contentRole): ReviewExtentFact[] => {
				const handle = item.contentRoles[contentRole] ?? null;
				if (handle === null) {
					return [];
				}
				return [
					{
						itemId: item.itemId,
						contentRole,
						lineCount: lineCountForReviewItemContentRole({ contentRole, item }),
					},
				];
			},
		),
	);
}

function lineCountForReviewItemContentRole(props: {
	readonly contentRole: BridgeContentRole;
	readonly item: BridgeReviewItemDescriptor;
}): number {
	const exactLineCount = props.item.contentLineCountsByRole?.[props.contentRole];
	if (exactLineCount !== null && exactLineCount !== undefined) {
		return exactLineCount;
	}
	switch (props.contentRole) {
		case 'base':
			return Math.max(props.item.deletions, 1);
		case 'head':
		case 'file':
			return Math.max(props.item.additions, 1);
		case 'diff':
			return Math.max(props.item.additions + props.item.deletions, 1);
	}
	const exhaustiveContentRole: never = props.contentRole;
	void exhaustiveContentRole;
	throw new Error('Unhandled Bridge review content role');
}
