{
  config,
  pkgs,
  lib,
  ...
}: {
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

  environment.persistence."/persist".directories = ["/var/lib/firefly-iii"];

  systemd.services.firefly-backup = {
    description = "Backup Firefly III database to ~/sync/geral/FireflyBKP";
    path = with pkgs; [sqlite gzip];
    script = ''
      DATABASE="/var/lib/firefly-iii/storage/database/database.sqlite"
      OUTDIR="/home/rakki/sync/geral/FireflyBKP"
      install -d -o rakki -g users -m 0700 "$OUTDIR"

      FILENAME="$OUTDIR/firefly-$(date +%Y%m%d-%H%M%S).sqlite.gz"
      SNAPSHOT=$(mktemp "$OUTDIR/.firefly-XXXXXXXX.sqlite")
      TMPFILE="$FILENAME.tmp"
      trap 'rm -f "$SNAPSHOT" "$TMPFILE"' EXIT

      sqlite3 "$DATABASE" ".backup '$SNAPSHOT'"
      test "$(sqlite3 "$SNAPSHOT" 'PRAGMA quick_check;')" = ok
      gzip -c "$SNAPSHOT" > "$TMPFILE"
      gzip -t "$TMPFILE"
      chmod 0600 "$TMPFILE"
      chown rakki:users "$TMPFILE"
      mv "$TMPFILE" "$FILENAME"
      rm "$SNAPSHOT"
      trap - EXIT

      ls -t "$OUTDIR"/firefly-* \
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
