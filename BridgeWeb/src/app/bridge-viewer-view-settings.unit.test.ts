import type { CodeViewOptions } from '@pierre/diffs';
import { describe, expect, test } from 'vitest';

import {
	createBridgeFilesViewSettingsDefaults,
	deriveBridgeFilesCodeViewOptions,
} from '../file-viewer/bridge-file-viewer-code-view-options.js';
import {
	createBridgeReviewViewSettingsDefaults,
	deriveBridgeReviewCodeViewOptions,
} from '../review-viewer/code-view/bridge-code-view-options.js';
import type { BridgeReviewChangeIndicators } from './bridge-viewer-view-settings.js';

const reviewIndicatorMappings: readonly (readonly [
	BridgeReviewChangeIndicators,
	'bars' | 'classic' | 'none',
])[] = [
	['bars', 'bars'],
	['symbols', 'classic'],
	['none', 'none'],
];

describe('BridgeViewer View Settings policy', () => {
	test('derives Files defaults from the supplied compatibility options', () => {
		// Arrange
		const compatibilityOptions = {
			disableLineNumbers: true,
			overflow: 'scroll',
		} satisfies CodeViewOptions<undefined>;

		// Act
		const defaults = createBridgeFilesViewSettingsDefaults(compatibilityOptions);

		// Assert
		expect(defaults).toEqual({ lineNumbers: false, wordWrap: false });
		expect(Object.isFrozen(defaults)).toBe(true);
	});

	test('derives Review defaults and translates Pierre classic indicators to visible symbols', () => {
		// Arrange
		const compatibilityOptions = {
			diffIndicators: 'classic',
			diffStyle: 'unified',
			disableBackground: true,
			disableLineNumbers: true,
			overflow: 'scroll',
		} satisfies CodeViewOptions<undefined>;

		// Act
		const defaults = createBridgeReviewViewSettingsDefaults(compatibilityOptions);

		// Assert
		expect(defaults).toEqual({
			changeBackgrounds: false,
			changeIndicators: 'symbols',
			diffLayout: 'unified',
			lineNumbers: false,
			wordWrap: false,
		});
		expect(Object.isFrozen(defaults)).toBe(true);
	});

	test('uses Pierre effective defaults when optional compatibility values are absent', () => {
		// Arrange
		const compatibilityOptions = {} satisfies CodeViewOptions<undefined>;

		// Act
		const filesDefaults = createBridgeFilesViewSettingsDefaults(compatibilityOptions);
		const reviewDefaults = createBridgeReviewViewSettingsDefaults(compatibilityOptions);

		// Assert
		expect(filesDefaults).toEqual({ lineNumbers: true, wordWrap: false });
		expect(reviewDefaults).toEqual({
			changeBackgrounds: true,
			changeIndicators: 'bars',
			diffLayout: 'split',
			lineNumbers: true,
			wordWrap: false,
		});
	});

	test('maps every Files setting without mutating or returning the base options', () => {
		// Arrange
		const compatibilityOptions = Object.freeze({
			disableFileHeader: true,
			disableLineNumbers: false,
			overflow: 'wrap',
			stickyHeaders: false,
		} satisfies CodeViewOptions<undefined>);
		const compatibilitySnapshot = { ...compatibilityOptions };

		// Act
		const derivedOptions = deriveBridgeFilesCodeViewOptions({
			compatibilityOptions,
			viewSettings: { lineNumbers: false, wordWrap: false },
		});

		// Assert
		expect(derivedOptions).not.toBe(compatibilityOptions);
		expect(derivedOptions).toEqual({
			disableFileHeader: true,
			disableLineNumbers: true,
			overflow: 'scroll',
			stickyHeaders: false,
		});
		expect(Object.isFrozen(derivedOptions)).toBe(true);
		expect(compatibilityOptions).toEqual(compatibilitySnapshot);
	});

	test.each(reviewIndicatorMappings)(
		'maps Review change indicators %s to Pierre %s',
		(changeIndicators, expectedDiffIndicators) => {
			// Arrange
			const compatibilityOptions = {
				diffIndicators: 'none',
			} satisfies CodeViewOptions<undefined>;

			// Act
			const derivedOptions = deriveBridgeReviewCodeViewOptions({
				compatibilityOptions,
				viewSettings: {
					changeBackgrounds: true,
					changeIndicators,
					diffLayout: 'split',
					lineNumbers: true,
					wordWrap: true,
				},
			});

			// Assert
			expect(derivedOptions.diffIndicators).toBe(expectedDiffIndicators);
		},
	);

	test('maps every Review setting while preserving unrelated options and the base value', () => {
		// Arrange
		const compatibilityOptions = Object.freeze({
			collapsedContextThreshold: 7,
			diffIndicators: 'bars',
			diffStyle: 'split',
			disableBackground: false,
			disableLineNumbers: false,
			overflow: 'wrap',
			stickyHeaders: true,
		} satisfies CodeViewOptions<undefined>);
		const compatibilitySnapshot = { ...compatibilityOptions };

		// Act
		const derivedOptions = deriveBridgeReviewCodeViewOptions({
			compatibilityOptions,
			viewSettings: {
				changeBackgrounds: false,
				changeIndicators: 'symbols',
				diffLayout: 'unified',
				lineNumbers: false,
				wordWrap: false,
			},
		});

		// Assert
		expect(derivedOptions).not.toBe(compatibilityOptions);
		expect(derivedOptions).toEqual({
			collapsedContextThreshold: 7,
			diffIndicators: 'classic',
			diffStyle: 'unified',
			disableBackground: true,
			disableLineNumbers: true,
			overflow: 'scroll',
			stickyHeaders: true,
		});
		expect(Object.isFrozen(derivedOptions)).toBe(true);
		expect(compatibilityOptions).toEqual(compatibilitySnapshot);
	});

	test('resetting from changed values re-derives each surface compatibility defaults', () => {
		// Arrange
		const compatibilityOptions = {
			diffIndicators: 'bars',
			diffStyle: 'split',
			disableBackground: false,
			disableLineNumbers: false,
			overflow: 'wrap',
		} satisfies CodeViewOptions<undefined>;

		// Act
		const resetFilesSettings = createBridgeFilesViewSettingsDefaults(compatibilityOptions);
		const resetReviewSettings = createBridgeReviewViewSettingsDefaults(compatibilityOptions);

		// Assert
		expect(resetFilesSettings).toEqual({ lineNumbers: true, wordWrap: true });
		expect(resetReviewSettings).toEqual({
			changeBackgrounds: true,
			changeIndicators: 'bars',
			diffLayout: 'split',
			lineNumbers: true,
			wordWrap: true,
		});
	});
});
