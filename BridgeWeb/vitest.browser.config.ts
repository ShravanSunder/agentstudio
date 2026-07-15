import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import react from '@vitejs/plugin-react';
// oxlint-disable-next-line import/no-empty-named-blocks, unicorn/require-module-specifiers -- Vitest provider import installs Browser project type augmentation.
import type {} from '@vitest/browser/providers/playwright';
import { defineConfig, type UserConfig } from 'vitest/config';

import { createBridgeSourceCellHarness } from './tests/bridge-viewer-source-cell-reporter.js';

const bridgeWebPackageRoot = dirname(fileURLToPath(import.meta.url));
const bridgeProductDevRoutesPath = `${bridgeWebPackageRoot}/src/core/comm-worker/bridge-product-dev-routes.ts`;
const deterministicSourceCellTestEntry =
	'src/app/bridge-app-product-deterministic-fixture.browser.test.tsx';
const deterministicSourceCellHarness = createBridgeSourceCellHarness({
	packageRoot: bridgeWebPackageRoot,
	projectName: 'VB-deterministic-fixture',
	sourceKind: 'deterministicFixture',
	testEntry: deterministicSourceCellTestEntry,
});

const browserConfig = {
	enabled: true,
	provider: 'playwright',
	headless: true,
	instances: [
		{
			browser: 'chromium',
			launch: {
				channel: 'chrome',
			},
		},
	],
	api: {
		host: '127.0.0.1',
		port: 63325,
	},
	viewport: {
		width: 1728,
		height: 972,
	},
	fileParallelism: true,
	screenshotFailures: true,
	screenshotDirectory: '../tmp/bridgeweb-vitest-screenshots',
} satisfies NonNullable<NonNullable<UserConfig['test']>['browser']>;

export default defineConfig({
	plugins: [react()],
	resolve: {
		alias: {
			'@': `${bridgeWebPackageRoot}/src`,
		},
	},
	optimizeDeps: {
		include: ['@pierre/diffs/worker', 'react-dom/client', 'zustand/vanilla'],
	},
	test: {
		globals: true,
		projects: [
			{
				define: {
					__BRIDGE_REAL_VITE_PRODUCT_TEST__: 'true',
				},
				plugins: [react(), deterministicSourceCellHarness.plugin],
				resolve: {
					alias: [
						{
							find: './bridge-product-routes.js',
							replacement: bridgeProductDevRoutesPath,
						},
						{ find: '@', replacement: `${bridgeWebPackageRoot}/src` },
					],
				},
				test: {
					name: 'VB-deterministic-fixture',
					setupFiles: ['./tests/vitest-browser-setup.ts'],
					browser: {
						...browserConfig,
						api: {
							host: '127.0.0.1',
							port: 63327,
						},
						commands: deterministicSourceCellHarness.browserCommands,
						fileParallelism: false,
					},
					testTimeout: 60_000,
					include: [deterministicSourceCellTestEntry],
					sequence: {
						shuffle: false,
					},
				},
			},
			{
				plugins: [react()],
				resolve: {
					alias: {
						'@': `${bridgeWebPackageRoot}/src`,
					},
				},
				test: {
					name: 'integration-browser',
					setupFiles: ['./tests/vitest-browser-setup.ts'],
					browser: browserConfig,
					testTimeout: 60_000,
					include: ['src/**/*.browser.test.ts', 'src/**/*.browser.test.tsx'],
					exclude: [
						'**/node_modules/**',
						'**/dist/**',
						'src/**/*.browser.benchmark.ts',
						'src/**/*.browser.benchmark.tsx',
					],
				},
			},
			{
				plugins: [react()],
				resolve: {
					alias: {
						'@': `${bridgeWebPackageRoot}/src`,
					},
				},
				test: {
					name: 'benchmarks-browser',
					setupFiles: ['./tests/vitest-browser-setup.ts'],
					browser: {
						...browserConfig,
						api: {
							host: '127.0.0.1',
							port: 63326,
						},
						fileParallelism: false,
					},
					benchmark: {
						include: ['src/**/*.browser.benchmark.ts', 'src/**/*.browser.benchmark.tsx'],
					},
					include: ['src/**/*.browser.benchmark.ts', 'src/**/*.browser.benchmark.tsx'],
					exclude: ['**/node_modules/**', '**/dist/**'],
					sequence: {
						shuffle: false,
					},
				},
			},
		],
	},
});
