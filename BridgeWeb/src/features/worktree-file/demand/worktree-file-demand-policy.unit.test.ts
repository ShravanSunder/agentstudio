import { describe, expect, test } from 'vitest';

import type {
	BridgeDescriptorDemandState,
	BridgeViewInterest,
} from '../../../core/models/bridge-demand-models.js';
import type { BridgeDescriptorRef } from '../../../core/models/bridge-resource-descriptor.js';
import { mapWorktreeFileDemandStimulusToIntents } from './worktree-file-demand-policy.js';

describe('worktree file demand policy', () => {
	test('maps selected files and explicit refresh to foreground demand', () => {
		const descriptorRef = makeDescriptorRef('file-content-1', 'worktree.fileContent');
		const readContext = makeReadContext({
			descriptorState: {
				kind: 'valid',
				freshnessKey: 'file-content-1:gen-1',
				needsBodyOrWindow: true,
			},
			viewInterest: { kind: 'selected' },
		});

		expect(
			mapWorktreeFileDemandStimulusToIntents({
				stimulus: { kind: 'fileSelected', descriptorRef },
				readContext,
			})[0]?.lane,
		).toBe('foreground');
		expect(
			mapWorktreeFileDemandStimulusToIntents({
				stimulus: { kind: 'explicitRefresh', descriptorRef },
				readContext,
			})[0]?.lane,
		).toBe('foreground');
	});

	test('marks open invalidation stale without emitting content demand', () => {
		const descriptorRef = makeDescriptorRef('file-content-1', 'worktree.fileContent');
		const readContext = makeReadContext({
			descriptorState: {
				kind: 'stale',
				freshnessKey: 'file-content-1:gen-2',
				needsBodyOrWindow: true,
			},
			viewInterest: { kind: 'open' },
		});

		expect(
			mapWorktreeFileDemandStimulusToIntents({
				stimulus: { kind: 'openFileInvalidated', descriptorRef },
				readContext,
			}),
		).toEqual([]);
	});

	test('maps tree viewport and expansion windows to generic visible and nearby lanes', () => {
		const visibleRef = makeDescriptorRef('tree-window-visible', 'worktree.treeWindow');
		const nearbyRef = makeDescriptorRef('tree-window-nearby', 'worktree.treeWindow');
		const readContext = makeReadContext({
			descriptorStateById: {
				'tree-window-visible': {
					kind: 'valid',
					freshnessKey: 'visible:gen-1',
					needsBodyOrWindow: true,
				},
				'tree-window-nearby': {
					kind: 'valid',
					freshnessKey: 'nearby:gen-1',
					needsBodyOrWindow: true,
				},
			},
			viewInterestById: {
				'tree-window-visible': { kind: 'visible' },
				'tree-window-nearby': { kind: 'nearby' },
			},
		});

		expect(
			mapWorktreeFileDemandStimulusToIntents({
				stimulus: { kind: 'treeViewportChanged', descriptorRefs: [visibleRef] },
				readContext,
			})[0]?.lane,
		).toBe('visible');
		expect(
			mapWorktreeFileDemandStimulusToIntents({
				stimulus: {
					kind: 'treeExpanded',
					descriptorRef: visibleRef,
					nearbyDescriptorRefs: [nearbyRef],
				},
				readContext,
			}).map((intent) => intent.lane),
		).toEqual(['visible', 'nearby']);
	});

	test('maps recently updated files to nearby or speculative preloads without foreground demand', () => {
		const nearbyRef = makeDescriptorRef('updated-nearby', 'worktree.fileContent');
		const remoteRef = makeDescriptorRef('updated-remote', 'worktree.fileContent');
		const readContext = makeReadContext({
			descriptorStateById: {
				'updated-nearby': {
					kind: 'valid',
					freshnessKey: 'updated-nearby:gen-1',
					needsBodyOrWindow: true,
				},
				'updated-remote': {
					kind: 'valid',
					freshnessKey: 'updated-remote:gen-1',
					needsBodyOrWindow: true,
				},
			},
		});

		const lanes = [
			...mapWorktreeFileDemandStimulusToIntents({
				stimulus: {
					kind: 'recentlyUpdatedFile',
					descriptorRef: nearbyRef,
					proximity: 'nearby',
					sourceIdentity: 'source-1',
				},
				readContext,
			}),
			...mapWorktreeFileDemandStimulusToIntents({
				stimulus: {
					kind: 'recentlyUpdatedFile',
					descriptorRef: remoteRef,
					proximity: 'remote',
					sourceIdentity: 'source-1',
				},
				readContext,
			}),
		].map((intent) => intent.lane);

		expect(lanes).toEqual(['nearby', 'speculative']);
		expect(lanes).not.toContain('foreground');
	});

	test('drops source reset and missing descriptors without emitting demand', () => {
		const descriptorRef = makeDescriptorRef('missing', 'worktree.fileContent');
		const readContext = makeReadContext({
			descriptorState: { kind: 'missing' },
			viewInterest: { kind: 'selected' },
		});

		expect(
			mapWorktreeFileDemandStimulusToIntents({
				stimulus: { kind: 'sourceReset', sourceIdentity: 'source-1' },
				readContext,
			}),
		).toEqual([]);
		expect(
			mapWorktreeFileDemandStimulusToIntents({
				stimulus: { kind: 'fileSelected', descriptorRef },
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
): Parameters<typeof mapWorktreeFileDemandStimulusToIntents>[0]['readContext'] {
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

function makeDescriptorRef(descriptorId: string, resourceKind: string): BridgeDescriptorRef {
	return {
		descriptorId,
		expectedProtocol: 'worktree-file',
		expectedResourceKind: resourceKind,
		expectedIdentity: {
			paneId: 'pane-1',
			protocol: 'worktree-file',
			sourceId: 'source-1',
			generation: 1,
			streamId: 'worktree-file:pane-1',
		},
	};
}
