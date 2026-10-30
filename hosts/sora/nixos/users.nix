{
  pkgs,
  config,
  lib,
  ...
}: {
  users = {
    defaultUserShell = "${lib.getExe pkgs.fish}";
    mutableUsers = false;
    groups.i2c.members = ["rakki"];
    users = {
      rakki = {
        isNormalUser = true;
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFjf4oKMc8ZFzSAJXO5YYOQM9alEUxph80pA67ePwiOA rakki@sora"
        ];
        hashedPasswordFile = config.sops.secrets.soraPass.path;
        extraGroups = [
          "minecraft"
          "corectrl"
          "networkmanager"
          "storage"
          "wheel"
          "disk"
          "libvirtd"
          "libvirt"
          "qemu-libvirtd"
          "scanner"
          "lp"
          "video"
          "render"
          "audio"
          "docker"
          "podman"
          "input"
          "uinput"
          "ydotool"
        ];
      };
    };
  };
  environment.shells = with pkgs; [fish];
}
