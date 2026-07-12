import {
	bridgeProductSurfaceForCallKind,
	type BridgeProductCallKind,
	type BridgeProductCallRegistry,
} from './bridge-product-call-contracts.js';
import {
	bridgeProductSurfaceForContentKind,
	type BridgeProductContentKind,
	type BridgeProductContentRegistry,
} from './bridge-product-content-contracts.js';
import {
	BRIDGE_PRODUCT_CAPABILITY_HEADER_NAME,
	BRIDGE_PRODUCT_COMMAND_ROUTE,
	BRIDGE_PRODUCT_CONTENT_ROUTE,
	BRIDGE_PRODUCT_REQUEST_METHOD,
	BRIDGE_PRODUCT_STREAM_ROUTE,
	type BridgeProductRegistryValue,
	type BridgeProductSurface,
} from './bridge-product-contract-primitives.js';
import type {
	BridgeProductControlRequest,
	BridgeProductMetadataFrame,
} from './bridge-product-session-contracts.js';
import type {
	BridgeProductSubscriptionEvent,
	BridgeProductSubscriptionKind,
	BridgeProductSubscriptionRegistry,
	BridgeProductSubscriptionUpdateOptions,
} from './bridge-product-subscription-contracts.js';
import { bridgeProductSurfaceForSubscriptionKind } from './bridge-product-subscription-contracts.js';
import type {
	BridgeProductCallResult,
	BridgeProductContentStream,
	BridgeProductSubscription,
	BridgeProductTransport,
} from './bridge-product-transport-contract.js';

declare const productTransport: BridgeProductTransport;
declare const abortSignal: AbortSignal;
declare function acceptControlRequest(request: BridgeProductControlRequest): void;
declare function acceptMetadataFrame(frame: BridgeProductMetadataFrame): void;
const requestMethod: 'POST' = BRIDGE_PRODUCT_REQUEST_METHOD;
const commandRoute: 'agentstudio://rpc/command' = BRIDGE_PRODUCT_COMMAND_ROUTE;
const contentRoute: 'agentstudio://rpc/content' = BRIDGE_PRODUCT_CONTENT_ROUTE;
const streamRoute: 'agentstudio://rpc/stream' = BRIDGE_PRODUCT_STREAM_ROUTE;
const capabilityHeaderName: 'X-AgentStudio-Bridge-Product-Capability' =
	BRIDGE_PRODUCT_CAPABILITY_HEADER_NAME;
void requestMethod;
void commandRoute;
void contentRoute;
void streamRoute;
void capabilityHeaderName;

type SyntheticCorrelationRegistry = {
	readonly first: {
		readonly descriptor: { readonly descriptorCase: 'first' };
		readonly identity: { readonly identityCase: 'first' };
		readonly request: { readonly requestCase: 'first' };
		readonly result: { readonly resultCase: 'first' };
		readonly terminal: { readonly terminalCase: 'first' };
	};
	readonly second: {
		readonly descriptor: { readonly descriptorCase: 'second' };
		readonly identity: { readonly identityCase: 'second' };
		readonly request: { readonly requestCase: 'second' };
		readonly result: { readonly resultCase: 'second' };
		readonly terminal: { readonly terminalCase: 'second' };
	};
};

type SyntheticCallCorrelation<TCase extends keyof SyntheticCorrelationRegistry> = readonly [
	request: BridgeProductRegistryValue<SyntheticCorrelationRegistry, TCase, 'request'>,
	result: BridgeProductRegistryValue<SyntheticCorrelationRegistry, TCase, 'result'>,
];

type SyntheticContentCorrelation<TCase extends keyof SyntheticCorrelationRegistry> = readonly [
	descriptor: BridgeProductRegistryValue<SyntheticCorrelationRegistry, TCase, 'descriptor'>,
	identity: BridgeProductRegistryValue<SyntheticCorrelationRegistry, TCase, 'identity'>,
	terminal: BridgeProductRegistryValue<SyntheticCorrelationRegistry, TCase, 'terminal'>,
];

const syntheticFirstCall: SyntheticCallCorrelation<'first'> = [
	{ requestCase: 'first' },
	{ resultCase: 'first' },
];
const syntheticFirstContent: SyntheticContentCorrelation<'first'> = [
	{ descriptorCase: 'first' },
	{ identityCase: 'first' },
	{ terminalCase: 'first' },
];
const syntheticSecondCall: SyntheticCallCorrelation<'second'> = [
	{ requestCase: 'second' },
	{ resultCase: 'second' },
];
const syntheticSecondContent: SyntheticContentCorrelation<'second'> = [
	{ descriptorCase: 'second' },
	{ identityCase: 'second' },
	{ terminalCase: 'second' },
];
void syntheticFirstCall;
void syntheticFirstContent;
void syntheticSecondCall;
void syntheticSecondContent;

const syntheticCrossWiredRequest: SyntheticCallCorrelation<'first'> = [
	{
		// @ts-expect-error A registry case cannot borrow another case's request.
		requestCase: 'second',
	},
	{ resultCase: 'first' },
];
const syntheticCrossWiredResult: SyntheticCallCorrelation<'first'> = [
	{ requestCase: 'first' },
	{
		// @ts-expect-error A registry case cannot borrow another case's result.
		resultCase: 'second',
	},
];
const syntheticCrossWiredDescriptor: SyntheticContentCorrelation<'first'> = [
	{
		// @ts-expect-error A registry case cannot borrow another case's descriptor.
		descriptorCase: 'second',
	},
	{ identityCase: 'first' },
	{ terminalCase: 'first' },
];
const syntheticCrossWiredIdentity: SyntheticContentCorrelation<'first'> = [
	{ descriptorCase: 'first' },
	{
		// @ts-expect-error A registry case cannot borrow another case's identity.
		identityCase: 'second',
	},
	{ terminalCase: 'first' },
];
const syntheticCrossWiredTerminal: SyntheticContentCorrelation<'first'> = [
	{ descriptorCase: 'first' },
	{ identityCase: 'first' },
	{
		// @ts-expect-error A registry case cannot borrow another case's terminal.
		terminalCase: 'second',
	},
];
void syntheticCrossWiredRequest;
void syntheticCrossWiredResult;
void syntheticCrossWiredDescriptor;
void syntheticCrossWiredIdentity;
void syntheticCrossWiredTerminal;

const surfaceByCallKind = {
	'file.activeViewerMode.update': 'file',
	'file.source.current': 'file',
	'review.activeViewerMode.update': 'review',
	'review.markFileViewed': 'review',
} as const satisfies {
	readonly [TCallKind in BridgeProductCallKind]: BridgeProductCallRegistry[TCallKind]['surface'];
};
const surfaceBySubscriptionKind = {
	'file.metadata': 'file',
	'review.metadata': 'review',
} as const satisfies {
	readonly [TSubscriptionKind in BridgeProductSubscriptionKind]: BridgeProductSubscriptionRegistry[TSubscriptionKind]['surface'];
};
const surfaceByContentKind = {
	'file.content': 'file',
	'review.content': 'review',
} as const satisfies {
	readonly [TContentKind in BridgeProductContentKind]: BridgeProductContentRegistry[TContentKind]['surface'];
};

const reviewCallSurface: 'review' = bridgeProductSurfaceForCallKind('review.markFileViewed');
const reviewActiveModeCallSurface: 'review' = bridgeProductSurfaceForCallKind(
	'review.activeViewerMode.update',
);
const fileActiveModeCallSurface: 'file' = bridgeProductSurfaceForCallKind(
	'file.activeViewerMode.update',
);
const fileSourceCurrentCallSurface: 'file' = bridgeProductSurfaceForCallKind('file.source.current');
const reviewSubscriptionSurface: 'review' =
	bridgeProductSurfaceForSubscriptionKind('review.metadata');
const fileSubscriptionSurface: 'file' = bridgeProductSurfaceForSubscriptionKind('file.metadata');
const fileContentSurface: 'file' = bridgeProductSurfaceForContentKind('file.content');
const reviewContentSurface: 'review' = bridgeProductSurfaceForContentKind('review.content');
const allMappedSurfaces: readonly BridgeProductSurface[] = [
	...Object.values(surfaceByCallKind),
	...Object.values(surfaceBySubscriptionKind),
	...Object.values(surfaceByContentKind),
];
void reviewCallSurface;
void reviewActiveModeCallSurface;
void fileActiveModeCallSurface;
void fileSourceCurrentCallSurface;
void reviewSubscriptionSurface;
void fileSubscriptionSurface;
void fileContentSurface;
void reviewContentSurface;
void allMappedSurfaces;

// @ts-expect-error A closed call mapper cannot infer a surface from a string prefix.
void bridgeProductSurfaceForCallKind('file.arbitrary');
// @ts-expect-error A closed subscription mapper cannot infer a surface from a string prefix.
void bridgeProductSurfaceForSubscriptionKind('review.arbitrary');
// @ts-expect-error A closed content mapper cannot infer a surface from a string prefix.
void bridgeProductSurfaceForContentKind('file.arbitrary');

// @ts-expect-error Route inference must retain the exact command URL literal.
const invalidCommandRoute: 'agentstudio://rpc/content' = BRIDGE_PRODUCT_COMMAND_ROUTE;
void invalidCommandRoute;

const markViewedResult: Promise<null> = productTransport.call('review.markFileViewed', {
	itemId: 'review-item-1',
});
void markViewedResult;

const emptyMarkViewedResult: BridgeProductCallResult<'review.markFileViewed'> = null;
void emptyMarkViewedResult;

const currentFileSourceResult = productTransport.call('file.source.current', {});
const availableCurrentFileSourceResult: BridgeProductCallResult<'file.source.current'> = {
	source: {
		cwdScope: null,
		freshness: 'live',
		includeStatuses: true,
		repoId: '00000000-0000-4000-8000-000000000001',
		rootPathToken: 'root-token-1',
		worktreeId: '00000000-0000-4000-8000-000000000002',
	},
	status: 'available',
};
const unavailableCurrentFileSourceResult: BridgeProductCallResult<'file.source.current'> = {
	reason: 'no-file-source-authority',
	status: 'unavailable',
};
void currentFileSourceResult;
void availableCurrentFileSourceResult;
void unavailableCurrentFileSourceResult;

const reviewSubscription: BridgeProductSubscription<'review.metadata'> = productTransport.subscribe(
	'review.metadata',
	{
		interests: [{ itemIds: ['review-item-1'], lane: 'foreground' }],
	},
);
void reviewSubscription;
void reviewSubscription.update({
	interests: [{ itemIds: ['review-item-2'], lane: 'visible' }],
});
void reviewSubscription.update({
	interests: [
		{
			lane: 'visible',
			// @ts-expect-error Review updates cannot cross-wire File path interests.
			paths: ['src/file.ts'],
		},
	],
});

const fileSubscription: BridgeProductSubscription<'file.metadata'> = productTransport.subscribe(
	'file.metadata',
	{
		interests: [{ lane: 'visible', paths: ['src/file.ts'] }],
		pathScope: [],
		source: {
			cwdScope: null,
			freshness: 'live',
			includeStatuses: true,
			repoId: '00000000-0000-4000-8000-000000000001',
			rootPathToken: 'root-token-1',
			worktreeId: '00000000-0000-4000-8000-000000000002',
		},
	},
);
void fileSubscription.update({
	interests: [{ lane: 'foreground', paths: ['src/file.ts'] }],
	pathScope: ['src'],
});
void fileSubscription.update({
	interests: [
		{
			// @ts-expect-error File updates cannot cross-wire Review item interests.
			itemIds: ['review-item-1'],
			lane: 'foreground',
		},
	],
	pathScope: [],
});

declare const unionSubscriptionKind: BridgeProductSubscriptionKind;
// @ts-expect-error A union subscription key cannot borrow one variant's options.
void productTransport.subscribe(unionSubscriptionKind, {
	interests: [{ itemIds: ['review-item-1'], lane: 'foreground' }],
});

declare const unionSubscription: BridgeProductSubscription<BridgeProductSubscriptionKind>;
const reviewSubscriptionUpdate = {
	interests: [{ itemIds: ['review-item-2'], lane: 'visible' }],
} satisfies BridgeProductSubscriptionUpdateOptions<'review.metadata'>;
const fileSubscriptionUpdate = {
	interests: [{ lane: 'foreground', paths: ['src/file.ts'] }],
	pathScope: ['src'],
} satisfies BridgeProductSubscriptionUpdateOptions<'file.metadata'>;
// @ts-expect-error A union subscription must be narrowed before accepting Review updates.
void unionSubscription.update(reviewSubscriptionUpdate);
// @ts-expect-error A union subscription must be narrowed before accepting File updates.
void unionSubscription.update(fileSubscriptionUpdate);

if (unionSubscription.subscriptionKind === 'review.metadata') {
	void unionSubscription.update(reviewSubscriptionUpdate);
} else {
	void unionSubscription.update(fileSubscriptionUpdate);
}

declare const fileMetadataEvent: BridgeProductSubscriptionEvent<'file.metadata'>;
// @ts-expect-error Review and File subscription events cannot cross-wire.
const invalidReviewMetadataEvent: BridgeProductSubscriptionEvent<'review.metadata'> =
	fileMetadataEvent;
void invalidReviewMetadataEvent;

switch (fileMetadataEvent.eventKind) {
	case 'file.sourceAccepted':
		void fileMetadataEvent.source.sourceId;
		break;
	case 'file.treeWindow':
		void fileMetadataEvent.rows;
		break;
	case 'file.treeDelta':
		void fileMetadataEvent.operations;
		break;
	case 'file.statusPatch':
		void fileMetadataEvent.patch.patchKind;
		break;
	case 'file.descriptorReady':
		void fileMetadataEvent.availability.availabilityKind;
		const descriptorEncoding: 'utf-8' | null = fileMetadataEvent.encoding;
		const descriptorPayloadByteCount: number = fileMetadataEvent.payloadByteCount;
		const descriptorPayloadLineCount: number = fileMetadataEvent.payloadLineCount;
		const descriptorTotalLineCount: number | null = fileMetadataEvent.totalLineCount;
		void descriptorEncoding;
		void descriptorPayloadByteCount;
		void descriptorPayloadLineCount;
		void descriptorTotalLineCount;
		// @ts-expect-error Descriptor-ready events cannot expose legacy resource carriers.
		void fileMetadataEvent.resourceUrl;
		// @ts-expect-error Descriptor-ready events no longer expose ambiguous line counts.
		void fileMetadataEvent.lineCount;
		break;
	case 'file.invalidated':
		void fileMetadataEvent.replacementDescriptor;
		break;
}

const fileContent: BridgeProductContentStream<'file.content'> = productTransport.openContent(
	{
		contentKind: 'file.content',
		declaredByteLength: 12,
		descriptorId: 'file-descriptor-1',
		encoding: 'utf-8',
		expectedSha256: 'a'.repeat(64),
		fileId: 'file-1',
		maximumBytes: 2 * 1024 * 1024,
		source: {
			repoId: '00000000-0000-4000-8000-000000000001',
			rootRevisionToken: null,
			sourceCursor: 'source-cursor-1',
			sourceId: 'source-1',
			subscriptionGeneration: 11,
			worktreeId: '00000000-0000-4000-8000-000000000002',
		},
		window: {
			kind: 'prefix',
			maximumBytes: 2 * 1024 * 1024,
			maximumLines: 10_000,
			startByte: 0,
		},
	},
	abortSignal,
);
void fileContent;

const reviewContent: BridgeProductContentStream<'review.content'> = productTransport.openContent(
	{
		contentDigest: {
			algorithm: 'git-oid',
			authority: 'provisional',
			value: '0123456789abcdef0123456789abcdef01234567',
		},
		contentKind: 'review.content',
		declaredByteLength: null,
		descriptorId: 'review-descriptor-1',
		encoding: 'utf-8',
		endpointId: 'review-endpoint-1',
		expectedSha256: null,
		handleId: 'review-handle-1',
		isBinary: false,
		itemId: 'review-item-1',
		language: 'typescript',
		maximumBytes: 512 * 1024,
		mimeType: 'text/plain',
		packageId: 'review-package-1',
		reviewGeneration: 7,
		role: 'head',
		sourceIdentity: 'review-query-1',
		wholeByteLength: 2_400_000,
		window: {
			kind: 'byteRange',
			maximumBytes: 512 * 1024,
			startByte: 0,
		},
	},
	abortSignal,
);
void reviewContent;
// @ts-expect-error Review content streams cannot cross-wire into File content results.
const invalidFileContent: BridgeProductContentStream<'file.content'> = reviewContent;
void invalidFileContent;

// @ts-expect-error Unknown calls cannot enter the closed registry.
void productTransport.call('review.arbitrary', null);

// @ts-expect-error The mark-viewed call requires its exact request.
void productTransport.call('review.markFileViewed', null);

// @ts-expect-error File source discovery accepts only its strict empty request.
void productTransport.call('file.source.current', { retry: true });

// @ts-expect-error Empty results use null, never an empty object.
const invalidMarkViewedResult: BridgeProductCallResult<'review.markFileViewed'> = {};
void invalidMarkViewedResult;

void productTransport.subscribe('review.metadata', {
	interests: [
		{
			lane: 'foreground',
			// @ts-expect-error Review and File subscription options cannot cross-wire.
			paths: ['src/file.ts'],
		},
	],
});

// @ts-expect-error Review content opens require the complete strict source and range descriptor.
void productTransport.openContent({ contentKind: 'review.content' }, abortSignal);

// @ts-expect-error Content opens always require a caller-owned AbortSignal.
void productTransport.openContent({
	contentKind: 'file.content',
	declaredByteLength: 12,
	descriptorId: 'file-descriptor-1',
	encoding: 'utf-8',
	expectedSha256: 'a'.repeat(64),
	fileId: 'file-1',
	maximumBytes: 2 * 1024 * 1024,
	source: {
		repoId: '00000000-0000-4000-8000-000000000001',
		rootRevisionToken: null,
		sourceCursor: 'source-cursor-1',
		sourceId: 'source-1',
		subscriptionGeneration: 11,
		worktreeId: '00000000-0000-4000-8000-000000000002',
	},
	window: {
		kind: 'prefix',
		maximumBytes: 2 * 1024 * 1024,
		maximumLines: 10_000,
		startByte: 0,
	},
});

// A Review update cannot carry the File delta variant.
acceptControlRequest({
	baseInterestRevision: 0,
	baseInterestSha256: '1a71797cab8ed23c72233b7706b166a33049e4e87dfbc55b9e252f9c1843eca6',
	batchCount: 1,
	batchIndex: 0,
	delta: {
		add: [
			{
				lane: 'foreground',
				// @ts-expect-error Review deltas cannot carry File paths.
				path: 'src/file.ts',
			},
		],
		addPathScope: [],
		removePathScope: [],
		removePaths: [],
		// @ts-expect-error Nested delta kind must match the outer Review kind.
		subscriptionKind: 'file.metadata',
	},
	kind: 'subscription.updateBatch',
	paneSessionId: 'pane-session-1',
	requestId: 'request-1',
	requestSequence: 1,
	subscriptionId: 'review-subscription-1',
	subscriptionKind: 'review.metadata',
	targetInterestRevision: 1,
	targetInterestSha256: '2535176c2a822c1f5007dd72a7987b7c0a1b6e9af1bc28324ec4618b43f71ebd',
	totalDeltaItemCount: 1,
	updateId: 'update-1',
	wireVersion: 2,
	workerDerivationEpoch: 3,
	workerInstanceId: 'worker-instance-1',
});

// A Review metadata frame cannot carry the File data variant.
acceptMetadataFrame({
	cursor: null,
	data: {
		event: {
			// @ts-expect-error Review frames cannot carry File events.
			eventKind: 'file.sourceAccepted',
			source: {
				repoId: '00000000-0000-4000-8000-000000000001',
				rootRevisionToken: null,
				sourceCursor: 'source-cursor-1',
				sourceId: 'source-1',
				subscriptionGeneration: 1,
				worktreeId: '00000000-0000-4000-8000-000000000002',
			},
		},
		// @ts-expect-error Nested data kind must match the outer Review kind.
		subscriptionKind: 'file.metadata',
	},
	interestRevision: 1,
	interestSha256: '2535176c2a822c1f5007dd72a7987b7c0a1b6e9af1bc28324ec4618b43f71ebd',
	kind: 'subscription.data',
	metadataStreamId: 'metadata-stream-1',
	paneSessionId: 'pane-session-1',
	sourceGeneration: 1,
	streamSequence: 1,
	subscriptionId: 'review-subscription-1',
	subscriptionKind: 'review.metadata',
	subscriptionSequence: 1,
	wireVersion: 2,
	workerDerivationEpoch: 3,
	workerInstanceId: 'worker-instance-1',
});
