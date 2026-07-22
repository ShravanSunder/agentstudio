import type {
	BridgeWorkerHealthEvent,
	BridgeWorkerMainToServerMessage,
} from './bridge-worker-contracts.js';

export interface DeferredBridgeWorkerReply {
	readonly promise: Promise<BridgeWorkerHealthEvent>;
	readonly settled: boolean;
	readonly resolve: (message: BridgeWorkerHealthEvent) => void;
	readonly reject: (error: Error) => void;
}

export interface CreateBridgeCommWorkerHostileServerTransportProps {
	readonly replyPlan: readonly DeferredBridgeWorkerReply[];
}

export interface BridgeCommWorkerHostileServerTransport {
	readonly postedMessages: readonly BridgeWorkerMainToServerMessage[];
	readonly droppedReplyCount: number;
	readonly postMessage: (message: BridgeWorkerMainToServerMessage) => void;
	readonly waitForHealth: (
		message: BridgeWorkerMainToServerMessage,
	) => Promise<BridgeWorkerHealthEvent>;
}

export function createDeferredBridgeWorkerReply(): DeferredBridgeWorkerReply {
	let settled = false;
	let resolveReply: ((message: BridgeWorkerHealthEvent) => void) | null = null;
	let rejectReply: ((error: Error) => void) | null = null;
	const promise = new Promise<BridgeWorkerHealthEvent>((resolve, reject): void => {
		resolveReply = (message: BridgeWorkerHealthEvent): void => {
			settled = true;
			resolve(message);
		};
		rejectReply = (error: Error): void => {
			settled = true;
			reject(error);
		};
	});
	if (resolveReply === null || rejectReply === null) {
		throw new Error('Bridge worker reply handlers were not initialized.');
	}

	return {
		promise,
		get settled(): boolean {
			return settled;
		},
		resolve: resolveReply,
		reject: rejectReply,
	};
}

export function createNeverResolvingBridgeWorkerReply(): DeferredBridgeWorkerReply {
	return createDeferredBridgeWorkerReply();
}

export function createDroppedBridgeWorkerReply(): DeferredBridgeWorkerReply {
	const droppedReply = createDeferredBridgeWorkerReply();
	droppedReply.reject(new Error('Bridge worker reply dropped by hostile test transport.'));
	return droppedReply;
}

export function createBridgeCommWorkerHostileServerTransport(
	props: CreateBridgeCommWorkerHostileServerTransportProps,
): BridgeCommWorkerHostileServerTransport {
	const postedMessages: BridgeWorkerMainToServerMessage[] = [];
	const replyPlan = [...props.replyPlan];
	let droppedReplyCount = 0;

	const waitForHealth = (): Promise<BridgeWorkerHealthEvent> => {
		const reply = replyPlan.shift();
		if (reply === undefined) {
			return new Promise<BridgeWorkerHealthEvent>(() => {});
		}
		while (replyPlan[0] === reply) {
			replyPlan.shift();
			droppedReplyCount += 1;
		}
		return reply.promise;
	};

	return {
		get postedMessages(): readonly BridgeWorkerMainToServerMessage[] {
			return postedMessages;
		},
		get droppedReplyCount(): number {
			return droppedReplyCount;
		},
		postMessage: (message: BridgeWorkerMainToServerMessage): void => {
			postedMessages.push(message);
		},
		waitForHealth,
	};
}
