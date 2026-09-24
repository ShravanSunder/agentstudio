import { createContext, useContext, useEffect } from 'react';

/**
 * Every annotation surface of one Bridge page (Files and Review each own one
 * `WorktreeAnnotationSurfaceProvider`) registers its existing editor
 * preparation here, so a native navigation barrier can flush every active
 * editor on the page at once before it removes content or replaces a source.
 */
export interface WorktreeAnnotationEditorPreparationRegistry {
	/** Resolves `true` only when every registered surface prepared its editors. */
	readonly prepareAllActiveEditors: () => Promise<boolean>;
	readonly register: (prepareActiveEditors: () => Promise<boolean>) => () => void;
}

export function createWorktreeAnnotationEditorPreparationRegistry(): WorktreeAnnotationEditorPreparationRegistry {
	const registrations = new Map<symbol, () => Promise<boolean>>();
	return {
		prepareAllActiveEditors: async (): Promise<boolean> => {
			const results = await Promise.all(
				[...registrations.values()].map(async (prepare): Promise<boolean> => {
					try {
						return await prepare();
					} catch {
						return false;
					}
				}),
			);
			return results.every((prepared): boolean => prepared);
		},
		register: (prepareActiveEditors): (() => void) => {
			const registrationId = Symbol('worktree-annotation-editor-preparation');
			registrations.set(registrationId, prepareActiveEditors);
			return (): void => {
				registrations.delete(registrationId);
			};
		},
	};
}

export const worktreeAnnotationEditorPreparationRegistryContext =
	createContext<WorktreeAnnotationEditorPreparationRegistry | null>(null);

/** Registers one surface's editor preparation with the page registry, when present. */
export function useWorktreeAnnotationEditorPreparationRegistration(
	prepareActiveEditors: () => Promise<boolean>,
): void {
	const registry = useContext(worktreeAnnotationEditorPreparationRegistryContext);
	useEffect(
		(): (() => void) | undefined => registry?.register(prepareActiveEditors),
		[prepareActiveEditors, registry],
	);
}
