/**
 * Runner tracker for /lens-booboo and related commands
 *
 * Tracks execution time and findings for each analysis runner,
 * producing a summary of what each runner found.
 */
export class RunnerTracker {
    runners = [];
    onProgress;
    constructor(options) {
        this.onProgress = options?.onProgress;
    }
    /**
     * Run a function with timing and tracking
     */
    async run(name, runFn, _options) {
        const startMs = Date.now();
        const index = this.runners.length;
        const runner = {
            name,
            status: "running",
            findings: 0,
            elapsedMs: 0,
        };
        this.runners.push(runner);
        // Notify start
        this.onProgress?.(runner, index);
        try {
            const result = await runFn();
            const elapsedMs = Date.now() - startMs;
            // Extract findings if result has it
            const findings = typeof result === "object" &&
                result !== null &&
                "findings" in result &&
                typeof result.findings === "number"
                ? result.findings
                : 0;
            runner.status = "done";
            runner.elapsedMs = elapsedMs;
            runner.findings = findings;
            return result;
        }
        catch (err) {
            const elapsedMs = Date.now() - startMs;
            runner.status = "error";
            runner.elapsedMs = elapsedMs;
            runner.message = String(err);
            throw err;
        }
    }
    /**
     * Mark a runner as skipped (for when preconditions aren't met)
     */
    skip(name, message) {
        this.runners.push({
            name,
            status: "skipped",
            findings: 0,
            elapsedMs: 0,
            message,
        });
    }
    /**
     * Update findings for a runner (useful when findings are discovered asynchronously)
     */
    updateFindings(runnerName, findings) {
        const runner = this.runners.find((r) => r.name === runnerName);
        if (runner) {
            runner.findings = findings;
        }
    }
    /**
     * Get all tracked runners
     */
    getRunners() {
        return [...this.runners];
    }
    /**
     * Get summary statistics
     */
    getStats() {
        return {
            total: this.runners.length,
            done: this.runners.filter((r) => r.status === "done").length,
            skipped: this.runners.filter((r) => r.status === "skipped").length,
            errors: this.runners.filter((r) => r.status === "error").length,
            totalFindings: this.runners.reduce((sum, r) => sum + r.findings, 0),
            totalTimeMs: this.runners.reduce((sum, r) => sum + r.elapsedMs, 0),
        };
    }
    /**
     * Format a single runner result for display
     */
    formatRunner(runner, index) {
        const prefix = index !== undefined ? `[${index + 1}] ` : "";
        const statusIcon = runner.status === "done"
            ? "✓"
            : runner.status === "skipped"
                ? "⊘"
                : runner.status === "error"
                    ? "✗"
                    : "○";
        const findings = runner.findings > 0 ? ` (${runner.findings} findings)` : "";
        const time = this.formatElapsed(runner.elapsedMs);
        const message = runner.message ? ` — ${runner.message}` : "";
        return `${prefix}${statusIcon} ${runner.name}${findings} — ${time}${message}`;
    }
    /**
     * Format all runners as a summary table
     */
    formatSummary() {
        const lines = ["📊 Runner Summary:", ""];
        for (let i = 0; i < this.runners.length; i++) {
            lines.push(`  ${this.formatRunner(this.runners[i], i)}`);
        }
        const stats = this.getStats();
        lines.push("");
        lines.push(`  Total: ${stats.totalFindings} findings in ${this.formatElapsed(stats.totalTimeMs)}`);
        return lines.join("\n");
    }
    /**
     * Format elapsed time in human-readable form
     */
    formatElapsed(ms) {
        if (ms < 1000)
            return `${ms}ms`;
        if (ms < 60000)
            return `${(ms / 1000).toFixed(1)}s`;
        const mins = Math.floor(ms / 60000);
        const secs = ((ms % 60000) / 1000).toFixed(0);
        return `${mins}m${secs.padStart(2, "0")}s`;
    }
}
/**
 * Convenience function to create a tracker and run a sequence
 */
export async function runSequence(sequence, onProgress) {
    const tracker = new RunnerTracker({ onProgress });
    const results = [];
    for (const item of sequence) {
        const result = await tracker.run(item.name, item.run, {
            index: results.length,
            total: sequence.length,
        });
        results.push(result);
        // Update findings if handler provided
        if (item.onFindings) {
            const findings = item.onFindings(result);
            tracker.updateFindings(item.name, findings);
        }
    }
    return { results, tracker };
}
