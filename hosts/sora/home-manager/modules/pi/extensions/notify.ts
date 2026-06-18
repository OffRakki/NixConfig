import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { execSync } from "node:child_process";

export default function (pi: ExtensionAPI) {
  pi.on("agent_end", async (_event, ctx) => {
    try {
      const session = ctx.sessionManager.getSessionFile();
      const short = session
        ? session.split("/").pop()?.replace(".jsonl", "").slice(0, 8)
        : "?";
      execSync(
        `notify-send --app-name="Pi" --icon=dialog-information --urgency=normal "ciel — Task complete" "session: ${short}"`,
        { timeout: 3000 }
      );
    } catch {
      // notify-send may not be available; silently skip
    }
  });

  pi.registerCommand("notify", {
    description: "Send a desktop notification",
    handler: async (args, ctx) => {
      const summary = args || "Done";
      try {
        execSync(
          `notify-send --app-name="Pi" --icon=dialog-information --urgency=normal "ciel — ${summary}"`,
          { timeout: 3000 }
        );
      } catch {
        // silently skip if notify-send unavailable
      }
      ctx.ui.notify(summary, "info");
    },
  });
}
