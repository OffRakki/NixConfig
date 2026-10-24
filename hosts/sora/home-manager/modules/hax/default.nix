{
  inputs,
  pkgs,
  ...
}: let
  settings = import ./settings.nix;
  configFile = pkgs.writeText "hax-config.json" (builtins.toJSON settings);
  skills = {
    hax-tools = ./skills/hax-tools;
    browser = ./skills/browser;
    nix = ./skills/nix;
    jujutsu = ../pi/skills/jujutsu;
  };
  hax = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.hax.overrideAttrs (old: {
    nativeInstallCheckInputs = (old.nativeInstallCheckInputs or []) ++ [pkgs.python3];
    postInstallCheck =
      (old.postInstallCheck or "")
      + ''
        ${pkgs.python3}/bin/python3 ${./tests/smoke.py} \
          "$out/bin/hax" ${configFile} ${./context.md} \
          ${pkgs.linkFarm "hax-skills" (pkgs.lib.mapAttrsToList (name: path: {inherit name path;}) skills)}
      '';
  });
in {
  home = {
    packages = [hax pkgs.jujutsu pkgs.agent-browser pkgs.chromium];
    persistence."/persist".directories = [".local/state/hax"];
    file =
      {
        ".config/hax/config.json".source = configFile;
        ".config/hax/AGENTS.md".source = ./context.md;
        ".config/hax/docs".source = "${hax.src}/docs";
      }
      // pkgs.lib.mapAttrs' (name: source:
        pkgs.lib.nameValuePair ".config/hax/skills/${name}" {inherit source;})
      skills;
  };
  xdg.desktopEntries.hax = {
    name = "HAX";
    genericName = "AI Coding Assistant";
    comment = "CLI-first coding assistant (side-by-side pilot)";
    exec = "kitty --directory /home/rakki/Projects/NixConfig -e hax";
    icon = "utilities-terminal";
    terminal = false;
    categories = ["Development" "ConsoleOnly"];
  };
}
