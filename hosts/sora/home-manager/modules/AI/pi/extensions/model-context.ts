// @ts-nocheck -- Pi extension types live in Pi's runtime npm tree, not this Nix source tree.
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function modelContext(pi: ExtensionAPI) {
  pi.on("before_agent_start", async (event, ctx) => {
    const model = ctx.model
      ? `${ctx.model.provider}/${ctx.model.id}`
      : "unknown";

    return {
      systemPrompt: `${event.systemPrompt}\n\n# Runtime\n\nHarness: pi\nModel: ${model}\n`,
    };
  });
}
