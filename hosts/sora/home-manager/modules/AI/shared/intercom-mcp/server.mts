import { createHash, randomBytes } from "node:crypto";
import { mkdirSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const pkgDir = process.env.PI_INTERCOM_PKG_DIR;
const nodeModulesDir = process.env.PI_INTERCOM_NODE_MODULES;
if (!pkgDir || !nodeModulesDir) {
  throw new Error("PI_INTERCOM_PKG_DIR and PI_INTERCOM_NODE_MODULES are required");
}

const mcpBase = join(nodeModulesDir, "@modelcontextprotocol", "sdk", "dist", "esm");
const [
  { Server },
  { StdioServerTransport },
  { CallToolRequestSchema, ListToolsRequestSchema },
  { IntercomClient },
  { spawnBrokerIfNeeded },
] = await Promise.all([
  import(pathToFileURL(join(mcpBase, "server", "index.js")).href),
  import(pathToFileURL(join(mcpBase, "server", "stdio.js")).href),
  import(pathToFileURL(join(mcpBase, "types.js")).href),
  import(pathToFileURL(join(pkgDir, "broker", "client.ts")).href),
  import(pathToFileURL(join(pkgDir, "broker", "spawn.ts")).href),
]);

interface SessionInfo {
  id: string;
  name?: string;
  cwd: string;
  model: string;
  pid: number;
  status?: string;
}

interface InboundMessage {
  id: string;
  timestamp: number;
  replyTo?: string;
  expectsReply?: boolean;
  content: { text: string };
}

interface BufferedItem {
  id: string;
  fromId: string;
  fromName: string;
  fromCwd: string;
  text: string;
  expectsReply: boolean;
  replyTo?: string;
  receivedAt: number;
  read: boolean;
  replied: boolean;
}

interface PendingAskWaiter {
  targetId: string;
  targetName: string;
  resolve: (value: { from: SessionInfo; message: InboundMessage }) => void;
  reject: (err: Error) => void;
  timer: NodeJS.Timeout;
}

const cwd = resolve(process.cwd());
const folderSlug =
  basename(cwd)
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, "-")
    .replace(/^-+|-+$/g, "") || "session";
const shortTag = randomBytes(2).toString("hex");
let sessionName = process.env.PI_INTERCOM_SESSION_NAME?.trim() || `agy-${folderSlug}-${shortTag}`;
let isCustomName = Boolean(process.env.PI_INTERCOM_SESSION_NAME?.trim());

const agentDir = process.env.PI_CODING_AGENT_DIR || join(homedir(), ".pi", "agent");
const inboxDir = join(agentDir, "intercom", "agy-inbox");
const cwdHash = createHash("sha256").update(cwd).digest("hex").slice(0, 16);
const inboxFile = join(inboxDir, `${cwdHash}-${process.pid}.json`);

const client = new IntercomClient();
const inbox: BufferedItem[] = [];
const pendingAsks = new Map<string, PendingAskWaiter>();
let connectPromise: Promise<void> | null = null;
let reconnectTimer: NodeJS.Timeout | null = null;
let shuttingDown = false;

function persistUnreadInbox(): void {
  try {
    const unread = inbox.filter((m) => !m.read);
    if (unread.length === 0) {
      rmSync(inboxFile, { force: true });
      return;
    }
    mkdirSync(inboxDir, { recursive: true, mode: 0o700 });
    const tmp = `${inboxFile}.tmp`;
    writeFileSync(
      tmp,
      JSON.stringify({
        pid: process.pid,
        cwd,
        sessionName,
        messages: unread.map((m) => ({
          id: m.id,
          fromName: m.fromName,
          fromId: m.fromId,
          text: m.text,
          expectsReply: m.expectsReply,
          receivedAt: m.receivedAt,
        })),
      }),
      { mode: 0o600 },
    );
    renameSync(tmp, inboxFile);
  } catch {
    // Best-effort hook handoff; in-memory inbox remains authoritative.
  }
}

function cleanupInboxFile(): void {
  try {
    rmSync(inboxFile, { force: true });
  } catch {
    // Ignore cleanup errors on exit.
  }
}

async function ensureConnected(): Promise<void> {
  if (client.isConnected()) return;
  if (connectPromise) return connectPromise;

  connectPromise = (async () => {
    await spawnBrokerIfNeeded("npx", ["--no-install", "tsx"]);
    await client.connect({
      cwd,
      model: "antigravity",
      pid: process.pid,
      startedAt: Date.now(),
      lastActivity: Date.now(),
      name: sessionName,
      runtimeFallbackAlias: !isCustomName,
      status: "active",
    });
  })().finally(() => {
    connectPromise = null;
  });

  return connectPromise;
}

function scheduleReconnect(): void {
  if (shuttingDown || reconnectTimer) return;
  reconnectTimer = setTimeout(async () => {
    reconnectTimer = null;
    if (shuttingDown) return;
    try {
      await ensureConnected();
    } catch {
      scheduleReconnect();
    }
  }, 2000);
  reconnectTimer.unref();
}

client.on("disconnected", () => {
  scheduleReconnect();
});

client.on("error", () => {
  // Handled via disconnected / tool call errors; avoid crashing stdio MCP.
});

client.on("message", (from: SessionInfo, message: InboundMessage) => {
  try {
    client.sendMessageReceipt({
      messageId: message.id,
      status: "receiver_received",
      timestamp: Date.now(),
    });
  } catch {
    // Best-effort receipt.
  }

  // Check if this message resolves a blocking ask.
  if (message.replyTo && pendingAsks.has(message.replyTo)) {
    const waiter = pendingAsks.get(message.replyTo)!;
    pendingAsks.delete(message.replyTo);
    clearTimeout(waiter.timer);
    waiter.resolve({ from, message });
    return;
  }
  for (const [askId, waiter] of pendingAsks.entries()) {
    if (
      from.id === waiter.targetId ||
      (from.name && from.name === waiter.targetName)
    ) {
      pendingAsks.delete(askId);
      clearTimeout(waiter.timer);
      waiter.resolve({ from, message });
      return;
    }
  }

  inbox.push({
    id: message.id,
    fromId: from.id,
    fromName: from.name || from.id.slice(0, 8),
    fromCwd: from.cwd,
    text: message.content?.text ?? "",
    expectsReply: Boolean(message.expectsReply),
    replyTo: message.replyTo,
    receivedAt: Date.now(),
    read: false,
    replied: false,
  });
  if (inbox.length > 200) {
    inbox.splice(0, inbox.length - 200);
  }
  persistUnreadInbox();
});

async function resolveTarget(rawTarget: string): Promise<{ id: string; name: string }> {
  const sessions: SessionInfo[] = await client.listSessions();
  const target = rawTarget.trim();
  const exact = sessions.find((s) => s.name === target || s.id === target);
  if (exact) return { id: exact.id, name: exact.name || exact.id.slice(0, 8) };
  const prefix = sessions.filter(
    (s) =>
      (s.name && s.name.startsWith(target)) ||
      s.id.startsWith(target),
  );
  if (prefix.length === 1) {
    return { id: prefix[0].id, name: prefix[0].name || prefix[0].id.slice(0, 8) };
  }
  if (prefix.length > 1) {
    const names = prefix.map((s) => s.name || s.id.slice(0, 8)).join(", ");
    throw new Error(`Ambiguous target "${target}"; matches: ${names}`);
  }
  const available = sessions
    .filter((s) => s.id !== client.sessionId)
    .map((s) => s.name || s.id.slice(0, 8))
    .join(", ");
  throw new Error(
    `No connected session matching "${target}". Available peers: ${available || "(none)"}`,
  );
}

function jsonText(payload: unknown) {
  return {
    content: [{ type: "text" as const, text: JSON.stringify(payload, null, 2) }],
  };
}

const server = new Server(
  { name: "pi-intercom", version: "1.0.0" },
  { capabilities: { tools: {} } },
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "intercom",
      description:
        "Coordinate 1:1 with other live Pi and Antigravity sessions via the local pi-intercom broker (list, send, ask, inbox, reply, rename).",
      inputSchema: {
        type: "object",
        required: ["action"],
        properties: {
          action: {
            type: "string",
            enum: ["list", "send", "ask", "inbox", "reply", "rename"],
            description:
              "list: show live sessions; send: fire-and-forget message; ask: send and wait for reply; inbox: read unread messages and pending asks; reply: answer a pending ask; rename: set this session's alias.",
          },
          to: {
            type: "string",
            description: "Target session name, prefix, or session ID (for send, ask, or optional reply disambiguation).",
          },
          message: {
            type: "string",
            description: "Message text (for send, ask, or reply).",
          },
          replyTo: {
            type: "string",
            description: "Optional message ID to reply to (for reply; defaults to the latest pending ask).",
          },
          name: {
            type: "string",
            description: "New session alias (for rename, e.g. 'planner' or 'worker').",
          },
          timeoutMs: {
            type: "integer",
            minimum: 1000,
            maximum: 300000,
            description: "Timeout in milliseconds for ask (default 60000).",
          },
          includeRead: {
            type: "boolean",
            description: "For inbox: include previously read messages (default false).",
          },
        },
        additionalProperties: false,
      },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  if (request.params.name !== "intercom") {
    throw new Error(`Unknown tool: ${request.params.name}`);
  }
  const args = (request.params.arguments ?? {}) as Record<string, unknown>;
  const action = String(args.action ?? "");

  await ensureConnected();

  if (action === "list") {
    const sessions: SessionInfo[] = await client.listSessions();
    return jsonText({
      ok: true,
      self: { id: client.sessionId, name: sessionName, cwd },
      sessions: sessions.map((s) => ({
        name: s.name ?? "(unnamed)",
        id: s.id,
        model: s.model,
        status: s.status ?? "?",
        cwd: s.cwd,
        self: s.id === client.sessionId,
      })),
    });
  }

  if (action === "rename") {
    const next = String(args.name ?? "").trim();
    if (!next) {
      return jsonText({ ok: false, error: "name is required for rename" });
    }
    sessionName = next;
    isCustomName = true;
    client.updatePresence({ name: sessionName, runtimeFallbackAlias: false });
    persistUnreadInbox();
    return jsonText({ ok: true, id: client.sessionId, name: sessionName });
  }

  if (action === "inbox") {
    const includeRead = Boolean(args.includeRead);
    const items = inbox.filter((m) => includeRead || !m.read || (m.expectsReply && !m.replied));
    const snapshot = items.map((m) => ({
      id: m.id,
      from: m.fromName,
      fromId: m.fromId,
      fromCwd: m.fromCwd,
      text: m.text,
      expectsReply: m.expectsReply,
      replied: m.replied,
      receivedAt: m.receivedAt,
    }));
    for (const m of inbox) {
      m.read = true;
    }
    persistUnreadInbox();
    return jsonText({
      ok: true,
      self: sessionName,
      messages: snapshot,
      pendingAsks: inbox.filter((m) => m.expectsReply && !m.replied).length,
    });
  }

  if (action === "send") {
    const to = String(args.to ?? "").trim();
    const message = String(args.message ?? "");
    if (!to || !message) {
      return jsonText({ ok: false, error: "to and message are required for send" });
    }
    const target = await resolveTarget(to);
    const result = await client.send(target.id, { text: message });
    return jsonText({
      ok: result.delivered,
      id: result.id,
      to: target.name,
      toId: target.id,
      delivery: result.delivery,
      ...(result.reason ? { reason: result.reason } : {}),
    });
  }

  if (action === "ask") {
    const to = String(args.to ?? "").trim();
    const message = String(args.message ?? "");
    const timeoutMs =
      typeof args.timeoutMs === "number" && Number.isFinite(args.timeoutMs)
        ? Math.min(300_000, Math.max(1000, Math.floor(args.timeoutMs)))
        : 60_000;
    if (!to || !message) {
      return jsonText({ ok: false, error: "to and message are required for ask" });
    }
    const target = await resolveTarget(to);
    const result = await client.send(target.id, { text: message, expectsReply: true });
    if (!result.delivered) {
      return jsonText({
        ok: false,
        id: result.id,
        to: target.name,
        error: result.reason ?? "delivery failed",
      });
    }

    try {
      const reply = await new Promise<{ from: SessionInfo; message: InboundMessage }>(
        (resolveWait, rejectWait) => {
          const timer = setTimeout(() => {
            pendingAsks.delete(result.id);
            try {
              client.cancelAsk(result.id);
            } catch {
              // Best-effort cancel.
            }
            rejectWait(new Error(`Timed out after ${timeoutMs}ms waiting for reply from ${target.name}`));
          }, timeoutMs);
          pendingAsks.set(result.id, {
            targetId: target.id,
            targetName: target.name,
            resolve: resolveWait,
            reject: rejectWait,
            timer,
          });
        },
      );
      return jsonText({
        ok: true,
        askId: result.id,
        from: reply.from.name || reply.from.id.slice(0, 8),
        fromId: reply.from.id,
        reply: reply.message.content?.text ?? "",
      });
    } catch (error) {
      return jsonText({
        ok: false,
        askId: result.id,
        to: target.name,
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }

  if (action === "reply") {
    const message = String(args.message ?? "");
    if (!message) {
      return jsonText({ ok: false, error: "message is required for reply" });
    }
    const requestedReplyTo = typeof args.replyTo === "string" ? args.replyTo.trim() : "";
    const requestedTo = typeof args.to === "string" ? args.to.trim() : "";

    let candidate: BufferedItem | undefined;
    if (requestedReplyTo) {
      candidate = inbox.find((m) => m.id === requestedReplyTo);
    } else if (requestedTo) {
      candidate = [...inbox]
        .reverse()
        .find(
          (m) =>
            !m.replied &&
            (m.fromName === requestedTo ||
              m.fromId === requestedTo ||
              m.fromName.startsWith(requestedTo)),
        );
    } else {
      candidate = [...inbox].reverse().find((m) => m.expectsReply && !m.replied);
    }

    if (!candidate) {
      return jsonText({
        ok: false,
        error: "No matching pending ask found in inbox; specify 'to' or use 'send'.",
      });
    }

    const result = await client.send(candidate.fromId, {
      text: message,
      replyTo: candidate.id,
    });
    if (result.delivered) {
      candidate.read = true;
      candidate.replied = true;
      persistUnreadInbox();
    }
    return jsonText({
      ok: result.delivered,
      id: result.id,
      to: candidate.fromName,
      replyTo: candidate.id,
      ...(result.reason ? { reason: result.reason } : {}),
    });
  }

  return jsonText({ ok: false, error: `Unsupported action: ${action}` });
});

async function shutdown(): Promise<void> {
  if (shuttingDown) return;
  shuttingDown = true;
  if (reconnectTimer) clearTimeout(reconnectTimer);
  for (const [, waiter] of pendingAsks) {
    clearTimeout(waiter.timer);
    waiter.reject(new Error("Shutting down"));
  }
  pendingAsks.clear();
  cleanupInboxFile();
  try {
    await client.disconnect();
  } catch {
    // Ignore disconnect errors on exit.
  }
  process.exit(0);
}

process.on("SIGINT", () => void shutdown());
process.on("SIGTERM", () => void shutdown());
process.stdin.on("end", () => void shutdown());

// Connect eagerly in background so this session appears in the broker roster immediately.
ensureConnected().catch(() => {
  scheduleReconnect();
});

const transport = new StdioServerTransport();
await server.connect(transport);
