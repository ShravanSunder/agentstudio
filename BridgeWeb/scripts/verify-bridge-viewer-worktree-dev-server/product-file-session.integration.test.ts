import { execFile } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

import { createServer as createViteServer, type ViteDevServer } from 'vite';
import { afterEach, describe, expect, test } from 'vitest';

import {
	runAllOwnedCleanupOperations,
	startOwnedBridgeDevelopmentServer,
	type OwnedBridgeDevelopmentServer,
} from '../dev-server/bridge-development-server-process.js';
import { BridgeVerifierProductFileSession } from './product-file-session.js';

const viteConfigFile = fileURLToPath(new URL('../../vite.config.ts', import.meta.url));
const repoRootPath = fileURLToPath(new URL('../../..', import.meta.url));
const productFileSessionTestTimeoutMilliseconds = 15_000;
const execFileAsync = promisify(execFile);

describe('Bridge verifier product File session', () => {
	let bridgeDevelopmentServer: OwnedBridgeDevelopmentServer | null = null;
	let bridgeDevelopmentServerDataRootPath: string | null = null;
	let bridgeDevelopmentServerWorktreeRootPath: string | null = null;
	let viteServer: ViteDevServer | null = null;
	const initialBackendOrigin = process.env['BRIDGE_WEB_DEV_BACKEND_ORIGIN'];

	afterEach(async (): Promise<void> => {
		const ownedViteServer = viteServer;
		const ownedBridgeDevelopmentServer = bridgeDevelopmentServer;
		const ownedBridgeDevelopmentServerDataRootPath = bridgeDevelopmentServerDataRootPath;
		const ownedBridgeDevelopmentServerWorktreeRootPath = bridgeDevelopmentServerWorktreeRootPath;
		viteServer = null;
		bridgeDevelopmentServer = null;
		bridgeDevelopmentServerDataRootPath = null;
		bridgeDevelopmentServerWorktreeRootPath = null;
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
					{
						name: 'integration Swift development backend worktree fixture',
						run: async (): Promise<void> => {
							if (ownedBridgeDevelopmentServerWorktreeRootPath !== null) {
								await rm(ownedBridgeDevelopmentServerWorktreeRootPath, {
									force: true,
									recursive: true,
								});
							}
						},
					},
					{
						name: 'integration Swift development backend data root',
						run: async (): Promise<void> => {
							if (ownedBridgeDevelopmentServerDataRootPath !== null) {
								await rm(ownedBridgeDevelopmentServerDataRootPath, {
									force: true,
									recursive: true,
								});
							}
						},
					},
				],
			});
		} finally {
			if (initialBackendOrigin === undefined) {
				delete process.env['BRIDGE_WEB_DEV_BACKEND_ORIGIN'];
			} else {
				process.env['BRIDGE_WEB_DEV_BACKEND_ORIGIN'] = initialBackendOrigin;
			}
		}
	});

	test(
		'proves source, tree, descriptor, content, cancellation, and stream closure through the typed carrier',
		async () => {
			// Arrange
			bridgeDevelopmentServerDataRootPath = await mkdtemp(
				join(tmpdir(), 'bridge-product-file-development-server-'),
			);
			bridgeDevelopmentServerWorktreeRootPath = await mkdtemp(
				join(tmpdir(), 'bridge-product-file-worktree-'),
			);
			await writeFile(
				join(bridgeDevelopmentServerWorktreeRootPath, 'README.md'),
				'# Agent Studio\n\nDeterministic product File session fixture.\n',
			);
			await writeFile(
				join(bridgeDevelopmentServerWorktreeRootPath, 'fixture.txt'),
				'bounded fixture content\n',
			);
			await runFixtureGit(bridgeDevelopmentServerWorktreeRootPath, [
				'init',
				'--initial-branch=main',
			]);
			await runFixtureGit(bridgeDevelopmentServerWorktreeRootPath, [
				'config',
				'user.name',
				'Bridge Product File Integration',
			]);
			await runFixtureGit(bridgeDevelopmentServerWorktreeRootPath, [
				'config',
				'user.email',
				'bridge-product-file@example.invalid',
			]);
			await runFixtureGit(bridgeDevelopmentServerWorktreeRootPath, ['add', '--all']);
			await runFixtureGit(bridgeDevelopmentServerWorktreeRootPath, [
				'-c',
				'commit.gpgsign=false',
				'commit',
				'-m',
				'fixture base',
			]);
			bridgeDevelopmentServer = await startOwnedBridgeDevelopmentServer({
				dataRootPath: bridgeDevelopmentServerDataRootPath,
				initialTarget: 'HEAD',
				paneId: randomUUID(),
				repoRootPath,
				worktreeRoot: bridgeDevelopmentServerWorktreeRootPath,
			});
			process.env['BRIDGE_WEB_DEV_BACKEND_ORIGIN'] = bridgeDevelopmentServer.origin;
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

async function runFixtureGit(
	worktreeRootPath: string,
	arguments_: readonly string[],
): Promise<void> {
	await execFileAsync('git', ['-C', worktreeRootPath, ...arguments_]);
}
