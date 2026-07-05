export type BridgeWorkerPierreRenderKind = 'reviewDiff' | 'fileText';
export type BridgeWorkerPierreBudgetClass = 'interactive' | 'visible' | 'background';
export type BridgeWorkerDemandLane =
	| 'selected'
	| 'visible'
	| 'nearby'
	| 'speculative'
	| 'background';

export interface BridgeWorkerDemandRank {
	readonly lane: BridgeWorkerDemandLane;
	readonly priority: number;
}

export interface BridgeWorkerPierreRenderWindow {
	readonly startLine: number;
	readonly endLine: number;
	readonly totalLineCount: number;
}

export interface BridgeWorkerPierreRenderPayload {
	readonly kind: 'textWindow';
	readonly textBytes: ArrayBuffer;
}

export interface BridgeWorkerPierreRenderBudget {
	readonly className: BridgeWorkerPierreBudgetClass;
	readonly maxBytes: number;
	readonly maxWindowLines: number;
}

export interface BuildBridgeWorkerPierreRenderJobProps {
	readonly itemId: string;
	readonly renderKind: BridgeWorkerPierreRenderKind;
	readonly contentCacheKey: string;
	readonly contentHash: string;
	readonly language: string;
	readonly bridgeDemandRank: BridgeWorkerDemandRank;
	readonly window: BridgeWorkerPierreRenderWindow;
	readonly payload: BridgeWorkerPierreRenderPayload;
	readonly budget: BridgeWorkerPierreRenderBudget;
}

export interface BridgeWorkerPierreRenderJob extends BuildBridgeWorkerPierreRenderJobProps {
	readonly budgetClass: BridgeWorkerPierreBudgetClass;
	readonly payloadByteLength: number;
	readonly windowLineCount: number;
}

export function buildBridgeWorkerPierreRenderJob(
	props: BuildBridgeWorkerPierreRenderJobProps,
): BridgeWorkerPierreRenderJob {
	const payloadByteLength = props.payload.textBytes.byteLength;
	const windowLineCount = props.window.endLine - props.window.startLine + 1;
	if (windowLineCount < 0) {
		throw new Error('Bridge worker Pierre render job has an invalid line window.');
	}
	if (payloadByteLength > props.budget.maxBytes) {
		throw new Error(
			`Bridge worker Pierre render job exceeds byte budget: ${payloadByteLength} > ${props.budget.maxBytes}.`,
		);
	}
	if (windowLineCount > props.budget.maxWindowLines) {
		throw new Error(
			`Bridge worker Pierre render job exceeds line budget: ${windowLineCount} > ${props.budget.maxWindowLines}.`,
		);
	}

	return {
		...props,
		budgetClass: props.budget.className,
		payloadByteLength,
		windowLineCount,
	};
}
