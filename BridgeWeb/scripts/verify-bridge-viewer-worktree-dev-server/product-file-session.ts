import { createHash, randomUUID } from 'node:crypto';

import { bridgeProductContentRequestSchema } from '../../src/core/comm-worker/bridge-product-content-contracts.js';
import { BridgeProductContentStreamDecoder } from '../../src/core/comm-worker/bridge-product-content-stream-decoder.js';
import { BRIDGE_PRODUCT_WIRE_VERSION } from '../../src/core/comm-worker/bridge-product-contract-primitives.js';
import {
	BRIDGE_PRODUCT_DEV_BOOTSTRAP_REQUEST_MEDIA_TYPE,
	BRIDGE_PRODUCT_DEV_BOOTSTRAP_RESPONSE_MEDIA_TYPE,
	BRIDGE_PRODUCT_DEV_BOOTSTRAP_ROUTE,
	decodeBridgeProductDevBootstrapDelivery,
} from '../../src/core/comm-worker/bridge-product-dev-bootstrap.js';
import {
	bridgeProductFrameAcknowledgementRequestSchema,
	type BridgeProductFrameAcknowledgementRequest,
} from '../../src/core/comm-worker/bridge-product-frame-acknowledgement-contracts.js';
import { BridgeProductMetadataFrameDecoder } from '../../src/core/comm-worker/bridge-product-metadata-frame-codec.js';
import {
	bridgeProductControlRequestSchema,
	bridgeProductControlResponseSchema,
	bridgeProductMetadataStreamRequestSchema,
	encodeBridgeProductCapabilityHeader,
	type BridgeProductControlResponse,
	type BridgeProductMetadataFrame,
} from '../../src/core/comm-worker/bridge-product-session-contracts.js';
import {
	type BridgeProductSubscriptionEvent,
	type BridgeProductSubscriptionInterestState,
} from '../../src/core/comm-worker/bridge-product-subscription-contracts.js';
import { encodeBridgeProductSubscriptionInterestState } from '../../src/core/comm-worker/bridge-product-subscription-interest-state-codec.js';

export type BridgeVerifierProductFileSessionState =
	| 'idle'
	| 'opening'
	| 'open'
	| 'closing'
	| 'closed';

type FileMetadataEvent = BridgeProductSubscriptionEvent<'file.metadata'>;
type FileSourceAcceptedEvent = Extract<
	FileMetadataEvent,
	{ readonly eventKind: 'file.sourceAccepted' }
>;
type FileTreeWindowEvent = Extract<FileMetadataEvent, { readonly eventKind: 'file.treeWindow' }>;
type FileDescriptorReadyEvent = Extract<
	FileMetadataEvent,
	{ readonly eventKind: 'file.descriptorReady' }
>;
export interface BridgeVerifierProductFileSource {
	readonly acceptedStreamSequence: number;
	readonly sourceAccepted: FileSourceAcceptedEvent;
	readonly sourceIdentity: FileSourceAcceptedEvent['source'];
	readonly treeWindows: readonly FileTreeWindowEvent[];
}

export interface BridgeVerifierProductFileContent {
	readonly byteLength: number;
	readonly bytes: ArrayBuffer;
}

export interface BridgeVerifierProductFileSessionProps {
	readonly baseUrl: string;
	readonly scenarioName: string;
}

interface BridgeVerifierProductAuthority {
	readonly capability: string;
	readonly paneSessionId: string;
	readonly workerInstanceId: string;
}

export class BridgeVerifierProductFileSession {
	readonly #baseUrl: string;
	#authority: BridgeVerifierProductAuthority | null = null;
	readonly #metadataStreamId = `verifier-file-stream-${randomUUID()}`;
	readonly #scenarioName: string;
	readonly #subscriptionId = `verifier-file-subscription-${randomUUID()}`;
	#controlSequence = 0;
	readonly #demandedPaths = new Set<string>();
	readonly #descriptorByPath = new Map<string, FileDescriptorReadyEvent>();
	#interestRevision = 0;
	#interestSha256: string | null = null;
	#metadataStream: BridgeVerifierMetadataStream | null = null;
	#state: BridgeVerifierProductFileSessionState = 'idle';

	constructor(props: BridgeVerifierProductFileSessionProps) {
		this.#baseUrl = props.baseUrl.replace(/\/$/u, '');
		this.#scenarioName = props.scenarioName;
	}

	get state(): BridgeVerifierProductFileSessionState {
		return this.#state;
	}

	async open(): Promise<BridgeVerifierProductFileSource> {
		this.#requireState('idle');
		this.#state = 'opening';
		await this.#installServerAuthority();

		const opened = await this.#postControl({ kind: 'workerSession.open', request: null });
		if (opened.kind !== 'workerSession.accepted') {
			throw new Error(`Expected workerSession.accepted, received ${opened.kind}.`);
		}
		const sourceResponse = await this.#postControl({
			call: { method: 'file.source.current', request: {} },
			kind: 'product.call',
			workerDerivationEpoch: 0,
		});
		if (
			sourceResponse.kind !== 'call.completed' ||
			sourceResponse.call.method !== 'file.source.current' ||
			sourceResponse.call.result.status !== 'available'
		) {
			throw new Error('Expected an available file.source.current product result.');
		}

		this.#metadataStream = await this.#openMetadataStream();
		const streamAccepted = await this.#metadataStream.frames.waitFor(
			(frame) => frame.kind === 'metadataStream.accepted',
		);
		if (streamAccepted.kind !== 'metadataStream.accepted') {
			throw new Error('Expected metadataStream.accepted.');
		}

		const subscriptionResponse = await this.#postControl({
			kind: 'subscription.open',
			subscription: {
				source: sourceResponse.call.result.source,
				subscriptionKind: 'file.metadata',
			},
			subscriptionId: this.#subscriptionId,
			workerDerivationEpoch: 0,
		});
		if (subscriptionResponse.kind !== 'subscription.openAccepted') {
			throw new Error(`Expected subscription.openAccepted, received ${subscriptionResponse.kind}.`);
		}
		this.#interestSha256 = subscriptionResponse.interestSha256;

		const sourceAccepted = await this.#waitForFileEvent(
			(event): event is FileSourceAcceptedEvent => event.eventKind === 'file.sourceAccepted',
		);
		const treeWindows: FileTreeWindowEvent[] = [];
		for (;;) {
			// oxlint-disable-next-line no-await-in-loop -- Tree snapshots are an ordered metadata sequence.
			const treeWindow = await this.#waitForFileEvent(
				(event): event is FileTreeWindowEvent => event.eventKind === 'file.treeWindow',
			);
			treeWindows.push(treeWindow);
			if (treeWindow.finalWindow) break;
		}

		this.#state = 'open';
		return {
			acceptedStreamSequence: streamAccepted.streamSequence,
			sourceAccepted,
			sourceIdentity: sourceAccepted.source,
			treeWindows,
		};
	}

	async demandDescriptor(path: string): Promise<FileDescriptorReadyEvent> {
		this.#requireState('open');
		const cachedDescriptor = this.#descriptorByPath.get(path);
		if (cachedDescriptor !== undefined) return cachedDescriptor;
		const baseInterestSha256 = this.#interestSha256;
		if (baseInterestSha256 === null) throw new Error('File subscription interest is unavailable.');
		const targetInterestRevision = this.#interestRevision + 1;
		const targetInterestState: BridgeProductSubscriptionInterestState = {
			interests: [{ lane: 'foreground', paths: [...this.#demandedPaths, path] }],
			pathScope: [],
			subscriptionKind: 'file.metadata',
		};
		const targetInterestSha256 = createHash('sha256')
			.update(encodeBridgeProductSubscriptionInterestState(targetInterestState))
			.digest('hex');
		const updateId = `verifier-file-update-${randomUUID()}`;
		const response = await this.#postControl({
			baseInterestRevision: this.#interestRevision,
			baseInterestSha256,
			batchCount: 1,
			batchIndex: 0,
			delta: {
				add: [{ lane: 'foreground', path }],
				addPathScope: [],
				removePathScope: [],
				removePaths: [],
				subscriptionKind: 'file.metadata',
			},
			kind: 'subscription.updateBatch',
			subscriptionId: this.#subscriptionId,
			subscriptionKind: 'file.metadata',
			targetInterestRevision,
			targetInterestSha256,
			totalDeltaItemCount: 1,
			updateId,
			workerDerivationEpoch: 0,
		});
		if (
			response.kind !== 'subscription.updateBatchAccepted' ||
			response.disposition !== 'committed'
		) {
			throw new Error('Expected a committed subscription.updateBatchAccepted response.');
		}

		const metadataStream = this.#requireMetadataStream();
		await metadataStream.frames.waitFor(
			(frame) =>
				frame.kind === 'subscription.interestsCommitted' &&
				frame.subscriptionId === this.#subscriptionId &&
				frame.updateId === updateId &&
				frame.interestRevision === targetInterestRevision &&
				frame.interestSha256 === targetInterestSha256,
		);
		this.#interestRevision = targetInterestRevision;
		this.#interestSha256 = targetInterestSha256;
		this.#demandedPaths.add(path);

		const descriptor = await this.#waitForFileEvent(
			(event): event is FileDescriptorReadyEvent =>
				event.eventKind === 'file.descriptorReady' && event.path === path,
		);
		if (descriptor.availability.availabilityKind !== 'available') {
			this.#descriptorByPath.set(path, descriptor);
			return descriptor;
		}
		this.#descriptorByPath.set(path, descriptor);
		return descriptor;
	}

	async openContent(
		descriptorEvent: FileDescriptorReadyEvent,
	): Promise<BridgeVerifierProductFileContent> {
		this.#requireState('open');
		if (descriptorEvent.availability.availabilityKind !== 'available') {
			throw new Error(`File descriptor for ${descriptorEvent.path} is not available.`);
		}
		const contentRequest = bridgeProductContentRequestSchema.parse({
			contentKind: 'file.content',
			contentRequestId: `verifier-file-content-${randomUUID()}`,
			descriptor: descriptorEvent.availability.contentDescriptor,
			kind: 'content.open',
			leaseId: `verifier-file-lease-${randomUUID()}`,
			paneSessionId: this.#paneSessionId,
			wireVersion: BRIDGE_PRODUCT_WIRE_VERSION,
			workerDerivationEpoch: 0,
			workerInstanceId: this.#workerInstanceId,
		});
		if (contentRequest.contentKind !== 'file.content') {
			throw new Error('Expected a file.content request.');
		}
		const response = await fetch(this.#endpoint('/__bridge-product/content'), {
			body: JSON.stringify(contentRequest),
			headers: this.#headers(),
			method: 'POST',
		});
		if (response.status !== 200 || response.body === null) {
			throw new Error(
				`File content request failed with status ${response.status}: ${await response.text()}`,
			);
		}

		const decoder = new BridgeProductContentStreamDecoder(contentRequest);
		const reader = response.body.getReader();
		let terminal: Awaited<ReturnType<typeof decoder.push>>['terminal'] = null;
		for (;;) {
			// oxlint-disable-next-line no-await-in-loop -- Content frames must be decoded in stream order.
			const chunk = await reader.read();
			if (chunk.done) break;
			// oxlint-disable-next-line no-await-in-loop -- Content validation is ordered with stream reads.
			const decoded = await decoder.push(chunk.value);
			for (const frame of decoded.frames) {
				// oxlint-disable-next-line no-await-in-loop -- Physical observations preserve content order.
				await this.#postFrameObservation({
					contentRequestId: contentRequest.contentRequestId,
					contentSequence: frame.header.contentSequence,
					kind: 'stream.frameObserved',
					leaseId: contentRequest.leaseId,
					paneSessionId: contentRequest.paneSessionId,
					streamKind: 'content',
					wireVersion: contentRequest.wireVersion,
					workerInstanceId: contentRequest.workerInstanceId,
				});
			}
			terminal = decoded.terminal ?? terminal;
		}
		decoder.finish();
		if (terminal === null) throw new Error('File content stream ended without a terminal frame.');
		if (terminal.kind !== 'complete') {
			throw new Error(`File content ended with ${terminal.kind}.`);
		}
		return {
			byteLength: terminal.bytes.byteLength,
			bytes: terminal.bytes,
		};
	}

	async close(): Promise<void> {
		this.#requireState('open');
		this.#state = 'closing';
		const response = await this.#postControl({
			kind: 'subscription.cancel',
			subscriptionId: this.#subscriptionId,
			subscriptionKind: 'file.metadata',
			workerDerivationEpoch: 0,
		});
		if (response.kind !== 'subscription.cancelAccepted') {
			throw new Error(`Expected subscription.cancelAccepted, received ${response.kind}.`);
		}
		const metadataStream = this.#requireMetadataStream();
		await metadataStream.frames.waitFor(
			(frame) =>
				frame.kind === 'subscription.cancelled' && frame.subscriptionId === this.#subscriptionId,
		);
		await metadataStream.close();
		this.#metadataStream = null;
		this.#authority = null;
		this.#state = 'closed';
	}

	async #installServerAuthority(): Promise<void> {
		const response = await fetch(this.#endpoint(BRIDGE_PRODUCT_DEV_BOOTSTRAP_ROUTE), {
			body: JSON.stringify({ reason: 'initial' }),
			headers: { 'Content-Type': BRIDGE_PRODUCT_DEV_BOOTSTRAP_REQUEST_MEDIA_TYPE },
			method: 'POST',
		});
		if (
			response.status !== 200 ||
			response.headers.get('content-type') !== BRIDGE_PRODUCT_DEV_BOOTSTRAP_RESPONSE_MEDIA_TYPE
		) {
			throw new Error(`Bridge product bootstrap failed with status ${response.status}.`);
		}
		const delivery = decodeBridgeProductDevBootstrapDelivery(await response.arrayBuffer());
		const capability = encodeBridgeProductCapabilityHeader(delivery.productCapability);
		new Uint8Array(delivery.productCapability).fill(0);
		this.#authority = {
			capability,
			paneSessionId: delivery.bootstrap.paneSessionId,
			workerInstanceId: delivery.bootstrap.workerInstanceId,
		};
	}

	async #postControl(
		requestBody: Readonly<Record<string, unknown>>,
	): Promise<BridgeProductControlResponse> {
		this.#controlSequence += 1;
		const request = bridgeProductControlRequestSchema.parse({
			...requestBody,
			paneSessionId: this.#paneSessionId,
			requestId: `verifier-file-request-${this.#controlSequence}`,
			requestSequence: this.#controlSequence,
			wireVersion: BRIDGE_PRODUCT_WIRE_VERSION,
			workerInstanceId: this.#workerInstanceId,
		});
		const response = await fetch(this.#endpoint('/__bridge-product/command'), {
			body: JSON.stringify(request),
			headers: this.#headers(),
			method: 'POST',
		});
		const responseText = await response.text();
		if (response.status !== 200) {
			throw new Error(
				`Bridge product control failed with status ${response.status}: ${responseText}`,
			);
		}
		const parsedResponse = bridgeProductControlResponseSchema.parse(
			JSON.parse(responseText) as unknown,
		);
		if (parsedResponse.kind === 'request.error') {
			throw new Error(`Bridge product control failed with ${parsedResponse.code}.`);
		}
		return parsedResponse;
	}

	async #openMetadataStream(): Promise<BridgeVerifierMetadataStream> {
		const abortController = new AbortController();
		const request = bridgeProductMetadataStreamRequestSchema.parse({
			kind: 'metadataStream.open',
			metadataStreamId: this.#metadataStreamId,
			paneSessionId: this.#paneSessionId,
			resumeFromStreamSequence: null,
			wireVersion: BRIDGE_PRODUCT_WIRE_VERSION,
			workerInstanceId: this.#workerInstanceId,
		});
		const response = await fetch(this.#endpoint('/__bridge-product/stream'), {
			body: JSON.stringify(request),
			headers: this.#headers(),
			method: 'POST',
			signal: abortController.signal,
		});
		if (response.status !== 200 || response.body === null) {
			throw new Error(
				`Bridge product metadata stream failed with status ${response.status}: ${await response.text()}`,
			);
		}
		const reader = response.body.getReader();
		return {
			close: async (): Promise<void> => {
				abortController.abort();
				await reader.cancel().catch((): void => undefined);
			},
			frames: new BridgeVerifierMetadataFrames(reader, async (frame): Promise<void> => {
				await this.#postFrameObservation({
					kind: 'stream.frameObserved',
					metadataStreamId: frame.metadataStreamId,
					paneSessionId: frame.paneSessionId,
					streamKind: 'metadata',
					streamSequence: frame.streamSequence,
					wireVersion: frame.wireVersion,
					workerInstanceId: frame.workerInstanceId,
				});
			}),
		};
	}

	async #postFrameObservation(
		observation: BridgeProductFrameAcknowledgementRequest,
	): Promise<void> {
		const body = bridgeProductFrameAcknowledgementRequestSchema.parse(observation);
		const response = await fetch(this.#endpoint('/__bridge-product/command'), {
			body: JSON.stringify(body),
			headers: this.#headers(),
			method: 'POST',
		});
		const responseText = await response.text();
		if (response.status !== 204 || responseText.length !== 0) {
			throw new Error(
				`Bridge product frame observation failed with status ${response.status}: ${responseText}`,
			);
		}
	}

	async #waitForFileEvent<TFileEvent extends FileMetadataEvent>(
		predicate: (event: FileMetadataEvent) => event is TFileEvent,
	): Promise<TFileEvent> {
		const frame = await this.#requireMetadataStream().frames.waitFor(
			(candidate) =>
				candidate.kind === 'subscription.data' &&
				candidate.subscriptionId === this.#subscriptionId &&
				candidate.data.subscriptionKind === 'file.metadata' &&
				predicate(candidate.data.event),
		);
		if (frame.kind !== 'subscription.data' || frame.data.subscriptionKind !== 'file.metadata') {
			throw new Error('Expected file.metadata subscription data.');
		}
		const event = frame.data.event;
		if (!predicate(event)) throw new Error('File metadata event failed correlation.');
		return event;
	}

	#endpoint(path: string): string {
		return `${this.#baseUrl}${path}?scenario=${encodeURIComponent(this.#scenarioName)}`;
	}

	#headers(): HeadersInit {
		return {
			'Content-Type': 'application/json',
			'X-AgentStudio-Bridge-Product-Capability': this.#capability,
		};
	}

	get #capability(): string {
		return this.#requireAuthority().capability;
	}

	get #paneSessionId(): string {
		return this.#requireAuthority().paneSessionId;
	}

	get #workerInstanceId(): string {
		return this.#requireAuthority().workerInstanceId;
	}

	#requireAuthority(): BridgeVerifierProductAuthority {
		if (this.#authority === null) {
			throw new Error('Bridge product verifier authority is not installed.');
		}
		return this.#authority;
	}

	#requireMetadataStream(): BridgeVerifierMetadataStream {
		if (this.#metadataStream === null)
			throw new Error('Bridge product metadata stream is not open.');
		return this.#metadataStream;
	}

	#requireState(expectedState: BridgeVerifierProductFileSessionState): void {
		if (this.#state !== expectedState) {
			throw new Error(
				`Expected Bridge product File session state ${expectedState}, received ${this.#state}.`,
			);
		}
	}
}

class BridgeVerifierMetadataFrames {
	readonly #decoder = new BridgeProductMetadataFrameDecoder();
	readonly #frames: BridgeProductMetadataFrame[] = [];
	readonly #observe: (frame: BridgeProductMetadataFrame) => Promise<void>;
	readonly #reader: ReadableStreamDefaultReader<Uint8Array>;

	constructor(
		reader: ReadableStreamDefaultReader<Uint8Array>,
		observe: (frame: BridgeProductMetadataFrame) => Promise<void>,
	) {
		this.#reader = reader;
		this.#observe = observe;
	}

	async waitFor(
		predicate: (frame: BridgeProductMetadataFrame) => boolean,
	): Promise<BridgeProductMetadataFrame> {
		for (;;) {
			const frameIndex = this.#frames.findIndex(predicate);
			if (frameIndex >= 0) {
				const [frame] = this.#frames.splice(frameIndex, 1);
				if (frame !== undefined) return frame;
			}
			// oxlint-disable-next-line no-await-in-loop -- Metadata frames must be decoded in stream order.
			const chunk = await this.#reader.read();
			if (chunk.done) throw new Error('Bridge product metadata stream ended early.');
			const frames = this.#decoder.push(chunk.value);
			for (const frame of frames) {
				// oxlint-disable-next-line no-await-in-loop -- Physical observations preserve stream order.
				await this.#observe(frame);
			}
			this.#frames.push(...frames);
		}
	}
}

interface BridgeVerifierMetadataStream {
	readonly close: () => Promise<void>;
	readonly frames: BridgeVerifierMetadataFrames;
}
