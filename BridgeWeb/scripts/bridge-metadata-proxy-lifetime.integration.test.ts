import { once } from 'node:events';
import { createServer, type Socket } from 'node:net';

import { createServer as createViteServer, type ViteDevServer } from 'vite';
import { expect, test } from 'vitest';

import { bridgeProductDevProxyConfiguration } from '../vite.config.js';

test.each(['baseline-abandoned', 'abandoned', 'completed'] as const)(
	'metadata proxy preserves %s response lifetime',
	async (completion): Promise<void> => {
		// Arrange: a real TCP backend permits request half-close, as the Swift carrier does.
		const sockets = new Set<Socket>();
		let latestSocket: Socket | null = null;
		let resetCount = 0;
		const backend = createServer({ allowHalfOpen: true }, (socket): void => {
			sockets.add(socket);
			latestSocket = socket;
			let requestHeaders = '';
			socket.on('error', (error: NodeJS.ErrnoException): void => {
				if (error.code === 'ECONNRESET') resetCount += 1;
			});
			socket.on('close', (): void => {
				sockets.delete(socket);
			});
			socket.on('data', (bytes): void => {
				requestHeaders += bytes.toString();
				if (!requestHeaders.includes('\r\n\r\n')) return;
				requestHeaders = '';
				socket.write(
					'HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nTransfer-Encoding: chunked\r\n\r\n1\r\nx\r\n' +
						(completion === 'completed' ? '0\r\n\r\n' : ''),
				);
			});
		});
		let vite: ViteDevServer | null = null;
		const controller = new AbortController();
		try {
			backend.listen({ host: '127.0.0.1', port: 0 });
			await once(backend, 'listening');
			const backendAddress = backend.address();
			if (backendAddress === null || typeof backendAddress === 'string')
				throw new Error('TCP port missing.');
			const backendOrigin = `http://127.0.0.1:${backendAddress.port}`;
			const proxy = { ...bridgeProductDevProxyConfiguration(backendOrigin) };
			if (completion === 'baseline-abandoned') {
				// Negative control: stock Vite cleanup sends FIN, which permits a response half-close.
				proxy['/__bridge-product/stream'] = { target: backendOrigin };
			}
			vite = await createViteServer({
				appType: 'custom',
				configFile: false,
				logLevel: 'silent',
				optimizeDeps: { noDiscovery: true, include: [] },
				server: {
					host: '127.0.0.1',
					port: 0,
					proxy,
				},
			});
			await vite.listen();
			const proxyAddress = vite.httpServer?.address();
			if (proxyAddress === null || proxyAddress === undefined || typeof proxyAddress === 'string')
				throw new Error('Proxy port missing.');
			const url = `http://127.0.0.1:${proxyAddress.port}/__bridge-product/stream`;
			const response = await fetch(url, { method: 'POST', signal: controller.signal });
			if (latestSocket === null) throw new Error('Upstream connection missing.');

			if (completion !== 'completed') {
				const termination = once(latestSocket, 'end', { signal: AbortSignal.timeout(3_000) }).then(
					(): string => 'FIN',
					(error: unknown): string =>
						typeof error === 'object' && error !== null && 'code' in error
							? String(error.code)
							: 'unknown',
				);
				// Act: abandon an established response after the POST request has completed.
				await response.body?.getReader().read();
				controller.abort();
				// Assert: this is cancellation, not permission to keep sending after a FIN.
				expect(await termination).toBe(completion === 'baseline-abandoned' ? 'FIN' : 'ECONNRESET');
			} else {
				// Act / Assert: finite responses complete normally and further requests work.
				expect(await response.text()).toBe('x');
				const nextResponse = await fetch(url, { method: 'POST', signal: controller.signal });
				expect(await nextResponse.text()).toBe('x');
				expect(resetCount).toBe(0);
			}
		} finally {
			controller.abort();
			for (const socket of sockets) socket.destroy();
			await vite?.close();
			await new Promise<void>((resolve): void => {
				backend.close((): void => resolve());
			});
		}
	},
);
