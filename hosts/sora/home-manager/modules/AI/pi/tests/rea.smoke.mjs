import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { once } from "node:events";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createInterface } from "node:readline";

const [entry] = process.argv.slice(2);
assert.ok(entry, "Usage: node rea.smoke.mjs <rea entry script>");
const home = mkdtempSync(join(tmpdir(), "rea-smoke-"));
// No production credentials, ambient REA settings, or user configuration.
const env = { HOME: home, PATH: process.env.PATH, REA_MCP_OUTPUT_SCHEMA_PROFILE: "off" };
const cli = spawnSync(process.execPath, [entry, "--version"], { cwd: home, env, encoding: "utf8", timeout: 30000 });
assert.equal(cli.status, 0, cli.stderr);
assert.equal(cli.stdout.trim(), "6.10.1");
const child = spawn(process.execPath, [entry, "mcp"], { cwd: home, env, stdio: ["pipe", "pipe", "pipe"] });
const exited = once(child, "exit");
let stderr = "";
child.stderr.on("data", chunk => { stderr = (stderr + chunk).slice(-8000); });
const pending = new Map();
const lines = createInterface({ input: child.stdout });
lines.on("line", line => {
  const message = JSON.parse(line);
  const request = pending.get(message.id);
  if (!request) return;
  pending.delete(message.id);
  clearTimeout(request.timer);
  if (message.error) request.reject(new Error(JSON.stringify(message.error)));
  else request.resolve(message.result);
});
child.on("exit", code => {
  for (const request of pending.values()) {
    clearTimeout(request.timer);
    request.reject(new Error(`REA exited (${code}): ${stderr}`));
  }
  pending.clear();
});
let id = 0;
function request(method, params = {}) {
  const requestId = ++id;
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      pending.delete(requestId);
      reject(new Error(`REA timeout in ${method}: ${stderr}`));
    }, 60000);
    pending.set(requestId, { resolve, reject, timer });
    child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id: requestId, method, params }) + "\n");
  });
}
async function call(name, args) {
  const result = await request("tools/call", { name, arguments: args });
  assert.ok(!result.isError, JSON.stringify(result));
  assert.ok(!result.structuredContent?.error, JSON.stringify(result));
  return result.structuredContent ?? JSON.parse(result.content.find(item => item.type === "text").text);
}
try {
  const initialized = await request("initialize", {
    protocolVersion: "2025-11-25", capabilities: {}, clientInfo: { name: "pi-rea-smoke", version: "1" },
  });
  assert.equal(initialized.serverInfo.name, "rea");
  assert.equal(initialized.serverInfo.version, "6.10.1");
  child.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");
  const { tools } = await request("tools/list");
  assert.equal(tools.length, 263);
  assert.ok(tools.every(tool => !tool.outputSchema), "Output schemas must stay omitted");
  assert.equal((await call("inspect_analysis_settings", {})).scope, "rea-runtime");

  const header = Buffer.from(JSON.stringify({ fixture_tensor: { dtype: "F32", shape: [1], data_offsets: [0, 4] } }));
  const size = Buffer.alloc(8);
  size.writeBigUInt64LE(BigInt(header.length));
  const model = join(home, "fixture.safetensors");
  writeFileSync(model, Buffer.concat([size, header, Buffer.alloc(4)]));
  assert.match(JSON.stringify(await call("inspect_model_artifact", { path: model, detail: "complete" })), /fixture_tensor/);

  // REA now owns its ASAR reader rather than depending on @electron/asar.
  // Encode a tiny ASAR fixture (two Pickle headers, then file bytes).
  const manifest = Buffer.from(JSON.stringify({ name: "rea-fixture", main: "main.js" }));
  const source = Buffer.from("exports.fixtureSum = (a, b) => a + b;\n");
  const listing = Buffer.from(JSON.stringify({ files: {
    "package.json": { size: manifest.length, offset: "0" },
    "main.js": { size: source.length, offset: String(manifest.length) },
  } }));
  const pickle = Buffer.alloc(8 + Math.ceil(listing.length / 4) * 4);
  pickle.writeUInt32LE(pickle.length - 4, 0);
  pickle.writeUInt32LE(listing.length, 4);
  listing.copy(pickle, 8);
  const prefix = Buffer.alloc(8);
  prefix.writeUInt32LE(4, 0);
  prefix.writeUInt32LE(pickle.length, 4);
  const archive = join(home, "fixture.asar");
  writeFileSync(archive, Buffer.concat([prefix, pickle, manifest, source]));
  const analysis = await call("analyze_javascript_application", {
    input_path: archive, detail: "summary", max_heap_mb: 256, analysis_timeout_ms: 30000,
  });
  const summary = analysis.normalized_result.summary;
  assert.equal(summary.format, "asar");
  assert.equal(summary.statistics.parsed_javascript_files, 1);
  assert.equal(summary.statistics.parse_failures, 0);
  assert.equal(summary.coverage.application.status, "complete");
  console.log("PASS: REA CLI, 263 MCP tools, runtime settings, model inspection, ASAR/JavaScript analysis; no target execution.");
} finally {
  child.stdin.end();
  const timer = setTimeout(() => child.kill("SIGKILL"), 10000);
  await exited;
  clearTimeout(timer);
  lines.close();
  rmSync(home, { recursive: true, force: true });
}
