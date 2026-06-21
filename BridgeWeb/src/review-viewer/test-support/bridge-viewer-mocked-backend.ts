import type { BridgeContentFetch } from '../../foundation/content/content-resource-loader.js';
import type { BridgeReviewDelta } from '../../foundation/review-package/bridge-review-delta.js';
import {
	makeBridgeContentHandle,
	makeBridgeReviewItem,
	makeBridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package-test-support.js';
import type {
	BridgeContentHandle,
	BridgeFileClass,
	BridgeFileChangeKind,
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package.js';
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

export type BridgeViewerMockedBackendLatencyProfile = 'zero' | 'small' | 'slowBounded';
export type BridgeViewerBrowserFixtureClass =
	| 'small-mixed'
	| 'medium-agentstudio'
	| 'large-diffshub';
export type BridgeViewerMockedBackendDeliveryMode = 'full-load' | 'streaming-append';
export type BridgeViewerLargeFixtureItemPlacement = 'near-start' | 'after-fillers';

export interface InstallBridgeViewerMockedBackendOptions {
	readonly latencyProfile?: BridgeViewerMockedBackendLatencyProfile;
	readonly contentFailures?: readonly string[];
	readonly deferContentHandleIds?: readonly string[];
	readonly projectionFailure?: boolean;
	readonly deferProjectionResponses?: boolean;
}

export interface BridgeViewerMockedBackendPushRecord {
	readonly op: 'replace' | 'merge';
	readonly revision: number;
	readonly reviewGeneration: number;
	readonly payloadKind: 'package' | 'delta';
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
	readonly pushPackage: (reviewPackage?: BridgeReviewPackage) => Promise<void>;
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

export function makeBridgeViewerBrowserFixture(
	props: {
		readonly fixtureClass?: BridgeViewerBrowserFixtureClass;
		readonly largeItemPlacement?: BridgeViewerLargeFixtureItemPlacement;
	} = {},
): BridgeViewerBrowserFixture {
	const fixtureClass = props.fixtureClass ?? 'small-mixed';
	const largeItemPlacement = props.largeItemPlacement ?? 'near-start';
	const basePackage = makeBridgeReviewPackage();
	const sourceItem = makeBrowserFixtureItem({
		itemId: 'browser-source-a',
		path: 'Sources/BridgeViewer/Alpha.ts',
		changeKind: 'modified',
		fileClass: 'source',
		language: 'typescript',
		extension: 'ts',
	});
	const secondItem = makeBrowserFixtureItem({
		itemId: 'browser-source-b',
		path: 'Sources/BridgeViewer/Beta.ts',
		changeKind: 'modified',
		fileClass: 'source',
		language: 'typescript',
		extension: 'ts',
	});
	const addedItem = makeBrowserFixtureItem({
		itemId: 'browser-added-source',
		path: 'Sources/BridgeViewer/NewPanel.ts',
		changeKind: 'added',
		fileClass: 'source',
		language: 'typescript',
		extension: 'ts',
	});
	const docsItem = makeBrowserFixtureItem({
		itemId: 'browser-docs-plan',
		path: 'docs/plans/bridge-viewer-browser.md',
		changeKind: 'added',
		fileClass: 'docs',
		language: 'markdown',
		extension: 'md',
	});
	const largeItem = makeBrowserFixtureItem({
		itemId: 'browser-large-diff',
		path: 'large/browser/huge-diff.ts',
		itemKind: 'file',
		changeKind: 'modified',
		fileClass: 'source',
		language: 'typescript',
		extension: 'ts',
	});
	const hunkedItem = makeBrowserFixtureItem({
		itemId: 'browser-hunked-diff',
		path: 'Sources/BridgeViewer/HunkedContext.ts',
		changeKind: 'modified',
		fileClass: 'source',
		language: 'typescript',
		extension: 'ts',
	});
	const appendedItem = makeBrowserFixtureItem({
		itemId: 'browser-streaming-append',
		path: 'streaming/append/NewStreamingPanel.ts',
		changeKind: 'added',
		fileClass: 'source',
		language: 'typescript',
		extension: 'ts',
	});
	const fillerItems = Array.from(
		{ length: fillerItemCountForFixtureClass(fixtureClass) },
		(_value: unknown, index: number) => makeBrowserFillerItem({ fixtureClass, index }),
	);
	const leadingItems = [sourceItem, secondItem, addedItem, docsItem];
	const items =
		largeItemPlacement === 'after-fillers'
			? [...leadingItems, hunkedItem, ...fillerItems, largeItem]
			: [...leadingItems, largeItem, hunkedItem, ...fillerItems];
	const contentByHandleId = new Map<string, string>();

	addContent(contentByHandleId, sourceItem, {
		base: "export const selectedFile = 'alpha base';\n",
		head: "export const selectedFile = 'alpha head visible';\n",
	});
	addContent(contentByHandleId, secondItem, {
		base: "export const selectedFile = 'beta base';\n",
		head: "export const selectedFile = 'beta selected content';\n",
	});
	addContent(contentByHandleId, addedItem, {
		head: [
			'export function renderAddedPanel(): string {',
			"\treturn 'full added file content';",
			'}',
			'',
		].join('\n'),
	});
	addContent(contentByHandleId, docsItem, {
		head: '# Browser fixture\n\n```ts\nconst fixture = true;\n```\n',
	});
	addContent(contentByHandleId, largeItem, {
		base: largeBrowserDiffText('base'),
		head: largeBrowserDiffText('head'),
	});
	addContent(contentByHandleId, hunkedItem, {
		base: hunkedBrowserDiffText('base'),
		head: hunkedBrowserDiffText('head'),
	});
	addContent(contentByHandleId, appendedItem, {
		head: [
			'export function renderStreamingPanel(): string {',
			"\treturn 'streaming appended file content';",
			'}',
			'',
		].join('\n'),
	});

	for (const item of fillerItems) {
		addContent(contentByHandleId, item, {
			base: `export const filler${item.itemId} = 'base';\n`,
			head: `export const filler${item.itemId} = 'head';\n`,
		});
	}

	const reviewPackage: BridgeReviewPackage = {
		...basePackage,
		packageId: `browser-mode-${fixtureClass}`,
		reviewGeneration: 338,
		revision: 1,
		orderedItemIds: items.map((item): string => item.itemId),
		itemsById: Object.fromEntries(items.map((item) => [item.itemId, item])),
		query: {
			...basePackage.query,
			pathScope: [],
		},
		summary: {
			filesChanged: items.length,
			additions: items.reduce((total, item): number => total + item.additions, 0),
			deletions: items.reduce((total, item): number => total + item.deletions, 0),
			visibleFileCount: items.length,
			hiddenFileCount: 0,
		},
		filterState: {
			...basePackage.filterState,
			showLargeFiles: true,
		},
	};

	const packageBytes = new TextEncoder().encode(JSON.stringify(reviewPackage)).byteLength;
	const selectedLargeFileLineCount = selectedLargeContentLineCount(contentByHandleId, largeItem);
	const addedFullContentTargetCount = items.filter((item: BridgeReviewItemDescriptor): boolean => {
		const headHandle = item.contentRoles.head ?? null;
		return (
			item.changeKind === 'added' &&
			headHandle !== null &&
			lineCount(contentByHandleId.get(headHandle.handleId)) > 2
		);
	}).length;
	const streamingAppendDelta: BridgeReviewDelta = {
		packageId: reviewPackage.packageId,
		reviewGeneration: reviewPackage.reviewGeneration,
		revision: reviewPackage.revision + 1,
		operations: {
			addItems: [appendedItem],
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
		items.length.toString(),
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
			changeKindCounts: countChangeKinds(items),
			fileClassCounts: countFileClasses(items),
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
			addedHeadHandleId: requiredHandleId(addedItem.contentRoles.head, 'added head'),
			hunkPath: 'Sources/BridgeViewer/HunkedContext.ts',
			hunkExpandedText: "export const stableContextLine0025 = 'same';",
			docsPath: 'docs/plans/bridge-viewer-browser.md',
			docsMarkdownText: '# Browser fixture',
			docsMarkdownHeading: 'Browser fixture',
			searchText: 'Hunked',
			searchPath: 'Sources/BridgeViewer/HunkedContext.ts',
			testFilterPath: 'tree/module-00/file-007.ts',
			largePath: 'large/browser/huge-diff.ts',
			largeText: "export const generatedLine0000 = 'head';",
			largeHeadHandleId: requiredHandleId(largeItem.contentRoles.head, 'large head'),
			secondHeadHandleId: requiredHandleId(secondItem.contentRoles.head, 'second head'),
			appendedPath: 'streaming/append/NewStreamingPanel.ts',
			appendedText: "return 'streaming appended file content';",
			appendedHeadHandleId: requiredHandleId(appendedItem.contentRoles.head, 'appended head'),
		},
	};
}

export function installBridgeViewerMockedBackend(
	fixture: BridgeViewerBrowserFixture = makeBridgeViewerBrowserFixture(),
	options: InstallBridgeViewerMockedBackendOptions = {},
): BridgeViewerMockedBackend {
	document.documentElement.setAttribute('data-bridge-nonce', bridgeViewerCommandNonce);
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
	let didReceiveHandshakeRequest = false;
	const commandListener = (event: Event): void => {
		commandDetails.push('detail' in event ? event.detail : null);
	};
	const handshakeRequestListener = (): void => {
		didReceiveHandshakeRequest = true;
		document.dispatchEvent(
			new CustomEvent('__bridge_handshake', {
				detail: { pushNonce: bridgeViewerPushNonce },
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
				await waitForLatencyProfile(latencyProfile);
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
			await waitForLatencyProfile(latencyProfile);
			if (init?.signal?.aborted === true) {
				return new Response('', { status: 499 });
			}
			const handleId = handleIdFromResourceUrl(url);
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
					pendingContentResponses.push({
						url,
						handleId,
						resolve: (): void => {
							resolve(response());
						},
					});
				});
			}
			return response();
		},
		pushPackage: async (
			reviewPackage: BridgeReviewPackage = fixture.reviewPackage,
		): Promise<void> => {
			await waitForBridgeHandshakeRequest((): boolean => didReceiveHandshakeRequest);
			pushRecords.push({
				op: 'replace',
				revision: reviewPackage.revision,
				reviewGeneration: reviewPackage.reviewGeneration,
				payloadKind: 'package',
			});
			document.dispatchEvent(
				new CustomEvent('__bridge_push', {
					detail: {
						__v: 1,
						__pushId: `push-${reviewPackage.packageId}-${reviewPackage.revision}`,
						__revision: reviewPackage.revision,
						__epoch: reviewPackage.reviewGeneration,
						store: 'diff',
						op: 'replace',
						level: 'cold',
						slice: 'diff_package_metadata',
						nonce: bridgeViewerPushNonce,
						data: { package: reviewPackage },
					},
				}),
			);
			await Promise.resolve();
			await Promise.resolve();
		},
		pushDelta: async (delta: BridgeReviewDelta = fixture.streamingAppendDelta): Promise<void> => {
			await waitForBridgeHandshakeRequest((): boolean => didReceiveHandshakeRequest);
			pushRecords.push({
				op: 'merge',
				revision: delta.revision,
				reviewGeneration: delta.reviewGeneration,
				payloadKind: 'delta',
			});
			document.dispatchEvent(
				new CustomEvent('__bridge_push', {
					detail: {
						__v: 1,
						__pushId: `push-${delta.packageId}-delta-${delta.revision}`,
						__revision: delta.revision,
						__epoch: delta.reviewGeneration,
						store: 'diff',
						op: 'merge',
						level: 'hot',
						slice: 'diff_package_metadata',
						nonce: bridgeViewerPushNonce,
						data: { delta },
					},
				}),
			);
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
		throw new Error('expected Bridge handshake request before package push');
	}
	await Promise.resolve();
	await new Promise<void>((resolve) => {
		requestAnimationFrame((): void => resolve());
	});
	await waitForBridgeHandshakeRequest(didReceiveHandshakeRequest, remainingAttempts - 1);
}

function makeBrowserFixtureItem(props: {
	readonly itemId: string;
	readonly path: string;
	readonly itemKind?: BridgeReviewItemDescriptor['itemKind'];
	readonly changeKind: BridgeFileChangeKind;
	readonly fileClass: BridgeFileClass;
	readonly language: string;
	readonly extension: string;
}): BridgeReviewItemDescriptor {
	const baseItem = makeBridgeReviewItem({ itemId: props.itemId, path: props.path });
	const base =
		props.changeKind === 'added'
			? null
			: makeBrowserContentHandle(props.itemId, 'base', props.language, props.extension);
	const head =
		props.changeKind === 'deleted'
			? null
			: makeBrowserContentHandle(props.itemId, 'head', props.language, props.extension);
	return {
		...baseItem,
		itemKind: props.itemKind ?? baseItem.itemKind,
		itemId: props.itemId,
		basePath: props.changeKind === 'added' ? null : props.path,
		headPath: props.changeKind === 'deleted' ? null : props.path,
		changeKind: props.changeKind,
		fileClass: props.fileClass,
		language: props.language,
		extension: props.extension,
		baseContentHash: base?.contentHash ?? null,
		headContentHash: head?.contentHash ?? null,
		additions: props.changeKind === 'deleted' ? 0 : 7,
		deletions: props.changeKind === 'added' ? 0 : 4,
		contentRoles: { base, head, diff: null, file: null },
		cacheKey: `${base?.cacheKey ?? 'none'}|${head?.cacheKey ?? 'none'}`,
		isHiddenByDefault: false,
		hiddenReason: null,
	};
}

function makeBrowserFillerItem(props: {
	readonly fixtureClass: BridgeViewerBrowserFixtureClass;
	readonly index: number;
}): BridgeReviewItemDescriptor {
	const pathRoot = props.fixtureClass === 'small-mixed' ? 'tree' : 'Sources/AgentStudio';
	const pathLeaf = props.index.toString().padStart(3, '0');
	const moduleName = Math.floor(props.index / 12)
		.toString()
		.padStart(2, '0');
	const fileClass = browserFillerFileClass(props.index);
	const changeKind = browserFillerChangeKind(props.index);
	const extension = fileClass === 'docs' ? 'md' : 'ts';
	const language = fileClass === 'docs' ? 'markdown' : 'typescript';
	const path =
		props.fixtureClass === 'small-mixed'
			? `tree/module-${moduleName}/file-${pathLeaf}.${extension}`
			: `${pathRoot}/${fileClass}/module-${moduleName}/file-${pathLeaf}.${extension}`;
	return makeBrowserFixtureItem({
		itemId: `browser-filler-${props.fixtureClass}-${pathLeaf}`,
		path,
		changeKind,
		fileClass,
		language,
		extension,
	});
}

function fillerItemCountForFixtureClass(fixtureClass: BridgeViewerBrowserFixtureClass): number {
	switch (fixtureClass) {
		case 'small-mixed':
			return 96;
		case 'medium-agentstudio':
			return 1_000;
		case 'large-diffshub':
			return 3_414;
	}
	const exhaustiveFixtureClass: never = fixtureClass;
	void exhaustiveFixtureClass;
	throw new Error('Unhandled fixture class');
}

function browserFillerFileClass(index: number): BridgeFileClass {
	if (index % 23 === 0) {
		return 'docs';
	}
	if (index % 17 === 0) {
		return 'config';
	}
	if (index % 7 === 0) {
		return 'test';
	}
	return 'source';
}

function browserFillerChangeKind(index: number): BridgeFileChangeKind {
	if (index % 29 === 0) {
		return 'renamed';
	}
	if (index % 31 === 0) {
		return 'deleted';
	}
	if (index % 5 === 0) {
		return 'added';
	}
	return 'modified';
}

function makeBrowserContentHandle(
	itemId: string,
	role: 'base' | 'head',
	language: string,
	extension: string,
): BridgeContentHandle {
	const handle = makeBridgeContentHandle(itemId, role);
	return {
		...handle,
		reviewGeneration: 338,
		resourceUrl: `agentstudio://resource/content/${handle.handleId}?generation=338`,
		mimeType: extension === 'md' ? 'text/markdown' : 'text/typescript',
		language,
		sizeBytes: 512,
	};
}

function addContent(
	contentByHandleId: Map<string, string>,
	item: BridgeReviewItemDescriptor,
	content: { readonly base?: string; readonly head?: string },
): void {
	const baseHandle = item.contentRoles.base ?? null;
	const headHandle = item.contentRoles.head ?? null;
	if (baseHandle !== null && content.base !== undefined) {
		contentByHandleId.set(baseHandle.handleId, content.base);
	}
	if (headHandle !== null && content.head !== undefined) {
		contentByHandleId.set(headHandle.handleId, content.head);
	}
}

function requiredHandleId(handle: BridgeContentHandle | null | undefined, label: string): string {
	if (handle === null || handle === undefined) {
		throw new Error(`expected ${label} content handle`);
	}
	return handle.handleId;
}

async function waitForLatencyProfile(
	latencyProfile: BridgeViewerMockedBackendLatencyProfile,
): Promise<void> {
	const delayMilliseconds = latencyDelayMilliseconds(latencyProfile);
	if (delayMilliseconds === 0) {
		await Promise.resolve();
		return;
	}
	await new Promise<void>((resolve) => {
		setTimeout(resolve, delayMilliseconds);
	});
}

function latencyDelayMilliseconds(latencyProfile: BridgeViewerMockedBackendLatencyProfile): number {
	switch (latencyProfile) {
		case 'zero':
			return 0;
		case 'small':
			return 6;
		case 'slowBounded':
			return 80;
	}
	const exhaustiveLatencyProfile: never = latencyProfile;
	void exhaustiveLatencyProfile;
	throw new Error('Unhandled latency profile');
}

function largeBrowserDiffText(label: 'base' | 'head'): string {
	return Array.from({ length: 50_000 }, (_value: unknown, index: number): string => {
		const paddedIndex = index.toString().padStart(4, '0');
		return `export const generatedLine${paddedIndex} = '${label}';`;
	}).join('\n');
}

function hunkedBrowserDiffText(label: 'base' | 'head'): string {
	return Array.from({ length: 60 }, (_value: unknown, index: number): string => {
		const paddedIndex = index.toString().padStart(4, '0');
		if (index === 4 || index === 47) {
			return `export const changedContextLine${paddedIndex} = '${label}';`;
		}
		return `export const stableContextLine${paddedIndex} = 'same';`;
	}).join('\n');
}

function handleIdFromResourceUrl(url: string): string | null {
	const parsedUrl = new URL(url);
	const [, resourceKind, handleId] = parsedUrl.pathname.split('/');
	if (
		parsedUrl.protocol !== 'agentstudio:' ||
		parsedUrl.hostname !== 'resource' ||
		resourceKind !== 'content'
	) {
		return null;
	}
	return handleId ?? null;
}

function countChangeKinds(
	items: readonly BridgeReviewItemDescriptor[],
): Readonly<Record<BridgeFileChangeKind, number>> {
	return {
		added: countItemsWhere(
			items,
			(item: BridgeReviewItemDescriptor): boolean => item.changeKind === 'added',
		),
		modified: countItemsWhere(
			items,
			(item: BridgeReviewItemDescriptor): boolean => item.changeKind === 'modified',
		),
		deleted: countItemsWhere(
			items,
			(item: BridgeReviewItemDescriptor): boolean => item.changeKind === 'deleted',
		),
		renamed: countItemsWhere(
			items,
			(item: BridgeReviewItemDescriptor): boolean => item.changeKind === 'renamed',
		),
		copied: countItemsWhere(
			items,
			(item: BridgeReviewItemDescriptor): boolean => item.changeKind === 'copied',
		),
	};
}

function countFileClasses(
	items: readonly BridgeReviewItemDescriptor[],
): Readonly<Record<BridgeFileClass, number>> {
	return {
		source: countItemsWhere(
			items,
			(item: BridgeReviewItemDescriptor): boolean => item.fileClass === 'source',
		),
		test: countItemsWhere(
			items,
			(item: BridgeReviewItemDescriptor): boolean => item.fileClass === 'test',
		),
		docs: countItemsWhere(
			items,
			(item: BridgeReviewItemDescriptor): boolean => item.fileClass === 'docs',
		),
		config: countItemsWhere(
			items,
			(item: BridgeReviewItemDescriptor): boolean => item.fileClass === 'config',
		),
		generated: countItemsWhere(
			items,
			(item: BridgeReviewItemDescriptor): boolean => item.fileClass === 'generated',
		),
		vendor: countItemsWhere(
			items,
			(item: BridgeReviewItemDescriptor): boolean => item.fileClass === 'vendor',
		),
		binary: countItemsWhere(
			items,
			(item: BridgeReviewItemDescriptor): boolean => item.fileClass === 'binary',
		),
		large: countItemsWhere(
			items,
			(item: BridgeReviewItemDescriptor): boolean => item.fileClass === 'large',
		),
		fixture: countItemsWhere(
			items,
			(item: BridgeReviewItemDescriptor): boolean => item.fileClass === 'fixture',
		),
		unknown: countItemsWhere(
			items,
			(item: BridgeReviewItemDescriptor): boolean => item.fileClass === 'unknown',
		),
	};
}

function countItemsWhere(
	items: readonly BridgeReviewItemDescriptor[],
	predicate: (item: BridgeReviewItemDescriptor) => boolean,
): number {
	return items.filter(predicate).length;
}

function selectedLargeContentLineCount(
	contentByHandleId: ReadonlyMap<string, string>,
	largeItem: BridgeReviewItemDescriptor,
): number {
	const baseHandle = largeItem.contentRoles.base ?? null;
	const headHandle = largeItem.contentRoles.head ?? null;
	const baseLineCount =
		baseHandle === null ? 0 : lineCount(contentByHandleId.get(baseHandle.handleId));
	const headLineCount =
		headHandle === null ? 0 : lineCount(contentByHandleId.get(headHandle.handleId));
	return baseLineCount + headLineCount;
}

function lineCount(content: string | undefined): number {
	if (content === undefined || content.length === 0) {
		return 0;
	}
	return content.split('\n').length;
}
