import { fileURLToPath } from 'node:url';

import { createServer as createViteServer, type ViteDevServer } from 'vite';
import { afterEach, describe, expect, test } from 'vitest';

import { BridgeVerifierProductFileSession } from './product-file-session.js';

const viteConfigFile = fileURLToPath(new URL('../../vite.config.ts', import.meta.url));
const productFileSessionTestTimeoutMilliseconds = 15_000;

describe('Bridge verifier product File session', () => {
	let viteServer: ViteDevServer | null = null;

	afterEach(async (): Promise<void> => {
		await viteServer?.close();
		viteServer = null;
	});

	test(
		'proves source, tree, descriptor, content, cancellation, and stream closure through the typed carrier',
		async () => {
			// Arrange
			let resolveMetadataStreamClosed: (() => void) | null = null;
			const metadataStreamClosed = new Promise<void>((resolve): void => {
				resolveMetadataStreamClosed = resolve;
			});
			viteServer = await createViteServer({
				configFile: viteConfigFile,
				logLevel: 'silent',
				plugins: [
					{
						configureServer(server): void {
							server.middlewares.use((request, response, next): void => {
								if (request.url?.startsWith('/__bridge-product/stream') === true) {
									response.once('close', (): void => resolveMetadataStreamClosed?.());
								}
								next();
							});
						},
						enforce: 'pre',
						name: 'bridge-verifier-product-file-session-close-observer',
					},
				],
				server: { host: '127.0.0.1', port: 0, strictPort: false },
			});
			await viteServer.listen();
			const address = viteServer.httpServer?.address();
			if (address === undefined || address === null || typeof address === 'string') {
				throw new Error('Expected a live Vite TCP address.');
			}
			const session = new BridgeVerifierProductFileSession({
				baseUrl: `http://127.0.0.1:${address.port}`,
				scenarioName: 'current-worktree',
			});

			// Act
			const source = await session.open();
			const finalTreeWindow = source.treeWindows.findLast((event) => event.finalWindow);
			const targetPath = source.treeWindows
				.flatMap((event) => event.rows)
				.find((row) => row.path === 'README.md' && !row.isDirectory)?.path;
			if (targetPath === undefined) throw new Error('Expected README.md in the product File tree.');
			const secondTargetPath = source.treeWindows
				.flatMap((event) => event.rows)
				.find((row) => row.path !== targetPath && !row.isDirectory)?.path;
			if (secondTargetPath === undefined) {
				throw new Error('Expected a second file in the product File tree.');
			}
			const descriptor = await session.demandDescriptor(targetPath);
			const secondDescriptor = await session.demandDescriptor(secondTargetPath);
			const repeatedDescriptor = await session.demandDescriptor(targetPath);
			const content = await session.openContent(descriptor);
			await session.close();
			await metadataStreamClosed;

			// Assert
			expect(source.acceptedStreamSequence).toBe(0);
			expect(source.sourceAccepted.source.sourceId).toBe(source.sourceIdentity.sourceId);
			expect(finalTreeWindow?.totalRowCount).toBeGreaterThan(0);
			expect(descriptor.path).toBe(targetPath);
			expect(descriptor.availability.availabilityKind).toBe('available');
			expect(secondDescriptor.path).toBe(secondTargetPath);
			expect(repeatedDescriptor).toBe(descriptor);
			expect(content.byteLength).toBeGreaterThan(0);
			expect(new TextDecoder().decode(content.bytes)).toContain('Agent Studio');
			expect(session.state).toBe('closed');
		},
		productFileSessionTestTimeoutMilliseconds,
	);
});
