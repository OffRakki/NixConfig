{inputs, ...}: {
  nixpkgs = {
    overlays = [
      inputs.nix-minecraft.overlay
      (_: prev: {
        aerc = prev.aerc.overrideAttrs (old: {
          patches = (old.patches or []) ++ [./aerc-config-includes.patch];
        });
      })
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
