import type { BridgeProductBatchFrame } from './bridge-product-batch-wire-contracts.js';
import {
	BridgeProductViewBatchReceiver,
	type BridgeProductViewInstallation,
} from './bridge-product-view-batch-receiver.js';
import type { BridgeProductViewAcknowledgementRequest } from './bridge-product-view-control-wire-contracts.js';

export interface BridgeProductBatchFrameSinks {
	readonly install: (installation: BridgeProductViewInstallation) => Promise<void> | void;
	readonly receipt: (
		frame: Extract<BridgeProductBatchFrame, { readonly kind: 'subscription.batchPart' }>,
		through: number,
	) => void;
	readonly resnapshot: (frame: BridgeProductBatchFrame) => void;
}

/** W4 routes certified installations; each application owns its typed install. */
export class BridgeProductBatchFrameRouter {
	readonly #receiversBySubscriptionId = new Map<
		string,
		{
			readonly receiver: BridgeProductViewBatchReceiver;
			handle: string;
			readonly lastBeginByDomain: Map<
				string,
				Extract<BridgeProductBatchFrame, { readonly kind: 'subscription.batchBegin' }>
			>;
			scopeRevision: number;
		}
	>();
	#sinks: BridgeProductBatchFrameSinks | null = null;

	setSinks(sinks: BridgeProductBatchFrameSinks): void {
		this.#sinks = sinks;
	}

	accept(frame: BridgeProductBatchFrame): void {
		const sinks = this.#sinks;
		if (sinks === null) throw new Error('Bridge product batch application owner is absent.');
		let state = this.#receiversBySubscriptionId.get(frame.subscriptionId);
		if (frame.kind === 'subscription.batchBegin') {
			if (state === undefined) {
				state = {
					receiver: new BridgeProductViewBatchReceiver({
						handle: frame.handle,
						scope: frame.scope,
						scopeRevision: frame.scopeRevision,
						subscriptionId: frame.subscriptionId,
						subscriptionKind: frame.subscriptionKind,
					}),
					handle: frame.handle,
					lastBeginByDomain: new Map(),
					scopeRevision: frame.scopeRevision,
				};
				this.#receiversBySubscriptionId.set(frame.subscriptionId, state);
			} else if (frame.handle !== state.handle) {
				state.receiver.replaceHandle(frame.handle, frame.scope, frame.scopeRevision);
				state.lastBeginByDomain.clear();
				state.handle = frame.handle;
				state.scopeRevision = frame.scopeRevision;
			} else if (frame.scopeRevision > state.scopeRevision) {
				state.receiver.setScope(frame.scope, frame.scopeRevision);
				state.lastBeginByDomain.clear();
				state.scopeRevision = frame.scopeRevision;
			}
			state.lastBeginByDomain.set(frame.domain, frame);
			state.receiver.admitDomain(frame.domain, frame.incarnation);
		}
		if (state === undefined) {
			sinks.resnapshot(frame);
			return;
		}
		const acceptance = state.receiver.accept(frame);
		if (acceptance.kind === 'resnapshot') sinks.resnapshot(frame);
		if (
			frame.kind === 'subscription.batchPart' &&
			acceptance.kind === 'staged' &&
			acceptance.receivedThroughDeliverySequence !== undefined
		)
			sinks.receipt(frame, acceptance.receivedThroughDeliverySequence);
		for (const installation of state.receiver.takeInstallations()) {
			try {
				const installed = sinks.install(installation);
				if (installed !== undefined) {
					void installed.catch((): void => {
						sinks.resnapshot(installation.begin);
					});
				}
			} catch {
				// A typed application rejected this domain's certified bank. Keep
				// siblings flowing and ask native for this domain again.
				sinks.resnapshot(installation.begin);
			}
		}
	}

	requestResnapshotForLostReceipt(request: BridgeProductViewAcknowledgementRequest): void {
		const state = this.#receiversBySubscriptionId.get(request.subscriptionId);
		const begin = state?.lastBeginByDomain.get(request.domain);
		if (
			begin === undefined ||
			begin.domain !== request.domain ||
			begin.handle !== request.handle ||
			begin.incarnation !== request.incarnation ||
			begin.paneSessionId !== request.paneSessionId ||
			begin.workerInstanceId !== request.workerInstanceId
		)
			return;
		this.#sinks?.resnapshot(begin);
	}

	retireSubscription(subscriptionId: string): void {
		this.#receiversBySubscriptionId.delete(subscriptionId);
	}

	clear(): void {
		this.#receiversBySubscriptionId.clear();
	}
}
