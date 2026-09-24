import { act, useState, type ReactElement, type ReactNode } from 'react';
import { afterEach, describe, expect, test } from 'vitest';
import { cleanup, render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production app CSS.
import './bridge-app.css';
import {
	annotationSessionId,
	RecordingAnnotationBrowserSurface,
} from '../worktree-annotations/worktree-annotation-browser-test-support.js';
import {
	createWorktreeAnnotationEditorPreparationRegistry,
	worktreeAnnotationEditorPreparationRegistryContext,
	type WorktreeAnnotationEditorPreparationRegistry,
} from '../worktree-annotations/worktree-annotation-editor-preparation-registry.js';
import { WorktreeAnnotationSurfaceProvider } from '../worktree-annotations/worktree-annotation-surface-provider.js';
import { settleBrowserCondition } from '../worktree-annotations/worktree-annotation-thread.browser.test-support.js';
import { WorktreeAnnotationNewMessageComposer } from '../worktree-annotations/worktree-annotation-thread.js';
import {
	bridgeNativeEditorPreparationEventName,
	useBridgeAppNativeEditorPreparation,
	type BridgeNativeEditorPreparationResult,
} from './bridge-app-native-editor-preparation.js';

/** Mirrors the page call native makes: dispatch, then take the probe promise. */
function dispatchNativePreparation(
	requestId: string,
): Promise<BridgeNativeEditorPreparationResult> | undefined {
	delete window.bridgeEditorPreparationProbe;
	window.dispatchEvent(
		new CustomEvent(bridgeNativeEditorPreparationEventName, { detail: { requestId } }),
	);
	const pending = window.bridgeEditorPreparationProbe;
	delete window.bridgeEditorPreparationProbe;
	return pending;
}

function NativePreparationPage(props: { readonly children: ReactNode }): ReactElement {
	const [registry] = useState<WorktreeAnnotationEditorPreparationRegistry>(
		createWorktreeAnnotationEditorPreparationRegistry,
	);
	useBridgeAppNativeEditorPreparation(registry);
	return (
		<worktreeAnnotationEditorPreparationRegistryContext.Provider value={registry}>
			{props.children}
		</worktreeAnnotationEditorPreparationRegistryContext.Provider>
	);
}

function RootComposer(): ReactElement {
	return (
		<WorktreeAnnotationNewMessageComposer
			createOperation={(body, editToken, admission) => ({
				admission: admission ?? { kind: 'implicitOrSingle' },
				body,
				editToken,
				kind: 'root.create',
				origin: {
					diffSide: null,
					endLine: 7,
					kind: 'located',
					path: 'Sources/App/View.swift',
					sourceIdentity: 'descriptor-file-1',
					sourceRole: 'file',
					startLine: 4,
				},
			})}
			onCancel={(): void => {}}
			onSaved={(): void => {}}
			placeholder="Write an annotation in Markdown"
		/>
	);
}

describe('native editor preparation barrier', () => {
	afterEach(async () => {
		await cleanup();
		delete window.bridgeEditorPreparationProbe;
	});

	test('answers prepared only after the typed draft is durable, and keeps the composer open', async () => {
		// Arrange
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await render(
			<NativePreparationPage>
				<WorktreeAnnotationSurfaceProvider surfaceClient={surface.client}>
					<RootComposer />
				</WorktreeAnnotationSurfaceProvider>
			</NativePreparationPage>,
		);
		await act(async (): Promise<void> => {
			await rendered
				.getByRole('textbox', { name: 'Write an annotation in Markdown' })
				.fill('Draft that must survive the source replacement');
		});
		await settleBrowserCondition(
			(): boolean => surface.sentOperations.some((operation) => operation.kind === 'root.create'),
			'Expected the typed draft to begin durable creation.',
		);

		// Act
		const pending = dispatchNativePreparation('native-preparation-durable');
		let settledBeforeAcknowledgement = false;
		void pending?.then((): void => {
			settledBeforeAcknowledgement = true;
		});
		await Promise.resolve();
		const answeredBeforeAcknowledgement = settledBeforeAcknowledgement;
		await act(async (): Promise<void> => {
			surface.settleMostRecentCommitted(annotationSessionId, 1);
			await Promise.resolve();
		});

		// Assert
		expect(pending).toBeDefined();
		expect(answeredBeforeAcknowledgement).toBe(false);
		await expect(pending).resolves.toEqual({
			requestId: 'native-preparation-durable',
			status: 'prepared',
		});
		await expect
			.element(rendered.getByRole('textbox', { name: 'Write an annotation in Markdown' }))
			.toBeVisible();
	});

	test('answers failed for an editor that cannot be made durable, keeping it open', async () => {
		// Arrange
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await render(
			<NativePreparationPage>
				<WorktreeAnnotationSurfaceProvider surfaceClient={surface.client}>
					<RootComposer />
				</WorktreeAnnotationSurfaceProvider>
			</NativePreparationPage>,
		);

		// Act
		const pending = dispatchNativePreparation('native-preparation-empty');

		// Assert
		await expect(pending).resolves.toEqual({
			requestId: 'native-preparation-empty',
			status: 'failed',
		});
		await expect
			.element(rendered.getByRole('textbox', { name: 'Write an annotation in Markdown' }))
			.toBeVisible();
	});

	test('answers prepared at once when no annotation surface has an editor', async () => {
		// Arrange
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		await render(
			<NativePreparationPage>
				<WorktreeAnnotationSurfaceProvider surfaceClient={surface.client}>
					<span>No editor</span>
				</WorktreeAnnotationSurfaceProvider>
			</NativePreparationPage>,
		);

		// Act / Assert
		await expect(dispatchNativePreparation('native-preparation-idle')).resolves.toEqual({
			requestId: 'native-preparation-idle',
			status: 'prepared',
		});
	});
});
