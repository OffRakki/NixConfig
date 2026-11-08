import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, writeFile, rename, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const [host, closure, firstPath, secondPath] = process.argv.slice(2);
assert.ok(host && closure && firstPath && secondPath,
  "Usage: node noctalia.smoke.mjs <Pi root> <package closure> <first rendered theme> <second rendered theme>");
const home = await mkdtemp(join(tmpdir(), "pi-noctalia-smoke-"));
const agentDir = join(home, ".pi/agent");
Object.assign(process.env, {
  HOME: home, PI_CODING_AGENT_DIR: agentDir, PI_OFFLINE: "1", PI_TELEMETRY: "0",
  PI_SUBAGENTS_PI_CODING_AGENT_PACKAGE_ROOT: host, COLORTERM: "truecolor",
});
const themesDir = join(agentDir, "themes");
const themePath = join(themesDir, "noctalia.json");
let session, themeModule, footer;
try {
  await mkdir(themesDir, { recursive: true });
  const first = await readFile(firstPath, "utf8");
  const second = await readFile(secondPath, "utf8");
  for (const content of [first, second]) {
    const parsed = JSON.parse(content);
    assert.equal(parsed.name, "noctalia");
    assert.equal(parsed.appearance, "dark");
    assert.ok(!content.includes("{{"), "All Noctalia tokens must render");
  }
  await writeFile(themePath, first);
  const sdk = await import(pathToFileURL(join(host, "dist/index.js")));
  themeModule = await import(pathToFileURL(join(host, "dist/modes/interactive/theme/theme.js")));
  const settingsManager = sdk.SettingsManager.inMemory({
    theme: "noctalia", packages: [join(closure, "node_modules/pi-powerline")],
    header: false, "header-info": false, defaultTools: [],
  });
  const loader = new sdk.DefaultResourceLoader({
    cwd: home, agentDir, settingsManager, noContextFiles: true,
  });
  await loader.reload();
  assert.deepEqual(loader.getExtensions().errors, []);
  ({ session } = await sdk.createAgentSession({
    cwd: home, agentDir, settingsManager, resourceLoader: loader,
    sessionManager: sdk.SessionManager.inMemory(home), tools: [],
  }));
  const errors = [];
  await session.bindExtensions({ mode: "print", onError: error => errors.push(error) });
  assert.deepEqual(errors, []);
  themeModule.initTheme("noctalia", true);
  let reloads = 0;
  themeModule.onThemeChange(() => reloads++);
  const colors = () => [
    themeModule.theme.fg("accent", "accent"),
    themeModule.theme.fg("borderAccent", "bar"),
    themeModule.theme.bg("toolSuccessBg", "block"),
  ];
  const before = colors();
  assert.equal(themeModule.theme.appearance, "dark");

  const { createJiti } = await import(pathToFileURL(join(host, "node_modules/jiti/lib/jiti.mjs")));
  const jiti = createJiti(import.meta.url, { alias: {
    "@earendil-works/pi-coding-agent": join(host, "dist/index.js"),
    "@earendil-works/pi-tui": join(host, "node_modules/@earendil-works/pi-tui/dist/index.js"),
  } });
  const { createFooterRenderer } = await jiti.import(join(closure, "node_modules/pi-powerline/extensions/footer.ts"));
  const { visibleWidth } = await import(pathToFileURL(join(host, "node_modules/@earendil-works/pi-tui/dist/index.js")));
  const ctx = {
    cwd: home, model: undefined, sessionManager: { getEntries: () => [] },
    getContextUsage: () => null, ui: { get theme() { return themeModule.theme; } },
  };
  footer = createFooterRenderer(ctx, { getAllTools: () => [] })(
    { requestRender() {} }, themeModule.theme,
    { onBranchChange: () => () => {}, getGitBranch: () => "theme-test", getExtensionStatuses: () => new Map() },
  );
  const widths = [60, 80, 100, 140];
  const footerBefore = widths.map(width => footer.render(width));

  // A partial write must not destroy the last valid palette.
  await writeFile(themePath, "{");
  await new Promise(resolve => setTimeout(resolve, 250));
  assert.deepEqual(colors(), before);
  assert.equal(reloads, 0);
  // Noctalia may replace files atomically: the directory watcher must handle it.
  await writeFile(`${themePath}.next`, second);
  await rename(`${themePath}.next`, themePath);
  const deadline = Date.now() + 3000;
  while (!reloads && Date.now() < deadline) await new Promise(resolve => setTimeout(resolve, 25));
  assert.ok(reloads > 0, "The running Pi theme must hot-reload without a restart");
  const after = colors();
  before.forEach((value, i) => assert.notEqual(after[i], value, `Theme role ${i} must change`));
  assert.equal(themeModule.theme.appearance, "dark", "Same-mode palette changes must work");
  widths.forEach((width, i) => {
    const lines = footer.render(width);
    assert.notDeepEqual(lines, footerBefore[i], "The existing footer must pick up the new palette");
    assert.ok(lines.every(line => visibleWidth(line) <= width));
  });
  const footerSource = await readFile(join(closure, "node_modules/pi-powerline/extensions/footer.ts"), "utf8");
  assert.ok(!footerSource.includes("#5faf5f"), "Git branch must not keep a fixed green");
  assert.ok(footerSource.includes("theme.fg('success', withIcon(ICON_GIT, branch))"));
  console.log("PASS: SDK load/bind; native same-dark-mode theme hot-reload; partial-write recovery; live panel/bar colors; footer at 60/80/100/140 columns; no model call.");
} finally {
  footer?.dispose();
  themeModule?.stopThemeWatcher();
  session?.dispose();
  await rm(home, { recursive: true, force: true });
}
