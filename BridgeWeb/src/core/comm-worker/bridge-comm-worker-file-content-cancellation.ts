export function abortBridgeCommWorkerFileContentPreparation(props: {
	readonly abortControllersByItemId: Map<string, AbortController>;
	readonly generationByItemId: Map<string, number>;
	readonly itemId: string;
}): void {
	const abortController = props.abortControllersByItemId.get(props.itemId);
	if (abortController === undefined) return;
	props.generationByItemId.set(props.itemId, (props.generationByItemId.get(props.itemId) ?? 0) + 1);
	props.abortControllersByItemId.delete(props.itemId);
	abortController.abort();
}

export function abortAllBridgeCommWorkerFileContentPreparations(props: {
	readonly abortControllersByItemId: Map<string, AbortController>;
	readonly generationByItemId: Map<string, number>;
}): void {
	for (const itemId of props.abortControllersByItemId.keys()) {
		abortBridgeCommWorkerFileContentPreparation({ ...props, itemId });
	}
}
