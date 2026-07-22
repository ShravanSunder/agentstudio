import { fileURLToPath } from 'node:url';

import { createServer as createViteServer, type ViteDevServer } from 'vite';

import { performanceOnlyMode } from './verify-bridge-viewer-worktree-dev-server/config.ts';
import { runSelfHostedBridgeViewerProductOnlyRegression } from './verify-bridge-viewer-worktree-dev-server/product-only-real-router-regression.ts';

if (performanceOnlyMode) {
	await runSelfHostedBridgeViewerPerformanceVerifier();
} else {
	await runSelfHostedBridgeViewerProductOnlyRegression();
}

async function runSelfHostedBridgeViewerPerformanceVerifier(): Promise<void> {
	const previousWorktreeDevServerUrl = process.env['BRIDGE_VIEWER_WORKTREE_DEV_SERVER_URL'];
	let viteServer: ViteDevServer | null = null;
	try {
		viteServer = await createViteServer({
			configFile: fileURLToPath(new URL('../vite.config.ts', import.meta.url)),
			server: {
				host: '127.0.0.1',
				port: 0,
				strictPort: true,
			},
		});
		await viteServer.listen();
		const serverAddress = viteServer.httpServer?.address();
		if (
			serverAddress === null ||
			serverAddress === undefined ||
			typeof serverAddress === 'string'
		) {
			throw new Error('Expected the owned performance Vite server to expose a loopback port.');
		}
		process.env['BRIDGE_VIEWER_WORKTREE_DEV_SERVER_URL'] =
			`http://127.0.0.1:${serverAddress.port}/?fixture=worktree&viewer=file&workers=on&scenario=current-worktree`;

		const loadedRunner: unknown = await viteServer.ssrLoadModule(
			'/scripts/verify-bridge-viewer-worktree-dev-server/runner.ts',
		);
		if (typeof loadedRunner !== 'object' || loadedRunner === null) {
			throw new Error('Expected the owned performance verifier runner module.');
		}
		const runVerifier = (loadedRunner as Readonly<Record<string, unknown>>)[
			'runBridgeViewerWorktreeDevServerVerifier'
		];
		if (typeof runVerifier !== 'function') {
			throw new Error('Expected the owned performance verifier runner entrypoint.');
		}
		await runVerifier();
	} finally {
		if (viteServer !== null) await viteServer.close();
		if (previousWorktreeDevServerUrl === undefined) {
			delete process.env['BRIDGE_VIEWER_WORKTREE_DEV_SERVER_URL'];
		} else {
			process.env['BRIDGE_VIEWER_WORKTREE_DEV_SERVER_URL'] = previousWorktreeDevServerUrl;
		}
	}
}
