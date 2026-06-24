import { describe, expect, test } from 'vitest';

import {
	bridgeDemandIntentSchema,
	bridgeDemandKeysSchema,
	bridgeDescriptorDemandStateSchema,
	bridgeViewInterestSchema,
} from './bridge-demand-models.js';

describe('bridge demand models', () => {
	test('parses demand intent, demand keys, descriptor state, and view interest', () => {
		const descriptorRef = {
			descriptorId: 'descriptor-1',
			expectedProtocol: 'review',
			expectedResourceKind: 'content',
			expectedIdentity: {
				paneId: 'pane-1',
				protocol: 'review',
				sourceId: 'source-1',
				packageId: 'package-1',
				generation: 1,
				revision: 2,
			},
		};

		expect(
			bridgeDemandIntentSchema.parse({
				descriptorRef,
				lane: 'foreground',
				orderingKey: '0001',
				dedupeKey: 'review:descriptor-1',
				freshnessKey: 'review:descriptor-1:revision-2',
				cancellationGroup: 'review:package-1',
			}),
		).toEqual({
			descriptorRef,
			lane: 'foreground',
			orderingKey: '0001',
			dedupeKey: 'review:descriptor-1',
			freshnessKey: 'review:descriptor-1:revision-2',
			cancellationGroup: 'review:package-1',
		});
		expect(
			bridgeDemandKeysSchema.parse({
				orderingKey: '0001',
				dedupeKey: 'review:descriptor-1',
				freshnessKey: 'review:descriptor-1:revision-2',
				cancellationGroup: 'review:package-1',
			}),
		).toEqual({
			orderingKey: '0001',
			dedupeKey: 'review:descriptor-1',
			freshnessKey: 'review:descriptor-1:revision-2',
			cancellationGroup: 'review:package-1',
		});
		expect(
			bridgeDescriptorDemandStateSchema.parse({
				kind: 'valid',
				freshnessKey: 'review:descriptor-1:revision-2',
				needsBodyOrWindow: true,
			}),
		).toEqual({
			kind: 'valid',
			freshnessKey: 'review:descriptor-1:revision-2',
			needsBodyOrWindow: true,
		});
		expect(bridgeViewInterestSchema.parse({ kind: 'selected' })).toEqual({
			kind: 'selected',
		});
	});

	test('rejects loose scheduling fields and unknown lanes', () => {
		const descriptorRef = {
			descriptorId: 'descriptor-1',
			expectedProtocol: 'review',
			expectedResourceKind: 'content',
			expectedIdentity: {
				paneId: 'pane-1',
				protocol: 'review',
			},
		};

		expect(
			bridgeDemandIntentSchema.safeParse({
				descriptorRef,
				lane: 'selected',
				orderingKey: '0001',
				dedupeKey: 'review:descriptor-1',
				freshnessKey: 'review:descriptor-1:revision-2',
				cancellationGroup: 'review:package-1',
			}).success,
		).toBe(false);
		expect(
			bridgeDemandIntentSchema.safeParse({
				descriptorRef,
				lane: 'foreground',
				orderingKey: '0001',
				dedupeKey: 'review:descriptor-1',
				freshnessKey: 'review:descriptor-1:revision-2',
				cancellationGroup: 'review:package-1',
				reason: 'selected',
			}).success,
		).toBe(false);
		expect(
			bridgeDescriptorDemandStateSchema.safeParse({
				kind: 'valid',
				freshnessKey: 'review:descriptor-1:revision-2',
				needsBodyOrWindow: true,
				resourceUrl: 'agentstudio://resource/review/content/descriptor-1',
			}).success,
		).toBe(false);
	});
});
