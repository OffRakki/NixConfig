// Exercise the actual Nix-pinned integrations without real credentials, network, mail or browser work.
import assert from 'node:assert/strict';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
const [sdkRoot, runner] = process.argv.slice(2);
assert.ok(sdkRoot && runner, 'Usage: node mail.resources.smoke.mjs SDK_ROOT RUNNER_PACKAGE');
const directory = await mkdtemp(join(tmpdir(), 'mail-resources-'));
Object.assign(process.env, { HOME: directory, PI_CODING_AGENT_DIR: join(directory, 'agent'), PI_OFFLINE: '1', PI_TELEMETRY: '0', PI_SKIP_VERSION_CHECK: '1' });
let network = 0;
globalThis.fetch = async () => { network++; throw new Error('Network forbidden in resource smoke'); };
const source = await readFile(join(runner, 'bin/mail-assistant-runner'), 'utf8');
const configFile = /--config-file (\/nix\/store\/[^\s'"\\]+)/.exec(source)?.[1]; assert.ok(configFile);
const host = JSON.parse(await readFile(configFile, 'utf8'));
process.env.PI_AGENT_BROWSER_PINNED_CONFIG = host.config.assistantProfile.browserConfigFile;
process.env.PI_AGENT_BROWSER_NATIVE_CONFIG = host.config.assistantProfile.browserNativeConfigFile;
// Malicious ambient layers and overrides must have NO effect in mail mode.
const ambientDir = join(directory, '.pi/config/pi-agent-browser-native'); await mkdir(ambientDir, { recursive: true });
const ambient = join(ambientDir, 'config.json');
await writeFile(ambient, JSON.stringify({ version: 1, browser: { executablePath: '/AMBIENT_MUST_NOT_RUN', defaultProfile: '/AMBIENT_PROFILE' } }));
process.env.PI_AGENT_BROWSER_CONFIG = ambient;
const browserPackage = host.config.assistantProfile.extensionPaths.find(path => path.endsWith('/pi-agent-browser-native'));
const { loadAgentBrowserConfigStateSync } = await import(pathToFileURL(join(browserPackage, 'dist/extensions/agent-browser/lib/config-policy.js')));
const effective = loadAgentBrowserConfigStateSync({ cwd: directory });
assert.equal(effective.layers.length, 1); assert.equal(effective.layers[0].path, process.env.PI_AGENT_BROWSER_PINNED_CONFIG);
assert.equal(effective.projectConfigIncluded, false); assert.deepEqual(effective.errors, []);
assert.doesNotMatch(JSON.stringify(effective), /AMBIENT_MUST_NOT_RUN|AMBIENT_PROFILE/);
assert.throws(() => loadAgentBrowserConfigStateSync({ env: { HOME: directory, PI_AGENT_BROWSER_PINNED_CONFIG: ambient } }), /Nix-owned/);
const { getAgentBrowserProcessEnvironment, withAgentBrowserProcessEnvironment } = await import(pathToFileURL(join(browserPackage, 'dist/extensions/agent-browser/lib/process-environment.js')));
const { withNativeSessionDefaults } = await import(pathToFileURL(join(browserPackage, 'dist/extensions/agent-browser/lib/orchestration/native-session-defaults.js')));
const poisoned = { ...process.env, AGENT_BROWSER_CONFIG: ambient, AGENT_BROWSER_PROFILE: '/AMBIENT_PROFILE', AGENT_BROWSER_SESSION: 'AMBIENT_SESSION', AGENT_BROWSER_CDP: 'http://127.0.0.1:1', AGENT_BROWSER_PROVIDER: 'AMBIENT_PROVIDER', AGENT_BROWSER_EXECUTABLE_PATH: '/AMBIENT_MUST_NOT_RUN', HTTPS_PROXY: 'http://127.0.0.1:1' };
const native = getAgentBrowserProcessEnvironment(poisoned);
assert.equal(native.AGENT_BROWSER_CONFIG, process.env.PI_AGENT_BROWSER_NATIVE_CONFIG);
for (const key of ['AGENT_BROWSER_PROFILE', 'AGENT_BROWSER_SESSION', 'AGENT_BROWSER_CDP', 'AGENT_BROWSER_PROVIDER', 'AGENT_BROWSER_EXECUTABLE_PATH', 'HTTPS_PROXY']) assert.equal(native[key], undefined);
Object.assign(process.env, poisoned);
const input = { kind: 'native', toolArgs: ['open', 'https://example.test'], toolStdin: undefined };
await withNativeSessionDefaults(input, directory, AbortSignal.timeout(2000), effective => {
  assert.deepEqual(effective.toolArgs, input.toolArgs);
  assert.equal(getAgentBrowserProcessEnvironment().AGENT_BROWSER_CONFIG, process.env.PI_AGENT_BROWSER_NATIVE_CONFIG);
  assert.doesNotMatch(JSON.stringify(effective), /AMBIENT/);
});
withAgentBrowserProcessEnvironment({ AGENT_BROWSER_SESSION: 'explicit-approved-session' }, () => assert.equal(getAgentBrowserProcessEnvironment().AGENT_BROWSER_SESSION, 'explicit-approved-session'));
const { sdkModules, runSession } = await import(pathToFileURL(join(runner, 'share/mail-assistant/runner.mjs')));
const { normalize, Store, Gate } = await import(pathToFileURL(join(runner, 'share/mail-assistant/core.mjs')));
const { sdk, ai } = await sdkModules(sdkRoot);
const runtime = await sdk.ModelRuntime.create({ credentials: new ai.InMemoryCredentialStore(), modelsPath: null, refreshOnCreate: false, allowModelNetwork: false });
const faux = ai.fauxProvider(); runtime.registerNativeProvider(faux.provider);
const config = { ...host.config, cwd: directory, contextPaths: [], mailbox: 'fixture', selfAddress: 'assistant@example.test', provider: `${faux.getModel().provider}/${faux.getModel().id}` };
const request = normalize({ version: 1, messageId: null, from: 'owner@example.test', subject: 'Fixture', body: 'No real actions.', autoSubmitted: 'no', precedence: '', attachments: [] }, config);
const store = new Store(join(directory, 'state')); store.claim(request);
let proposals = 0;
const approval = { configured: true, async createProposal() { proposals++; return 'fixture'; }, async fetchDecision() { return { status: 'pending' }; } };
const signal = AbortSignal.timeout(20000), gate = new Gate(store, approval, signal);
try {
  faux.setResponses([ai.fauxAssistantMessage([ai.fauxToolCall('agent_browser', { args: ['get', 'url'] })])]);
  const result = await runSession({ sdk, config, modelRuntime: runtime, model: faux.getModel(), cwd: directory, agentDir: join(directory, 'agent'), prompt: 'Return a JSON draft without any effects.', personal: true, useProfile: true, request, gate, signal,
    inspect: ({ session, loader }) => {
      assert.deepEqual(loader.getExtensions().errors, []);
      assert.ok(loader.getSkills().skills.some(skill => skill.name === 'ciel-brain'));
      assert.ok(loader.getSkills().skills.some(skill => skill.name === 'firefly'));
      assert.match(session.systemPrompt, /Ciel is a Deity/);
      assert.match(session.systemPrompt, /MAIL CHANNEL/);
      const tools = session.getAllTools().map(tool => tool.name);
      assert.ok(tools.includes('agent_browser')); assert.ok(tools.includes('web_enable'));
      assert.ok(!tools.some(name => /^(?:Agent|subagent|intercom|bg_wait)$/.test(name)));
      console.log('Actual pinned resources:', { extensions: loader.getExtensions().extensions.length, skills: loader.getSkills().skills.length, browserAndWebRegistered: true, delegatedBackgroundToolsAbsent: true });
    } });
  assert.equal(result, ''); assert.equal(gate.pending, true); assert.equal(proposals, 1); assert.equal(network, 0);
  console.log('PASS: real resource loading, zero network/browser effects, browser operation approval-gated.');
} finally { store.close(); await rm(directory, { recursive: true, force: true }); }
