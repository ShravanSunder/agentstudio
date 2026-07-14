import { fileURLToPath } from 'node:url';

import { defineConfig, type UserConfig } from 'tsdown';

const bridgePierreBundledThemeRegistryPath = fileURLToPath(
	new URL('./src/review-viewer/theme/bridge-pierre-bundled-theme-registry.ts', import.meta.url),
);
const bridgeShikiRuntimePath = fileURLToPath(
	new URL('./src/review-viewer/theme/bridge-shiki-runtime.ts', import.meta.url),
);

const sharedBridgeWebBuildConfig = {
	alias: {
		'@pierre/theming/themes': bridgePierreBundledThemeRegistryPath,
		shiki: bridgeShikiRuntimePath,
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
} satisfies UserConfig;

export default defineConfig([
	{
		...sharedBridgeWebBuildConfig,
		name: 'bridge-app',
		entry: {
			'bridge-app': './src/app/bridge-app-bootstrap.tsx',
		},
	},
	{
		...sharedBridgeWebBuildConfig,
		name: 'bridge-markdown-render-worker',
		entry: {
			'bridge-markdown-render-worker':
				'./src/review-viewer/workers/markdown/bridge-markdown-render-worker-entry.ts',
		},
		outputOptions: {
			codeSplitting: false,
		},
	},
	{
		...sharedBridgeWebBuildConfig,
		name: 'bridge-worker-fetch-probe-worker',
		entry: {
			'bridge-worker-fetch-probe-worker':
				'./src/app/diagnostics/bridge-worker-fetch-probe-worker-entry.ts',
		},
		outputOptions: {
			codeSplitting: false,
		},
	},
	{
		...sharedBridgeWebBuildConfig,
		name: 'bridge-comm-worker',
		entry: {
			'bridge-comm-worker': './src/core/comm-worker/bridge-comm-worker-entry.ts',
		},
		outputOptions: {
			codeSplitting: false,
		},
	},
	{
		...sharedBridgeWebBuildConfig,
		name: 'bridge-telemetry-worker',
		entry: {
			'bridge-telemetry-worker': './src/core/telemetry-worker/bridge-telemetry-worker-entry.ts',
		},
		outputOptions: {
			codeSplitting: false,
		},
	},
]);
