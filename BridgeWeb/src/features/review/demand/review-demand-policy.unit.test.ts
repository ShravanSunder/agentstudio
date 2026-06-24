import { describe, expect, test } from 'vitest';

import type {
	BridgeDescriptorDemandState,
	BridgeViewInterest,
} from '../../../core/models/bridge-demand-models.js';
import type { BridgeDescriptorRef } from '../../../core/models/bridge-resource-descriptor.js';
import { mapReviewDemandStimulusToIntents } from './review-demand-policy.js';

describe('review demand policy', () => {
	test('maps selected and explicit refresh review stimuli to foreground demand', () => {
		const descriptorRef = makeDescriptorRef('descriptor-1');
		const readContext = makeReadContext({
			descriptorState: {
				kind: 'valid',
				freshnessKey: 'descriptor-1:rev-1',
				needsBodyOrWindow: true,
			},
			viewInterest: { kind: 'selected' },
		});

		expect(
			mapReviewDemandStimulusToIntents({
				stimulus: { kind: 'reviewItemSelected', descriptorRef },
				readContext,
			}),
		).toEqual([
			{
				descriptorRef,
				lane: 'foreground',
				orderingKey: 'order:descriptor-1',
				dedupeKey: 'dedupe:descriptor-1',
				freshnessKey: 'fresh:descriptor-1',
				cancellationGroup: 'cancel:descriptor-1',
			},
		]);
		expect(
			mapReviewDemandStimulusToIntents({
				stimulus: { kind: 'reviewExplicitRefresh', descriptorRef },
				readContext,
			})[0]?.lane,
		).toBe('foreground');
	});

	test('maps invalidated descriptors by dominant view interest and fails closed', () => {
		const selectedRef = makeDescriptorRef('selected');
		const openRef = makeDescriptorRef('open');
		const visibleRef = makeDescriptorRef('visible');
		const hiddenRef = makeDescriptorRef('hidden');
		const missingRef = makeDescriptorRef('missing');
		const readContext = makeReadContext({
			descriptorStateById: {
				selected: {
					kind: 'stale',
					freshnessKey: 'selected:rev-2',
					needsBodyOrWindow: true,
				},
				open: {
					kind: 'stale',
					freshnessKey: 'open:rev-2',
					needsBodyOrWindow: true,
				},
				visible: {
					kind: 'stale',
					freshnessKey: 'visible:rev-2',
					needsBodyOrWindow: true,
				},
				hidden: {
					kind: 'stale',
					freshnessKey: 'hidden:rev-2',
					needsBodyOrWindow: true,
				},
				missing: { kind: 'missing' },
			},
			viewInterestById: {
				selected: { kind: 'selected' },
				open: { kind: 'open' },
				visible: { kind: 'visible' },
				hidden: { kind: 'none' },
				missing: { kind: 'selected' },
			},
		});

		expect(
			mapReviewDemandStimulusToIntents({
				stimulus: { kind: 'reviewDescriptorInvalidated', descriptorRef: selectedRef },
				readContext,
			})[0]?.lane,
		).toBe('foreground');
		expect(
			mapReviewDemandStimulusToIntents({
				stimulus: { kind: 'reviewDescriptorInvalidated', descriptorRef: openRef },
				readContext,
			})[0]?.lane,
		).toBe('active');
		expect(
			mapReviewDemandStimulusToIntents({
				stimulus: { kind: 'reviewDescriptorInvalidated', descriptorRef: visibleRef },
				readContext,
			})[0]?.lane,
		).toBe('visible');
		expect(
			mapReviewDemandStimulusToIntents({
				stimulus: { kind: 'reviewDescriptorInvalidated', descriptorRef: hiddenRef },
				readContext,
			}),
		).toEqual([]);
		expect(
			mapReviewDemandStimulusToIntents({
				stimulus: { kind: 'reviewDescriptorInvalidated', descriptorRef: missingRef },
				readContext,
			}),
		).toEqual([]);
	});

	test('maps viewport and hover stimuli without app-specific lanes', () => {
		const visibleRef = makeDescriptorRef('visible');
		const hoverRef = makeDescriptorRef('hover');
		const readContext = makeReadContext({
			descriptorStateById: {
				visible: {
					kind: 'valid',
					freshnessKey: 'visible:rev-1',
					needsBodyOrWindow: true,
				},
				hover: {
					kind: 'valid',
					freshnessKey: 'hover:rev-1',
					needsBodyOrWindow: true,
				},
			},
			viewInterestById: {
				visible: { kind: 'visible' },
				hover: { kind: 'speculative' },
			},
		});

		expect(
			mapReviewDemandStimulusToIntents({
				stimulus: { kind: 'reviewViewportChanged', descriptorRefs: [visibleRef] },
				readContext,
			})[0]?.lane,
		).toBe('visible');
		expect(
			mapReviewDemandStimulusToIntents({
				stimulus: { kind: 'reviewHoverChanged', descriptorRef: hoverRef },
				readContext,
			})[0]?.lane,
		).toBe('speculative');
		expect(
			mapReviewDemandStimulusToIntents({
				stimulus: { kind: 'reviewHoverChanged', descriptorRef: null },
				readContext,
			}),
		).toEqual([]);
	});
});

interface MakeReadContextProps {
	readonly descriptorState?: BridgeDescriptorDemandState;
	readonly descriptorStateById?: Readonly<Record<string, BridgeDescriptorDemandState>>;
	readonly viewInterest?: BridgeViewInterest;
	readonly viewInterestById?: Readonly<Record<string, BridgeViewInterest>>;
}

function makeReadContext(
	props: MakeReadContextProps,
): Parameters<typeof mapReviewDemandStimulusToIntents>[0]['readContext'] {
	return {
		getDescriptorState: (ref: BridgeDescriptorRef): BridgeDescriptorDemandState => {
			return (
				props.descriptorStateById?.[ref.descriptorId] ??
				props.descriptorState ?? { kind: 'missing' }
			);
		},
		getViewInterest: (ref: BridgeDescriptorRef): BridgeViewInterest => {
			return props.viewInterestById?.[ref.descriptorId] ?? props.viewInterest ?? { kind: 'none' };
		},
		buildDemandKeys: (ref: BridgeDescriptorRef) => ({
			orderingKey: `order:${ref.descriptorId}`,
			dedupeKey: `dedupe:${ref.descriptorId}`,
			freshnessKey: `fresh:${ref.descriptorId}`,
			cancellationGroup: `cancel:${ref.descriptorId}`,
		}),
	};
}

function makeDescriptorRef(descriptorId: string): BridgeDescriptorRef {
	return {
		descriptorId,
		expectedProtocol: 'review',
		expectedResourceKind: 'content',
		expectedIdentity: {
			paneId: 'pane-1',
			protocol: 'review',
			sourceId: 'source-1',
			packageId: 'package-1',
			generation: 1,
			revision: 1,
		},
	};
}
