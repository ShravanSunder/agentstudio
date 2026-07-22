import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import react from '@vitejs/plugin-react';
import { playwright } from '@vitest/browser-playwright';
import { defineConfig, type TestUserConfig } from 'vitest/config';

const bridgeWebPackageRoot = dirname(fileURLToPath(import.meta.url));

const browserConfig = {
	enabled: true,
	provider: playwright({
		launchOptions: { channel: 'chrome' },
	}),
	headless: true,
	instances: [{ browser: 'chromium', name: 'integration-chromium' }],
	api: {
		host: '127.0.0.1',
		port: 63325,
	},
	viewport: {
		width: 1728,
		height: 972,
	},
	screenshotFailures: true,
	screenshotDirectory: '../tmp/bridgeweb-vitest-screenshots',
} satisfies NonNullable<TestUserConfig['browser']>;

export default defineConfig({
	plugins: [react()],
	resolve: {
		alias: {
			'@': `${bridgeWebPackageRoot}/src`,
		},
	},
	optimizeDeps: {
		include: ['@pierre/diffs/worker', 'react-dom/client'],
	},
	test: {
		globals: true,
		tags: [
			{
				description: 'Scale-bound browser workloads run outside the per-commit correctness lane.',
				name: 'stress',
			},
		],
		projects: [
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
						instances: [{ browser: 'chromium', name: 'benchmark-chromium' }],
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
