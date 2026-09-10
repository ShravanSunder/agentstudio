import type { Page } from 'playwright';

// Observe metadata at the product MessagePort; forward observed sends unchanged.
export async function installReviewRenderObservation(props: {
	readonly itemId: string;
	readonly page: Page;
}): Promise<void> {
	await props.page.addInitScript(
		({ itemId }): void => {
			const firstEvents: Readonly<Record<string, unknown>>[] = [];
			const recentEvents: Readonly<Record<string, unknown>>[] = [];
			const annotationEvents: Readonly<Record<string, unknown>>[] = [];
			const pendingPublications = new Map<string, Readonly<Record<string, unknown>>>();
			let discardedPublicationCount = 0;
			const recentReceipts: Readonly<Record<string, unknown>>[] = [];
			const healthEvents: Readonly<Record<string, unknown>>[] = [];
			let observedEventCount = 0;
			let previousContentFacts: string | null = null;
			let previousDescriptors: string | null = null;
			// oxlint-disable-next-line unicorn/consistent-function-scoping -- Playwright serializes this self-contained callback into the browser realm.
			const isRecord = (value: unknown): value is Readonly<Record<string, unknown>> =>
				typeof value === 'object' && value !== null && !Array.isArray(value);
			// oxlint-disable-next-line unicorn/consistent-function-scoping -- Playwright serializes this callback into the browser realm.
			const receiptKey = (identity: Readonly<Record<string, unknown>>): string =>
				JSON.stringify([
					identity['workerInstanceId'],
					identity['workerDerivationEpoch'],
					identity['itemId'],
					identity['publicationId'],
					identity['publicationSequence'],
					identity['attemptId'],
					identity['submissionId'],
				]);
			const observeSentCommand = (message: unknown): void => {
				if (
					!isRecord(message) ||
					message['command'] !== 'renderDisposition' ||
					!Array.isArray(message['receipts'])
				)
					return;
				for (const receipt of message['receipts']) {
					if (!isRecord(receipt) || receipt['surface'] !== 'review') continue;
					const key = receiptKey(receipt);
					recentReceipts.push({
						key,
						disposition: receipt['disposition'],
						reason: receipt['reason'],
						atMilliseconds: Math.round(performance.now()),
					});
					if (recentReceipts.length > 64) recentReceipts.shift();
					if (['queued', 'rejected', 'superseded'].includes(String(receipt['disposition'])))
						pendingPublications.delete(key);
				}
			};
			const record = (value: Readonly<Record<string, unknown>>): void => {
				observedEventCount += 1;
				const observation = { ...value, atMilliseconds: Math.round(performance.now()) };
				if (firstEvents.length < 16) firstEvents.push(observation);
				else {
					recentEvents.push(observation);
					if (recentEvents.length > 12) recentEvents.shift();
				}
			};
			const observeDisplayItem = (
				item: unknown,
				common: Readonly<Record<string, unknown>>,
			): void => {
				if (!isRecord(item) || !isRecord(item['metadata'])) return;
				const metadata = item['metadata'];
				if (metadata['itemId'] !== itemId) return;
				const contentFacts = JSON.stringify(item['contentFacts']);
				const descriptors = JSON.stringify(metadata['contentDescriptorIdsByRole']);
				record({
					...common,
					contentFactsChanged:
						previousContentFacts !== null && previousContentFacts !== contentFacts,
					contentFactCount: Array.isArray(item['contentFacts'])
						? item['contentFacts'].length
						: null,
					descriptorsChanged: previousDescriptors !== null && previousDescriptors !== descriptors,
					roles: metadata['contentRoles'],
				});
				previousContentFacts = contentFacts;
				previousDescriptors = descriptors;
			};
			const observeMessage = (event: MessageEvent<unknown>): void => {
				const message = event.data;
				if (!isRecord(message)) return;
				if (message['kind'] === 'health') {
					healthEvents.push({
						status: message['status'],
						requestId: message['requestId'],
						atMilliseconds: Math.round(performance.now()),
					});
					if (healthEvents.length > 16) healthEvents.shift();
				}
				if (message['surface'] !== 'review') return;
				if (
					message['kind'] === 'reviewPierreRenderJob' &&
					isRecord(message['renderReceiptIdentity'])
				) {
					const key = receiptKey(message['renderReceiptIdentity']);
					pendingPublications.set(key, { key, atMilliseconds: Math.round(performance.now()) });
					if (pendingPublications.size > 64) {
						const oldest = pendingPublications.keys().next().value;
						if (oldest !== undefined) {
							pendingPublications.delete(oldest);
							discardedPublicationCount += 1;
						}
					}
				}
				const common = {
					epoch: message['epoch'],
					kind: message['kind'],
					publication: message['reviewPublicationIdentity'] ?? {
						packageId: message['packageId'],
						publicationId: message['publicationId'],
						reviewGeneration: message['reviewGeneration'],
						revision: message['revision'],
						sourceIdentity: message['sourceIdentity'],
					},
					publicationSequence: message['publicationSequence'],
					sequence: message['sequence'],
					workerDerivationEpoch: message['workerDerivationEpoch'],
				};
				if (message['kind'] === 'annotationProjectionConvergence') {
					const state = message['state'];
					const snapshot = isRecord(state) ? state['snapshot'] : null;
					annotationEvents.push({
						atMilliseconds: Math.round(performance.now()),
						kind: message['kind'],
						state: isRecord(state) ? state['kind'] : null,
						publication: isRecord(state) ? state['reviewPublicationIdentity'] : null,
						contentSessionIds: isRecord(state) ? state['contentSessionIds'] : null,
						threadCount:
							isRecord(snapshot) && Array.isArray(snapshot['threads'])
								? snapshot['threads'].length
								: null,
						sessions:
							isRecord(snapshot) && Array.isArray(snapshot['sessions'])
								? snapshot['sessions'].slice(0, 8).map((session: unknown) =>
										isRecord(session)
											? {
													sessionId: session['sessionId'],
													revision: session['semanticRevision'],
													state: session['state'],
												}
											: null,
									)
								: null,
					});
					if (annotationEvents.length > 24) annotationEvents.shift();
					return;
				}
				if (message['kind'] === 'annotationCatalogStaging') {
					const transfer = message['transfer'];
					if (isRecord(transfer) && transfer['kind'] === 'catalog.commit') {
						annotationEvents.push({
							atMilliseconds: Math.round(performance.now()),
							kind: message['kind'],
							authority: message['authority'],
							revision: transfer['catalogRevision'],
							entryCount: transfer['entryCount'],
						});
						if (annotationEvents.length > 24) annotationEvents.shift();
					}
					return;
				}
				if (message['kind'] === 'reviewPierreRenderJob') {
					const job = message['job'];
					if (isRecord(job) && job['itemId'] === itemId) record(common);
					return;
				}
				if (
					message['kind'] === 'reviewCandidateStarted' ||
					message['kind'] === 'reviewCandidateFailed' ||
					message['kind'] === 'reviewCandidateReady'
				) {
					record({ ...common, reason: message['reason'] });
					return;
				}
				if (!Array.isArray(message['patches'])) return;
				for (const patch of message['patches']) {
					if (!isRecord(patch)) continue;
					const patchCommon = { ...common, operation: patch['operation'], slice: patch['slice'] };
					if (message['kind'] === 'reviewRenderPatch') {
						if (patch['itemId'] !== itemId && patch['operation'] !== 'reset') continue;
						const payload = patch['payload'];
						record({
							...patchCommon,
							reason: isRecord(payload) ? payload['reason'] : null,
							state: isRecord(payload) ? payload['state'] : null,
						});
						continue;
					}
					if (message['kind'] !== 'reviewDisplayPatch' || patch['slice'] !== 'reviewItem') continue;
					if (patch['operation'] === 'reset') {
						record(patchCommon);
						continue;
					}
					const payload = patch['payload'];
					if (!isRecord(payload)) continue;
					if (payload['reset'] === true) record({ ...patchCommon, reset: true });
					if (Array.isArray(payload['items'])) {
						for (const item of payload['items']) observeDisplayItem(item, patchCommon);
					}
					if (!Array.isArray(payload['operations'])) continue;
					for (const operation of payload['operations']) {
						if (!isRecord(operation)) continue;
						const operationCommon = { ...patchCommon, operationKind: operation['operationKind'] };
						if (Array.isArray(operation['items'])) {
							for (const item of operation['items']) observeDisplayItem(item, operationCommon);
						}
						if (
							operation['operationKind'] === 'removeItems' &&
							Array.isArray(operation['itemIds']) &&
							operation['itemIds'].includes(itemId)
						) {
							record(operationCommon);
						}
					}
				}
			};
			const OriginalMessageChannel = globalThis.MessageChannel;
			globalThis.MessageChannel = class ObservedReviewChannel extends OriginalMessageChannel {
				constructor() {
					super();
					// BridgePaneCommWorkerSession keeps port2 on Main and transfers port1.
					// The production owner still starts/closes the port; the observer does neither.
					this.port2.addEventListener('message', observeMessage);
					const originalPostMessage = this.port2.postMessage.bind(this.port2);
					this.port2.postMessage = (
						message: unknown,
						options?: Transferable[] | StructuredSerializeOptions,
					): void => {
						if (Array.isArray(options)) originalPostMessage(message, options);
						else originalPostMessage(message, options);
						observeSentCommand(message);
					};
				}
			};
			Object.defineProperty(globalThis, '__bridgeReviewRenderObservation', {
				get: (): Readonly<Record<string, unknown>> => ({
					annotationEvents,
					discardedPublicationCount,
					healthEvents,
					pendingPublications: [...pendingPublications.values()],
					recentReceipts,
					firstEvents,
					itemId,
					observedEventCount,
					recentEvents,
				}),
			});
		},
		{ itemId: props.itemId },
	);
}

export async function readReviewRenderObservation(page: Page): Promise<unknown> {
	return await page.evaluate((): unknown =>
		Reflect.get(globalThis, '__bridgeReviewRenderObservation'),
	);
}

export async function requireReviewRenderObservationStarted(page: Page): Promise<void> {
	const observation = await readReviewRenderObservation(page);
	if (
		typeof observation !== 'object' ||
		observation === null ||
		!('observedEventCount' in observation) ||
		typeof observation.observedEventCount !== 'number' ||
		observation.observedEventCount === 0
	) {
		throw new Error(
			'Review render observer did not witness the selected item on the product MessagePort.',
		);
	}
}
