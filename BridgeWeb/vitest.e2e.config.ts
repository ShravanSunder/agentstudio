import { defineConfig } from 'vitest/config';

export default defineConfig({
	test: {
		environment: 'node',
		include: [
			'src/**/*.e2e.test.ts',
			'src/**/*.e2e.test.tsx',
			'tests/e2e/**/*.e2e.test.ts',
			'tests/e2e/**/*.e2e.test.tsx',
		],
		testTimeout: 180_000,
		hookTimeout: 60_000,
	},
});
