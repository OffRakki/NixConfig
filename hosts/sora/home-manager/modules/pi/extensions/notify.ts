// @ts-nocheck -- Pi extension types live in Pi's runtime npm tree, not this Nix source tree.
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { execFileSync } from "node:child_process";

export default function (pi: ExtensionAPI) {
  pi.registerCommand("notify", {
    description: "Send a desktop notification",
    handler: async (args, ctx) => {
      const summary = args || "Done";
      try {
        execFileSync(
          "notify-send",
          [
            "--app-name=Pi",
            "--icon=dialog-information",
            "--urgency=normal",
            `ciel — ${summary}`,
          ],
          { timeout: 3000 }
        );
      } catch {
        // silently skip if notify-send unavailable
      }
      ctx.ui.notify(summary, "info");
    },
  });
}
