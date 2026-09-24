import { describe, expect, test } from 'vitest';

import { createWorktreeAnnotationEditorPreparationRegistry } from '../worktree-annotations/worktree-annotation-editor-preparation-registry.js';
import { prepareBridgeEditorsForNativeRequest } from './bridge-app-native-editor-preparation.js';

describe('prepareBridgeEditorsForNativeRequest', () => {
	test('reports prepared once every surface flushed its active editors', async () => {
		// Arrange
		const registry = createWorktreeAnnotationEditorPreparationRegistry();
		const preparedSurfaces: string[] = [];
		registry.register(async (): Promise<boolean> => {
			preparedSurfaces.push('file');
			return true;
		});
		registry.register(async (): Promise<boolean> => {
			preparedSurfaces.push('review');
			return true;
		});

		// Act
		const result = await prepareBridgeEditorsForNativeRequest(registry, {
			requestId: 'native-preparation-1',
		});

		// Assert
		expect(result).toEqual({ requestId: 'native-preparation-1', status: 'prepared' });
		expect(preparedSurfaces.sort()).toEqual(['file', 'review']);
	});

	test('reports failed when any surface cannot flush, including a thrown flush', async () => {
		// Arrange
		const registry = createWorktreeAnnotationEditorPreparationRegistry();
		registry.register(async (): Promise<boolean> => true);
		registry.register(async (): Promise<boolean> => {
			throw new Error('draft.flush was not acknowledged');
		});

		// Act
		const result = await prepareBridgeEditorsForNativeRequest(registry, {
			requestId: 'native-preparation-2',
		});

		// Assert
		expect(result).toEqual({ requestId: 'native-preparation-2', status: 'failed' });
	});

	test('no longer asks a surface that unregistered', async () => {
		// Arrange
		const registry = createWorktreeAnnotationEditorPreparationRegistry();
		const unregister = registry.register(async (): Promise<boolean> => false);
		unregister();

		// Act
		const result = await prepareBridgeEditorsForNativeRequest(registry, {
			requestId: 'native-preparation-3',
		});

		// Assert
		expect(result?.status).toBe('prepared');
	});

	test('ignores a malformed request so native sees no answer', () => {
		// Arrange
		const registry = createWorktreeAnnotationEditorPreparationRegistry();

		// Act
		const result = prepareBridgeEditorsForNativeRequest(registry, { requestId: '' });

		// Assert
		expect(result).toBeNull();
	});
});
