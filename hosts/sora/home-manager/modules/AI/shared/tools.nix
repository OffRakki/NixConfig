{
  pkgs,
  inputs,
  ollamaContextLength ? null,
}: let
  runtime = import ../pi/runtime.nix {inherit pkgs inputs;};
  inherit (runtime) nodejs piPackage piPackages;
  closure = piPackages.npmClosure;

  rea = pkgs.writeShellApplication {
    name = "rea";
    runtimeInputs = [nodejs pkgs.procps];
    text = ''
      exec node "${closure}/node_modules/rea-agents/scripts/rea.mjs" "$@"
    '';
  };

  piWebAccessMcp = pkgs.writeShellApplication {
    name = "pi-web-access-mcp";
    runtimeInputs = [nodejs];
    text = ''
      exec node "${closure}/node_modules/pi-web-access/dist/mcp-cli.js" "$@"
    '';
  };

  piIntercom = pkgs.writeShellApplication {
    name = "pi-intercom";
    runtimeInputs = [nodejs];
    text = ''
      exec node "${closure}/node_modules/pi-intercom/cli.mjs" "$@"
    '';
  };

  bili = pkgs.writeShellApplication {
    name = "bili";
    runtimeInputs = [nodejs];
    text = ''
      exec node "${closure}/node_modules/billion-context/dist/index.js" "$@"
    '';
  };

  ollamaCheck = pkgs.writeShellApplication {
    name = "ollama-check";
    runtimeInputs = [pkgs.curl pkgs.jq];
    text = ''
      base_url="''${OLLAMA_HOST:-http://127.0.0.1:11434}"
      echo "Ollama endpoint: $base_url"
      ${pkgs.lib.optionalString (ollamaContextLength != null) ''
        echo "Sora OLLAMA_CONTEXT_LENGTH: ${toString ollamaContextLength}"
      ''}
      echo ""
      echo "=== Downloaded models (/api/tags) ==="
      if tags="$(curl -fsS --max-time 3 "$base_url/api/tags" 2>/dev/null)"; then
        printf '%s\n' "$tags" | jq -r '
          if (.models | length) == 0 then "(none)"
          else .models[] | "\(.name)\t\(.details.parameter_size // "?")\t\(.details.quantization_level // "?")\t\(((.size // 0) / 1073741824 * 10 | round) / 10) GiB"
          end
        '
      else
        echo "Ollama is not reachable at $base_url" >&2
        exit 1
      fi
      echo ""
      echo "=== Loaded runtime models (/api/ps) ==="
      if ps_json="$(curl -fsS --max-time 3 "$base_url/api/ps" 2>/dev/null)"; then
        printf '%s\n' "$ps_json" | jq -r '
          if (.models | length) == 0 then "(none loaded)"
          else .models[] | "\(.name)\tctx=\(.context_length // "?")\tvram=\(((.size_vram // 0) / 1073741824 * 10 | round) / 10) GiB\ttotal=\(((.size // 0) / 1073741824 * 10 | round) / 10) GiB"
          end
        '
      fi
    '';
  };

  reaSkill = "${closure}/node_modules/rea-agents/skills/reverse-engineer-anything";
in {
  inherit
    nodejs
    piPackage
    piPackages
    rea
    piWebAccessMcp
    piIntercom
    bili
    ollamaCheck
    reaSkill
    ;
}
