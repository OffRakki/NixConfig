import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  pi.registerProvider("deepseek", {
    name: "DeepSeek",
    baseUrl: "https://api.deepseek.com/v1",
    apiKey: "$DEEPSEEK_API_KEY",
    api: "openai-completions",
    models: [
      {
        id: "deepseek-v4-flash",
        name: "DeepSeek V4 Flash",
        reasoning: true,
        input: ["text"],
        cost: {
          input: 0.14,
          output: 0.28,
          cacheRead: 0.014,
          cacheWrite: 0.14,
        },
        contextWindow: 128000,
        maxTokens: 16384,
        compat: {
          thinkingFormat: "deepseek" as const,
        },
      },
      {
        id: "deepseek-v4-pro",
        name: "DeepSeek V4 Pro",
        reasoning: true,
        input: ["text"],
        cost: {
          input: 0.55,
          output: 2.19,
          cacheRead: 0.055,
          cacheWrite: 0.55,
        },
        contextWindow: 128000,
        maxTokens: 32768,
        compat: {
          thinkingFormat: "deepseek" as const,
        },
      },
    ],
  });
}
