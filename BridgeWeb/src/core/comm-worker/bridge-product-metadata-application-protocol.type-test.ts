import { z } from 'zod';

import {
	type BridgeProductMetadataApplicationEvent,
	type BridgeProductMetadataApplicationOptions,
	type BridgeProductMetadataApplicationUpdateOptions,
	type BridgeProductMetadataDataFrame,
	defineBridgeProductMetadataApplicationProtocol,
} from './bridge-product-metadata-application-protocol.js';
import type { BridgeProductMetadataApplicationSubscription } from './bridge-product-transport-contract.js';

const inferredProtocol = defineBridgeProductMetadataApplicationProtocol({
	dataSchema: z
		.object({
			event: z.object({ generation: z.number(), payload: z.string() }).strict(),
			subscriptionKind: z.literal('inference.metadata'),
		})
		.strict(),
	emptyInterestState: () => ({ subscriptionKind: 'inference.metadata', values: [] }),
	encodeInterestState: () => new Uint8Array(),
	initialOpen: (options) => ({ source: options.source, subscriptionKind: 'inference.metadata' }),
	initialUpdateOptions: (options) => ({ values: options.values }),
	interestDelta: (_current, target) => ({
		subscriptionKind: 'inference.metadata',
		values: target.values,
	}),
	interestDeltaItemCount: (delta) => delta.values.length,
	interestDeltaSchema: z
		.object({
			subscriptionKind: z.literal('inference.metadata'),
			values: z.array(z.string()).readonly(),
		})
		.strict(),
	interestStatePreflightSchema: z
		.object({
			subscriptionKind: z.literal('inference.metadata'),
			values: z.array(z.string()).readonly(),
		})
		.strict(),
	interestStateForUpdate: (options) => ({
		subscriptionKind: 'inference.metadata',
		values: options.values,
	}),
	interestStateSchema: z
		.object({
			subscriptionKind: z.literal('inference.metadata'),
			values: z.array(z.string()).readonly(),
		})
		.strict(),
	kind: 'inference.metadata',
	openSchema: z
		.object({ source: z.string(), subscriptionKind: z.literal('inference.metadata') })
		.strict(),
	optionsSchema: z.object({ source: z.string(), values: z.array(z.string()).readonly() }).strict(),
	preflightInterestState: () => ({
		canonicalByteLength: 6,
		status: 'accepted',
		visitedTextValueCount: 0,
	}),
	readEventSourceGeneration: (event) => event.generation,
	surface: 'review',
	updateOptionsSchema: z.object({ values: z.array(z.string()).readonly() }).strict(),
});

const inferredOptions: BridgeProductMetadataApplicationOptions<typeof inferredProtocol> = {
	source: 'source-1',
	values: ['one'],
};
const inferredUpdate: BridgeProductMetadataApplicationUpdateOptions<typeof inferredProtocol> = {
	values: ['two'],
};
const inferredEvent: BridgeProductMetadataApplicationEvent<typeof inferredProtocol> = {
	generation: 3,
	payload: 'typed',
};
declare const inferredSubscription: BridgeProductMetadataApplicationSubscription<
	typeof inferredProtocol
>;
void inferredOptions;
void inferredEvent;
void inferredSubscription.update(inferredUpdate);

async function consumeInferredSubscriptionFrames(): Promise<void> {
	for await (const frame of inferredSubscription.events) {
		const typedFrame: BridgeProductMetadataDataFrame<
			BridgeProductMetadataApplicationEvent<typeof inferredProtocol>
		> = frame;
		const payload: string = typedFrame.data.payload;
		const sourceGeneration: number = typedFrame.sourceGeneration;
		const workerDerivationEpoch: number = typedFrame.workerDerivationEpoch;
		void payload;
		void sourceGeneration;
		void workerDerivationEpoch;
	}
}
void consumeInferredSubscriptionFrames;

declare const incorrectlyUnwrappedEvent: BridgeProductMetadataApplicationEvent<
	typeof inferredProtocol
>;
// @ts-expect-error Subscription iterators yield transport frames, not bare application events.
const invalidUnwrappedFrame: BridgeProductMetadataDataFrame<
	BridgeProductMetadataApplicationEvent<typeof inferredProtocol>
> = incorrectlyUnwrappedEvent;
void invalidUnwrappedFrame;

// @ts-expect-error Protocol options retain their required source.
const missingSource: BridgeProductMetadataApplicationOptions<typeof inferredProtocol> = {
	values: [],
};
void missingSource;

const crossWiredUpdate: BridgeProductMetadataApplicationUpdateOptions<typeof inferredProtocol> = {
	// @ts-expect-error Protocol update options cannot borrow the initial-open source field.
	source: 'wrong-owner',
	values: [],
};
void crossWiredUpdate;

const malformedEvent: BridgeProductMetadataApplicationEvent<typeof inferredProtocol> = {
	generation: 3,
	// @ts-expect-error Protocol event payload remains strictly typed.
	payload: 4,
};
void malformedEvent;
