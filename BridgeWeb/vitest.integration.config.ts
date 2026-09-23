import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import react from '@vitejs/plugin-react';
import { defineConfig } from 'vitest/config';

import { reactActWarningGuardScope } from './tests/console-error-guard-scope.ts';
import { nodeIntegrationTestTimeoutMilliseconds } from './tests/vitest-hang-bounds.ts';

const bridgeWebPackageRoot = dirname(fileURLToPath(import.meta.url));

export default defineConfig({
	plugins: [react()],
	resolve: {
		alias: {
			'@': `${bridgeWebPackageRoot}/src`,
		},
	},
	test: {
		environment: 'node',
		// Integration files share one Swift product-session authority and process-wide
		// backend-origin configuration; run them serially to preserve ownership.
		fileParallelism: false,
		globals: true,
		include: [
			'scripts/**/*.integration.test.ts',
			'src/**/*.integration.test.ts',
			'src/**/*.integration.test.tsx',
			'tests/**/*.integration.test.ts',
		],
		provide: reactActWarningGuardScope,
		setupFiles: ['./tests/console-error-guard.ts'],
		testTimeout: nodeIntegrationTestTimeoutMilliseconds,
		exclude: ['**/node_modules/**', '**/dist/**'],
	},
});
