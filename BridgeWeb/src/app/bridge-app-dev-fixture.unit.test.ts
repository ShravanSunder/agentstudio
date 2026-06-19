import { describe, expect, test } from 'vitest';

import { makeBridgeViewerBrowserFixture } from '../review-viewer/test-support/bridge-viewer-mocked-backend.js';
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
			scenario: 'markdown',
			workersEnabled: false,
		});
	});

	test('rejects unknown fixtures instead of loading arbitrary sources', () => {
		expect(() =>
			parseBridgeAppDevFixtureOptions(new URLSearchParams('fixture=file:///tmp/repo')),
		).toThrow(/Invalid BridgeWeb dev fixture query/);
	});

	test('keeps the zod schema available as the canonical model', () => {
		expect(() =>
			bridgeAppDevFixtureOptionsSchema.parse({
				deliveryMode: 'full-load',
				fixtureClass: 'small-mixed',
				latencyProfile: 'small',
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
		expect(markdownPackage.orderedItemIds).toHaveLength(
			fixture.reviewPackage.orderedItemIds.length,
		);
		expect(new Set(markdownPackage.orderedItemIds)).toEqual(
			new Set(fixture.reviewPackage.orderedItemIds),
		);
	});
});
