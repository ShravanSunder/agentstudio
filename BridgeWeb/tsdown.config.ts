import { defineConfig } from 'tsdown';

export default defineConfig({
	entry: {
		'bridge-app': './src/app/bridge-app-bootstrap.tsx',
		'review-projection-worker': './src/review-viewer/workers/rpc/review-projection-worker-entry.ts',
	},
	outDir: '../Sources/AgentStudio/Resources/BridgeWeb/app/assets',
	platform: 'browser',
	format: 'esm',
	target: 'es2022',
	dts: false,
	sourcemap: false,
	minify: true,
	clean: false,
	hash: true,
	report: true,
	deps: {
		alwaysBundle: [/./],
		onlyBundle: false,
	},
});
