import { createServer, request as requestHTTP, type ServerResponse } from 'node:http';
import type { Socket } from 'node:net';

import { BridgeFileRenewalWireObserver } from './bridge-viewer-vite-file-renewal-observer.ts';

export interface BridgeStreamFaultProxy {
	readonly origin: string;
	readonly disconnectMetadata: () => number;
	readonly snapshot: () => {
		readonly activeMetadataResponses: number;
		readonly metadataRequestCount: number;
		readonly metadataByteCount: number;
		readonly fileRenewal: readonly ReturnType<BridgeFileRenewalWireObserver['snapshot']>[];
	};
	readonly stop: () => Promise<void>;
}

// Test-only wire seam. Bytes come from the real Vite/Swift stack unchanged.
// This does not implement reconnect, alter commands, or fabricate protocol frames.
export async function startBridgeStreamFaultProxy(
	upstreamOrigin: string,
): Promise<BridgeStreamFaultProxy> {
	const connections = new Set<Socket>();
	const metadataResponses = new Set<ServerResponse>();
	let metadataRequestCount = 0;
	let metadataByteCount = 0;
	const fileRenewalObservers: BridgeFileRenewalWireObserver[] = [];
	const server = createServer((incomingRequest, outgoingResponse): void => {
		const destination = new URL(incomingRequest.url ?? '/', upstreamOrigin);
		const isMetadata = destination.pathname === '/__bridge-product/stream';
		if (isMetadata) metadataRequestCount += 1;
		const upstreamRequest = requestHTTP(
			destination,
			{
				method: incomingRequest.method,
				headers: { ...incomingRequest.headers, host: destination.host },
			},
			(upstreamResponse): void => {
				outgoingResponse.writeHead(upstreamResponse.statusCode ?? 502, upstreamResponse.headers);
				outgoingResponse.flushHeaders();
				if (isMetadata) {
					const observer = new BridgeFileRenewalWireObserver();
					fileRenewalObservers.push(observer);
					metadataResponses.add(outgoingResponse);
					upstreamResponse.on('data', (chunk: Buffer): void => {
						metadataByteCount += chunk.byteLength;
						observer.observe(chunk);
					});
				}
				upstreamResponse.on('error', (): void => {
					outgoingResponse.destroy();
				});
				outgoingResponse.once('close', (): void => {
					upstreamResponse.destroy();
				});
				upstreamResponse.pipe(outgoingResponse);
			},
		);
		upstreamRequest.on('error', (): void => {
			outgoingResponse.destroy();
		});
		incomingRequest.once('aborted', (): void => {
			upstreamRequest.destroy();
		});
		outgoingResponse.once('close', (): void => {
			metadataResponses.delete(outgoingResponse);
			upstreamRequest.destroy();
		});
		incomingRequest.pipe(upstreamRequest);
	});
	server.on('connection', (socket): void => {
		connections.add(socket);
		socket.once('close', (): void => {
			connections.delete(socket);
		});
	});
	await new Promise<void>((resolve, reject): void => {
		server.once('error', reject);
		server.listen(0, '127.0.0.1', resolve);
	});
	const address = server.address();
	if (address === null || typeof address === 'string')
		throw new Error('Fault proxy has no TCP address.');
	return {
		origin: `http://127.0.0.1:${address.port}`,
		disconnectMetadata: (): number => {
			const count = metadataResponses.size;
			for (const response of metadataResponses) response.destroy();
			return count;
		},
		snapshot: () => ({
			activeMetadataResponses: metadataResponses.size,
			metadataRequestCount,
			metadataByteCount,
			fileRenewal: fileRenewalObservers.map((observer) => observer.snapshot()),
		}),
		stop: async (): Promise<void> => {
			await new Promise<void>((resolve, reject): void => {
				server.close((error): void => (error === undefined ? resolve() : reject(error)));
				for (const socket of connections) socket.destroy();
			});
		},
	};
}
