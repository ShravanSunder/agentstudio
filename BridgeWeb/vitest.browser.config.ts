import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import react from '@vitejs/plugin-react';
import { playwright } from '@vitest/browser-playwright';
import { defineConfig, type TestUserConfig } from 'vitest/config';

const bridgeWebPackageRoot = dirname(fileURLToPath(import.meta.url));
const repositoryTemporaryRoot = resolve(bridgeWebPackageRoot, '..', 'tmp');

const browserOptimizedDependencies = [
	'@base-ui/react/combobox',
	'@pierre/diffs/worker',
	'@shikijs/markdown-exit',
	'markdown-exit',
	'react-dom/client',
	'shiki/core',
	'shiki/engine/javascript',
	'shiki/langs/css.mjs',
	'shiki/langs/diff.mjs',
	'shiki/langs/html.mjs',
	'shiki/langs/javascript.mjs',
	'shiki/langs/json.mjs',
	'shiki/langs/jsonc.mjs',
	'shiki/langs/md.mjs',
	'shiki/langs/shellscript.mjs',
	'shiki/langs/swift.mjs',
	'shiki/langs/tsx.mjs',
	'shiki/langs/typescript.mjs',
	'shiki/langs/yaml.mjs',
	'shiki/themes/github-dark.mjs',
];

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
	screenshotDirectory: resolve(repositoryTemporaryRoot, 'bridgeweb-vitest-screenshots'),
} satisfies NonNullable<TestUserConfig['browser']>;

export default defineConfig({
	plugins: [react()],
	resolve: {
		alias: {
			'@': `${bridgeWebPackageRoot}/src`,
		},
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
				optimizeDeps: {
					include: [...browserOptimizedDependencies],
				},
				server: {
					fs: {
						allow: [bridgeWebPackageRoot, repositoryTemporaryRoot],
					},
				},
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
				optimizeDeps: {
					include: [...browserOptimizedDependencies],
				},
				server: {
					fs: {
						allow: [bridgeWebPackageRoot, repositoryTemporaryRoot],
					},
				},
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
