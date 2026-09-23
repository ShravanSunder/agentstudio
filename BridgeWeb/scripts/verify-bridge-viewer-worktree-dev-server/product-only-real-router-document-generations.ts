import type { Page, Request as PlaywrightRequest } from 'playwright';

// Which page document issued a request or created a worker. A response waiter is
// bound to one generation and accepts only responses to that generation's
// requests, so a late response from an earlier document cannot satisfy it.
//
// Every page document mints a token at document start (an init script, main
// frame only) and stamps it on its Bridge requests. The journey's product
// requests are issued by the dedicated comm worker, where init scripts do not
// run, so the init script also wraps the document's `Worker` constructor: each
// module worker starts from a small module that records the creating
// document's token, stamps it on the worker's own Bridge fetches, then imports
// the original worker script. A worker therefore keeps its creating document's
// token after a reload. Generations are assigned in order of each token's first
// appearance: a reload advances the generation; same-document navigation
// (pushState, hash), a redirect's intermediate response and an aborted
// navigation do not, because none of them starts a document.
export interface BridgeViewerDocumentGenerations {
	// The newest page document's generation; 0 before the first document.
	readonly currentGeneration: () => number;
	// The generation of the document that issued `request`, or
	// `untaggedRequestGeneration` when the request carries no document token.
	readonly requestGeneration: (request: PlaywrightRequest) => number;
	// The generation of the document that created the worker at `workerUrl`, and
	// the script the worker runs.
	readonly observedWorker: (workerUrl: string) => BridgeViewerObservedWorkerOrigin;
}

export interface BridgeViewerObservedWorkerOrigin {
	readonly documentGeneration: number;
	readonly scriptUrl: string;
}

// No live document has generation 0, so an untagged request never satisfies a
// generation-bound waiter; it is never attributed to whichever page is current.
export const untaggedRequestGeneration = 0;

interface DocumentTokenPageConfiguration {
	readonly documentStartedBinding: string;
	readonly documentTokenHeader: string;
	readonly journeyRequestPathPrefixes: readonly string[];
	readonly workerOriginFragmentKey: string;
}

const documentTokenPageConfiguration: DocumentTokenPageConfiguration = {
	documentStartedBinding: '__bridgeJourneyDocumentStarted',
	documentTokenHeader: 'x-bridge-journey-document-token',
	journeyRequestPathPrefixes: ['/__bridge-product/', '/__bridge-worktree/'],
	workerOriginFragmentKey: 'bridge-journey-worker-origin',
};

export async function installBridgeViewerDocumentGenerations(
	page: Page,
): Promise<BridgeViewerDocumentGenerations> {
	const generationByToken = new Map<string, number>();
	let newestGeneration = 0;
	const generationForToken = (documentToken: string): number => {
		const knownGeneration = generationByToken.get(documentToken);
		if (knownGeneration !== undefined) return knownGeneration;
		newestGeneration += 1;
		generationByToken.set(documentToken, newestGeneration);
		return newestGeneration;
	};

	await page.exposeBinding(
		documentTokenPageConfiguration.documentStartedBinding,
		(source, documentToken: unknown): void => {
			if (source.frame !== page.mainFrame() || typeof documentToken !== 'string') return;
			generationForToken(documentToken);
		},
	);
	await page.addInitScript(installDocumentTokenInPage, documentTokenPageConfiguration);

	return {
		currentGeneration: (): number => newestGeneration,
		observedWorker: (workerUrl: string): BridgeViewerObservedWorkerOrigin => {
			const workerOrigin = parseWrappedWorkerOrigin(workerUrl);
			// Classic and blob-script workers are not wrapped; they are created by the
			// current document and never issue journey requests.
			if (workerOrigin === null) {
				return { documentGeneration: newestGeneration, scriptUrl: workerUrl };
			}
			return {
				documentGeneration: generationForToken(workerOrigin.documentToken),
				scriptUrl: workerOrigin.scriptUrl,
			};
		},
		requestGeneration: (request: PlaywrightRequest): number => {
			const documentToken = request.headers()[documentTokenPageConfiguration.documentTokenHeader];
			return documentToken === undefined
				? untaggedRequestGeneration
				: generationForToken(documentToken);
		},
	};
}

function parseWrappedWorkerOrigin(
	workerUrl: string,
): { readonly documentToken: string; readonly scriptUrl: string } | null {
	const fragmentPrefix = `#${documentTokenPageConfiguration.workerOriginFragmentKey}=`;
	const fragmentIndex = workerUrl.indexOf(fragmentPrefix);
	if (fragmentIndex === -1) return null;
	try {
		const origin: unknown = JSON.parse(
			decodeURIComponent(workerUrl.slice(fragmentIndex + fragmentPrefix.length)),
		);
		if (
			typeof origin === 'object' &&
			origin !== null &&
			'documentToken' in origin &&
			typeof origin.documentToken === 'string' &&
			'scriptUrl' in origin &&
			typeof origin.scriptUrl === 'string'
		) {
			return { documentToken: origin.documentToken, scriptUrl: origin.scriptUrl };
		}
	} catch {}
	return null;
}

// Runs in every page document before its scripts; it must be self-contained.
function installDocumentTokenInPage(configuration: DocumentTokenPageConfiguration): void {
	if (window !== window.top) return;
	const documentToken = crypto.randomUUID();
	const announceDocumentStarted: unknown = Reflect.get(
		window,
		configuration.documentStartedBinding,
	);
	if (typeof announceDocumentStarted === 'function') announceDocumentStarted(documentToken);

	const isJourneyRequestUrl = (url: URL): boolean =>
		configuration.journeyRequestPathPrefixes.some((prefix): boolean =>
			url.pathname.startsWith(prefix),
		);

	const nativeFetch = window.fetch.bind(window);
	window.fetch = async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
		const requestUrl = new URL(input instanceof Request ? input.url : String(input), location.href);
		if (!isJourneyRequestUrl(requestUrl)) return await nativeFetch(input, init);
		const headers = new Headers(input instanceof Request ? input.headers : undefined);
		new Headers(init?.headers).forEach((value, name): void => headers.set(name, value));
		headers.set(configuration.documentTokenHeader, documentToken);
		return await nativeFetch(input, { ...init, headers });
	};

	const journeyRequestByXhr = new WeakSet<XMLHttpRequest>();
	// oxlint-disable-next-line typescript/unbound-method -- Reapplied with the live receiver below.
	const nativeOpen = XMLHttpRequest.prototype.open;
	// oxlint-disable-next-line typescript/unbound-method -- Reapplied with the live receiver below.
	const nativeSend = XMLHttpRequest.prototype.send;
	XMLHttpRequest.prototype.open = function openJourneyRequest(
		this: XMLHttpRequest,
		method: string,
		url: string | URL,
		async = true,
		username?: string | null,
		password?: string | null,
	): void {
		if (isJourneyRequestUrl(new URL(String(url), location.href))) journeyRequestByXhr.add(this);
		Reflect.apply(nativeOpen, this, [method, url, async, username, password]);
	};
	XMLHttpRequest.prototype.send = function sendJourneyRequest(
		this: XMLHttpRequest,
		body?: Document | XMLHttpRequestBodyInit | null,
	): void {
		if (journeyRequestByXhr.has(this)) {
			this.setRequestHeader(configuration.documentTokenHeader, documentToken);
		}
		Reflect.apply(nativeSend, this, [body]);
	};

	// oxlint-disable-next-line unicorn/consistent-function-scoping -- Playwright serializes this init script; helpers must live inside it.
	const moduleUrl = (source: string): string =>
		URL.createObjectURL(new Blob([source], { type: 'text/javascript' }));
	const NativeWorker = window.Worker;
	window.Worker = class JourneyDocumentWorker extends NativeWorker {
		constructor(scriptUrl: string | URL, options?: WorkerOptions) {
			if (options?.type !== 'module') {
				super(scriptUrl, options);
				return;
			}
			const resolvedScriptUrl = new URL(String(scriptUrl), location.href).href;
			// The token module is imported before the original script, and both imports
			// are static, so the worker evaluates exactly as before (no top-level await
			// that could drop early messages) with its Bridge fetches already stamped.
			const tokenModuleSource = `
const documentToken = ${JSON.stringify(documentToken)};
const scriptUrl = ${JSON.stringify(resolvedScriptUrl)};
const documentTokenHeader = ${JSON.stringify(configuration.documentTokenHeader)};
const journeyRequestPathPrefixes = ${JSON.stringify(configuration.journeyRequestPathPrefixes)};
const nativeFetch = self.fetch.bind(self);
self.fetch = (input, init) => {
	let requestUrl;
	try {
		requestUrl = new URL(input instanceof Request ? input.url : String(input), scriptUrl);
	} catch {
		return nativeFetch(input, init);
	}
	if (!journeyRequestPathPrefixes.some((prefix) => requestUrl.pathname.startsWith(prefix))) {
		return nativeFetch(input instanceof Request ? input : requestUrl, init);
	}
	const headers = new Headers(input instanceof Request ? input.headers : undefined);
	new Headers(init?.headers).forEach((value, name) => headers.set(name, value));
	headers.set(documentTokenHeader, documentToken);
	return nativeFetch(input instanceof Request ? input : requestUrl, { ...init, headers });
};
`;
			const tokenModuleUrl = moduleUrl(tokenModuleSource);
			const wrapperUrl = moduleUrl(
				`import ${JSON.stringify(tokenModuleUrl)};\nimport ${JSON.stringify(resolvedScriptUrl)};\n`,
			);
			const workerOrigin = encodeURIComponent(
				JSON.stringify({ documentToken, scriptUrl: resolvedScriptUrl }),
			);
			super(`${wrapperUrl}#${configuration.workerOriginFragmentKey}=${workerOrigin}`, options);
		}
	};
}
