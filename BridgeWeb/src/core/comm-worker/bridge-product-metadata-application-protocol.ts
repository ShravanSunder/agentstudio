import { z } from 'zod';

import type { BridgeProductSurface } from './bridge-product-contract-primitives.js';

export const bridgeProductMetadataApplicationKindSchema = z.string().min(1);

export type BridgeProductMetadataApplicationInterestStateEncodingPreflight =
	| {
			readonly canonicalByteLength: number;
			readonly status: 'accepted';
			readonly visitedTextValueCount: number;
	  }
	| {
			readonly canonicalByteLengthLowerBound: number;
			readonly maximumCanonicalByteLength: number;
			readonly status: 'exceedsMaximum';
			readonly visitedTextValueCount: number;
	  };

export interface BridgeProductMetadataApplicationProtocolIdentity {
	readonly kind: string;
	readonly surface: BridgeProductSurface;
}

export interface BridgeProductMetadataApplicationProtocol<
	TKind extends string,
	TOptions,
	TUpdateOptions,
	TOpen extends { readonly subscriptionKind: TKind },
	TInterestState extends { readonly subscriptionKind: TKind },
	TInterestDelta extends { readonly subscriptionKind: TKind },
	TData extends { readonly event: unknown; readonly subscriptionKind: TKind },
> extends BridgeProductMetadataApplicationProtocolIdentity {
	readonly dataSchema: z.ZodType<TData>;
	readonly kind: TKind;
	readonly interestDeltaSchema: z.ZodType<TInterestDelta>;
	readonly interestStatePreflightSchema: z.ZodType<TInterestState>;
	readonly interestStateSchema: z.ZodType<TInterestState>;
	readonly openSchema: z.ZodType<TOpen>;
	readonly optionsSchema: z.ZodType<TOptions>;
	readonly surface: BridgeProductSurface;
	readonly updateOptionsSchema: z.ZodType<TUpdateOptions>;
	emptyInterestState(): TInterestState;
	encodeInterestState(state: TInterestState): Uint8Array;
	initialOpen(options: TOptions): TOpen;
	initialUpdateOptions(options: TOptions): TUpdateOptions;
	interestDelta(current: TInterestState, target: TInterestState): TInterestDelta;
	interestDeltaItemCount(delta: TInterestDelta): number;
	interestStateForUpdate(options: TUpdateOptions): TInterestState;
	preflightInterestState(
		state: TInterestState,
	): BridgeProductMetadataApplicationInterestStateEncodingPreflight;
	readEventSourceGeneration(event: TData['event']): number;
}

export function defineBridgeProductMetadataApplicationProtocol<
	const TKind extends string,
	const TSurface extends BridgeProductSurface,
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
	> & { readonly surface: TSurface },
): BridgeProductMetadataApplicationProtocol<
	TKind,
	TOptions,
	TUpdateOptions,
	TOpen,
	TInterestState,
	TInterestDelta,
	TData
> & { readonly surface: TSurface } {
	return Object.freeze(protocol);
}

export type BridgeProductMetadataApplicationKind<
	TProtocol extends BridgeProductMetadataApplicationProtocolIdentity,
> = TProtocol['kind'];

export type BridgeProductMetadataApplicationOptions<
	TProtocol extends BridgeProductMetadataApplicationProtocolIdentity,
> =
	TProtocol extends BridgeProductMetadataApplicationProtocol<
		string,
		infer TOptions,
		unknown,
		{ readonly subscriptionKind: string },
		{ readonly subscriptionKind: string },
		{ readonly subscriptionKind: string },
		{ readonly event: unknown; readonly subscriptionKind: string }
	>
		? TOptions
		: never;

export type BridgeProductMetadataApplicationUpdateOptions<
	TProtocol extends BridgeProductMetadataApplicationProtocolIdentity,
> =
	TProtocol extends BridgeProductMetadataApplicationProtocol<
		string,
		unknown,
		infer TUpdateOptions,
		{ readonly subscriptionKind: string },
		{ readonly subscriptionKind: string },
		{ readonly subscriptionKind: string },
		{ readonly event: unknown; readonly subscriptionKind: string }
	>
		? TUpdateOptions
		: never;

export type BridgeProductMetadataApplicationEvent<
	TProtocol extends BridgeProductMetadataApplicationProtocolIdentity,
> =
	TProtocol extends BridgeProductMetadataApplicationProtocol<
		string,
		unknown,
		unknown,
		{ readonly subscriptionKind: string },
		{ readonly subscriptionKind: string },
		{ readonly subscriptionKind: string },
		infer TData
	>
		? TData['event']
		: never;

export type BridgeProductMetadataApplicationOpen<
	TProtocol extends BridgeProductMetadataApplicationProtocolIdentity,
> =
	TProtocol extends BridgeProductMetadataApplicationProtocol<
		string,
		unknown,
		unknown,
		infer TOpen,
		{ readonly subscriptionKind: string },
		{ readonly subscriptionKind: string },
		{ readonly event: unknown; readonly subscriptionKind: string }
	>
		? TOpen
		: never;

export type BridgeProductMetadataApplicationInterestState<
	TProtocol extends BridgeProductMetadataApplicationProtocolIdentity,
> =
	TProtocol extends BridgeProductMetadataApplicationProtocol<
		string,
		unknown,
		unknown,
		{ readonly subscriptionKind: string },
		infer TInterestState,
		{ readonly subscriptionKind: string },
		{ readonly event: unknown; readonly subscriptionKind: string }
	>
		? TInterestState
		: never;

export type BridgeProductMetadataApplicationInterestDelta<
	TProtocol extends BridgeProductMetadataApplicationProtocolIdentity,
> =
	TProtocol extends BridgeProductMetadataApplicationProtocol<
		string,
		unknown,
		unknown,
		{ readonly subscriptionKind: string },
		{ readonly subscriptionKind: string },
		infer TInterestDelta,
		{ readonly event: unknown; readonly subscriptionKind: string }
	>
		? TInterestDelta
		: never;

export type BridgeProductMetadataApplicationData<
	TProtocol extends BridgeProductMetadataApplicationProtocolIdentity,
> =
	TProtocol extends BridgeProductMetadataApplicationProtocol<
		string,
		unknown,
		unknown,
		{ readonly subscriptionKind: string },
		{ readonly subscriptionKind: string },
		{ readonly subscriptionKind: string },
		infer TData
	>
		? TData
		: never;

export interface BridgeProductMetadataApplicationRegistration extends BridgeProductMetadataApplicationProtocolIdentity {
	readonly protocol: BridgeProductMetadataApplicationProtocolIdentity;
	encodeInterestState(state: unknown): Uint8Array;
	interestDeltaItemCount(delta: unknown): number;
	preflightInterestState(
		state: unknown,
	): BridgeProductMetadataApplicationInterestStateEncodingPreflight;
	validateInterestState(state: unknown): { readonly subscriptionKind: string };
	validateInterestDelta(delta: unknown): { readonly subscriptionKind: string };
	validateOpen(open: unknown): { readonly subscriptionKind: string };
}

export function registerBridgeProductMetadataApplicationProtocol<
	const TKind extends string,
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
): BridgeProductMetadataApplicationRegistration {
	return Object.freeze({
		encodeInterestState: (state: unknown): Uint8Array => {
			const preflightState = protocol.interestStatePreflightSchema.parse(state);
			const preflight = protocol.preflightInterestState(preflightState);
			if (preflight.status === 'exceedsMaximum') {
				throw new Error(
					`Bridge product canonical interest state cannot exceed ${preflight.maximumCanonicalByteLength} bytes.`,
				);
			}
			const parsedState = protocol.interestStateSchema.parse(state);
			return protocol.encodeInterestState(parsedState);
		},
		interestDeltaItemCount: (delta: unknown): number =>
			protocol.interestDeltaItemCount(protocol.interestDeltaSchema.parse(delta)),
		kind: protocol.kind,
		preflightInterestState: (state: unknown) =>
			protocol.preflightInterestState(protocol.interestStatePreflightSchema.parse(state)),
		protocol,
		surface: protocol.surface,
		validateInterestState: (state: unknown) => protocol.interestStateSchema.parse(state),
		validateInterestDelta: (delta: unknown) => protocol.interestDeltaSchema.parse(delta),
		validateOpen: (open: unknown) => protocol.openSchema.parse(open),
	});
}

export class BridgeProductMetadataApplicationRegistry {
	readonly #registrationByKind: ReadonlyMap<string, BridgeProductMetadataApplicationRegistration>;

	constructor(registrations: readonly BridgeProductMetadataApplicationRegistration[]) {
		const registrationByKind = new Map<string, BridgeProductMetadataApplicationRegistration>();
		for (const registration of registrations) {
			if (registrationByKind.has(registration.kind)) {
				throw new Error(`Duplicate Bridge product metadata application: ${registration.kind}.`);
			}
			registrationByKind.set(registration.kind, registration);
		}
		this.#registrationByKind = registrationByKind;
	}

	get registeredKinds(): readonly string[] {
		return Object.freeze([...this.#registrationByKind.keys()]);
	}

	lookup(kind: string): BridgeProductMetadataApplicationProtocolIdentity {
		return this.#registration(kind).protocol;
	}

	encodeInterestState(state: unknown): Uint8Array {
		return this.#registrationForApplicationValue(state).encodeInterestState(state);
	}

	interestDeltaItemCount(delta: unknown): number {
		return this.#registrationForApplicationValue(delta).interestDeltaItemCount(delta);
	}

	preflightInterestState(
		state: unknown,
	): BridgeProductMetadataApplicationInterestStateEncodingPreflight {
		return this.#registrationForApplicationValue(state).preflightInterestState(state);
	}

	validateInterestState(state: unknown): { readonly subscriptionKind: string } {
		return this.#registrationForApplicationValue(state).validateInterestState(state);
	}

	validateInterestDelta(kind: string, delta: unknown): { readonly subscriptionKind: string } {
		return this.#registration(kind).validateInterestDelta(delta);
	}

	validateOpen(kind: string, open: unknown): { readonly subscriptionKind: string } {
		return this.#registration(kind).validateOpen(open);
	}

	#registration(kind: string): BridgeProductMetadataApplicationRegistration {
		const registration = this.#registrationByKind.get(kind);
		if (registration === undefined) {
			throw new Error(`Unknown Bridge product metadata application: ${kind}.`);
		}
		return registration;
	}

	#registrationForApplicationValue(value: unknown): BridgeProductMetadataApplicationRegistration {
		const identity = z
			.object({ subscriptionKind: bridgeProductMetadataApplicationKindSchema })
			.passthrough()
			.parse(value);
		return this.#registration(identity.subscriptionKind);
	}

	requireProtocol<TProtocol extends BridgeProductMetadataApplicationProtocolIdentity>(
		protocol: TProtocol,
	): TProtocol {
		if (this.#registrationByKind.get(protocol.kind)?.protocol !== protocol) {
			throw new Error(`Unregistered Bridge product metadata application: ${protocol.kind}.`);
		}
		return protocol;
	}
}
