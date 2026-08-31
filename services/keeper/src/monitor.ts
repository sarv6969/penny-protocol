import type { StepRecord } from "./state.js";

/**
 * Monitoring hook (Phase 9): every step outcome is reported through `Metrics`. The default
 * `DevMetrics` keeps an in-memory series for tests/human eyeballs; a production sink (metrics
 * endpoint, alerting) implements the same interface. Nothing here fakes alerting.
 *
 * Timing: `record` takes an optional per-step latency in milliseconds, `beginCycle` /
 * `endCycle` bracket a keeper cycle so `summary()` can expose a cycle-duration timer, and
 * per-job success/skip/fail counters keep running totals without rescanning history. This
 * module is deliberately dependency-free — no telemetry client, no sampling, no network.
 */

/** Per-job tally of terminal step outcomes. */
export interface StepCounter {
  succeeded: number;
  skipped: number;
  failed: number;
}

/** Small, JSON-safe snapshot returned by `Metrics.summary()`. */
export interface MetricsSummary {
  steps: number;
  succeeded: number;
  skipped: number;
  failed: number;
  cycles: number;
  failedCycles: number;
  jobs: Record<string, StepCounter>;
  /** Per-step latency statistics, ms. Present once a timing has been recorded. */
  latencyMs?: {
    min: number;
    max: number;
    total: number;
    count: number;
    last: number;
  };
  /** Cycle-duration statistics, ms. Present once a cycle has been timed. */
  cycleMs?: {
    min: number;
    max: number;
    total: number;
    count: number;
    last: number;
  };
}

export interface Metrics {
  record(step: StepRecord, latencyMs?: number): void;
  heartbeat(cycleId: string, ok: boolean, atBlock?: number): void;
  beginCycle(cycleId: string): void;
  endCycle(cycleId: string, ok: boolean): void;
  summary(): MetricsSummary;
}

/** Monotonic accumulator for millisecond timings (per-step latency / cycle duration). */
class Timing {
  private min = Number.POSITIVE_INFINITY;
  private max = 0;
  private total = 0;
  private count = 0;
  private last = 0;

  push(ms: number): void {
    this.count += 1;
    this.total += ms;
    this.last = ms;
    if (ms < this.min) this.min = ms;
    if (ms > this.max) this.max = ms;
  }

  get():
    | { min: number; max: number; total: number; count: number; last: number }
    | undefined {
    if (this.count === 0) return undefined;
    return {
      min: this.min,
      max: this.max,
      total: this.total,
      count: this.count,
      last: this.last,
    };
  }
}

/** Shared accounting for in-memory sinks: series, timers and per-job counters. */
abstract class Monitor implements Metrics {
  rows: StepRecord[] = [];
  heartbeats: number = 0;
  protected readonly jobCounters = new Map<string, StepCounter>();
  private readonly cycleStarts = new Map<string, number>();
  private readonly stepTiming = new Timing();
  private readonly cycleTiming = new Timing();
  private cycles = 0;
  private failedCycles = 0;

  record(step: StepRecord, latencyMs?: number): void {
    this.rows.push(step);
    if (latencyMs !== undefined) this.stepTiming.push(latencyMs);
    const counter = this.jobCounters.get(step.job) ?? {
      succeeded: 0,
      skipped: 0,
      failed: 0,
    };
    if (step.status === "succeeded") counter.succeeded += 1;
    else if (step.status === "skipped") counter.skipped += 1;
    else if (step.status === "failed") counter.failed += 1;
    this.jobCounters.set(step.job, counter);
  }

  heartbeat(_cycleId: string, _ok: boolean, _atBlock?: number): void {
    this.heartbeats += 1;
  }

  beginCycle(cycleId: string): void {
    this.cycles += 1;
    this.cycleStarts.set(cycleId, performance.now());
  }

  endCycle(cycleId: string, ok: boolean): void {
    const start = this.cycleStarts.get(cycleId);
    if (start !== undefined) this.cycleTiming.push(performance.now() - start);
    this.cycleStarts.delete(cycleId);
    if (!ok) this.failedCycles += 1;
  }

  summary(): MetricsSummary {
    const jobs: Record<string, StepCounter> = {};
    for (const [job, counter] of this.jobCounters) jobs[job] = { ...counter };
    const summary: MetricsSummary = {
      steps: this.rows.length,
      succeeded: 0,
      skipped: 0,
      failed: 0,
      cycles: this.cycles,
      failedCycles: this.failedCycles,
      jobs,
    };
    for (const counter of this.jobCounters.values()) {
      summary.succeeded += counter.succeeded;
      summary.skipped += counter.skipped;
      summary.failed += counter.failed;
    }
    const latencyMs = this.stepTiming.get();
    const cycleMs = this.cycleTiming.get();
    if (latencyMs !== undefined) summary.latencyMs = latencyMs;
    if (cycleMs !== undefined) summary.cycleMs = cycleMs;
    return summary;
  }
}

export class DevMetrics extends Monitor {}

/** Human-readable series (stdout) for a headful keeper run. */
export class ConsoleMetrics extends Monitor {
  record(step: StepRecord, latencyMs?: number): void {
    super.record(step, latencyMs);
    const tag = step.status.toUpperCase().padEnd(9);
    console.log(
      `[keeper] ${step.cycleId} ${step.job} ${tag}${step.detail ? ` — ${step.detail}` : ""}${step.lastError ? ` — ${step.lastError}` : ""}${latencyMs !== undefined ? ` — ${latencyMs.toFixed(0)}ms` : ""}`,
    );
  }

  heartbeat(cycleId: string, ok: boolean, atBlock?: number): void {
    super.heartbeat(cycleId, ok, atBlock);
    console.log(
      `[keeper] heartbeat cycle=${cycleId} ok=${ok}${atBlock !== undefined ? ` block=${atBlock}` : ""}`,
    );
  }

  beginCycle(cycleId: string): void {
    super.beginCycle(cycleId);
    console.log(`[keeper] cycle ${cycleId} begin`);
  }

  endCycle(cycleId: string, ok: boolean): void {
    super.endCycle(cycleId, ok);
    console.log(`[keeper] cycle ${cycleId} end ok=${ok}`);
  }
}
