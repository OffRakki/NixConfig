import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { stripTypeScriptTypes } from "node:module";
import { join } from "node:path";
import { test } from "node:test";
import { pathToFileURL } from "node:url";
import { promisify } from "node:util";
import { SourceTextModule, SyntheticModule } from "node:vm";

// Run with node --experimental-vm-modules --test and PI_PACKAGE_ROOT set to Pi's npm root.
assert.ok(process.env.PI_PACKAGE_ROOT, "Set PI_PACKAGE_ROOT to the installed pi-monorepo directory");
const { Type } = await import(pathToFileURL(join(
  process.env.PI_PACKAGE_ROOT, "node_modules/@earendil-works/pi-ai/dist/index.js",
)));
const source = stripTypeScriptTypes(await readFile(new URL("../extensions/notify.ts", import.meta.url), "utf8"));

async function load(run = (_file, _args, _options, callback) => callback(null, "", "")) {
  const calls = [];
  const tools = [];
  const commands = new Map();
  const hooks = new Map();
  const modules = {
    "@earendil-works/pi-ai": { Type },
    "@earendil-works/pi-coding-agent": { defineTool: (tool) => tool },
    "node:child_process": {
      execFile: (...args) => {
        calls.push(args.slice(0, 3));
        return run(...args);
      },
    },
    "node:util": { promisify },
  };
  const extension = new SourceTextModule(source);
  await extension.link(async (name) => {
    const values = modules[name];
    assert.ok(values, `Unexpected import: ${name}`);
    return new SyntheticModule(Object.keys(values), function () {
      for (const [key, value] of Object.entries(values)) this.setExport(key, value);
    });
  });
  await extension.evaluate();
  extension.namespace.default({
    registerTool: (tool) => tools.push(tool),
    registerCommand: (name, command) => commands.set(name, command),
    on: (name, handler) => hooks.set(name, handler),
  });
  assert.equal(tools.length, 1);
  return { tool: tools[0], commands, hooks, calls };
}

const input = { title: "Mail", body: "Deadline tomorrow" };

test("uses literal arguments, an option terminator, no shell, and escaped markup", async () => {
  const { tool, calls } = await load();
  const title = "--help $(touch /tmp/not-a-real-command); `id`";
  const body = "quotes ' \" ; & <b>literal</b>\nsecond line";
  const result = await tool.execute("test", { title, body });
  assert.equal(result.details.sent, true);
  assert.equal(calls.length, 1);
  const [file, args, options] = calls[0];
  assert.equal(file, "notify-send");
  assert.deepEqual(args, [
    "--app-name=Pi", "--icon=dialog-information", "--urgency=normal", "--",
    title, "quotes ' \" ; &amp; &lt;b&gt;literal&lt;/b&gt;\nsecond line",
  ]);
  assert.equal(options.shell, false);
  assert.equal(options.timeout, 3000);
  assert.equal(options.maxBuffer, 8192);
  assert.equal(tool.parameters.additionalProperties, false);
  assert.equal(tool.parameters.properties.title.maxLength, 160);
  assert.equal(tool.parameters.properties.body.maxLength, 2000);
});

test("reserves the attempt before awaiting parallel calls and resets for a new request", async () => {
  let finish;
  const { tool, calls, hooks } = await load((_file, _args, _options, callback) => { finish = callback; });
  const first = tool.execute("first", input);
  const second = await tool.execute("second", input);
  assert.equal(second.isError, true);
  assert.equal(calls.length, 1);
  finish(null, "", "");
  assert.equal((await first).details.sent, true);
  hooks.get("before_agent_start")();
  const third = tool.execute("third", input);
  assert.equal(calls.length, 2);
  finish(null, "", "");
  assert.equal((await third).details.sent, true);
});

test("reports infrastructure failure without claiming success or retrying", async () => {
  const { tool, calls } = await load((_file, _args, _options, callback) => callback(new Error("No bus")));
  const result = await tool.execute("test", input);
  assert.equal(result.isError, true);
  assert.equal(result.details.sent, false);
  assert.equal((await tool.execute("retry", input)).isError, true);
  assert.equal(calls.length, 1);
});

test("rejects an already-aborted call or NUL text without starting a process", async () => {
  for (const [params, signal] of [
    [input, AbortSignal.abort()],
    [{ title: "bad\0title", body: "" }, undefined],
  ]) {
    const { tool, calls } = await load();
    assert.equal((await tool.execute("test", params, signal)).isError, true);
    assert.equal(calls.length, 0);
  }
});

test("passes cancellation to the child process", async () => {
  const controller = new AbortController();
  const { tool, calls } = await load((_file, _args, options, callback) => {
    options.signal.addEventListener("abort", () => callback(new Error("Aborted")), { once: true });
  });
  const pending = tool.execute("test", input, controller.signal);
  assert.equal(calls[0][2].signal, controller.signal);
  controller.abort();
  assert.equal((await pending).details.sent, false);
});

test("preserves /notify and reports command failure instead of silently succeeding", async () => {
  const { commands } = await load((_file, _args, _options, callback) => callback(new Error("No bus")));
  const messages = [];
  await commands.get("notify").handler("Done", { ui: { notify: (...args) => messages.push(args) } });
  assert.equal(messages[0][1], "error");
});
