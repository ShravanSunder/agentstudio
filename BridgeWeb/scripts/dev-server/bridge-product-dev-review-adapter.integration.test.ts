import { fileURLToPath } from 'node:url';

import { describe, expect, test } from 'vitest';

import { encodeBridgeProductMetadataFrame } from '../../src/core/comm-worker/bridge-product-metadata-frame-codec.js';
import type { BridgeProductMetadataFrame } from '../../src/core/comm-worker/bridge-product-session-contracts.js';
import { BridgeProductDevReviewAdapter } from './bridge-product-dev-review-adapter.js';
import { resolveBridgeWorktreeDevProviderConfig } from './bridge-worktree-dev-provider.js';

const bridgeWebPackageRoot = fileURLToPath(new URL('../..', import.meta.url));
const liveWorktreeAdapterTestTimeoutMilliseconds = 15_000;
const maximumCarrierIdentifier = 'x'.repeat(128);
const maximumCarrierSequence = Number.MAX_SAFE_INTEGER;

describe('Bridge product dev Review adapter live worktree integration', () => {
	test(
		'constructs a contract-valid bounded metadata snapshot for the configured worktree',
		async () => {
			// Arrange
			const config = await resolveBridgeWorktreeDevProviderConfig({
				env: process.env,
				packageRoot: bridgeWebPackageRoot,
				requestUrl: null,
			});
			const adapter = new BridgeProductDevReviewAdapter(config);

			// Act
			const source = await adapter.loadSource();
			const encodedFrames = source.events.map((event, eventIndex) =>
				encodeBridgeProductMetadataFrame({
					cursor: source.cursor,
					data: { event, subscriptionKind: 'review.metadata' },
					interestRevision: maximumCarrierSequence,
					interestSha256: '0'.repeat(64),
					kind: 'subscription.data',
					metadataStreamId: maximumCarrierIdentifier,
					paneSessionId: maximumCarrierIdentifier,
					sourceGeneration: source.generation,
					streamSequence: maximumCarrierSequence - eventIndex,
					subscriptionId: maximumCarrierIdentifier,
					subscriptionKind: 'review.metadata',
					subscriptionSequence: maximumCarrierSequence - eventIndex,
					wireVersion: 2,
					workerDerivationEpoch: maximumCarrierSequence,
					workerInstanceId: maximumCarrierIdentifier,
				} satisfies BridgeProductMetadataFrame),
			);

			// Assert
			expect(source.events[0]).toMatchObject({
				eventKind: 'review.sourceAccepted',
				generation: source.generation,
				packageId: source.packageId,
				revision: source.revision,
				sourceIdentity: source.sourceIdentity,
			});
			expect(source.events.some((event) => event.eventKind === 'review.snapshot')).toBe(true);
			const metadataEvents = source.events.filter(
				(event) => event.eventKind === 'review.snapshot' || event.eventKind === 'review.window',
			);
			const metadataItems = metadataEvents.flatMap((event) => event.itemMetadata);
			const extentFacts = metadataEvents.flatMap((event) => event.extentFacts);
			const treeRows = metadataEvents.flatMap((event) => event.treeRows);
			const snapshotEvent = metadataEvents.find((event) => event.eventKind === 'review.snapshot');
			expect(snapshotEvent?.query.grouping).toEqual({ kind: 'folder', label: 'Folders' });
			expect(treeRows).toHaveLength(metadataItems.length);
			expect(
				treeRows.every((row) => row.depth === Math.max(row.path.split('/').length - 1, 0)),
			).toBe(true);
			expect(metadataItems.every((item) => item.contentRoles.length > 0)).toBe(true);
			expect(
				extentFacts,
				'git numstat additions/deletions are delta counts, not total base/head extents; the dev adapter must omit unknown extents so worker content preparation derives exact line counts from fetched roles.',
			).toEqual([]);
			expect(
				source.events.some(
					(event) =>
						(event.eventKind === 'review.snapshot' || event.eventKind === 'review.window') &&
						event.itemWindow.finalWindow &&
						event.treeWindow.finalWindow,
				),
			).toBe(true);
			expect(encodedFrames).toHaveLength(source.events.length);
		},
		liveWorktreeAdapterTestTimeoutMilliseconds,
	);
});
