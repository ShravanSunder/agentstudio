import { act, type ReactElement } from 'react';
import { expect, test } from 'vitest';
import { cleanup, render } from 'vitest-browser-react';

import {
	useBridgeMarkdownPresentation,
	type BridgeMarkdownRenderIntent,
} from './use-bridge-markdown-presentation.js';
import {
	createBridgeMarkdownRenderWorkerClient,
	type BridgeMarkdownRenderWorkerClient,
} from './worker/bridge-markdown-render-worker-client.js';
import {
	identityFromMarkdownRenderWorkerRequest,
	type BridgeMarkdownRenderWorkerRequest,
} from './worker/bridge-markdown-render-worker-rpc.js';

interface PendingRender {
	readonly request: BridgeMarkdownRenderWorkerRequest;
	readonly resolve: (value: unknown) => void;
}

test('keeps the completed document through inactivity and a pending same-file refresh', async () => {
	// Arrange — real client identity checks, manually controlled render completion.
	const pending: PendingRender[] = [];
	const client = createBridgeMarkdownRenderWorkerClient({
		transport: {
			send: (request): Promise<unknown> =>
				new Promise((resolve): void => {
					pending.push({ request, resolve });
				}),
		},
	});
	const first = intent('guide.md', 'v1');
	const view = (
		isActive: boolean,
		renderIntent: BridgeMarkdownRenderIntent | null,
	): ReactElement => (
		<PresentationProbe
			client={client}
			isActive={isActive}
			intent={renderIntent}
			selectedPath="guide.md"
		/>
	);
	try {
		const rendered = await render(view(true, first));
		await act(async (): Promise<void> => {
			complete(pending, 0);
		});
		await expect
			.element(rendered.getByTestId('presentation'))
			.toHaveTextContent('ready:guide.md:v1');

		// Act / Assert — completed activation does not create another worker request.
		await rendered.rerender(view(false, first));
		await rendered.rerender(view(true, first));
		expect(pending).toHaveLength(1);
		await rendered.rerender(view(true, null));
		await expect
			.element(rendered.getByTestId('presentation'))
			.toHaveTextContent('ready:guide.md:v1');
		await rendered.rerender(view(true, intent('guide.md', 'v2')));
		await expect
			.element(rendered.getByTestId('presentation'))
			.toHaveTextContent('ready:guide.md:v1');
		await act(async (): Promise<void> => {
			complete(pending, 1);
		});
		await expect
			.element(rendered.getByTestId('presentation'))
			.toHaveTextContent('ready:guide.md:v2');
	} finally {
		await renderedCleanup(client);
	}
});

test('rejects a superseded completion and renders a revisited file after another selection', async () => {
	const pending: PendingRender[] = [];
	const client = createBridgeMarkdownRenderWorkerClient({
		transport: {
			send: (request): Promise<unknown> =>
				new Promise((resolve): void => {
					pending.push({ request, resolve });
				}),
		},
	});
	const view = (path: string, renderIntent: BridgeMarkdownRenderIntent | null): ReactElement => (
		<PresentationProbe client={client} isActive intent={renderIntent} selectedPath={path} />
	);
	try {
		const rendered = await render(view('guide.md', intent('guide.md', 'v1')));
		await rendered.rerender(view('other.md', intent('other.md', 'v2')));
		await act(async (): Promise<void> => {
			complete(pending, 0);
		});
		await expect.element(rendered.getByTestId('presentation')).toHaveTextContent('loading');
		await act(async (): Promise<void> => {
			complete(pending, 1);
		});
		await expect
			.element(rendered.getByTestId('presentation'))
			.toHaveTextContent('ready:other.md:v2');
		await rendered.rerender(view('code.ts', null));
		await rendered.rerender(view('other.md', intent('other.md', 'v2')));
		expect(pending).toHaveLength(3);
		await act(async (): Promise<void> => {
			complete(pending, 2);
		});
		await expect
			.element(rendered.getByTestId('presentation'))
			.toHaveTextContent('ready:other.md:v2');
	} finally {
		await renderedCleanup(client);
	}
});

function PresentationProbe(props: {
	readonly client: BridgeMarkdownRenderWorkerClient;
	readonly isActive: boolean;
	readonly intent: BridgeMarkdownRenderIntent | null;
	readonly selectedPath: string;
}): ReactElement {
	const { presentationState: state } = useBridgeMarkdownPresentation({
		...props,
		abortKey: 'probe',
		workerClient: props.client,
	});
	return (
		<output data-testid="presentation">
			{state.status === 'ready'
				? `ready:${state.sourcePath}:${state.identity.contentHash}`
				: state.status}
		</output>
	);
}

function intent(path: string, version: string): BridgeMarkdownRenderIntent {
	return {
		sourcePath: path,
		contentCacheKey: version,
		contentHash: version,
		markdownText: '# Guide',
		sourceIdentity: {
			surface: 'file',
			sourceId: 'source',
			sourceGeneration: 1,
			fileId: path,
			fileVersion: 1,
		},
	};
}

function complete(pending: readonly PendingRender[], index: number): void {
	const task = pending[index];
	if (task === undefined) throw new Error(`Missing pending render ${index}`);
	task.resolve({
		schemaVersion: 1,
		method: 'markdown.render',
		ok: true,
		...identityFromMarkdownRenderWorkerRequest(task.request),
		htmlCandidate: '<h1>Guide</h1>',
		mermaidDiagrams: [],
		metrics: { durationMilliseconds: 0, inputBytes: 7, outputBytes: 14, mermaidDiagramCount: 0 },
	});
}

async function renderedCleanup(client: BridgeMarkdownRenderWorkerClient): Promise<void> {
	await act(async (): Promise<void> => {
		await cleanup();
		client.dispose();
	});
}
