import { describe, expect, test, vi } from 'vitest';

import type { ReviewMaterializerDelta } from '../features/review/materialization/review-materializer.js';
import type {
	ReviewMetadataDeltaFrame,
	ReviewMetadataOperation,
	ReviewMetadataSnapshotFrame,
	ReviewMetadataWindowFrame,
} from '../features/review/models/review-protocol-models.js';
import {
	buildReviewMetadataDeltaFrame,
	buildReviewMetadataSnapshotFrame,
	buildReviewMetadataWindowFrame,
} from '../features/review/protocol/review-metadata-frame-builder.js';
import { bridgeReviewPackageSchema } from '../foundation/review-package/bridge-review-package-schema.js';
import { makeBridgeReviewPackage } from '../foundation/review-package/bridge-review-package-test-support.js';
import type {
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../foundation/review-package/bridge-review-package.js';
import { makeBridgeReviewProjectionInput } from '../review-viewer/navigation/review-projection.js';
import { makeBrowserFillerItem } from '../review-viewer/test-support/bridge-viewer-mocked-backend-support.js';
import {
	applyReviewMetadataDeltaToReviewPackage,
	bridgeReviewPackageFromMetadataSnapshot,
	bridgeReviewPackageWithMetadataWindow,
} from './bridge-app-review-metadata-package.js';

type ReviewSnapshotMaterializerDelta = Extract<
	ReviewMaterializerDelta,
	{ readonly kind: 'metadataSnapshot' }
>;
type ReviewWindowMaterializerDelta = Extract<
	ReviewMaterializerDelta,
	{ readonly kind: 'metadataWindow' }
>;
type ReviewDeltaMaterializerDelta = Extract<
	ReviewMaterializerDelta,
	{ readonly kind: 'metadataDelta' }
>;

interface FrameMeasurement {
	readonly frameKind: 'snapshot' | 'window';
	readonly finalItemCount: number;
	readonly durationMilliseconds: number;
}

interface SequenceMeasurement {
	readonly itemCount: number;
	readonly windowCount: number;
	readonly cumulativeValidatedItems: number;
	readonly cumulativeMilliseconds: number;
	readonly snapshotMilliseconds: number;
	readonly averageWindowMilliseconds: number;
	readonly maxWindowMilliseconds: number;
	readonly finalPackage: BridgeReviewPackage;
}

interface DeltaMeasurement {
	readonly operationCount: number;
	readonly durationMilliseconds: number;
	readonly finalRevision: number;
}

const metadataWindowSize = 80;
const metadataScalingItemCounts = [500, 1_000, 2_500, 5_000] as const;
const benchmarkPaneId = 'metadata-scaling-pane';
const benchmarkStreamId = `review:${benchmarkPaneId}`;
const benchmarkSourceIdentity = 'metadata-scaling-source';

describe('Bridge review metadata package scaling probe', () => {
	test('snapshot plus metadata windows reports apply-path growth and zod parse share', () => {
		runWarmup();

		const normalSequences = metadataScalingItemCounts.map((itemCount) =>
			measureMetadataWindowApplicationSequence({
				itemCount,
				parseMode: 'zod',
			}),
		);
		const normalFiveThousandItemPackage = requiredSequence(normalSequences, 5_000).finalPackage;
		const normalDelta = measureThousandItemChurnDelta(normalFiveThousandItemPackage);

		const parseSpy = vi.spyOn(bridgeReviewPackageSchema, 'parse');
		parseSpy.mockImplementation(
			// oxlint-disable-next-line typescript/no-unsafe-type-assertion -- This probe intentionally stubs zod parse to identity so the apply path can be measured with validation removed.
			(input: unknown): BridgeReviewPackage => input as BridgeReviewPackage,
		);
		try {
			const parseBypassedSequences = metadataScalingItemCounts.map((itemCount) =>
				measureMetadataWindowApplicationSequence({
					itemCount,
					parseMode: 'identity',
				}),
			);
			const parseBypassedFiveThousandItemPackage = requiredSequence(
				parseBypassedSequences,
				5_000,
			).finalPackage;
			const parseBypassedDelta = measureThousandItemChurnDelta(
				parseBypassedFiveThousandItemPackage,
			);
			const report = makeScalingReport({
				normalDelta,
				normalSequences,
				parseBypassedDelta,
				parseBypassedSequences,
			});
			process.stdout.write(report);

			for (const itemCount of metadataScalingItemCounts) {
				const normalSequence = requiredSequence(normalSequences, itemCount);
				const parseBypassedSequence = requiredSequence(parseBypassedSequences, itemCount);
				expect(normalSequence.finalPackage.orderedItemIds).toHaveLength(itemCount);
				expect(parseBypassedSequence.finalPackage.orderedItemIds).toHaveLength(itemCount);
				expect(normalSequence.windowCount).toBe(
					Math.ceil((itemCount - metadataWindowSize) / metadataWindowSize),
				);
			}
			expect(normalDelta.operationCount).toBe(1_000);
			expect(parseBypassedDelta.operationCount).toBe(1_000);
			expect(normalDelta.finalRevision).toBe(normalFiveThousandItemPackage.revision + 1);
			expect(parseBypassedDelta.finalRevision).toBe(
				parseBypassedFiveThousandItemPackage.revision + 1,
			);
		} finally {
			parseSpy.mockRestore();
		}
	}, 120_000);
});

function runWarmup(): void {
	measureMetadataWindowApplicationSequence({ itemCount: 160, parseMode: 'zod' });
}

function measureMetadataWindowApplicationSequence(props: {
	readonly itemCount: number;
	readonly parseMode: 'zod' | 'identity';
}): SequenceMeasurement {
	const sourcePackage = makeSyntheticReviewPackage(props.itemCount);
	const frameMeasurements: FrameMeasurement[] = [];
	const snapshotItemIds = sourcePackage.orderedItemIds.slice(0, metadataWindowSize);
	const snapshotFrame = buildReviewMetadataSnapshotFrame({
		package: sourcePackage,
		paneId: benchmarkPaneId,
		sourceIdentity: benchmarkSourceIdentity,
		streamId: benchmarkStreamId,
		sequence: 0,
		selectedItemId: snapshotItemIds[0] ?? null,
		visibleItemIds: snapshotItemIds,
	});
	const snapshotMeasurement = measureDuration(() =>
		bridgeReviewPackageFromMetadataSnapshot(snapshotMaterializerDeltaFromFrame(snapshotFrame)),
	);
	let currentPackage = snapshotMeasurement.value;
	frameMeasurements.push({
		frameKind: 'snapshot',
		finalItemCount: currentPackage.orderedItemIds.length,
		durationMilliseconds: snapshotMeasurement.durationMilliseconds,
	});

	let sequence = 1;
	for (
		let offset = metadataWindowSize;
		offset < sourcePackage.orderedItemIds.length;
		offset += metadataWindowSize
	) {
		const itemIds = sourcePackage.orderedItemIds.slice(offset, offset + metadataWindowSize);
		const windowFrame = buildReviewMetadataWindowFrame({
			package: sourcePackage,
			paneId: benchmarkPaneId,
			sourceIdentity: benchmarkSourceIdentity,
			streamId: benchmarkStreamId,
			sequence,
			itemIds,
		});
		const windowMeasurement = measureDuration(() =>
			bridgeReviewPackageWithMetadataWindow({
				reviewPackage: currentPackage,
				windowFrame: windowMaterializerDeltaFromFrame(windowFrame),
			}),
		);
		currentPackage = windowMeasurement.value;
		frameMeasurements.push({
			frameKind: 'window',
			finalItemCount: currentPackage.orderedItemIds.length,
			durationMilliseconds: windowMeasurement.durationMilliseconds,
		});
		sequence += 1;
	}

	const windowMeasurements = frameMeasurements.filter(
		(measurement): measurement is FrameMeasurement => measurement.frameKind === 'window',
	);
	const cumulativeMilliseconds = sumBy(
		frameMeasurements,
		(measurement) => measurement.durationMilliseconds,
	);
	const averageWindowMilliseconds =
		windowMeasurements.length === 0
			? 0
			: sumBy(windowMeasurements, (measurement) => measurement.durationMilliseconds) /
				windowMeasurements.length;
	const maxWindowMilliseconds = Math.max(
		0,
		...windowMeasurements.map((measurement) => measurement.durationMilliseconds),
	);
	void props.parseMode;
	return {
		itemCount: props.itemCount,
		windowCount: windowMeasurements.length,
		cumulativeValidatedItems: sumBy(frameMeasurements, (measurement) => measurement.finalItemCount),
		cumulativeMilliseconds,
		snapshotMilliseconds: snapshotMeasurement.durationMilliseconds,
		averageWindowMilliseconds,
		maxWindowMilliseconds,
		finalPackage: currentPackage,
	};
}

function measureThousandItemChurnDelta(reviewPackage: BridgeReviewPackage): DeltaMeasurement {
	const projectionInput = makeBridgeReviewProjectionInput(reviewPackage);
	const churnOperations = projectionInput.orderedItems
		.slice(0, 1_000)
		.map((item): ReviewMetadataOperation => {
			const nextReviewState = item.reviewState === 'viewed' ? 'unreviewed' : 'viewed';
			return {
				kind: 'upsertItemMetadata',
				item: {
					...item,
					reviewState: nextReviewState,
				},
			};
		});
	const deltaFrame = buildReviewMetadataDeltaFrame({
		package: reviewPackage,
		paneId: benchmarkPaneId,
		sourceIdentity: benchmarkSourceIdentity,
		streamId: benchmarkStreamId,
		sequence: 9_000,
		fromRevision: reviewPackage.revision,
		toRevision: reviewPackage.revision + 1,
		operations: churnOperations,
	});
	const deltaMeasurement = measureDuration(() =>
		applyReviewMetadataDeltaToReviewPackage({
			reviewPackage,
			deltaFrame: deltaMaterializerDeltaFromFrame(deltaFrame),
		}),
	);
	const nextPackage = deltaMeasurement.value;
	if (nextPackage === null) {
		throw new Error('Expected thousand-item churn delta to apply');
	}
	return {
		operationCount: churnOperations.length,
		durationMilliseconds: deltaMeasurement.durationMilliseconds,
		finalRevision: nextPackage.revision,
	};
}

function makeSyntheticReviewPackage(itemCount: number): BridgeReviewPackage {
	const basePackage = makeBridgeReviewPackage();
	const items = Array.from({ length: itemCount }, (_unused, index) =>
		makeBrowserFillerItem({
			fixtureClass: 'large-diffshub',
			index,
		}),
	);
	const itemsById = Object.fromEntries(
		items.map((item): readonly [string, BridgeReviewItemDescriptor] => [item.itemId, item]),
	);
	return {
		...basePackage,
		packageId: 'metadata-scaling-package',
		reviewGeneration: 338,
		revision: 1,
		query: {
			...basePackage.query,
			queryId: benchmarkSourceIdentity,
		},
		orderedItemIds: items.map((item) => item.itemId),
		itemsById,
		summary: {
			filesChanged: itemCount,
			additions: sumBy(items, (item) => item.additions),
			deletions: sumBy(items, (item) => item.deletions),
			visibleFileCount: itemCount,
			hiddenFileCount: 0,
		},
	};
}

function snapshotMaterializerDeltaFromFrame(
	frame: ReviewMetadataSnapshotFrame,
): ReviewSnapshotMaterializerDelta {
	return {
		kind: 'metadataSnapshot',
		packageId: frame.comparison.packageId,
		sourceIdentity: frame.comparison.sourceIdentity,
		generation: frame.comparison.generation,
		revision: frame.comparison.revision,
		baseEndpoint: frame.comparison.baseEndpoint,
		headEndpoint: frame.comparison.headEndpoint,
		selectedItemId: frame.selectedItemId,
		visibleItemIds: frame.visibleItemIds,
		projectionInput: {
			packageId: frame.comparison.packageId,
			reviewGeneration: frame.comparison.generation,
			revision: frame.comparison.revision,
			orderedItems: frame.itemMetadata,
		},
		treeRows: frame.treeRows,
		extentFacts: frame.extentFacts,
		summary: frame.summary,
		registeredContentDescriptorRefs: [],
		contentDescriptors: frame.comparison.contentDescriptors ?? [],
		changesetCluster: frame.comparison.changesetCluster ?? null,
	};
}

function windowMaterializerDeltaFromFrame(
	frame: ReviewMetadataWindowFrame,
): ReviewWindowMaterializerDelta {
	return {
		kind: 'metadataWindow',
		packageId: frame.packageId,
		generation: frame.generation,
		revision: frame.revision,
		itemMetadata: frame.itemMetadata,
		treeRows: frame.treeRows,
		extentFacts: frame.extentFacts,
		summary: frame.summary,
		registeredContentDescriptorRefs: [],
		contentDescriptors: frame.contentDescriptors ?? [],
	};
}

function deltaMaterializerDeltaFromFrame(
	frame: ReviewMetadataDeltaFrame,
): ReviewDeltaMaterializerDelta {
	return {
		kind: 'metadataDelta',
		packageId: frame.packageId,
		fromRevision: frame.fromRevision,
		toRevision: frame.toRevision,
		operations: frame.operations,
		summary: frame.summary,
		registeredContentDescriptorRefs: [],
		contentDescriptors: frame.contentDescriptors ?? [],
	};
}

function measureDuration<TValue>(operation: () => TValue): {
	readonly value: TValue;
	readonly durationMilliseconds: number;
} {
	const startedAtMilliseconds = performance.now();
	const value = operation();
	return {
		value,
		durationMilliseconds: performance.now() - startedAtMilliseconds,
	};
}

function makeScalingReport(props: {
	readonly normalSequences: readonly SequenceMeasurement[];
	readonly parseBypassedSequences: readonly SequenceMeasurement[];
	readonly normalDelta: DeltaMeasurement;
	readonly parseBypassedDelta: DeltaMeasurement;
}): string {
	const normalSlope = logLogSlope(
		props.normalSequences.map((sequence) => ({
			x: sequence.itemCount,
			y: sequence.cumulativeMilliseconds,
		})),
	);
	const parseBypassedSlope = logLogSlope(
		props.parseBypassedSequences.map((sequence) => ({
			x: sequence.itemCount,
			y: sequence.cumulativeMilliseconds,
		})),
	);
	const lines = [
		'',
		'Bridge review metadata package scaling probe',
		'itemCount | windows | cumulativeValidatedItems | normalTotalMs | normalSnapshotMs | normalAvgWindowMs | normalMaxWindowMs | identityTotalMs | zodShareMs | zodSharePercent',
		...props.normalSequences.map((normalSequence) => {
			const parseBypassedSequence = requiredSequence(
				props.parseBypassedSequences,
				normalSequence.itemCount,
			);
			const zodShareMilliseconds =
				normalSequence.cumulativeMilliseconds - parseBypassedSequence.cumulativeMilliseconds;
			const zodSharePercent =
				normalSequence.cumulativeMilliseconds === 0
					? 0
					: (zodShareMilliseconds / normalSequence.cumulativeMilliseconds) * 100;
			return [
				normalSequence.itemCount,
				normalSequence.windowCount,
				normalSequence.cumulativeValidatedItems,
				formatMilliseconds(normalSequence.cumulativeMilliseconds),
				formatMilliseconds(normalSequence.snapshotMilliseconds),
				formatMilliseconds(normalSequence.averageWindowMilliseconds),
				formatMilliseconds(normalSequence.maxWindowMilliseconds),
				formatMilliseconds(parseBypassedSequence.cumulativeMilliseconds),
				formatMilliseconds(zodShareMilliseconds),
				formatPercent(zodSharePercent),
			].join(' | ');
		}),
		`growthExponent.normal=${normalSlope.toFixed(2)}`,
		`growthExponent.identityParse=${parseBypassedSlope.toFixed(2)}`,
		[
			'deltaChurn1000',
			`normalMs=${formatMilliseconds(props.normalDelta.durationMilliseconds)}`,
			`identityMs=${formatMilliseconds(props.parseBypassedDelta.durationMilliseconds)}`,
			`zodShareMs=${formatMilliseconds(
				props.normalDelta.durationMilliseconds - props.parseBypassedDelta.durationMilliseconds,
			)}`,
		].join(' | '),
		'',
	];
	return `${lines.join('\n')}\n`;
}

function requiredSequence(
	sequences: readonly SequenceMeasurement[],
	itemCount: number,
): SequenceMeasurement {
	const sequence = sequences.find((candidate) => candidate.itemCount === itemCount);
	if (sequence === undefined) {
		throw new Error(`Missing sequence measurement for ${itemCount} items`);
	}
	return sequence;
}

function logLogSlope(points: readonly { readonly x: number; readonly y: number }[]): number {
	const positivePoints = points.filter((point) => point.x > 0 && point.y > 0);
	const count = positivePoints.length;
	if (count < 2) {
		return Number.NaN;
	}
	const logXValues = positivePoints.map((point) => Math.log(point.x));
	const logYValues = positivePoints.map((point) => Math.log(point.y));
	const averageLogX = sumBy(logXValues, (value) => value) / count;
	const averageLogY = sumBy(logYValues, (value) => value) / count;
	const numerator = sumBy(
		logXValues,
		(logX, index) => (logX - averageLogX) * ((logYValues[index] ?? 0) - averageLogY),
	);
	const denominator = sumBy(logXValues, (logX) => (logX - averageLogX) ** 2);
	return denominator === 0 ? Number.NaN : numerator / denominator;
}

function sumBy<TValue>(
	values: readonly TValue[],
	project: (value: TValue, index: number) => number,
): number {
	return values.reduce((total, value, index) => total + project(value, index), 0);
}

function formatMilliseconds(value: number): string {
	return value.toFixed(2);
}

function formatPercent(value: number): string {
	return `${value.toFixed(1)}%`;
}
