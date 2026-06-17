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

  sops.secrets.fireflyPat = {
    owner = "rakki";
  };

  sops.secrets.mercadoPagoToken = {
    owner = "rakki";
  };

  # /var/lib owned by rakki (from /persist) blocks systemd-tmpfiles from
  # creating nested subdirs for any service under /var/lib. Fix it upstream.
  systemd.tmpfiles.rules = ["z /var/lib 0755 root root - -"];

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

  systemd.services.firefly-backup = {
    description = "Backup Firefly III database to ~/sync/geral/FireflyBKP";
    path = with pkgs; [mariadb gzip];
    script = ''
      OUTDIR="/home/rakki/sync/geral/FireflyBKP"
      mkdir -p "$OUTDIR"

      FILENAME="$OUTDIR/firefly-$(date +%Y%m%d-%H%M%S).sql.gz"

      mysqldump --databases firefly | gzip > "$FILENAME"
      chown rakki:users "$FILENAME"

      ls -t "$OUTDIR"/firefly-*.sql.gz \
        | tail -n +31 \
        | xargs -r rm
    '';
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
  };

  systemd.timers.firefly-backup = {
    description = "Daily Firefly III database backup";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = 1800;
    };
  };
}
