{inputs, ...}: {
  nixpkgs = {
    overlays = [
      inputs.nix-minecraft.overlay
      inputs.millennium.overlays.default
      (final: _: {
        inputs =
          builtins.mapAttrs (
            _: flake: let
              legacyPackages = (flake.legacyPackages or {}).${final.stdenv.hostPlatform.system} or {};
              packages = (flake.packages or {}).${final.stdenv.hostPlatform.system} or {};
            in
              packages // legacyPackages
          )
          inputs;
      })
    ];
    config = {
      allowUnfree = true;
    };
  };
}
