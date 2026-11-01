import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const [host, closure] = process.argv.slice(2);
assert.ok(host && closure, "Usage: node failover.smoke.mjs <Pi package root> <package closure>");
const home = mkdtempSync(join(tmpdir(), "pi-failover-smoke-"));
Object.assign(process.env, {
  HOME: home,
  PI_CODING_AGENT_DIR: join(home, ".pi/agent"),
  PI_SUBAGENTS_PI_CODING_AGENT_PACKAGE_ROOT: host,
  PI_TELEMETRY: "0",
  PI_SKIP_VERSION_CHECK: "1",
});
const agentDir = process.env.PI_CODING_AGENT_DIR;
mkdirSync(agentDir, { recursive: true, mode: 0o700 });
// Never contact a real provider or resolve production credentials in this test.
globalThis.fetch = async () => new Response("{}", { status: 503 });
const routes = ["openai-codex/gpt-6.1-sol", "openai/gpt-6.1-sol"];
writeFileSync(join(agentDir, "provider-failover.json"), JSON.stringify({
  enabled: true, autoContinue: false, autoDiscover: false,
  autoDiscoverModels: false, childProxy: false, antigravitySubscription: false,
  followLastSuccessfulModel: false, contextGuard: false, debugLog: false,
  showUsage: false, fallbacks: routes,
}), { mode: 0o600 });
writeFileSync(join(agentDir, "auth.json"), JSON.stringify({
  "openai-codex": {
    type: "oauth", access: "fixture-not-a-real-token",
    refresh: "fixture-not-a-real-refresh", expires: Date.now() + 3600000,
  },
  openai: { type: "api_key", key: "fixture-not-a-real-key" },
}), { mode: 0o600 });
const { createAgentSession, DefaultResourceLoader, SessionManager, SettingsManager } =
  await import(pathToFileURL(join(host, "dist/index.js")).href);
const settingsManager = SettingsManager.inMemory({
  packages: [join(closure, "node_modules/pi-multi-account")],
  defaultProvider: "openai-codex", defaultModel: "gpt-6.1-sol",
  enableAnalytics: false, enableInstallTelemtry: false,
});
const resourceLoader = new DefaultResourceLoader({
  cwd: home, agentDir, settingsManager, noContextFiles: true,
});
await resourceLoader.reload();
assert.deepEqual(resourceLoader.getExtensions().errors, []);
const { session } = await createAgentSession({
  cwd: home, agentDir, settingsManager, resourceLoader,
  sessionManager: SessionManager.inMemory(home),
});
try {
  for (const provider of ["openai-codex", "openai"])
    assert.ok(session.modelRuntime.getModel(provider, "gpt-6.1-sol"), `Missing ${provider}/gpt-6.1-sol`);
  const errors = [];
  await session.bindExtensions({ onError: error => errors.push(error) });
  assert.equal(session.model.provider, "openai-codex");
  const command = session.extensionRunner.getCommand("multi-account");
  assert.ok(command);
  await session.extensionRunner.emit({
    type: "message_end",
    message: {
      role: "assistant", provider: "openai-codex", model: "gpt-6.1-sol",
      api: "openai-codex-responses", content: [],
      usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0,
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } },
      stopReason: "error", errorMessage: "429 usage limit reached. Try again in 5 hours.",
      timestamp: Date.now(),
    },
  });
  assert.equal(session.model.provider, "openai", "Quota refusal must switch to API");
  assert.equal(session.model.id, "gpt-6.1-sol");
  await command.handler("switch openai-codex/gpt-6.1-sol", session.extensionRunner.createContext());
  assert.equal(session.model.provider, "openai-codex", "Manual return must work");
  assert.deepEqual(errors, []);
  assert.deepEqual(JSON.parse(readFileSync(join(agentDir, "provider-failover.json"), "utf8")).fallbacks, routes);
  console.log("PASS: Codex startup; simulated quota → API; manual return → Codex; no live inference.");
} finally {
  session.dispose();
}
process.exit(0);
