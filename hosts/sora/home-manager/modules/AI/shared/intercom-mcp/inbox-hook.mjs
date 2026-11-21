import { createHash } from "node:crypto";
import { readdirSync, readFileSync, rmSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve } from "node:path";

function readStdin() {
  try {
    return readFileSync(0, "utf8");
  } catch {
    return "";
  }
}

function isPidAlive(pid) {
  if (!Number.isInteger(pid) || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch (err) {
    return err && err.code === "EPERM";
  }
}

function main() {
  const raw = readStdin().trim();
  if (!raw) {
    process.stdout.write("{}\n");
    return;
  }

  let input;
  try {
    input = JSON.parse(raw);
  } catch {
    process.stdout.write("{}\n");
    return;
  }

  const cwd = input.cwd || (Array.isArray(input.workspacePaths) ? input.workspacePaths[0] : "");
  if (!cwd) {
    process.stdout.write("{}\n");
    return;
  }

  const agentDir = process.env.PI_CODING_AGENT_DIR || join(homedir(), ".pi", "agent");
  const inboxDir = join(agentDir, "intercom", "agy-inbox");
  const cwdHash = createHash("sha256").update(resolve(cwd)).digest("hex").slice(0, 16);

  let files;
  try {
    files = readdirSync(inboxDir).filter((f) => f.startsWith(`${cwdHash}-`) && f.endsWith(".json"));
  } catch {
    process.stdout.write("{}\n");
    return;
  }

  const collected = [];
  for (const file of files) {
    const fullPath = join(inboxDir, file);
    try {
      const data = JSON.parse(readFileSync(fullPath, "utf8"));
      if (!isPidAlive(data.pid)) {
        rmSync(fullPath, { force: true });
        continue;
      }
      if (Array.isArray(data.messages) && data.messages.length > 0) {
        for (const msg of data.messages) {
          collected.push({
            sessionName: data.sessionName || "agy",
            fromName: msg.fromName || "peer",
            text: msg.text || "",
            expectsReply: Boolean(msg.expectsReply),
            id: msg.id || "",
          });
        }
        rmSync(fullPath, { force: true });
      }
    } catch {
      // Ignore corrupt or concurrently replaced inbox files.
    }
  }

  if (collected.length === 0) {
    process.stdout.write("{}\n");
    return;
  }

  const lines = [
    "[pi-intercom] Inbound message(s) received for this workspace:",
    ...collected.map((m) => {
      const tag = m.expectsReply ? " (ASK — expects reply via intercom action='reply')" : "";
      return `- From ${m.fromName}${tag}: ${m.text}`;
    }),
    "Use the pi-intercom MCP `intercom` tool (action: 'inbox' or 'reply') if a response is needed.",
  ];

  process.stdout.write(
    `${JSON.stringify({
      injectSteps: [
        {
          systemMessage: {
            systemMessage: lines.join("\n"),
          },
        },
      ],
    })}\n`,
  );
}

main();
