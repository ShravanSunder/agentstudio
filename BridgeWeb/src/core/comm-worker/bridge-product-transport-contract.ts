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
	BridgeProductMetadataApplicationEvent,
	BridgeProductMetadataApplicationKind,
	BridgeProductMetadataApplicationProtocol,
	BridgeProductMetadataApplicationProtocolIdentity,
	BridgeProductMetadataApplicationUpdateOptions,
	BridgeProductMetadataDataFrame,
} from './bridge-product-metadata-application-protocol.js';
import type {
	BridgeProductSubscriptionEvent,
	BridgeProductSubscriptionKind,
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

export type BridgeProductMetadataApplicationSubscription<
	TProtocol extends BridgeProductMetadataApplicationProtocolIdentity,
> = {
	readonly events: AsyncIterable<
		BridgeProductMetadataDataFrame<BridgeProductMetadataApplicationEvent<TProtocol>>
	>;
	readonly subscriptionId: string;
	readonly subscriptionKind: BridgeProductMetadataApplicationKind<TProtocol>;
	cancel(): Promise<void>;
	update(options: BridgeProductMetadataApplicationUpdateOptions<TProtocol>): Promise<void>;
};

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
		operationCorrelationId?: string | null,
	): BridgeProductContentStream<TContentKind>;
	subscribe<
		TKind extends string,
		TOptions,
		TUpdateOptions,
		TOpen extends { readonly subscriptionKind: TKind },
		TInterestState extends { readonly subscriptionKind: TKind },
		TInterestDelta extends { readonly subscriptionKind: TKind },
		TData extends { readonly event: unknown; readonly subscriptionKind: TKind },
	>(
		protocol: BridgeProductMetadataApplicationProtocol<
			TKind,
			TOptions,
			TUpdateOptions,
			TOpen,
			TInterestState,
			TInterestDelta,
			TData
		>,
		options: TOptions,
	): {
		readonly events: AsyncIterable<BridgeProductMetadataDataFrame<TData['event']>>;
		readonly subscriptionId: string;
		readonly subscriptionKind: TKind;
		cancel(): Promise<void>;
		update(options: TUpdateOptions): Promise<void>;
	};
};

export type { BridgeProductCallResult } from './bridge-product-call-contracts.js';
export type { BridgeProductContentTerminal } from './bridge-product-content-contracts.js';
