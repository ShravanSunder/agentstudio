import type { Server } from 'node:http';

import { afterEach, describe, expect, test, vi } from 'vitest';

import { BRIDGE_PRODUCT_MAXIMUM_CONTENT_STREAM_BYTES } from '../../src/core/comm-worker/bridge-product-contract-primitives.js';
import {
	type BridgeProductDevNavigationIntent,
	bridgeProductDevNavigationIntentSchema,
} from '../../src/core/comm-worker/bridge-product-dev-bootstrap.js';
import {
	closeServer,
	controlRequest,
	fakeFileProvider,
	fakeReviewAdapter,
	observeInitialMetadataFrames,
	openMetadataStream,
	openReviewSubscription,
	openWorkerSession,
	postControl,
	postMetadataObservation,
	productHeaders,
	startCarrierServer,
} from './bridge-product-dev-carrier-stream.test-support.js';
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

const unregisteredAuthority = {
	capability: Buffer.alloc(32, 7).toString('base64url'),
	paneSessionId: 'unregistered-pane-session',
	workerInstanceId: 'unregistered-worker-instance',
} satisfies TestProductAuthority;
const defaultNavigationIntent = bridgeProductDevNavigationIntentSchema.parse({
	commandId: 'dev:test:file:target',
	commandKind: 'activateTarget',
	surface: 'file',
	target: { path: 'src/app.ts', targetKind: 'file', version: 'current' },
});

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
		const delivery = carrier.issueBootstrap({
			navigationIntent: defaultNavigationIntent,
			reason: 'initial',
		});

		// Assert
		expect(delivery.bootstrap.policy.maximumContentBytes).toBe(
			BRIDGE_PRODUCT_MAXIMUM_CONTENT_STREAM_BYTES,
		);
	});

	test('binds Review target intent from the accepted source and truthfully rebinds replacement', async () => {
		// Arrange
		const navigationIntent = {
			commandId: 'dev:test:review:target',
			commandKind: 'activateTarget',
			surface: 'review',
			target: { reviewItemId: 'review-item-1', targetKind: 'review' },
		} as const satisfies BridgeProductDevNavigationIntent;
		const started = await startCarrierServer({ navigationIntent });
		carrier = started.carrier;
		server = started.server;
		const firstAuthority = started.authority;
		await openWorkerSession(started.baseURL, firstAuthority);
		const firstStream = await openMetadataStream(started.baseURL, firstAuthority);
		await observeInitialMetadataFrames(started.baseURL, firstStream, firstAuthority);

		// Act
		await openReviewSubscription(started.baseURL, firstAuthority);
		const firstNavigationFrame = await firstStream.nextFrame();

		// Assert
		expect(firstNavigationFrame).toMatchObject({
			kind: 'pane.surfaceSelectionRequested',
			navigationCommand: {
				bindingRevision: 1,
				commandId: navigationIntent.commandId,
				commandKind: 'activateTarget',
				source: {
					generation: 1,
					metadataSourceId: 'review-source-1',
					packageId: 'review-package-1',
					sourceKind: 'review',
				},
				surface: 'review',
				target: navigationIntent.target,
			},
		});
		expect(
			await postMetadataObservation(
				started.baseURL,
				firstNavigationFrame,
				firstAuthority.capability,
			),
		).toBe(204);
		await firstStream.close();

		// Act: worker replacement retains command identity but rebinds the new authority revision.
		const replacementAuthority = authorityForDelivery(
			carrier.issueBootstrap({
				navigationIntent,
				paneSessionId: firstAuthority.paneSessionId,
				reason: 'workerReplacement',
			}),
		);
		await openWorkerSession(started.baseURL, replacementAuthority);
		const replacementStream = await openMetadataStream(started.baseURL, replacementAuthority);
		await observeInitialMetadataFrames(started.baseURL, replacementStream, replacementAuthority);
		await openReviewSubscription(started.baseURL, replacementAuthority);
		const replacementNavigationFrame = await replacementStream.nextFrame();

		// Assert
		expect(replacementNavigationFrame).toMatchObject({
			kind: 'pane.surfaceSelectionRequested',
			navigationCommand: {
				bindingRevision: 2,
				commandId: navigationIntent.commandId,
				source: {
					generation: 1,
					metadataSourceId: 'review-source-1',
					packageId: 'review-package-1',
					sourceKind: 'review',
				},
			},
		});
		await replacementStream.close();
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
		let authority = authorityForDelivery(
			carrier.issueBootstrap({ navigationIntent: defaultNavigationIntent, reason: 'initial' }),
		);

		for (const contentType of rejectedMediaTypes) {
			authority = authorityForDelivery(
				carrier.issueBootstrap({
					navigationIntent: defaultNavigationIntent,
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
		const authority = authorityForDelivery(
			carrier.issueBootstrap({ navigationIntent: defaultNavigationIntent, reason: 'initial' }),
		);
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
		const pendingAuthority = authorityForDelivery(
			carrier.issueBootstrap({ navigationIntent: defaultNavigationIntent, reason: 'initial' }),
		);
		const replacementAuthority = authorityForDelivery(
			carrier.issueBootstrap({
				navigationIntent: defaultNavigationIntent,
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
				navigationIntent: defaultNavigationIntent,
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
		const firstPane = authorityForDelivery(
			carrier.issueBootstrap({ navigationIntent: defaultNavigationIntent, reason: 'initial' }),
		);
		const secondPane = authorityForDelivery(
			carrier.issueBootstrap({ navigationIntent: defaultNavigationIntent, reason: 'initial' }),
		);
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
				navigationIntent: defaultNavigationIntent,
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
