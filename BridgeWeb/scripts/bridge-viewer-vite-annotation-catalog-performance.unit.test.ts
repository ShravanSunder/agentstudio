import { describe, expect, test } from 'vitest';

import {
	annotationCatalogLongTasksOverlappingMainStaging,
	type AnnotationCatalogLongTaskObservation,
	type AnnotationCatalogTransferTelemetryObservation,
} from '../tests/e2e/bridge-viewer-vite-annotation-catalog-performance.js';

describe('annotation catalog Long Task attribution', () => {
	test('keeps only tasks that overlap the exact local main-staging interval', () => {
		const observation = {
			entries: [
				longTask('before', 10, 20),
				longTask('overlaps-begin', 40, 20),
				longTask('inside', 100, 20),
				longTask('overlaps-commit', 190, 20),
				longTask('after', 201, 20),
			],
			phases: [],
		} satisfies AnnotationCatalogLongTaskObservation;
		const transfer = {
			mainBeginStartTimeMilliseconds: 50,
			mainCommitStartTimeMilliseconds: 200,
			maximumUnitByteCount: 128,
			operationCorrelationId: 'a'.repeat(64),
			presentationRevisionAfter: 2,
			presentationRevisionBefore: 1,
			windowCount: 2,
		} satisfies AnnotationCatalogTransferTelemetryObservation;

		expect(
			annotationCatalogLongTasksOverlappingMainStaging(observation, transfer).map(
				(entry) => entry.name,
			),
		).toEqual(['overlaps-begin', 'inside', 'overlaps-commit']);
	});
});

function longTask(
	name: string,
	startTimeMilliseconds: number,
	durationMilliseconds: number,
): AnnotationCatalogLongTaskObservation['entries'][number] {
	return { durationMilliseconds, name, startTimeMilliseconds };
}
