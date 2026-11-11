{
  config,
  pkgs,
  lib,
  ...
}: let
  clip-notify = pkgs.callPackage ./clip-notify/package.nix {};
in {
  systemd.user.services.clip-notify = {
    Unit = {
      Description = "Clipboard copy notifications";
      PartOf = [config.wayland.systemd.target];
      After = [config.wayland.systemd.target];
    };
    Service = {
      Type = "simple";
      ExecStart = "${lib.getExe' pkgs.wl-clipboard "wl-paste"} --watch ${lib.getExe' clip-notify "clip-notify"}";
      Restart = "on-failure";
    };
    Install.WantedBy = [config.wayland.systemd.target];
  };
}
