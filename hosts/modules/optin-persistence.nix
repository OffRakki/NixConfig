{
  lib,
  inputs,
  config,
  ...
}: {
  imports = [inputs.impermanence.nixosModules.impermanence];

  environment.persistence = {
    "/persist" = {
      files = [
        "/etc/machine-id"
      ];
      directories = [
        "/var/lib/systemd"
        "/var/lib/nixos"
        "/var/lib/tailscale"
        "/var/lib/containers"
        "/var/lib/private"
        "/var/lib/OpenRGB"
        "/var/lib/waydroid"
        "/var/lib/sbctl"
        "/var/log"
      ];
    };
  };

  system.activationScripts = {
    persistent-dirs = {
      deps = ["specialfs" "users" "groups"];
      text = let
        mkHomePersist = user:
          lib.optionalString user.createHome ''
            mkdir -p /persist/${user.home}
            chown ${user.name}:${user.group} /persist/${user.home}
            chmod ${user.homeMode} /persist/${user.home}
          '';
        users = lib.attrValues config.users.users;
      in ''
        install -d -m 0755 -o root -g root \
          /persist /persist/etc /persist/home /persist/var /persist/var/lib /persist/var/log
        ${lib.concatLines (map mkHomePersist users)}
      '';
    };

    createPersistentStorageDirs.deps = ["persistent-dirs"];
  };
}
