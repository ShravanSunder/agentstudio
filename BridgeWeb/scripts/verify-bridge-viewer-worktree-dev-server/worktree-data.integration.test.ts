import { fileURLToPath } from 'node:url';

import { createServer as createViteServer, type ViteDevServer } from 'vite';
import { afterEach, describe, expect, test, vi } from 'vitest';

import {
	runAllOwnedCleanupOperations,
	startOwnedBridgeDevelopmentServer,
	type OwnedBridgeDevelopmentServer,
} from '../dev-server/bridge-development-server-process.js';

const viteConfigFile = fileURLToPath(new URL('../../vite.config.ts', import.meta.url));
const repoRootPath = fileURLToPath(new URL('../../..', import.meta.url));
const worktreeDataTestTimeoutMilliseconds = 15_000;

describe('Bridge viewer typed product File worktree data', () => {
	let bridgeDevelopmentServer: OwnedBridgeDevelopmentServer | null = null;
	let viteServer: ViteDevServer | null = null;
	const initialBackendOrigin = process.env['BRIDGE_WEB_DEV_BACKEND_ORIGIN'];
	const initialDevServerUrl = process.env['BRIDGE_VIEWER_WORKTREE_DEV_SERVER_URL'];

	afterEach(async (): Promise<void> => {
		const ownedViteServer = viteServer;
		const ownedBridgeDevelopmentServer = bridgeDevelopmentServer;
		viteServer = null;
		bridgeDevelopmentServer = null;
		try {
			await runAllOwnedCleanupOperations({
				operations: [
					{
						name: 'integration Vite server',
						run: async (): Promise<void> => {
							await ownedViteServer?.close();
						},
					},
					{
						name: 'integration Swift development backend',
						run: async (): Promise<void> => {
							await ownedBridgeDevelopmentServer?.stop();
						},
					},
				],
			});
		} finally {
			if (initialDevServerUrl === undefined) {
				delete process.env['BRIDGE_VIEWER_WORKTREE_DEV_SERVER_URL'];
			} else {
				process.env['BRIDGE_VIEWER_WORKTREE_DEV_SERVER_URL'] = initialDevServerUrl;
			}
			if (initialBackendOrigin === undefined) {
				delete process.env['BRIDGE_WEB_DEV_BACKEND_ORIGIN'];
			} else {
				process.env['BRIDGE_WEB_DEV_BACKEND_ORIGIN'] = initialBackendOrigin;
			}
			vi.resetModules();
		}
	});

	test(
		'opens typed File data and drains every verifier-owned metadata stream',
		async () => {
			// Arrange
			bridgeDevelopmentServer = await startOwnedBridgeDevelopmentServer({
				baseRef: 'HEAD',
				repoRootPath,
				worktreeRoot: repoRootPath,
			});
			process.env['BRIDGE_WEB_DEV_BACKEND_ORIGIN'] = bridgeDevelopmentServer.origin;
			let observedMetadataStreamCloseCount = 0;
			let resolveMetadataStreamsClosed: (() => void) | null = null;
			const metadataStreamsClosed = new Promise<void>((resolve): void => {
				resolveMetadataStreamsClosed = resolve;
			});
			viteServer = await createViteServer({
				configFile: viteConfigFile,
				logLevel: 'silent',
				plugins: [
					{
						configureServer(server): void {
							server.middlewares.use((request, response, next): void => {
								if (request.url?.startsWith('/__bridge-product/stream') === true) {
									response.once('close', (): void => {
										observedMetadataStreamCloseCount += 1;
										if (observedMetadataStreamCloseCount === 2) {
											resolveMetadataStreamsClosed?.();
										}
									});
								}
								next();
							});
						},
						enforce: 'pre',
						name: 'bridge-verifier-worktree-data-close-observer',
					},
				],
				server: { host: '127.0.0.1', port: 0, strictPort: false },
			});
			await viteServer.listen();
			const address = viteServer.httpServer?.address();
			if (address === undefined || address === null || typeof address === 'string') {
				throw new Error('Expected a live Vite TCP address.');
			}
			process.env['BRIDGE_VIEWER_WORKTREE_DEV_SERVER_URL'] =
				`http://127.0.0.1:${address.port}/?fixture=worktree&viewer=file&workers=on&scenario=current-worktree`;
			vi.resetModules();
			const worktreeData = await import('./worktree-data.js');

			// Act
			const surface = await worktreeData.fetchWorktreeSurface();
			const secondSurface = await worktreeData.fetchWorktreeSurface();
			const descriptor = await worktreeData.fetchFetchableWorktreeFileDescriptorForPath({
				path: 'README.md',
				surface: secondSurface,
			});
			const content = await worktreeData.fetchWorktreeFileContent(descriptor);
			await worktreeData.closeAllWorktreeFileSurfaces();
			await metadataStreamsClosed;

			// Assert
			expect(surface.frames.at(-1)?.finalWindow).toBe(true);
			expect(secondSurface.frames.at(-1)?.finalWindow).toBe(true);
			expect(worktreeData.worktreeFileTreeRows(surface.frames).length).toBeGreaterThan(0);
			expect(worktreeData.openWorktreeFileSurfaceCount()).toBe(0);
			expect(observedMetadataStreamCloseCount).toBe(2);
			expect(descriptor.availability.availabilityKind).toBe('available');
			expect(descriptor.contentHandle).toBe(
				descriptor.availability.availabilityKind === 'available'
					? descriptor.availability.contentDescriptor.descriptorId
					: '',
			);
			expect(content).toContain('Agent Studio');
		},
		worktreeDataTestTimeoutMilliseconds,
	);
});
