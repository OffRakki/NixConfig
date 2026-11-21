{
  pkgs,
  inputs,
  osConfig,
  ...
}: let
  ollamaContextLength =
    osConfig.virtualisation.oci-containers.containers.ollama.environment.OLLAMA_CONTEXT_LENGTH or null;
  tools = import ./tools.nix {
    inherit pkgs inputs ollamaContextLength;
  };
in {
  home.packages = [
    tools.rea
    tools.piWebAccessMcp
    tools.piIntercom
    tools.bili
    tools.ollamaCheck
    pkgs.agent-browser
    pkgs.chromium
  ];
}
