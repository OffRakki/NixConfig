{
  config,
  pkgs,
  lib,
  ...
}: let
  # Vendored from misterio77/nix-config (MIT).
  clip-notify = pkgs.writeShellApplication {
    name = "clip-notify";
    runtimeInputs = with pkgs; [file coreutils libnotify wl-clipboard];
    text = builtins.readFile ./clip-notify.sh;
  };
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
