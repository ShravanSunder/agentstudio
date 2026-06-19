import { z } from 'zod';

import type {
	BridgeReviewPackage,
	BridgeReviewItemDescriptor,
} from '../foundation/review-package/bridge-review-package.js';
import type {
	BridgeViewerBrowserFixture,
	BridgeViewerBrowserFixtureClass,
	BridgeViewerMockedBackendDeliveryMode,
	BridgeViewerMockedBackendLatencyProfile,
} from '../review-viewer/test-support/bridge-viewer-mocked-backend.js';

export const bridgeAppDevFixtureClassSchema = z.enum([
	'small-mixed',
	'medium-agentstudio',
	'large-diffshub',
	'off',
]);

export type BridgeAppDevFixtureClass = z.infer<typeof bridgeAppDevFixtureClassSchema>;

export const bridgeAppDevFixtureDeliveryModeSchema = z.enum(['full-load', 'streaming-append']);

export type BridgeAppDevFixtureDeliveryMode = z.infer<typeof bridgeAppDevFixtureDeliveryModeSchema>;

export const bridgeAppDevFixtureLatencyProfileSchema = z.enum(['zero', 'small', 'slowBounded']);

export type BridgeAppDevFixtureLatencyProfile = z.infer<
	typeof bridgeAppDevFixtureLatencyProfileSchema
>;

export const bridgeAppDevFixtureScenarioSchema = z.enum([
	'default',
	'scroll',
	'markdown',
	'failure',
]);

export type BridgeAppDevFixtureScenario = z.infer<typeof bridgeAppDevFixtureScenarioSchema>;

export const bridgeAppDevFixtureWorkersModeSchema = z.enum(['on', 'off']);

export type BridgeAppDevFixtureWorkersMode = z.infer<typeof bridgeAppDevFixtureWorkersModeSchema>;

export const bridgeAppDevFixtureOptionsSchema = z
	.object({
		fixtureClass: bridgeAppDevFixtureClassSchema,
		deliveryMode: bridgeAppDevFixtureDeliveryModeSchema,
		latencyProfile: bridgeAppDevFixtureLatencyProfileSchema,
		scenario: bridgeAppDevFixtureScenarioSchema,
		workersEnabled: z.boolean(),
	})
	.strict();

export type BridgeAppDevFixtureOptions = z.infer<typeof bridgeAppDevFixtureOptionsSchema>;

export function parseBridgeAppDevFixtureOptions(
	searchParams: URLSearchParams,
): BridgeAppDevFixtureOptions {
	const parsed = bridgeAppDevFixtureOptionsSchema.safeParse({
		fixtureClass: searchParams.get('fixture') ?? 'large-diffshub',
		deliveryMode: searchParams.get('delivery') ?? 'full-load',
		latencyProfile: searchParams.get('latency') ?? 'zero',
		scenario: searchParams.get('scenario') ?? 'default',
		workersEnabled: parseWorkersEnabled(searchParams.get('workers') ?? 'on'),
	});

	if (!parsed.success) {
		throw new Error(`Invalid BridgeWeb dev fixture query: ${parsed.error.message}`);
	}

	return parsed.data;
}

export function fixtureClassForMockedBackend(
	fixtureClass: BridgeAppDevFixtureClass,
): BridgeViewerBrowserFixtureClass | null {
	if (fixtureClass === 'off') {
		return null;
	}
	return fixtureClass satisfies BridgeViewerBrowserFixtureClass;
}

export function deliveryModeForMockedBackend(
	deliveryMode: BridgeAppDevFixtureDeliveryMode,
): BridgeViewerMockedBackendDeliveryMode {
	return deliveryMode;
}

export function latencyProfileForMockedBackend(
	latencyProfile: BridgeAppDevFixtureLatencyProfile,
): BridgeViewerMockedBackendLatencyProfile {
	return latencyProfile;
}

export function selectedPathForBridgeAppDevFixtureScenario(props: {
	readonly fixture: BridgeViewerBrowserFixture;
	readonly scenario: BridgeAppDevFixtureScenario;
}): string | null {
	switch (props.scenario) {
		case 'default':
		case 'failure':
			return null;
		case 'markdown':
			return props.fixture.expected.docsPath;
		case 'scroll':
			return props.fixture.expected.largePath;
	}
	return null;
}

export function reviewPackageForBridgeAppDevFixtureScenario(props: {
	readonly fixture: BridgeViewerBrowserFixture;
	readonly scenario: BridgeAppDevFixtureScenario;
}): BridgeReviewPackage {
	const selectedPath = selectedPathForBridgeAppDevFixtureScenario(props);
	if (selectedPath === null) {
		return props.fixture.reviewPackage;
	}
	const selectedItem = Object.values(props.fixture.reviewPackage.itemsById).find(
		(item: BridgeReviewItemDescriptor): boolean =>
			item.headPath === selectedPath || item.basePath === selectedPath,
	);
	if (selectedItem === undefined) {
		return props.fixture.reviewPackage;
	}
	return {
		...props.fixture.reviewPackage,
		orderedItemIds: [
			selectedItem.itemId,
			...props.fixture.reviewPackage.orderedItemIds.filter(
				(itemId: string): boolean => itemId !== selectedItem.itemId,
			),
		],
	};
}

function parseWorkersEnabled(workersMode: string): boolean {
	const parsed = bridgeAppDevFixtureWorkersModeSchema.safeParse(workersMode);
	if (!parsed.success) {
		throw new Error(`Invalid BridgeWeb dev fixture query: workers=${workersMode}`);
	}
	return parsed.data === 'on';
}
