export class RecordingBridgeCommWorker extends EventTarget implements Worker {
	onmessage: ((this: Worker, event: MessageEvent) => void) | null = null;
	onmessageerror: ((this: Worker, event: MessageEvent) => void) | null = null;
	onerror: ((this: AbstractWorker, event: ErrorEvent) => void) | null = null;
	readonly postedMessages: unknown[] = [];
	terminateCount = 0;
	throwOnNextPostMessage = false;

	override addEventListener<KEventName extends keyof WorkerEventMap>(
		type: KEventName,
		listener: (this: Worker, event: WorkerEventMap[KEventName]) => void,
		options?: boolean | AddEventListenerOptions,
	): void;
	override addEventListener(
		type: string,
		listener: EventListenerOrEventListenerObject | null,
		options?: boolean | AddEventListenerOptions,
	): void;
	override addEventListener(
		type: string,
		listener: EventListenerOrEventListenerObject | null,
		options?: boolean | AddEventListenerOptions,
	): void {
		super.addEventListener(type, listener, options);
	}

	override removeEventListener<KEventName extends keyof WorkerEventMap>(
		type: KEventName,
		listener: (this: Worker, event: WorkerEventMap[KEventName]) => void,
		options?: boolean | EventListenerOptions,
	): void;
	override removeEventListener(
		type: string,
		listener: EventListenerOrEventListenerObject | null,
		options?: boolean | EventListenerOptions,
	): void;
	override removeEventListener(
		type: string,
		listener: EventListenerOrEventListenerObject | null,
		options?: boolean | EventListenerOptions,
	): void {
		super.removeEventListener(type, listener, options);
	}

	postMessage(message: unknown): void {
		if (this.throwOnNextPostMessage) {
			this.throwOnNextPostMessage = false;
			throw new Error('worker postMessage failed');
		}
		this.postedMessages.push(message);
	}

	terminate(): void {
		this.terminateCount += 1;
	}

	override dispatchEvent(event: Event): boolean {
		return super.dispatchEvent(event);
	}

	emitMessage(message: unknown): void {
		this.dispatchEvent(new MessageEvent('message', { data: message }));
	}

	emitError(): void {
		this.dispatchEvent(new Event('error'));
	}
}
