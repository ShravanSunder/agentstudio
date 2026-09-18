import { defineConfig } from 'vitest/config';

export default defineConfig({
	test: {
		environment: 'node',
		fileParallelism: false,
		include: [
			'src/**/*.e2e.test.ts',
			'src/**/*.e2e.test.tsx',
			'tests/e2e/**/*.e2e.test.ts',
			'tests/e2e/**/*.e2e.test.tsx',
		],
		// The runner's hang bound, and the only clock these journeys are allowed. It is not a budget:
		// a real-backend journey on a 3-vCPU runner may legitimately be slow, so tests wait on owner-
		// published state rather than on time, and this only stops a wedged run from hanging forever.
		testTimeout: 600_000,
		hookTimeout: 60_000,
	},
});
