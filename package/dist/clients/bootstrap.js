let bootstrapPromise = null;
export function loadBootstrapClients() {
    bootstrapPromise ??= (async () => {
        const [ruffMod, biomeMod, knipMod, todoMod, jscpdMod, typeCoverageMod, depCheckerMod, testRunnerMod, metricsMod, complexityMod, goMod, govulncheckMod, gitleaksMod, rustMod, agentBehaviorMod,] = await Promise.all([
            import("./ruff-client.js"),
            import("./biome-client.js"),
            import("./knip-client.js"),
            import("./todo-scanner.js"),
            import("./jscpd-client.js"),
            import("./type-coverage-client.js"),
            import("./dependency-checker.js"),
            import("./test-runner-client.js"),
            import("./metrics-client.js"),
            import("./complexity-client.js"),
            import("./go-client.js"),
            import("./govulncheck-client.js"),
            import("./gitleaks-client.js"),
            import("./rust-client.js"),
            import("./agent-behavior-client.js"),
        ]);
        return {
            ruffClient: new ruffMod.RuffClient(),
            biomeClient: new biomeMod.BiomeClient(),
            knipClient: new knipMod.KnipClient(),
            todoScanner: new todoMod.TodoScanner(),
            jscpdClient: new jscpdMod.JscpdClient(),
            typeCoverageClient: new typeCoverageMod.TypeCoverageClient(),
            depChecker: new depCheckerMod.DependencyChecker(),
            testRunnerClient: new testRunnerMod.TestRunnerClient(),
            metricsClient: new metricsMod.MetricsClient(),
            complexityClient: new complexityMod.ComplexityClient(),
            goClient: new goMod.GoClient(),
            govulncheckClient: new govulncheckMod.GovulncheckClient(),
            gitleaksClient: new gitleaksMod.GitleaksClient(),
            rustClient: new rustMod.RustClient(),
            agentBehaviorClient: new agentBehaviorMod.AgentBehaviorClient(),
        };
    })();
    return bootstrapPromise;
}
