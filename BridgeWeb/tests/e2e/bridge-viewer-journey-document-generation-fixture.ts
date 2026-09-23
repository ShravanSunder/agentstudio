import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';

// A minimal page whose dedicated module worker issues Bridge product commands
// the way the comm worker does: a relative `fetch('/__bridge-product/command')`
// from worker code. It lets a real browser prove which document a product
// request belongs to without the Vite product stack.
export interface BridgeViewerJourneyDocumentGenerationServer {
	readonly origin: string;
	readonly close: () => Promise<void>;
}

const journeyPageHtml = `<!doctype html>
<html>
	<body>
		<script type="module">
			const worker = new Worker('/journey-worker.js', { type: 'module' });
			window.bridgeJourneyWorkerSend = (kind, requestId) =>
				new Promise((resolve) => {
					const onMessage = (event) => {
						if (event.data.requestId !== requestId) return;
						worker.removeEventListener('message', onMessage);
						resolve(event.data.status);
					};
					worker.addEventListener('message', onMessage);
					worker.postMessage({ kind, requestId });
				});
			worker.postMessage({ kind: 'ready-probe', requestId: 'ready-probe' });
			worker.addEventListener('message', (event) => {
				if (event.data.requestId === 'ready-probe') document.body.dataset.workerReady = 'true';
			});
		</script>
	</body>
</html>`;

const journeyWorkerSource = `self.addEventListener('message', async (event) => {
	if (event.data.kind === 'ready-probe') {
		self.postMessage({ requestId: event.data.requestId, status: 0 });
		return;
	}
	const response = await fetch('/__bridge-product/command', {
		body: JSON.stringify({ kind: event.data.kind, requestId: event.data.requestId }),
		headers: { 'content-type': 'application/json' },
		method: 'POST',
	});
	self.postMessage({ requestId: event.data.requestId, status: response.status });
});`;

export async function startBridgeViewerJourneyDocumentGenerationServer(): Promise<BridgeViewerJourneyDocumentGenerationServer> {
	const server = createServer((request: IncomingMessage, response: ServerResponse): void => {
		const path = new URL(request.url ?? '/', 'http://127.0.0.1').pathname;
		if (request.method === 'GET' && path === '/journey.html') {
			response.writeHead(200, { 'content-type': 'text/html' }).end(journeyPageHtml);
			return;
		}
		if (request.method === 'GET' && path === '/journey-worker.js') {
			response.writeHead(200, { 'content-type': 'text/javascript' }).end(journeyWorkerSource);
			return;
		}
		if (request.method === 'GET' && path === '/redirect-to-journey') {
			response.writeHead(302, { location: '/journey.html' }).end();
			return;
		}
		if (request.method === 'POST' && path === '/__bridge-product/command') {
			request.resume();
			request.once('end', (): void => {
				response.writeHead(204).end();
			});
			return;
		}
		response.writeHead(404).end();
	});
	await new Promise<void>((resolve, reject): void => {
		server.once('error', reject);
		server.listen(0, '127.0.0.1', (): void => resolve());
	});
	const address = server.address();
	if (address === null || typeof address === 'string') {
		throw new Error('Journey document-generation server did not bind a TCP port.');
	}
	return {
		close: async (): Promise<void> =>
			await new Promise<void>((resolve, reject): void => {
				server.closeAllConnections();
				server.close((error): void => (error === undefined ? resolve() : reject(error)));
			}),
		origin: `http://127.0.0.1:${address.port}`,
	};
}
