{
  inputs,
  lib,
  pkgs,
  ...
}: {
  nix = let
    flakeInputs = lib.filterAttrs (_: lib.isType "flake") inputs;
  in {
    package = pkgs.lixPackageSets.stable.lix;
    settings = {
      trusted-users = ["root" "rakki"];
      accept-flake-config = true;
      # Enable flakes and new 'nix' command
      experimental-features = ["nix-command flakes" "flake-self-attrs"];
      # Opinionated: disable global registry
      flake-registry = "";
      # Workaround to get rid of the download buffer size warning
      ### Disabled for lix
      # download-buffer-size = 524288000;
    };

    # Opinionated: make flake registry and nix path match flake inputs
    registry = lib.mapAttrs (_: flake: {inherit flake;}) flakeInputs;
    nixPath = lib.mapAttrsToList (n: _: "${n}=flake:${n}") flakeInputs;
  };
}
