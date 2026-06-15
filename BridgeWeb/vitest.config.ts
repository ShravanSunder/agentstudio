import react from '@vitejs/plugin-react';
import { defineConfig } from 'vitest/config';

export default defineConfig({
	plugins: [react()],
	test: {
		environment: 'node',
		globals: true,
		include: [
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
