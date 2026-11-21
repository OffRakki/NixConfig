---
name: ollama
description: Inspect and use Sora's local Ollama models, verify runtime context allocation and VRAM offload, and follow local-model compatibility rules across harnesses.
---

# Local Ollama on Sora

Sora runs a local Ollama container at `http://127.0.0.1:11434` (configured in NixOS `hosts/modules/ai.nix`).

## Inspect live models and allocated context

Run `ollama-check` (on `PATH`) to inspect:
- Configured `OLLAMA_CONTEXT_LENGTH` on Sora.
- Downloaded models (`/api/tags`), parameter sizes, and quantization.
- Currently loaded models (`/api/ps`), **actual allocated context window**, and GPU vs CPU/RAM offload split.

Never rely solely on model metadata or a short greeting to confirm context size — Ollama discovery reports a model's *trained* maximum, not its allocated runtime `OLLAMA_CONTEXT_LENGTH`. Verify `/api/ps` and test a real long prompt when validating a new model.

## Compatibility rules

- **`supportsDeveloperRole = false`**: Send instructions as `system`, not `developer`; Sora's Ollama path ignores `developer` messages.
- **`maxTokensField = "max_tokens"`**: Prefer `max_tokens` over OpenAI-only `max_completion_tokens`.
- **Exclude embedding models** from chat routing.
- **Compaction budgets**: Smaller local context windows (e.g., Qwen3.5 9B, Qwen3.8 27B Q4_K_M) need tighter compaction reserves than cloud models.
- **Hardware reality (RTX 5070)**: 27B-class Q4_K_M models require partial CPU offloading — benchmark both prompt processing and token generation before recommending them for interactive loops.

## Harness wiring

- **Pi**: Auto-discovers via `@jamesjfoong/pi-ollama` and Nix-managed `~/.pi/agent/pi-ollama.json`; run `/ollama-refresh` after pulling a new model. Do not run `/ollama-setup` to overwrite Nix-managed config.
- **Other harnesses / scripts**: Query `http://127.0.0.1:11434/v1` (OpenAI-compatible endpoint) or `http://127.0.0.1:11434/api/chat` directly for private or offline subtasks.
