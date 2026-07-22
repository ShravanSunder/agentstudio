import { describe, expect, test } from 'vitest';

import {
	createTheme,
	pierreThemes,
	shikiThemes,
	themes,
} from './bridge-pierre-bundled-theme-registry.js';

describe('Bridge Pierre bundled theme registry', () => {
	test('keeps packaged BridgeWeb free of bundled Pierre and Shiki theme collections', () => {
		expect(pierreThemes.getThemes()).toEqual([]);
		expect(pierreThemes.getTheme('pierre-dark')).toBeUndefined();
		expect(shikiThemes.getThemes()).toEqual([]);
		expect(themes.getThemeNames()).toEqual([]);
	});

	test('preserves Pierre custom theme registration helper shape', async () => {
		const theme = {
			name: 'catppuccin-mocha',
			load: async (): Promise<Record<string, unknown>> => ({
				name: 'catppuccin-mocha',
				type: 'dark',
			}),
			colorScheme: 'dark',
			collection: 'agentstudio',
			displayName: 'Catppuccin Mocha',
		} as const;

		const descriptor = createTheme(theme);

		await expect(descriptor.load()).resolves.toEqual({
			name: 'catppuccin-mocha',
			type: 'dark',
		});
		expect(descriptor).toMatchObject({
			name: 'catppuccin-mocha',
			colorScheme: 'dark',
			collection: 'agentstudio',
			displayName: 'Catppuccin Mocha',
		});
	});
});
