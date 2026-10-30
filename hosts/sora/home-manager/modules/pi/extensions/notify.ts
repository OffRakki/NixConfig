import { Type } from "@earendil-works/pi-ai";
import { defineTool, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

function plainText(value: string): string {
  return value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

async function notify(title: string, body: string, signal?: AbortSignal) {
  signal?.throwIfAborted();
  if (title.includes("\0") || body.includes("\0")) {
    throw new Error("Notification text must not contain NUL characters.");
  }
  await execFileAsync(
    "notify-send",
    [
      "--app-name=Pi",
      "--icon=dialog-information",
      "--urgency=normal",
      "--",
      plainText(title),
      plainText(body),
    ],
    { shell: false, signal, timeout: 3000, maxBuffer: 8192 },
  );
}

export default function (pi: ExtensionAPI) {
  let attempted = false;
  pi.on("before_agent_start", () => {
    attempted = false;
  });

  pi.registerTool(defineTool({
    name: "desktop_notify",
    label: "Desktop Notification",
    description:
      "Send one desktop notification per request using literal text, without a shell. " +
      "Use only for important, actionable matters. Requires a working desktop notification bus. " +
      "A failed or cancelled attempt cannot be retried in the same request.",
    parameters: Type.Object({
      title: Type.String({ minLength: 1, maxLength: 160, description: "Plain-text notification title." }),
      body: Type.String({ maxLength: 2000, description: "Plain-text notification body." }),
    }, { additionalProperties: false }),
    async execute(_toolCallId, { title, body }, signal) {
      if (attempted) {
        return {
          isError: true,
          content: [{ type: "text", text: "A notification was already attempted for this request." }],
          details: { sent: false },
        };
      }
      // Reserve before awaiting: parallel calls must not send duplicate notifications.
      attempted = true;
      try {
        await notify(title, body, signal);
        return {
          content: [{ type: "text", text: "Desktop notification sent." }],
          details: { sent: true },
        };
      } catch {
        return {
          isError: true,
          content: [{ type: "text", text: "Desktop notification failed or was cancelled; do not claim it was sent." }],
          details: { sent: false },
        };
      }
    },
  }));

  pi.registerCommand("notify", {
    description: "Send a desktop notification",
    handler: async (args, ctx) => {
      const summary = args || "Done";
      try {
        await notify(`Ciel — ${summary}`, "", ctx.signal);
        ctx.ui.notify(summary, "info");
      } catch {
        ctx.ui.notify("Desktop notification failed or was cancelled.", "error");
      }
    },
  });
}
