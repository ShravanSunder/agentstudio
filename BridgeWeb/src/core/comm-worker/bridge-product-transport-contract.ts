import type {
	BridgeProductCallKind,
	BridgeProductCallRequest,
	BridgeProductCallResult,
} from './bridge-product-call-contracts.js';
import type {
	BridgeProductContentDescriptor,
	BridgeProductContentKind,
	BridgeProductContentFrameFor,
	BridgeProductContentTerminal,
} from './bridge-product-content-contracts.js';
import type {
	BridgeProductSubscriptionEvent,
	BridgeProductSubscriptionKind,
	BridgeProductSubscriptionOptions,
	BridgeProductSubscriptionUpdateOptions,
} from './bridge-product-subscription-contracts.js';

export type BridgeProductCallOptions = {
	readonly signal?: AbortSignal;
};

type BridgeProductCallArguments = {
	[TCallKind in BridgeProductCallKind]: readonly [
		method: TCallKind,
		request: BridgeProductCallRequest<TCallKind>,
		options?: BridgeProductCallOptions,
	];
}[BridgeProductCallKind];

type BridgeProductSubscriptionArguments = {
	[TSubscriptionKind in BridgeProductSubscriptionKind]: readonly [
		subscriptionKind: TSubscriptionKind,
		options: BridgeProductSubscriptionOptions<TSubscriptionKind>,
	];
}[BridgeProductSubscriptionKind];

export type BridgeProductSubscription<TSubscriptionKind extends BridgeProductSubscriptionKind> = {
	[TRegistrySubscriptionKind in TSubscriptionKind]: {
		readonly events: AsyncIterable<BridgeProductSubscriptionEvent<TRegistrySubscriptionKind>>;
		readonly subscriptionId: string;
		readonly subscriptionKind: TRegistrySubscriptionKind;
		cancel(): Promise<void>;
		update(
			options: BridgeProductSubscriptionUpdateOptions<TRegistrySubscriptionKind>,
		): Promise<void>;
	};
}[TSubscriptionKind];

export type BridgeProductContentStream<TContentKind extends BridgeProductContentKind> = {
	readonly contentKind: TContentKind;
	readonly contentRequestId: string;
	readonly frames: AsyncIterable<BridgeProductContentFrameFor<TContentKind>>;
	readonly responseStartControl?: BridgeProductContentResponseStartControl;
	readonly terminal: Promise<BridgeProductContentTerminal<TContentKind>>;
};

export interface BridgeProductContentResponseStartControl {
	pauseBeforeStart(): void;
	resumeBeforeStart(): void;
}

export type BridgeProductTransport = {
	call<TCallArguments extends BridgeProductCallArguments>(
		...arguments_: TCallArguments
	): Promise<BridgeProductCallResult<TCallArguments[0]>>;
	openContent<TContentKind extends BridgeProductContentKind>(
		descriptor: BridgeProductContentDescriptor<TContentKind>,
		abortSignal: AbortSignal,
	): BridgeProductContentStream<TContentKind>;
	subscribe<TSubscriptionArguments extends BridgeProductSubscriptionArguments>(
		...arguments_: TSubscriptionArguments
	): BridgeProductSubscription<TSubscriptionArguments[0]>;
};

export type { BridgeProductCallResult } from './bridge-product-call-contracts.js';
export type { BridgeProductContentTerminal } from './bridge-product-content-contracts.js';
