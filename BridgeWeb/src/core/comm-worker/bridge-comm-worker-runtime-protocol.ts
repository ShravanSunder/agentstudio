import {
	createBridgeCommWorkerCommandHandler,
	type BridgeCommWorkerSelectedReviewContentReadyPreparationRequest,
} from './bridge-comm-worker-command-handler.js';
import type { BridgeCommWorkerPort } from './bridge-comm-worker-entry.js';
import { enqueueSelectedBridgeWorkerReviewContentReadyPreparation } from './bridge-comm-worker-review-preparation.js';
import type { BridgeCommWorkerRow } from './bridge-comm-worker-store.js';
import {
	createWorkerContentPreparationPump,
	type WorkerContentPreparationPump,
	type WorkerContentPreparationPumpRunResult,
} from './bridge-worker-content-preparation-pump.js';
import {
	BRIDGE_WORKER_WIRE_VERSION,
	bridgeWorkerMainToServerMessageSchema,
	type BridgeWorkerReviewContentMetadata,
	type BridgeWorkerReviewContentRequestDescriptor,
	type BridgeWorkerReviewRenderSemantics,
	type BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';
import type {
	BridgeWorkerDemandRank,
	BridgeWorkerPierreRenderBudget,
} from './bridge-worker-pierre-render-job.js';
import type { BridgeWorkerContentFetch } from './bridge-worker-review-content-fetch.js';

export type BridgeCommWorkerPreparationDrain = () => Promise<WorkerContentPreparationPumpRunResult>;

export interface RegisterBridgeCommWorkerRuntimePortProtocolProps {
	readonly bridgeDemandRank: BridgeWorkerDemandRank;
	readonly budget: BridgeWorkerPierreRenderBudget;
	readonly contentItems: readonly BridgeWorkerReviewContentMetadata[];
	readonly contentRequestDescriptors: readonly BridgeWorkerReviewContentRequestDescriptor[];
	readonly createSequence?: () => number;
	readonly fetchContent?: BridgeWorkerContentFetch;
	readonly maxPreparationSliceMs?: number;
	readonly now?: () => number;
	readonly pump?: WorkerContentPreparationPump;
	readonly renderSemantics: readonly BridgeWorkerReviewRenderSemantics[];
	readonly rows: readonly BridgeCommWorkerRow[];
	readonly schedulePreparationDrain?: (drain: BridgeCommWorkerPreparationDrain) => void;
}

export function registerBridgeCommWorkerRuntimePortProtocol(
	port: BridgeCommWorkerPort,
	props: RegisterBridgeCommWorkerRuntimePortProtocolProps,
): void {
	const createSequence = props.createSequence ?? createBridgeWorkerRuntimeSequenceCounter();
	const pump =
		props.pump ??
		createWorkerContentPreparationPump({
			maxSliceMs: props.maxPreparationSliceMs ?? 8,
			...(props.now === undefined ? {} : { now: props.now }),
		});
	const schedulePreparationDrain =
		props.schedulePreparationDrain ?? scheduleDefaultBridgeCommWorkerPreparationDrain;
	const preparationCompletions: Promise<void>[] = [];
	let drainScheduled = false;
	let shouldRequestDrainAfterMessage = false;

	const drainPreparation: BridgeCommWorkerPreparationDrain = async () => {
		drainScheduled = false;
		const runResult = pump.runUntilBudget();
		const completions = preparationCompletions.splice(0, preparationCompletions.length);
		const completionResults = await Promise.allSettled(completions);
		const rejectedCompletion = completionResults.find(
			(result): result is PromiseRejectedResult => result.status === 'rejected',
		);
		if (rejectedCompletion !== undefined) {
			throw rejectedCompletion.reason;
		}
		if (pump.getPendingWorkIds().length > 0) {
			requestPreparationDrain();
		}
		return runResult;
	};

	const requestPreparationDrain = (): void => {
		if (drainScheduled) {
			return;
		}
		drainScheduled = true;
		schedulePreparationDrain(drainPreparation);
	};

	const handler = createBridgeCommWorkerCommandHandler({
		contentItems: props.contentItems,
		rows: props.rows,
		createSequence,
		scheduleSelectedReviewContentReadyPreparation: (
			request: BridgeCommWorkerSelectedReviewContentReadyPreparationRequest,
		): void => {
			const ticket = enqueueSelectedBridgeWorkerReviewContentReadyPreparation({
				bridgeDemandRank: props.bridgeDemandRank,
				budget: props.budget,
				contentRequestDescriptors: props.contentRequestDescriptors,
				epoch: request.epoch,
				...(props.fetchContent === undefined ? {} : { fetchContent: props.fetchContent }),
				itemId: request.itemId,
				port,
				pump,
				renderSemantics: props.renderSemantics,
				requestPreparationDrain,
				sequence: createSequence(),
				store: request.store,
			});
			if (ticket.enqueued) {
				preparationCompletions.push(ticket.completion);
				shouldRequestDrainAfterMessage = true;
			}
		},
	});

	port.addEventListener('message', (event: MessageEvent<unknown>): void => {
		const parsedMessage = bridgeWorkerMainToServerMessageSchema.safeParse(event.data);
		if (!parsedMessage.success) {
			port.postMessage(buildBridgeWorkerRuntimeDegradedHealthEvent());
			return;
		}

		shouldRequestDrainAfterMessage = false;
		for (const message of handler.handleMessage(parsedMessage.data)) {
			port.postMessage(message);
		}
		if (shouldRequestDrainAfterMessage) {
			requestPreparationDrain();
		}
	});
	port.start?.();
}

function buildBridgeWorkerRuntimeDegradedHealthEvent(): BridgeWorkerServerToMainMessage {
	return {
		wireVersion: BRIDGE_WORKER_WIRE_VERSION,
		direction: 'serverWorkerToMain',
		transferDescriptors: [],
		kind: 'health',
		status: 'degraded',
		message: 'Bridge comm worker received invalid message.',
	};
}

function createBridgeWorkerRuntimeSequenceCounter(): () => number {
	let nextSequence = 1;
	return (): number => {
		const sequence = nextSequence;
		nextSequence += 1;
		return sequence;
	};
}

function scheduleDefaultBridgeCommWorkerPreparationDrain(
	drain: BridgeCommWorkerPreparationDrain,
): void {
	queueMicrotask(() => {
		void drain();
	});
}
