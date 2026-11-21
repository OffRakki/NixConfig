import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { once } from "node:events";
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createInterface } from "node:readline";

const [mcpBin, hookBin] = process.argv.slice(2);
assert.ok(mcpBin && hookBin, "Usage: node smoke.mjs <pi-intercom-mcp-bin> <inbox-hook-bin>");

const tempRoot = mkdtempSync(join(tmpdir(), "pi-intercom-mcp-smoke-"));
const workDir = join(tempRoot, "workspace");
const agentDir = join(tempRoot, "agent");
spawnSync("mkdir", ["-p", workDir, agentDir]);

const baseEnv = {
  ...process.env,
  HOME: tempRoot,
  PI_CODING_AGENT_DIR: agentDir,
};

function spawnMcp(name) {
  const child = spawn(mcpBin, [], {
    cwd: workDir,
    env: { ...baseEnv, PI_INTERCOM_SESSION_NAME: name },
    stdio: ["pipe", "pipe", "pipe"],
  });
  let stderr = "";
  child.stderr.on("data", (chunk) => {
    stderr = (stderr + chunk.toString()).slice(-4000);
  });
  const pending = new Map();
  const rl = createInterface({ input: child.stdout });
  rl.on("line", (line) => {
    if (!line.trim()) return;
    const msg = JSON.parse(line);
    const req = pending.get(msg.id);
    if (!req) return;
    pending.delete(msg.id);
    clearTimeout(req.timer);
    if (msg.error) req.reject(new Error(JSON.stringify(msg.error)));
    else req.resolve(msg.result);
  });
  let seq = 0;
  function request(method, params = {}) {
    const id = ++seq;
    return new Promise((resolveReq, rejectReq) => {
      const timer = setTimeout(() => {
        pending.delete(id);
        rejectReq(new Error(`Timeout in ${name}:${method}. stderr=${stderr}`));
      }, 20000);
      pending.set(id, { resolve: resolveReq, reject: rejectReq, timer });
      child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id, method, params })}\n`);
    });
  }
  async function init() {
    await request("initialize", {
      protocolVersion: "2024-11-05",
      capabilities: {},
      clientInfo: { name: "smoke", version: "1" },
    });
    child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" })}\n`);
  }
  async function intercom(args) {
    const res = await request("tools/call", { name: "intercom", arguments: args });
    assert.ok(!res.isError, JSON.stringify(res));
    return JSON.parse(res.content[0].text);
  }
  async function close() {
    rl.close();
    child.stdin.end();
    if (child.exitCode !== null || child.signalCode !== null) return;
    const exited = once(child, "exit");
    const timer = setTimeout(() => child.kill("SIGKILL"), 5000);
    await exited;
    clearTimeout(timer);
  }
  return { init, intercom, close, getStderr: () => stderr };
}

const a = spawnMcp("alpha");
const b = spawnMcp("beta");

try {
  await Promise.all([a.init(), b.init()]);

  // Wait until both sessions are visible in the broker roster.
  let listRes = await a.intercom({ action: "list" });
  for (let i = 0; i < 20 && listRes.sessions.length < 2; i++) {
    await new Promise((r) => setTimeout(r, 150));
    listRes = await a.intercom({ action: "list" });
  }
  assert.equal(listRes.ok, true);
  assert.equal(listRes.sessions.length, 2, JSON.stringify(listRes));

  // Rename both sessions.
  assert.equal((await a.intercom({ action: "rename", name: "planner" })).name, "planner");
  assert.equal((await b.intercom({ action: "rename", name: "worker" })).name, "worker");

  // Send fire-and-forget message planner -> worker.
  const sent = await a.intercom({ action: "send", to: "worker", message: "hello from planner" });
  assert.equal(sent.ok, true, JSON.stringify(sent));

  // Verify PreInvocation inbox hook picks up the unread message cleanly.
  const hookRun = spawnSync(hookBin, [], {
    cwd: workDir,
    env: baseEnv,
    input: JSON.stringify({ cwd: workDir, hookEventName: "PreInvocation" }),
    encoding: "utf8",
    timeout: 5000,
  });
  assert.equal(hookRun.status, 0, hookRun.stderr);
  const hookOut = JSON.parse(hookRun.stdout);
  assert.ok(
    hookOut.injectSteps?.[0]?.systemMessage?.systemMessage?.includes("hello from planner"),
    JSON.stringify(hookOut),
  );

  // Verify worker inbox also has it.
  const inboxRes = await b.intercom({ action: "inbox", includeRead: true });
  assert.ok(inboxRes.messages.some((m) => m.text === "hello from planner"), JSON.stringify(inboxRes));

  // Verify synchronous ask -> reply round-trip.
  const askPromise = a.intercom({
    action: "ask",
    to: "worker",
    message: "status check?",
    timeoutMs: 10000,
  });

  // Poll worker inbox until the ask arrives, then reply.
  let workerInbox;
  for (let i = 0; i < 20; i++) {
    workerInbox = await b.intercom({ action: "inbox" });
    if (workerInbox.messages.some((m) => m.expectsReply && m.text === "status check?")) break;
    await new Promise((r) => setTimeout(r, 100));
  }
  const replyRes = await b.intercom({ action: "reply", message: "all green" });
  assert.equal(replyRes.ok, true, JSON.stringify(replyRes));

  const askRes = await askPromise;
  assert.equal(askRes.ok, true, JSON.stringify(askRes));
  assert.equal(askRes.reply, "all green");
  assert.equal(askRes.from, "worker");

  console.log("PASS: pi-intercom-mcp list, rename, send, PreInvocation hook, inbox, ask -> reply.");
} catch (err) {
  console.error("SMOKE FAILED:", err);
  console.error("--- alpha stderr ---\n" + a.getStderr());
  console.error("--- beta stderr ---\n" + b.getStderr());
  process.exitCode = 1;
} finally {
  await Promise.all([a.close(), b.close()]);
  // Stop isolated test broker cleanly so temp directory removes with zero orphans.
  const pidPath = join(agentDir, "intercom", "broker.pid");
  if (existsSync(pidPath)) {
    const pid = Number.parseInt(readFileSync(pidPath, "utf8").trim(), 10);
    if (Number.isInteger(pid) && pid > 0) {
      try {
        process.kill(pid, "SIGTERM");
      } catch {
        // Already exited.
      }
    }
  }
  rmSync(tempRoot, { recursive: true, force: true });
}
