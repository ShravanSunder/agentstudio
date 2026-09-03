import { act, useState, type ReactElement } from 'react';
import { describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production app CSS.
import '../app/bridge-app.css';
import {
	annotationSessionId,
	RecordingAnnotationBrowserSurface,
} from './worktree-annotation-browser-test-support.js';
import {
	useWorktreeAnnotationEditorInstallationPreparation,
	useWorktreeAnnotationPrepareActiveEditorsForInstallation,
	useWorktreeAnnotationProjection,
	WorktreeAnnotationSurfaceProvider,
} from './worktree-annotation-surface-provider.js';
import { WorktreeAnnotationMessageEditor } from './worktree-annotation-thread-message.js';
import {
	makeSavedMessage,
	publishThreadMessages,
	rootMessageId,
	settleBrowserCondition,
} from './worktree-annotation-thread.browser.test-support.js';
import { WorktreeAnnotationNewMessageComposer } from './worktree-annotation-thread.js';

describe('worktree annotation editor installation preparation', () => {
	test('snapshots each active handler once and fails closed', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		let successfulHandlerCallCount = 0;
		let failingHandlerCallCount = 0;
		const rendered = await render(
			<WorktreeAnnotationSurfaceProvider surfaceClient={surface.client}>
				<InstallationPreparationRegistration
					editToken="annotation-edit-successful-preparation"
					prepare={async (): Promise<boolean> => {
						successfulHandlerCallCount += 1;
						return true;
					}}
				/>
				<InstallationPreparationRegistration
					editToken="annotation-edit-failing-preparation"
					prepare={async (): Promise<boolean> => {
						failingHandlerCallCount += 1;
						throw new Error('Preparation failed.');
					}}
				/>
				<InstallationPreparationTrigger />
			</WorktreeAnnotationSurfaceProvider>,
		);

		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Prepare active editors' }).click();
		});
		await expect
			.element(rendered.getByTestId('installation-preparation-result'))
			.toHaveTextContent('false');
		expect(successfulHandlerCallCount).toBe(1);
		expect(failingHandlerCallCount).toBe(1);
	});

	test('makes a typed new root durable without closing its composer', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		let cancelCallCount = 0;
		let savedCallCount = 0;
		const rendered = await render(
			<WorktreeAnnotationSurfaceProvider surfaceClient={surface.client}>
				<RootComposer
					onCancel={(): void => {
						cancelCallCount += 1;
					}}
					onSaved={(): void => {
						savedCallCount += 1;
					}}
				/>
				<InstallationPreparationTrigger />
			</WorktreeAnnotationSurfaceProvider>,
		);

		await act(async (): Promise<void> => {
			await rendered
				.getByRole('textbox', { name: 'Write an annotation in Markdown' })
				.fill('Durable root before installation');
		});
		await settleBrowserCondition(
			(): boolean => surface.sentOperations.some((operation) => operation.kind === 'root.create'),
			'Expected typed root preparation to begin durable creation.',
		);
		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Prepare active editors' }).click();
			surface.settleMostRecentCommitted(annotationSessionId, 1);
			await Promise.resolve();
		});
		await expect
			.element(rendered.getByTestId('installation-preparation-result'))
			.toHaveTextContent('true');
		await expect
			.element(rendered.getByRole('textbox', { name: 'Write an annotation in Markdown' }))
			.toBeVisible();
		expect(cancelCallCount).toBe(0);
		expect(savedCallCount).toBe(0);
	});

	test('rejects an empty unpersisted root without closing it', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		let cancelCallCount = 0;
		const rendered = await render(
			<WorktreeAnnotationSurfaceProvider surfaceClient={surface.client}>
				<RootComposer
					onCancel={(): void => {
						cancelCallCount += 1;
					}}
					onSaved={(): void => {}}
				/>
				<InstallationPreparationTrigger />
			</WorktreeAnnotationSurfaceProvider>,
		);

		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Prepare active editors' }).click();
		});
		await expect
			.element(rendered.getByTestId('installation-preparation-result'))
			.toHaveTextContent('false');
		await expect
			.element(rendered.getByRole('textbox', { name: 'Write an annotation in Markdown' }))
			.toBeVisible();
		expect(cancelCallCount).toBe(0);
		expect(surface.sentOperations.some((operation) => operation.kind === 'root.create')).toBe(
			false,
		);
	});

	test('flushes an existing message editor without finishing the edit', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		let finishEditCallCount = 0;
		const rendered = await render(
			<WorktreeAnnotationSurfaceProvider surfaceClient={surface.client}>
				<AnnotationMessagePreparationFixture
					onFinishEdit={(): void => {
						finishEditCallCount += 1;
					}}
				/>
			</WorktreeAnnotationSurfaceProvider>,
		);
		await publishThreadMessages(surface, [
			makeSavedMessage({ body: 'Existing saved body.', messageId: rootMessageId }),
		]);

		await act(async (): Promise<void> => {
			await rendered.getByText('Existing saved body.').click();
		});
		const editor = rendered.getByRole('textbox', { name: 'Annotation Markdown' });
		await expect.element(editor).toBeEnabled();
		await act(async (): Promise<void> => {
			await editor.fill('Existing body made durable before installation');
		});
		await settleBrowserCondition(
			(): boolean => surface.sentOperations.some((operation) => operation.kind === 'draft.flush'),
			'Expected the existing editor to start its first durable flush.',
		);
		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Prepare active editors' }).click();
			surface.settleMostRecentCommitted(annotationSessionId, 1);
			await Promise.resolve();
		});
		await expect
			.element(rendered.getByTestId('installation-preparation-result'))
			.toHaveTextContent('true');
		await expect.element(editor).toBeVisible();
		expect(finishEditCallCount).toBe(0);
	});
});

function RootComposer(props: {
	readonly onCancel: () => void;
	readonly onSaved: () => void;
}): ReactElement {
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
			onCancel={props.onCancel}
			onSaved={props.onSaved}
			placeholder="Write an annotation in Markdown"
		/>
	);
}

function InstallationPreparationRegistration(props: {
	readonly editToken: string;
	readonly prepare: () => Promise<boolean>;
}): null {
	useWorktreeAnnotationEditorInstallationPreparation(props.editToken, props.prepare);
	return null;
}

function InstallationPreparationTrigger(): ReactElement {
	const prepareActiveEditorsForInstallation =
		useWorktreeAnnotationPrepareActiveEditorsForInstallation();
	const [result, setResult] = useState<boolean | null>(null);
	return (
		<>
			<button
				onClick={(): void => {
					void prepareActiveEditorsForInstallation().then(setResult);
				}}
				type="button"
			>
				Prepare active editors
			</button>
			<span data-testid="installation-preparation-result">
				{result === null ? 'pending' : String(result)}
			</span>
		</>
	);
}

function AnnotationMessagePreparationFixture(props: {
	readonly onFinishEdit: () => void;
}): ReactElement {
	const projection = useWorktreeAnnotationProjection();
	const message = projection.threads.at(0)?.messages.at(0);
	return (
		<>
			{message === undefined ? null : (
				<WorktreeAnnotationMessageEditor
					active
					canEdit
					commands={null}
					editToken="annotation-edit-existing-message-preparation"
					isEditing
					message={message}
					onBeginEdit={(): void => {}}
					onFinishEdit={props.onFinishEdit}
					ordinal={1}
					path="Sources/App/View.swift"
				/>
			)}
			<InstallationPreparationTrigger />
		</>
	);
}
