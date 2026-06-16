{
  config,
  pkgs,
  lib,
  ...
}: {
  services.mysql = {
    enable = true;
    package = pkgs.mariadb;
    ensureDatabases = ["firefly"];
    ensureUsers = [
      {
        name = "firefly-iii";
        ensurePermissions = {
          "firefly.*" = "ALL PRIVILEGES";
        };
      }
    ];
  };

  services.firefly-iii = {
    enable = true;
    enableNginx = true;
    virtualHost = "localhost";
    settings = {
      APP_KEY_FILE = config.sops.secrets.fireflyAppKey.path;
    };
  };

  sops.secrets.fireflyAppKey = {
    owner = "firefly-iii";
    group = "nginx";
  };

  system.activationScripts.firefly-iii-dirs = {
    supportsDryActivation = true;
    text = ''
      install -d -o firefly-iii -g nginx -m 0700 \
        /var/lib/firefly-iii/storage/app \
        /var/lib/firefly-iii/storage/database \
        /var/lib/firefly-iii/storage/export \
        /var/lib/firefly-iii/storage/framework/cache \
        /var/lib/firefly-iii/storage/framework/sessions \
        /var/lib/firefly-iii/storage/framework/views \
        /var/lib/firefly-iii/storage/logs \
        /var/lib/firefly-iii/storage/upload
      # Placeholder file so rm *.php doesn't fail with empty glob
      touch /var/lib/firefly-iii/cache/placeholder.php
      chown firefly-iii:nginx /var/lib/firefly-iii/cache/placeholder.php
    '';
  };

  environment.persistence."/persist".directories = [
    "/var/lib/mysql"
    "/var/lib/firefly-iii"
  ];
}
