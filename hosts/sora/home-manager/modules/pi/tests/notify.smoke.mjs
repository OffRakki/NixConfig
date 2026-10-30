import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

assert.ok(process.env.PI_PACKAGE_ROOT, "Set PI_PACKAGE_ROOT to the installed pi-monorepo directory");
process.env.PI_OFFLINE = "1";
process.env.PI_TELEMETRY = "0";
const { createAgentSession, DefaultResourceLoader, SessionManager, SettingsManager } = await import(
  pathToFileURL(join(process.env.PI_PACKAGE_ROOT, "dist/index.js"))
);
const root = await mkdtemp(join(tmpdir(), "pi-notify-smoke-"));
let session;
try {
  const settingsManager = SettingsManager.inMemory({ packages: [], defaultTools: ["desktop_notify"] });
  const loader = new DefaultResourceLoader({
    cwd: root,
    agentDir: join(root, "agent"),
    settingsManager,
    noExtensions: true,
    noSkills: true,
    noPromptTemplates: true,
    noThemes: true,
    noContextFiles: true,
    additionalExtensionPaths: [process.env.NOTIFY_EXTENSION ?? fileURLToPath(new URL("../extensions/notify.ts", import.meta.url))],
  });
  await loader.reload();
  assert.deepEqual(loader.getExtensions().errors, []);
  assert.equal(loader.getExtensions().extensions.length, 1);
  ({ session } = await createAgentSession({
    cwd: root,
    agentDir: join(root, "agent"),
    resourceLoader: loader,
    settingsManager,
    sessionManager: SessionManager.inMemory(root),
    tools: ["desktop_notify"],
  }));
  const errors = [];
  await session.bindExtensions({ mode: "print", onError: (error) => errors.push(error) });
  assert.deepEqual(errors, []);
  assert.deepEqual(session.getActiveToolNames(), ["desktop_notify"]);
  assert.ok(session.getAllTools().some((tool) => tool.name === "desktop_notify"));
  console.log("SDK smoke passed: extension loaded and bound; only desktop_notify active; no model call or notification sent.");
} finally {
  session?.dispose();
  await rm(root, { recursive: true, force: true });
}
