interface StepDwellProps {
  readonly labelTimes: readonly number[];
  readonly timelineDuration: number;
  readonly proofSeconds: number;
  readonly replayDelaySeconds: number;
}

/** A step remains current for its own scene beat, proof video, and replay hold. */
export function computeStepDwellSeconds(props: StepDwellProps): readonly number[] {
  return props.labelTimes.map((labelTime, stepIndex) => {
    const nextLabelTime = props.labelTimes[stepIndex + 1];
    const seconds =
      nextLabelTime === undefined
        ? props.timelineDuration - labelTime + props.proofSeconds + props.replayDelaySeconds
        : nextLabelTime - labelTime;
    return Number(seconds.toFixed(6));
  });
}
