import react from '@vitejs/plugin-react';
import { defineConfig, type UserConfig } from 'vitest/config';

const browserConfig = {
	enabled: true,
	provider: 'playwright',
	headless: true,
	instances: [{ browser: 'chromium' }],
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
	optimizeDeps: {
		include: ['react-dom/client'],
	},
	test: {
		globals: true,
		projects: [
			{
				plugins: [react()],
				test: {
					name: 'integration-browser',
					setupFiles: ['./tests/vitest-browser-setup.ts'],
					browser: browserConfig,
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
