import react from '@vitejs/plugin-react';
import { defineConfig } from 'vitest/config';

import { scriptBenchmarkTestTimeoutMilliseconds } from './tests/vitest-hang-bounds.ts';

export default defineConfig({
	plugins: [react()],
	test: {
		environment: 'node',
		globals: true,
		include: ['scripts/**/*.benchmark.ts'],
		exclude: ['**/node_modules/**', '**/dist/**'],
		testTimeout: scriptBenchmarkTestTimeoutMilliseconds,
	},
});
