# Observability and measurement overhead

## Volume

The production capture exported approximately 24,903 logs in nine minutes. The trailing two-minute window contained about 3,906 logs (32.6/s): roughly 22 Ghostty logs/s and 10.6 performance logs/s.

The debug launcher deliberately enables wildcard trace tags. Its fresh idle capture produced 589 records, 348 terminal/Ghostty records, and 88 runtime-delivery records in roughly 77 seconds. That is proof of export liveness, not proof of production CPU cost.

## Boundaries

Trace events are drained on a detached utility worker. OTLP log batching has a bounded queue and one-second schedule; metrics export is much slower. Performance records update metrics as well as logs. The app trace queue is bounded, but ordinary record-yield results are not exposed as a current metric.

## Findings

`accepted` — diagnostic volume is non-trivial and can perturb a measured workload.

`accepted` — the earlier unfiltered production sample found OTLP dispatch in only about 1.6% of active intervals, far below Git status and Repo Explorer list diffing.

`refuted` — available evidence does not support OTLP export as the primary cause of the 15% production CPU or as a MainActor blocker.

`unresolved` — the exact trace-queue shedding/export CPU cost is not measurable from current telemetry. A controlled same-workload trace-tags-on/off comparison is required before assigning a remediation priority.

The focused atom-tag diagnostic demonstrates why that comparison matters. With
the `atoms` tag enabled, the isolated debug marker emitted 11,233 atom-read
records and the process log reported OTLP batch queue drops of 7,583, 5,873,
and 3,473 records at a queue size of 8,192. An AppKit warning also reported a
reentrant `NSTableView` delegate operation. The marker's main-thread sample was
mostly waiting, so these observations establish telemetry perturbation and a
separate UI warning, not OTLP as the production MainActor cause.

## Measurement caveat

One-second VictoriaLogs delivery snapshots recorded a startup EventBus debt peak of 987, while sparse VictoriaMetrics gauges reported 112. Use log snapshots for short-lived pressure and metrics for longer-lived rates; do not infer that the metric maximum is the true peak.
