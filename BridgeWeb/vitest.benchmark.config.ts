import react from '@vitejs/plugin-react';
import { defineConfig } from 'vitest/config';

export default defineConfig({
	plugins: [react()],
	test: {
		environment: 'node',
		globals: true,
		include: ['scripts/**/*.benchmark.ts'],
		exclude: ['**/node_modules/**', '**/dist/**'],
	},
});
