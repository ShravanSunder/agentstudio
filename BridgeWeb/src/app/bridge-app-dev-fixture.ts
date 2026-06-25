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
import {
	bridgeViewerFileVersionSchema,
	bridgeViewerNavigationCommandSchema,
	type BridgeViewerFileVersion,
	type BridgeViewerNavigationCommand,
} from './bridge-viewer-navigation-models.js';

export const bridgeAppDevFixtureClassSchema = z.enum([
	'small-mixed',
	'medium-agentstudio',
	'large-diffshub',
	'worktree',
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

export const bridgeAppDevViewerModeSchema = z.enum(['file', 'review']);

export type BridgeAppDevViewerMode = z.infer<typeof bridgeAppDevViewerModeSchema>;

export const bridgeAppDevPresentationModeSchema = z.enum(['diff', 'file']);

export type BridgeAppDevPresentationMode = z.infer<typeof bridgeAppDevPresentationModeSchema>;

export const bridgeAppDevFixtureOptionsSchema = z
	.object({
		fixtureClass: bridgeAppDevFixtureClassSchema,
		deliveryMode: bridgeAppDevFixtureDeliveryModeSchema,
		latencyProfile: bridgeAppDevFixtureLatencyProfileSchema,
		navigationCommand: bridgeViewerNavigationCommandSchema,
		scenario: bridgeAppDevFixtureScenarioSchema,
		workersEnabled: z.boolean(),
	})
	.strict();

export type BridgeAppDevFixtureOptions = z.infer<typeof bridgeAppDevFixtureOptionsSchema>;

export function parseBridgeAppDevFixtureOptions(
	searchParams: URLSearchParams,
): BridgeAppDevFixtureOptions {
	const fixtureClass = parseRequiredQueryValue({
		name: 'fixture',
		rawValue: searchParams.get('fixture') ?? 'large-diffshub',
		schema: bridgeAppDevFixtureClassSchema,
	});
	const parsed = bridgeAppDevFixtureOptionsSchema.safeParse({
		fixtureClass,
		deliveryMode: searchParams.get('delivery') ?? 'full-load',
		latencyProfile: searchParams.get('latency') ?? 'zero',
		scenario: fixtureClass === 'worktree' ? 'default' : (searchParams.get('scenario') ?? 'default'),
		navigationCommand: bridgeViewerNavigationCommandForDevQuery({
			fixtureClass,
			searchParams,
		}),
		workersEnabled: parseWorkersEnabled(searchParams.get('workers') ?? 'on'),
	});

	if (!parsed.success) {
		throw new Error(`Invalid BridgeWeb dev fixture query: ${parsed.error.message}`);
	}

	return parsed.data;
}

export const bridgeAppDevWorktreeSourceId = 'dev-worktree-source';
export const bridgeAppDevWorktreeReviewSourceId = 'dev-current-worktree-review';
export const bridgeAppDevWorktreeReviewComparisonId = 'dev-current-worktree-comparison';

function bridgeViewerNavigationCommandForDevQuery(props: {
	readonly fixtureClass: BridgeAppDevFixtureClass;
	readonly searchParams: URLSearchParams;
}): BridgeViewerNavigationCommand {
	if (props.fixtureClass !== 'worktree') {
		return bridgeViewerNavigationCommandSchema.parse({
			commandId: `dev:fixture:${props.fixtureClass}:review`,
			commandKind: 'initialize',
			context: 'review',
			restoreMemory: true,
			source: {
				sourceKind: 'fixture',
				sourceId: props.fixtureClass,
			},
		});
	}

	const viewerMode = parseOptionalQueryValue<BridgeAppDevViewerMode>({
		defaultValue: 'file',
		name: 'viewer',
		rawValue: props.searchParams.get('viewer'),
		schema: bridgeAppDevViewerModeSchema,
	});
	const presentationMode = parseOptionalQueryValue<BridgeAppDevPresentationMode>({
		defaultValue: 'diff',
		name: 'presentation',
		rawValue: props.searchParams.get('presentation'),
		schema: bridgeAppDevPresentationModeSchema,
	});
	const selectedPath = props.searchParams.get('path');
	const selectedVersion = parseOptionalFileVersion(props.searchParams.get('version'));

	if (viewerMode === 'file') {
		return bridgeViewerFileNavigationCommand({
			selectedPath,
			selectedVersion,
		});
	}

	return bridgeViewerReviewNavigationCommand({
		presentationMode,
		selectedPath,
		selectedVersion,
	});
}

function bridgeViewerFileNavigationCommand(props: {
	readonly selectedPath: string | null;
	readonly selectedVersion: BridgeViewerFileVersion | null;
}): BridgeViewerNavigationCommand {
	if (props.selectedPath === null) {
		return bridgeViewerNavigationCommandSchema.parse({
			commandId: 'dev:worktree:files',
			commandKind: 'initialize',
			context: 'files',
			restoreMemory: true,
			source: {
				sourceKind: 'worktree',
				sourceId: bridgeAppDevWorktreeSourceId,
			},
		});
	}

	return bridgeViewerNavigationCommandSchema.parse({
		commandId: `dev:worktree:files:file:${props.selectedPath}:${
			props.selectedVersion ?? 'current'
		}`,
		commandKind: 'initialize',
		context: 'files',
		restoreMemory: true,
		source: {
			sourceKind: 'worktree',
			sourceId: bridgeAppDevWorktreeSourceId,
		},
		target: {
			targetKind: 'file',
			fileRef: {
				sourceId: bridgeAppDevWorktreeSourceId,
				path: props.selectedPath,
			},
			version: props.selectedVersion ?? 'current',
		},
	});
}

function bridgeViewerReviewNavigationCommand(props: {
	readonly presentationMode: BridgeAppDevPresentationMode;
	readonly selectedPath: string | null;
	readonly selectedVersion: BridgeViewerFileVersion | null;
}): BridgeViewerNavigationCommand {
	if (props.presentationMode === 'file') {
		if (props.selectedPath === null || props.selectedVersion === null) {
			throw new Error(
				'Invalid BridgeWeb dev fixture query: presentation=file requires path and version',
			);
		}
		return bridgeViewerNavigationCommandSchema.parse({
			commandId: `dev:worktree:review:file:${props.selectedPath}:${props.selectedVersion}`,
			commandKind: 'initialize',
			context: 'review',
			restoreMemory: true,
			source: {
				sourceKind: 'reviewComparison',
				sourceId: bridgeAppDevWorktreeReviewSourceId,
				comparisonId: bridgeAppDevWorktreeReviewComparisonId,
			},
			target: {
				targetKind: 'file',
				comparisonId: bridgeAppDevWorktreeReviewComparisonId,
				fileRef: {
					sourceId: bridgeAppDevWorktreeReviewSourceId,
					path: props.selectedPath,
				},
				version: props.selectedVersion,
			},
		});
	}

	return bridgeViewerNavigationCommandSchema.parse({
		commandId: 'dev:worktree:review',
		commandKind: 'initialize',
		context: 'review',
		restoreMemory: true,
		source: {
			sourceKind: 'reviewComparison',
			sourceId: bridgeAppDevWorktreeReviewSourceId,
			comparisonId: bridgeAppDevWorktreeReviewComparisonId,
		},
	});
}

export function fixtureClassForMockedBackend(
	fixtureClass: BridgeAppDevFixtureClass,
): BridgeViewerBrowserFixtureClass | null {
	if (fixtureClass === 'off' || fixtureClass === 'worktree') {
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

function parseOptionalFileVersion(rawValue: string | null): BridgeViewerFileVersion | null {
	if (rawValue === null) {
		return null;
	}
	return parseRequiredQueryValue({
		name: 'version',
		rawValue,
		schema: bridgeViewerFileVersionSchema,
	});
}

function parseOptionalQueryValue<TValue>(props: {
	readonly defaultValue: TValue;
	readonly name: string;
	readonly rawValue: string | null;
	readonly schema: z.ZodType<TValue>;
}): TValue {
	if (props.rawValue === null) {
		return props.defaultValue;
	}
	return parseRequiredQueryValue({
		name: props.name,
		rawValue: props.rawValue,
		schema: props.schema,
	});
}

function parseRequiredQueryValue<TValue>(props: {
	readonly name: string;
	readonly rawValue: string;
	readonly schema: z.ZodType<TValue>;
}): TValue {
	const parsed = props.schema.safeParse(props.rawValue);
	if (!parsed.success) {
		throw new Error(`Invalid BridgeWeb dev fixture query: ${props.name}=${props.rawValue}`);
	}
	return parsed.data;
}
