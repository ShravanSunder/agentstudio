import { useEffect } from 'react';
import { z } from 'zod';

import { bridgeProductIdentifierSchema } from '../core/comm-worker/bridge-product-contract-primitives.js';
import type { WorktreeAnnotationEditorPreparationRegistry } from '../worktree-annotations/worktree-annotation-editor-preparation-registry.js';

/**
 * Native navigation barrier. Before native removes displayed content or
 * replaces a source, it dispatches this event and awaits the probe promise in
 * the same page call, so the answer is bound to that request on this page.
 */
export const bridgeNativeEditorPreparationEventName = '__bridge_editor_preparation';

export const bridgeNativeEditorPreparationRequestSchema = z
	.object({ requestId: bridgeProductIdentifierSchema })
	.strict();

export interface BridgeNativeEditorPreparationResult {
	readonly requestId: string;
	readonly status: 'failed' | 'prepared';
}

declare global {
	interface Window {
		bridgeEditorPreparationProbe?: Promise<BridgeNativeEditorPreparationResult>;
	}
}

export function prepareBridgeEditorsForNativeRequest(
	registry: WorktreeAnnotationEditorPreparationRegistry,
	detail: unknown,
): Promise<BridgeNativeEditorPreparationResult> | null {
	const request = bridgeNativeEditorPreparationRequestSchema.safeParse(detail);
	if (!request.success) return null;
	return registry.prepareAllActiveEditors().then(
		(prepared): BridgeNativeEditorPreparationResult => ({
			requestId: request.data.requestId,
			status: prepared ? 'prepared' : 'failed',
		}),
	);
}

export function useBridgeAppNativeEditorPreparation(
	registry: WorktreeAnnotationEditorPreparationRegistry,
): void {
	useEffect((): (() => void) | undefined => {
		if (typeof window === 'undefined') return undefined;
		const handlePreparationRequest = (event: Event): void => {
			const detail = 'detail' in event ? event.detail : null;
			const preparation = prepareBridgeEditorsForNativeRequest(registry, detail);
			if (preparation === null) {
				delete window.bridgeEditorPreparationProbe;
				return;
			}
			window.bridgeEditorPreparationProbe = preparation;
		};
		window.addEventListener(bridgeNativeEditorPreparationEventName, handlePreparationRequest);
		return (): void => {
			window.removeEventListener(bridgeNativeEditorPreparationEventName, handlePreparationRequest);
		};
	}, [registry]);
}
