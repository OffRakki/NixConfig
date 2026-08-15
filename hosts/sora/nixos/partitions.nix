{inputs, ...}: {
  imports = [
    inputs.disko.nixosModules.disko
  ];
  disko.devices.disk = {
    ssd-nvme = {
      device = "/dev/disk/by-id/nvme-XPG_GAMMIX_S70_BLADE_2M372918S7GA";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          boot = {
            size = "1M";
            type = "EF02";
          };
          esp = {
            name = "ESP";
            size = "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
            };
          };
          luks = {
            size = "100%";
            content = {
              name = "root";
              type = "luks";
              settings.allowDiscards = true;
              content = {
                type = "btrfs";
                postCreateHook = ''
                  MNTPOINT=$(mktemp -d)
                  mount -t btrfs "$device" "$MNTPOINT"
                  trap 'umount $MNTPOINT; rm -d $MNTPOINT' EXIT
                  btrfs subvolume snapshot -r $MNTPOINT/root $MNTPOINT/root-blank
                '';
                subvolumes = {
                  "/root" = {
                    mountOptions = ["compress=zstd"];
                    mountpoint = "/";
                  };
                  "/nix" = {
                    mountOptions = [
                      "compress=zstd"
                      "noatime"
                    ];
                    mountpoint = "/nix";
                  };
                  "/persist" = {
                    mountOptions = ["compress=zstd"];
                    mountpoint = "/persist";
                  };
                  "/swap" = {
                    mountOptions = [
                      "compress=zstd"
                      "noatime"
                    ];
                    mountpoint = "/swap";
                    swap.swapfile = {
                      size = "8196M";
                      path = "swapfile";
                    };
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
