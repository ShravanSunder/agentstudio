import { act, type ReactElement } from 'react';
import { describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production app CSS.
import '../app/bridge-app.css';
import { RecordingAnnotationBrowserSurface } from './worktree-annotation-browser-test-support.js';
import { WorktreeAnnotationSurfaceProvider } from './worktree-annotation-surface-provider.js';
import { WorktreeAnnotationNewMessageComposer } from './worktree-annotation-thread.js';

const predecessorPublicationIdentity = {
	generation: 7,
	packageId: 'package-predecessor',
	publicationId: '00000000-0000-7000-8000-000000000041',
	revision: 3,
	sourceIdentity: 'source-predecessor',
} as const;

describe('worktree annotation Review publication continuity', () => {
	test('pairs a predecessor composer origin with the installed predecessor publication', async () => {
		// Arrange
		const surface = new RecordingAnnotationBrowserSurface('review');
		surface.setReviewActiveIdentity(predecessorPublicationIdentity);
		const renderedView = await render(<PredecessorReviewComposer surface={surface} />);

		// Act
		await act(async (): Promise<void> => {
			await renderedView
				.getByRole('textbox', { name: 'Write an annotation in Markdown' })
				.fill('Comment that remains bound to the displayed Review publication.');
			await settleBrowserInteraction();
		});
		await waitForRootCreate(surface);

		// Assert
		const rootOperationIndex = surface.sentOperations.findIndex(
			(operation) => operation.kind === 'root.create',
		);
		const rootOperation = surface.sentOperations[rootOperationIndex];
		expect(rootOperation).toMatchObject({
			kind: 'root.create',
			origin: { sourceIdentity: 'handle-item-source-head-predecessor' },
		});
		expect(surface.sentReviewPublicationIdentities[rootOperationIndex]).toEqual({
			packageId: 'package-predecessor',
			publicationId: '00000000-0000-7000-8000-000000000041',
			reviewGeneration: 7,
			revision: 3,
			sourceIdentity: 'source-predecessor',
		});
	});
});

function PredecessorReviewComposer(props: {
	readonly surface: RecordingAnnotationBrowserSurface;
}): ReactElement {
	return (
		<WorktreeAnnotationSurfaceProvider surfaceClient={props.surface.client}>
			<WorktreeAnnotationNewMessageComposer
				createOperation={(body, editToken, admission) => ({
					admission: admission ?? { kind: 'implicitOrSingle' },
					body,
					editToken,
					kind: 'root.create',
					origin: {
						diffSide: 'additions',
						endLine: 2,
						kind: 'located',
						path: 'Sources/App/View.swift',
						sourceIdentity: 'handle-item-source-head-predecessor',
						sourceRole: 'reviewHead',
						startLine: 2,
					},
				})}
				onCancel={() => {}}
				onSaved={() => {}}
				placeholder="Write an annotation in Markdown"
			/>
		</WorktreeAnnotationSurfaceProvider>
	);
}

async function waitForRootCreate(surface: RecordingAnnotationBrowserSurface): Promise<void> {
	for (let attempt = 0; attempt < 50; attempt += 1) {
		if (surface.sentOperations.some((operation) => operation.kind === 'root.create')) return;
		// eslint-disable-next-line no-await-in-loop -- Browser state must settle between bounded observations.
		await act(async (): Promise<void> => settleBrowserInteraction());
	}
	throw new Error('Expected one Review root.create operation.');
}

async function settleBrowserInteraction(): Promise<void> {
	await Promise.resolve();
	await new Promise<void>((resolve): void => {
		requestAnimationFrame((): void => resolve());
	});
	await Promise.resolve();
}
