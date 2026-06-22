import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import react from '@vitejs/plugin-react';
import { defineConfig } from 'vitest/config';

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
		globals: true,
		include: [
			'scripts/**/*.integration.test.ts',
			'scripts/**/*.unit.test.ts',
			'src/**/*.unit.test.ts',
			'src/**/*.unit.test.tsx',
			'src/**/*.integration.test.ts',
			'src/**/*.integration.test.tsx',
			'src/**/*.e2e.test.ts',
			'src/**/*.e2e.test.tsx',
		],
		exclude: ['**/node_modules/**', '**/dist/**'],
	},
});
