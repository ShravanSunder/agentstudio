import { createHash } from 'node:crypto';
import { createServer, type Server } from 'node:http';

import { afterEach, describe, expect, test, vi } from 'vitest';

import {
	BRIDGE_PRODUCT_MAXIMUM_CONTENT_STREAM_BYTES,
	BRIDGE_PRODUCT_WIRE_VERSION,
} from '../../src/core/comm-worker/bridge-product-contract-primitives.js';
import { BridgeProductMetadataFrameDecoder } from '../../src/core/comm-worker/bridge-product-metadata-frame-codec.js';
import { bridgeProductReviewMetadataEventSchema } from '../../src/core/comm-worker/bridge-product-review-metadata-contracts.js';
import {
	bridgeProductControlRequestSchema,
	bridgeProductControlResponseSchema,
	bridgeProductMetadataStreamRequestSchema,
	type BridgeProductControlRequest,
	type BridgeProductControlResponse,
	type BridgeProductMetadataFrame,
} from '../../src/core/comm-worker/bridge-product-session-contracts.js';
import {
	createBridgeProductDevCarrier,
	type BridgeProductDevCarrier,
} from './bridge-product-dev-carrier.js';
import {
	authorityForDelivery,
	dispatchCommandToCarrier,
	requestWithBodyProbe,
	TestServerResponse,
	type TestProductAuthority,
} from './bridge-product-dev-carrier.test-support.js';
import type { BridgeProductDevReviewAdapterPort } from './bridge-product-dev-review-adapter.js';
import { worktreeFileProtocolFrameSchema } from './bridge-worktree-dev-file-fixture-contracts.js';
import type {
	WorktreeFileDescriptor,
	WorktreeFileSurfaceSourceIdentity,
} from './bridge-worktree-dev-file-fixture-contracts.js';
import type { BridgeWorktreeDevProvider } from './bridge-worktree-dev-provider.js';

const unregisteredAuthority = {
	capability: Buffer.alloc(32, 7).toString('base64url'),
	paneSessionId: 'unregistered-pane-session',
	workerInstanceId: 'unregistered-worker-instance',
} satisfies TestProductAuthority;
const sourceCursor = 'cursor-1';

describe('Bridge product dev pane carrier', () => {
	let server: Server | null = null;
	let carrier: BridgeProductDevCarrier | null = null;

	afterEach(async () => {
		carrier?.dispose();
		carrier = null;
		await closeServer(server);
		server = null;
	});

	test('advertises the structural content stream bound instead of the legacy File prefix', () => {
		// Arrange
		carrier = createBridgeProductDevCarrier({
			createReviewAdapter: (): BridgeProductDevReviewAdapterPort => fakeReviewAdapter(),
			getFileProvider: async () => fakeFileProvider(),
			getReviewSourceConfig: async () => ({ baseRef: 'HEAD', worktreeRoot: '/opaque' }),
		});

		// Act
		const delivery = carrier.issueBootstrap({ reason: 'initial' });

		// Assert
		expect(delivery.bootstrap.policy.maximumContentBytes).toBe(
			BRIDGE_PRODUCT_MAXIMUM_CONTENT_STREAM_BYTES,
		);
	});

	test('accepts only the current Review publication receipt without opening additional product work', async () => {
		// Arrange
		const loadReviewSource = vi.fn(fakeReviewAdapter().loadSource);
		const createReviewAdapter = vi.fn(
			(): BridgeProductDevReviewAdapterPort => ({
				loadContent: async () => null,
				loadSource: loadReviewSource,
			}),
		);
		const getFileProvider = vi.fn(async () => fakeFileProvider());
		const getReviewSourceConfig = vi.fn(async () => ({
			baseRef: 'HEAD',
			worktreeRoot: '/opaque',
		}));
		const started = await startCarrierServer({
			createReviewAdapter,
			getFileProvider,
			getReviewSourceConfig,
		});
		carrier = started.carrier;
		server = started.server;
		const { authority, baseURL } = started;
		await postControl(
			baseURL,
			controlRequest(authority, { kind: 'workerSession.open', request: null }, 1),
			authority.capability,
		);
		const publicationId = '00000000-0000-7000-8000-000000000011';
		const noCurrentReceipt = await postControl(
			baseURL,
			controlRequest(
				authority,
				{
					call: { method: 'review.publication.applied', request: { publicationId } },
					kind: 'product.call',
					workerDerivationEpoch: 1,
				},
				2,
			),
			authority.capability,
		);
		const stream = await openMetadataStream(baseURL, authority);
		const streamAccepted = await stream.nextFrame();
		expect(await postMetadataObservation(baseURL, streamAccepted, authority.capability)).toBe(204);
		const foregroundPresentation = await stream.nextFrame();
		expect(foregroundPresentation).toMatchObject({
			activityRevision: 1,
			kind: 'pane.presentation',
			nativeActivity: 'foreground',
			refreshingLanes: [],
		});
		expect(
			await postMetadataObservation(baseURL, foregroundPresentation, authority.capability),
		).toBe(204);
		await postControl(
			baseURL,
			controlRequest(
				authority,
				{
					kind: 'subscription.open',
					subscription: { subscriptionKind: 'review.metadata' },
					subscriptionId: 'receipt-review-subscription',
					workerDerivationEpoch: 1,
				},
				3,
			),
			authority.capability,
		);
		const reviewSubscriptionAccepted = await stream.nextFrame();
		expect(
			await postMetadataObservation(baseURL, reviewSubscriptionAccepted, authority.capability),
		).toBe(204);
		const reviewSourceFrame = await stream.nextFrame();
		expect(await postMetadataObservation(baseURL, reviewSourceFrame, authority.capability)).toBe(
			204,
		);
		const exactReceiptRequest = controlRequest(
			authority,
			{
				call: {
					method: 'review.publication.applied',
					request: { publicationId },
				},
				kind: 'product.call',
				workerDerivationEpoch: 1,
			},
			4,
		);

		// Act
		const exactReceipt = await postControl(baseURL, exactReceiptRequest, authority.capability);
		const exactTransportRetry = await postControl(
			baseURL,
			exactReceiptRequest,
			authority.capability,
		);
		const exactSemanticReplay = await postControl(
			baseURL,
			controlRequest(
				authority,
				{
					call: { method: 'review.publication.applied', request: { publicationId } },
					kind: 'product.call',
					workerDerivationEpoch: 1,
				},
				5,
			),
			authority.capability,
		);
		const mismatchedReceipt = await postControl(
			baseURL,
			controlRequest(
				authority,
				{
					call: {
						method: 'review.publication.applied',
						request: { publicationId: '00000000-0000-7000-8000-000000000099' },
					},
					kind: 'product.call',
					workerDerivationEpoch: 1,
				},
				6,
			),
			authority.capability,
		);
		await stream.close();

		// Assert
		expect(noCurrentReceipt).toMatchObject({ code: 'invalid_request', kind: 'request.error' });
		expect(exactReceipt).toEqual({
			call: { method: 'review.publication.applied', result: null },
			kind: 'call.completed',
			paneSessionId: exactReceiptRequest.paneSessionId,
			requestId: exactReceiptRequest.requestId,
			requestSequence: exactReceiptRequest.requestSequence,
			wireVersion: exactReceiptRequest.wireVersion,
			workerInstanceId: exactReceiptRequest.workerInstanceId,
		});
		expect(exactTransportRetry).toEqual(exactReceipt);
		expect(exactSemanticReplay).toMatchObject({
			call: { method: 'review.publication.applied', result: null },
			kind: 'call.completed',
		});
		expect(mismatchedReceipt).toMatchObject({
			code: 'invalid_request',
			kind: 'request.error',
		});
		expect(createReviewAdapter).toHaveBeenCalledTimes(1);
		expect(loadReviewSource).toHaveBeenCalledTimes(1);
		expect(getFileProvider).not.toHaveBeenCalled();
		expect(getReviewSourceConfig).toHaveBeenCalledTimes(1);
	});

	test('multiplexes Review and File subscriptions while acknowledgements bypass control order', async () => {
		// Arrange
		const started = await startCarrierServer();
		carrier = started.carrier;
		server = started.server;
		const baseURL = started.baseURL;
		const authority = started.authority;
		await postControl(
			baseURL,
			controlRequest(authority, { kind: 'workerSession.open', request: null }, 1),
			authority.capability,
		);
		const stream = await openMetadataStream(baseURL, authority);
		const accepted = await stream.nextFrame();

		// Act: observation is out-of-band and an exact replay does not consume requestSequence.
		expect(await postMetadataObservation(baseURL, accepted, authority.capability)).toBe(204);
		expect(await postMetadataObservation(baseURL, accepted, authority.capability)).toBe(204);
		const foregroundPresentation = await stream.nextFrame();
		expect(foregroundPresentation).toMatchObject({
			activityRevision: 1,
			kind: 'pane.presentation',
			nativeActivity: 'foreground',
			refreshingLanes: [],
		});
		expect(
			await postMetadataObservation(baseURL, foregroundPresentation, authority.capability),
		).toBe(204);
		const reviewOpen = await postControl(
			baseURL,
			controlRequest(
				authority,
				{
					kind: 'subscription.open',
					subscription: { subscriptionKind: 'review.metadata' },
					subscriptionId: 'review-subscription-1',
					workerDerivationEpoch: 1,
				},
				2,
			),
			authority.capability,
		);
		const reviewAcceptedFrame = await stream.nextFrame();
		const fileSource = await postControl(
			baseURL,
			controlRequest(
				authority,
				{
					call: { method: 'file.source.current', request: {} },
					kind: 'product.call',
					workerDerivationEpoch: 1,
				},
				3,
			),
			authority.capability,
		);

		// Assert: ordinary control completed while Review metadata was still observation-blocked.
		expect(reviewOpen).toMatchObject({
			kind: 'subscription.openAccepted',
			subscriptionKind: 'review.metadata',
		});
		expect(fileSource).toMatchObject({ kind: 'call.completed' });
		expect(carrier.snapshot()).toMatchObject({ subscriptions: 1, waiters: 1 });
		expect(await postMetadataObservation(baseURL, reviewAcceptedFrame, authority.capability)).toBe(
			204,
		);
		const reviewSourceFrame = await stream.nextFrame();
		expect(reviewSourceFrame).toMatchObject({
			kind: 'subscription.data',
			subscriptionKind: 'review.metadata',
		});
		expect(await postMetadataObservation(baseURL, reviewSourceFrame, authority.capability)).toBe(
			204,
		);

		if (
			fileSource.kind !== 'call.completed' ||
			fileSource.call.method !== 'file.source.current' ||
			fileSource.call.result.status !== 'available'
		) {
			throw new Error('Expected an available File source.');
		}
		const fileOpen = await postControl(
			baseURL,
			controlRequest(
				authority,
				{
					kind: 'subscription.open',
					subscription: {
						source: fileSource.call.result.source,
						subscriptionKind: 'file.metadata',
					},
					subscriptionId: 'file-subscription-1',
					workerDerivationEpoch: 1,
				},
				4,
			),
			authority.capability,
		);
		expect(fileOpen).toMatchObject({
			kind: 'subscription.openAccepted',
			subscriptionKind: 'file.metadata',
		});
		expect(carrier.snapshot().subscriptions).toBe(2);

		const fileAcceptedFrame = await stream.nextFrame();
		expect(fileAcceptedFrame.streamSequence).toBe(reviewSourceFrame.streamSequence + 1);
		expect(await postMetadataObservation(baseURL, fileAcceptedFrame, authority.capability)).toBe(
			204,
		);
		const fileSourceFrame = await stream.nextFrame();
		expect(await postMetadataObservation(baseURL, fileSourceFrame, authority.capability)).toBe(204);
		const fileTreeFrame = await stream.nextFrame();
		expect(await postMetadataObservation(baseURL, fileTreeFrame, authority.capability)).toBe(204);

		const cancelled = await postControl(
			baseURL,
			controlRequest(
				authority,
				{
					kind: 'subscription.cancel',
					subscriptionId: 'review-subscription-1',
					subscriptionKind: 'review.metadata',
					workerDerivationEpoch: 1,
				},
				5,
			),
			authority.capability,
		);
		expect(cancelled).toMatchObject({ kind: 'subscription.cancelAccepted' });
		expect(carrier.snapshot().subscriptions).toBe(1);
		const cancelledFrame = await stream.nextFrame();
		expect(await postMetadataObservation(baseURL, cancelledFrame, authority.capability)).toBe(204);

		const skippedObservation = {
			...cancelledFrame,
			streamSequence: cancelledFrame.streamSequence + 2,
		};
		expect(await postMetadataObservation(baseURL, skippedObservation, authority.capability)).toBe(
			409,
		);
		await stream.close();
		carrier.dispose();
		expect(carrier.snapshot()).toEqual({
			leases: 0,
			pendingSessions: 0,
			producers: 0,
			responses: 0,
			sessions: 0,
			subscriptions: 0,
			waiters: 0,
		});
	});

	test('authenticates before parsing and returns bounded generic errors', async () => {
		const started = await startCarrierServer();
		carrier = started.carrier;
		server = started.server;

		const unauthenticated = await fetch(`${started.baseURL}/command`, {
			body: '{"secret":"must-not-parse"}',
			method: 'POST',
		});
		const malformed = await fetch(`${started.baseURL}/command`, {
			body: '{"kind":"workerSession.open","kind":"workerSession.open"}',
			headers: productHeaders(started.authority.capability),
			method: 'POST',
		});

		expect(unauthenticated.status).toBe(401);
		expect(await unauthenticated.text()).toBe('Unauthorized');
		expect(malformed.status).toBe(400);
		expect(await malformed.text()).toBe('Invalid Bridge product request');
	});

	test('rejects an unregistered format-valid capability before request-body access', async () => {
		// Arrange
		carrier = createBridgeProductDevCarrier({
			createReviewAdapter: (): BridgeProductDevReviewAdapterPort => fakeReviewAdapter(),
			getFileProvider: async () => fakeFileProvider(),
			getReviewSourceConfig: async () => ({ baseRef: 'HEAD', worktreeRoot: '/opaque' }),
		});
		const requestProbe = requestWithBodyProbe({
			body: JSON.stringify(
				controlRequest(unregisteredAuthority, { kind: 'workerSession.open', request: null }, 1),
			),
			capability: unregisteredAuthority.capability,
		});
		const responseProbe = new TestServerResponse();

		// Act
		await carrier.handleCommandRequest({
			request: requestProbe.request,
			response: responseProbe.response,
		});

		// Assert
		expect(responseProbe.statusCode).toBe(401);
		expect(responseProbe.bodyText).toBe('Unauthorized');
		expect(requestProbe.bodyReadCount()).toBe(0);
		expect(carrier.snapshot().sessions).toBe(0);
	});

	test('rejects missing or non-exact product JSON media types before body access', async () => {
		// Arrange
		carrier = createBridgeProductDevCarrier({
			createReviewAdapter: (): BridgeProductDevReviewAdapterPort => fakeReviewAdapter(),
			getFileProvider: async () => fakeFileProvider(),
			getReviewSourceConfig: async () => ({ baseRef: 'HEAD', worktreeRoot: '/opaque' }),
		});
		const rejectedMediaTypes = [
			null,
			'text/plain',
			'application/json; charset=utf-8',
			'Application/JSON',
		] as const;
		let authority = authorityForDelivery(carrier.issueBootstrap({ reason: 'initial' }));

		for (const contentType of rejectedMediaTypes) {
			authority = authorityForDelivery(
				carrier.issueBootstrap({
					paneSessionId: authority.paneSessionId,
					reason: 'workerReplacement',
				}),
			);
			const requestProbe = requestWithBodyProbe({
				body: JSON.stringify(
					controlRequest(authority, { kind: 'workerSession.open', request: null }, 1),
				),
				capability: authority.capability,
				contentType,
			});
			const responseProbe = new TestServerResponse();

			// Act
			// oxlint-disable-next-line no-await-in-loop -- Each case verifies its own replacement authority and body probe serially.
			await carrier.handleCommandRequest({
				request: requestProbe.request,
				response: responseProbe.response,
			});

			// Assert
			expect(responseProbe.statusCode).toBe(415);
			expect(responseProbe.bodyText).toBe('Unsupported Media Type');
			expect(requestProbe.bodyReadCount()).toBe(0);
			expect(carrier.snapshot()).toMatchObject({ pendingSessions: 1, sessions: 0 });
		}
	});

	test('rejects authenticated cross-pane identity after strict decode and before side effects', async () => {
		// Arrange
		const getFileProvider = vi.fn(async () => fakeFileProvider());
		const getReviewSourceConfig = vi.fn(async () => ({
			baseRef: 'HEAD',
			worktreeRoot: '/opaque',
		}));
		carrier = createBridgeProductDevCarrier({
			createReviewAdapter: (): BridgeProductDevReviewAdapterPort => fakeReviewAdapter(),
			getFileProvider,
			getReviewSourceConfig,
		});
		const authority = authorityForDelivery(carrier.issueBootstrap({ reason: 'initial' }));
		const opened = await dispatchCommandToCarrier({
			authority,
			body: JSON.stringify(
				controlRequest(authority, { kind: 'workerSession.open', request: null }, 1),
			),
			carrier,
		});
		const duplicateIdentityBody = JSON.stringify({
			...controlRequest(
				{ ...authority, paneSessionId: 'foreign-pane-session' },
				{
					call: { method: 'file.source.current', request: {} },
					kind: 'product.call',
					workerDerivationEpoch: 1,
				},
				2,
			),
		}).replace(
			'"paneSessionId":"foreign-pane-session"',
			'"paneSessionId":"foreign-pane-session","paneSessionId":"foreign-pane-session"',
		);
		const wellFormedCrossPaneBody = JSON.stringify(
			controlRequest(
				{ ...authority, paneSessionId: 'foreign-pane-session' },
				{
					call: { method: 'file.source.current', request: {} },
					kind: 'product.call',
					workerDerivationEpoch: 1,
				},
				2,
			),
		);

		// Act
		const malformed = await dispatchCommandToCarrier({
			authority,
			body: duplicateIdentityBody,
			carrier,
		});
		const crossPane = await dispatchCommandToCarrier({
			authority,
			body: wellFormedCrossPaneBody,
			carrier,
		});

		// Assert
		expect(opened.response.statusCode).toBe(200);
		expect(malformed.response.statusCode).toBe(400);
		expect(malformed.request.bodyReadCount()).toBe(1);
		expect(crossPane.response.statusCode).toBe(401);
		expect(crossPane.request.bodyReadCount()).toBe(1);
		expect(getFileProvider).not.toHaveBeenCalled();
		expect(getReviewSourceConfig).not.toHaveBeenCalled();
		expect(carrier.snapshot()).toEqual({
			leases: 0,
			pendingSessions: 0,
			producers: 0,
			responses: 0,
			sessions: 1,
			subscriptions: 0,
			waiters: 0,
		});

		const matching = await dispatchCommandToCarrier({
			authority,
			body: JSON.stringify(
				controlRequest(
					authority,
					{
						call: { method: 'file.source.current', request: {} },
						kind: 'product.call',
						workerDerivationEpoch: 1,
					},
					2,
				),
			),
			carrier,
		});
		expect(matching.response.statusCode).toBe(200);
		expect(getFileProvider).toHaveBeenCalledTimes(1);
	});

	test('worker replacement revokes both pending and active prior capabilities', async () => {
		// Arrange
		carrier = createBridgeProductDevCarrier({
			createReviewAdapter: (): BridgeProductDevReviewAdapterPort => fakeReviewAdapter(),
			getFileProvider: async () => fakeFileProvider(),
			getReviewSourceConfig: async () => ({ baseRef: 'HEAD', worktreeRoot: '/opaque' }),
		});
		const pendingAuthority = authorityForDelivery(carrier.issueBootstrap({ reason: 'initial' }));
		const replacementAuthority = authorityForDelivery(
			carrier.issueBootstrap({
				paneSessionId: pendingAuthority.paneSessionId,
				reason: 'workerReplacement',
			}),
		);

		// Act: replacement revokes the first pending authority before body access.
		const revokedPending = await dispatchCommandToCarrier({
			authority: pendingAuthority,
			body: JSON.stringify(
				controlRequest(pendingAuthority, { kind: 'workerSession.open', request: null }, 1),
			),
			carrier,
		});
		const openedReplacement = await dispatchCommandToCarrier({
			authority: replacementAuthority,
			body: JSON.stringify(
				controlRequest(replacementAuthority, { kind: 'workerSession.open', request: null }, 1),
			),
			carrier,
		});
		const activeReplacementAuthority = authorityForDelivery(
			carrier.issueBootstrap({
				paneSessionId: replacementAuthority.paneSessionId,
				reason: 'workerReplacement',
			}),
		);
		const revokedActive = await dispatchCommandToCarrier({
			authority: replacementAuthority,
			body: JSON.stringify(
				controlRequest(replacementAuthority, { kind: 'workerSession.open', request: null }, 1),
			),
			carrier,
		});

		// Assert
		expect(revokedPending.response.statusCode).toBe(401);
		expect(revokedPending.request.bodyReadCount()).toBe(0);
		expect(openedReplacement.response.statusCode).toBe(200);
		expect(revokedActive.response.statusCode).toBe(401);
		expect(revokedActive.request.bodyReadCount()).toBe(0);
		expect(carrier.snapshot()).toMatchObject({ pendingSessions: 1, sessions: 0 });

		const openedActiveReplacement = await dispatchCommandToCarrier({
			authority: activeReplacementAuthority,
			body: JSON.stringify(
				controlRequest(
					activeReplacementAuthority,
					{ kind: 'workerSession.open', request: null },
					1,
				),
			),
			carrier,
		});
		expect(openedActiveReplacement.response.statusCode).toBe(200);
		expect(carrier.snapshot()).toMatchObject({ pendingSessions: 0, sessions: 1 });
		carrier.dispose();
		expect(carrier.snapshot()).toMatchObject({ pendingSessions: 0, sessions: 0 });
	});

	test('keeps independently minted panes alive when replacing only one pane authority', async () => {
		// Arrange
		carrier = createBridgeProductDevCarrier({
			createReviewAdapter: (): BridgeProductDevReviewAdapterPort => fakeReviewAdapter(),
			getFileProvider: async () => fakeFileProvider(),
			getReviewSourceConfig: async () => ({ baseRef: 'HEAD', worktreeRoot: '/opaque' }),
		});
		const firstPane = authorityForDelivery(carrier.issueBootstrap({ reason: 'initial' }));
		const secondPane = authorityForDelivery(carrier.issueBootstrap({ reason: 'initial' }));
		const pendingSnapshot = carrier.snapshot();

		const firstPaneOpenBody = JSON.stringify(
			controlRequest(firstPane, { kind: 'workerSession.open', request: null }, 1),
		);
		const secondPaneOpenBody = JSON.stringify(
			controlRequest(secondPane, { kind: 'workerSession.open', request: null }, 1),
		);
		const firstOpened = await dispatchCommandToCarrier({
			authority: firstPane,
			body: firstPaneOpenBody,
			carrier,
		});
		const secondOpened = await dispatchCommandToCarrier({
			authority: secondPane,
			body: secondPaneOpenBody,
			carrier,
		});

		// Act
		const firstPaneReplacement = authorityForDelivery(
			carrier.issueBootstrap({
				paneSessionId: firstPane.paneSessionId,
				reason: 'workerReplacement',
			}),
		);
		const revokedFirstPane = await dispatchCommandToCarrier({
			authority: firstPane,
			body: firstPaneOpenBody,
			carrier,
		});
		const secondPaneExactRetry = await dispatchCommandToCarrier({
			authority: secondPane,
			body: secondPaneOpenBody,
			carrier,
		});

		// Assert
		expect(firstPane.paneSessionId).not.toBe(secondPane.paneSessionId);
		expect(pendingSnapshot).toMatchObject({ pendingSessions: 2, sessions: 0 });
		expect(firstOpened.response.statusCode).toBe(200);
		expect(secondOpened.response.statusCode).toBe(200);
		expect(revokedFirstPane.response.statusCode).toBe(401);
		expect(revokedFirstPane.request.bodyReadCount()).toBe(0);
		expect(secondPaneExactRetry.response.statusCode).toBe(200);
		expect(secondPaneExactRetry.request.bodyReadCount()).toBe(1);
		expect(carrier.snapshot()).toMatchObject({ pendingSessions: 1, sessions: 1 });

		const replacementOpened = await dispatchCommandToCarrier({
			authority: firstPaneReplacement,
			body: JSON.stringify(
				controlRequest(firstPaneReplacement, { kind: 'workerSession.open', request: null }, 1),
			),
			carrier,
		});
		expect(replacementOpened.response.statusCode).toBe(200);
		expect(carrier.snapshot()).toMatchObject({ pendingSessions: 0, sessions: 2 });
	});
});

async function startCarrierServer(props?: {
	readonly createReviewAdapter?: () => BridgeProductDevReviewAdapterPort;
	readonly getFileProvider?: () => Promise<BridgeWorktreeDevProvider>;
	readonly getReviewSourceConfig?: () => Promise<{
		readonly baseRef: string;
		readonly worktreeRoot: string;
	}>;
}): Promise<{
	readonly authority: TestProductAuthority;
	readonly baseURL: string;
	readonly carrier: BridgeProductDevCarrier;
	readonly server: Server;
}> {
	const carrier = createBridgeProductDevCarrier({
		createReviewAdapter:
			props?.createReviewAdapter ?? ((): BridgeProductDevReviewAdapterPort => fakeReviewAdapter()),
		getFileProvider: props?.getFileProvider ?? (async () => fakeFileProvider()),
		getReviewSourceConfig:
			props?.getReviewSourceConfig ?? (async () => ({ baseRef: 'HEAD', worktreeRoot: '/opaque' })),
	});
	const authority = authorityForDelivery(carrier.issueBootstrap({ reason: 'initial' }));
	const server = createServer((request, response): void => {
		switch (request.url) {
			case '/command':
				void carrier.handleCommandRequest({ request, response });
				return;
			case '/stream':
				void carrier.handleStreamRequest({ request, response });
				return;
			case '/content':
				void carrier.handleContentRequest({ request, response });
				return;
			case undefined:
			default:
				response.statusCode = 404;
				response.end();
		}
	});
	return { authority, baseURL: await listen(server), carrier, server };
}

function fakeReviewAdapter(): BridgeProductDevReviewAdapterPort {
	return {
		loadContent: async () => null,
		loadSource: async () => ({
			cursor: 'review-cursor-1',
			events: [
				bridgeProductReviewMetadataEventSchema.parse({
					eventKind: 'review.sourceAccepted',
					generation: 1,
					packageId: 'review-package-1',
					publicationId: '00000000-0000-7000-8000-000000000011',
					revision: 1,
					sourceIdentity: 'review-source-1',
				}),
			],
			generation: 1,
			packageId: 'review-package-1',
			publicationId: '00000000-0000-7000-8000-000000000011',
			revision: 1,
			sourceIdentity: 'review-source-1',
		}),
	};
}

function fakeFileProvider(): BridgeWorktreeDevProvider {
	const source = legacySource();
	return {
		loadWorktreeFileContent: async () => 'alpha\nbeta\n',
		loadWorktreeFileDescriptor: async (request) => {
			const frame = worktreeFileProtocolFrameSchema.parse({
				descriptor: legacyDescriptor(request.path),
				frameKind: 'worktree.fileDescriptor',
				generation: 1,
				kind: 'delta',
				sequence: 2,
				streamId: 'worktree-file:dev-pane',
			});
			if (frame.frameKind !== 'worktree.fileDescriptor') throw new Error('Invalid fake frame.');
			return frame;
		},
		loadWorktreeFileSurface: async () => ({
			frames: [
				worktreeFileProtocolFrameSchema.parse({
					frameKind: 'worktree.snapshot',
					generation: 1,
					kind: 'snapshot',
					metadataLineage: { lane: 'foreground', loadedBy: 'startup_window' },
					sequence: 0,
					source,
					streamId: 'worktree-file:dev-pane',
					treeRows: [
						{
							changeStatus: 'modified',
							depth: 1,
							fileId: 'dev-file-id-1',
							isDirectory: false,
							lineCount: 2,
							name: 'app.ts',
							parentPath: 'src',
							path: 'src/app.ts',
							rowId: 'row:src/app.ts',
							sizeBytes: 11,
						},
					],
					treeSizeFacts: { extentKind: 'exactPathCount', pathCount: 1, rowHeightPixels: 24 },
				}),
			],
			provenance: {
				baseRef: 'HEAD',
				scenarioName: 'current-worktree',
				worktreeRootToken: 'root-token',
			},
			source,
			treeSizeFacts: { extentKind: 'exactPathCount', pathCount: 1, rowHeightPixels: 24 },
		}),
	};
}

class MetadataStreamClient {
	readonly #decoder = new BridgeProductMetadataFrameDecoder();
	readonly #pendingFrames: BridgeProductMetadataFrame[] = [];
	readonly #reader: ReadableStreamDefaultReader<Uint8Array>;

	constructor(reader: ReadableStreamDefaultReader<Uint8Array>) {
		this.#reader = reader;
	}

	async nextFrame(): Promise<BridgeProductMetadataFrame> {
		while (this.#pendingFrames.length === 0) {
			// oxlint-disable-next-line no-await-in-loop -- Network chunks are consumed in protocol order.
			const chunk = await this.#reader.read();
			if (chunk.done) throw new Error('Metadata stream ended early.');
			this.#pendingFrames.push(...this.#decoder.push(chunk.value));
		}
		const frame = this.#pendingFrames.shift();
		if (frame === undefined) throw new Error('Metadata frame queue was unexpectedly empty.');
		return frame;
	}

	async close(): Promise<void> {
		await this.#reader.cancel();
	}
}

async function openMetadataStream(
	baseURL: string,
	authority: TestProductAuthority,
): Promise<MetadataStreamClient> {
	const response = await fetch(`${baseURL}/stream`, {
		body: JSON.stringify(
			bridgeProductMetadataStreamRequestSchema.parse({
				kind: 'metadataStream.open',
				metadataStreamId: 'metadata-stream-1',
				paneSessionId: authority.paneSessionId,
				resumeFromStreamSequence: null,
				wireVersion: 2,
				workerInstanceId: authority.workerInstanceId,
			}),
		),
		headers: productHeaders(authority.capability),
		method: 'POST',
	});
	expect(response.status).toBe(200);
	if (response.body === null) throw new Error('Expected metadata body.');
	return new MetadataStreamClient(response.body.getReader());
}

async function postMetadataObservation(
	baseURL: string,
	frame: Pick<
		BridgeProductMetadataFrame,
		'metadataStreamId' | 'paneSessionId' | 'streamSequence' | 'wireVersion' | 'workerInstanceId'
	>,
	capability: string,
): Promise<number> {
	const response = await fetch(`${baseURL}/command`, {
		body: JSON.stringify({
			kind: 'stream.frameObserved',
			metadataStreamId: frame.metadataStreamId,
			paneSessionId: frame.paneSessionId,
			streamKind: 'metadata',
			streamSequence: frame.streamSequence,
			wireVersion: frame.wireVersion,
			workerInstanceId: frame.workerInstanceId,
		}),
		headers: productHeaders(capability),
		method: 'POST',
	});
	const responseBody = await response.text();
	if (response.status === 204) expect(responseBody).toBe('');
	return response.status;
}

function legacySource(): WorktreeFileSurfaceSourceIdentity {
	return {
		repoId: 'legacy-repo',
		rootRevisionToken: 'revision-1',
		sourceCursor,
		sourceId: 'source-1',
		subscriptionGeneration: 1,
		worktreeId: 'legacy-worktree',
	};
}

function legacyDescriptor(path: string): WorktreeFileDescriptor {
	const descriptorId = 'dev-file-descriptor-1';
	return {
		contentHandle: descriptorId,
		contentHash: `sha256:${createHash('sha256').update('alpha\nbeta\n').digest('hex')}`,
		fileExtension: 'ts',
		fileId: 'dev-file-id-1',
		isBinary: false,
		unavailableReason: null,
		language: 'typescript',
		lineCount: 2,
		path,
		sizeBytes: 11,
		sourceIdentity: legacySource(),
		virtualizedExtentKind: 'exactLineCount',
	};
}

function controlRequest(
	authority: Pick<TestProductAuthority, 'paneSessionId' | 'workerInstanceId'>,
	request: Readonly<Record<string, unknown>>,
	requestSequence: number,
): BridgeProductControlRequest {
	return bridgeProductControlRequestSchema.parse({
		paneSessionId: authority.paneSessionId,
		requestId: `request-${requestSequence}`,
		requestSequence,
		wireVersion: BRIDGE_PRODUCT_WIRE_VERSION,
		workerInstanceId: authority.workerInstanceId,
		...request,
	});
}

async function postControl(
	baseURL: string,
	request: BridgeProductControlRequest,
	capability: string,
): Promise<BridgeProductControlResponse> {
	const response = await fetch(`${baseURL}/command`, {
		body: JSON.stringify(request),
		headers: productHeaders(capability),
		method: 'POST',
	});
	const text = await response.text();
	expect(response.status, text).toBe(200);
	return bridgeProductControlResponseSchema.parse(JSON.parse(text) as unknown);
}

function productHeaders(productCapability: string): HeadersInit {
	return {
		'Content-Type': 'application/json',
		'X-AgentStudio-Bridge-Product-Capability': productCapability,
	};
}

async function listen(server: Server): Promise<string> {
	await new Promise<void>((resolve): void => {
		server.listen(0, '127.0.0.1', resolve);
	});
	const address = server.address();
	if (address === null || typeof address === 'string') throw new Error('Expected TCP address.');
	return `http://127.0.0.1:${address.port}`;
}

async function closeServer(server: Server | null): Promise<void> {
	if (server === null) return;
	server.closeAllConnections();
	await new Promise<void>((resolve): void => {
		server?.close((): void => resolve());
	});
}
