import { describe, expect, test } from 'vitest';

import { bridgeReviewPackageSchema } from '../foundation/review-package/bridge-review-package-schema.js';
import { makeBridgeViewerBrowserFixture } from '../review-viewer/test-support/bridge-viewer-mocked-backend-fixture.js';
import {
	bridgeAppDevFixtureOptionsSchema,
	parseBridgeAppDevFixtureOptions,
	reviewPackageForBridgeAppDevFixtureScenario,
	selectedPathForBridgeAppDevFixtureScenario,
} from './bridge-app-dev-fixture.js';

describe('bridge app dev fixture options', () => {
	test('defaults to the large fixture with worker-backed rendering enabled', () => {
		const options = parseBridgeAppDevFixtureOptions(new URLSearchParams());

		expect(options).toEqual({
			deliveryMode: 'full-load',
			fixtureClass: 'large-diffshub',
			latencyProfile: 'zero',
			navigationIntent: {
				commandId: 'dev:fixture:large-diffshub:review',
				commandKind: 'activateContext',
				surface: 'review',
			},
			scenario: 'default',
			workersEnabled: true,
		});
	});

	test('parses typed query parameters without widening to arbitrary values', () => {
		const options = parseBridgeAppDevFixtureOptions(
			new URLSearchParams(
				'fixture=medium-agentstudio&delivery=streaming-append&latency=slowBounded&workers=off&scenario=markdown',
			),
		);

		expect(options).toEqual({
			deliveryMode: 'streaming-append',
			fixtureClass: 'medium-agentstudio',
			latencyProfile: 'slowBounded',
			navigationIntent: {
				commandId: 'dev:fixture:medium-agentstudio:review',
				commandKind: 'activateContext',
				surface: 'review',
			},
			scenario: 'markdown',
			workersEnabled: false,
		});
	});

	test('rejects unknown fixtures instead of loading arbitrary sources', () => {
		expect(() =>
			parseBridgeAppDevFixtureOptions(new URLSearchParams('fixture=file:///tmp/repo')),
		).toThrow(/Invalid BridgeWeb dev fixture query/);
	});

	test('allows named worktree scenarios without treating them as mocked fixture scenarios', () => {
		const options = parseBridgeAppDevFixtureOptions(
			new URLSearchParams('fixture=worktree&scenario=current-worktree&workers=on'),
		);

		expect(options).toEqual({
			deliveryMode: 'full-load',
			fixtureClass: 'worktree',
			latencyProfile: 'zero',
			navigationIntent: {
				commandId: 'dev:worktree:files',
				commandKind: 'activateContext',
				surface: 'file',
			},
			scenario: 'default',
			workersEnabled: true,
		});
	});

	test('maps worktree review dev URLs to review context instead of the file viewer', () => {
		const options = parseBridgeAppDevFixtureOptions(
			new URLSearchParams('fixture=worktree&viewer=review&scenario=current-worktree&workers=on'),
		);

		expect(options.navigationIntent).toEqual({
			commandId: 'dev:worktree:review',
			commandKind: 'activateContext',
			surface: 'review',
		});
	});

	test('maps review file presentation dev URLs to a typed file target', () => {
		const options = parseBridgeAppDevFixtureOptions(
			new URLSearchParams(
				'fixture=worktree&viewer=review&presentation=file&path=BridgeWeb/src/app/bridge-app.tsx&version=current',
			),
		);

		expect(options.navigationIntent).toEqual({
			commandId: 'dev:worktree:review:target',
			commandKind: 'activateTarget',
			surface: 'review',
			target: {
				path: 'BridgeWeb/src/app/bridge-app.tsx',
				targetKind: 'review',
				version: 'current',
			},
		});
	});

	test('maps review file presentation dev URLs with review item identity', () => {
		const options = parseBridgeAppDevFixtureOptions(
			new URLSearchParams(
				'fixture=worktree&viewer=review&presentation=file&path=BridgeWeb/src/app/bridge-app.tsx&reviewItemId=worktree-review-123&version=current',
			),
		);

		expect(options.navigationIntent).toEqual({
			commandId: 'dev:worktree:review:target',
			commandKind: 'activateTarget',
			surface: 'review',
			target: {
				path: 'BridgeWeb/src/app/bridge-app.tsx',
				reviewItemId: 'worktree-review-123',
				targetKind: 'review',
				version: 'current',
			},
		});
	});

	test('rejects malformed worktree navigation query parameters', () => {
		expect(() =>
			parseBridgeAppDevFixtureOptions(new URLSearchParams('fixture=worktree&viewer=diffs')),
		).toThrow(/Invalid BridgeWeb dev fixture query/);
		expect(() =>
			parseBridgeAppDevFixtureOptions(new URLSearchParams('fixture=worktree&presentation=rich')),
		).toThrow(/Invalid BridgeWeb dev fixture query/);
		expect(() =>
			parseBridgeAppDevFixtureOptions(
				new URLSearchParams('fixture=worktree&viewer=review&presentation=file&path=README.md'),
			),
		).toThrow(/Invalid BridgeWeb dev fixture query/);
	});

	test('keeps the zod schema available as the canonical model', () => {
		expect(() =>
			bridgeAppDevFixtureOptionsSchema.parse({
				deliveryMode: 'full-load',
				fixtureClass: 'small-mixed',
				latencyProfile: 'small',
				navigationIntent: {
					commandId: 'dev:fixture:small-mixed:review',
					commandKind: 'activateContext',
					surface: 'review',
				},
				scenario: 'scroll',
				workersEnabled: true,
			}),
		).not.toThrow();
	});

	test('maps visual scenarios to fixture paths that the dev server must select', () => {
		const fixture = makeBridgeViewerBrowserFixture({ fixtureClass: 'large-diffshub' });

		expect(selectedPathForBridgeAppDevFixtureScenario({ fixture, scenario: 'default' })).toBeNull();
		expect(selectedPathForBridgeAppDevFixtureScenario({ fixture, scenario: 'markdown' })).toBe(
			fixture.expected.docsPath,
		);
		expect(selectedPathForBridgeAppDevFixtureScenario({ fixture, scenario: 'scroll' })).toBe(
			fixture.expected.largePath,
		);
	});

	test('moves the scenario target to the front of the dev package for initial selection', () => {
		const fixture = makeBridgeViewerBrowserFixture({ fixtureClass: 'large-diffshub' });

		const markdownPackage = reviewPackageForBridgeAppDevFixtureScenario({
			fixture,
			scenario: 'markdown',
		});
		const scrollPackage = reviewPackageForBridgeAppDevFixtureScenario({
			fixture,
			scenario: 'scroll',
		});

		expect(markdownPackage.orderedItemIds[0]).toBe('browser-docs-plan');
		expect(scrollPackage.orderedItemIds[0]).toBe('browser-large-diff');
		expect(bridgeReviewPackageSchema.safeParse(scrollPackage).success).toBe(true);
		expect(markdownPackage.orderedItemIds).toHaveLength(
			fixture.reviewPackage.orderedItemIds.length,
		);
		expect(new Set(markdownPackage.orderedItemIds)).toEqual(
			new Set(fixture.reviewPackage.orderedItemIds),
		);
	});
});
